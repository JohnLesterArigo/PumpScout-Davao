part of '../main.dart';

class _AiScreeningConfig {
  const _AiScreeningConfig({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

class _FullScreenSheetAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _FullScreenSheetAppBar({required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  ui.Size get preferredSize => const ui.Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: _psPageColor(context),
      foregroundColor: _psPrimaryTextColor(context),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      title: Text(title),
      leading: IconButton(
        tooltip: 'Close',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close),
      ),
      actions: actions,
    );
  }
}

enum _VehicleSaveMode { updateActive, addNew }

class _FuelConsumptionEditorSheet extends StatefulWidget {
  const _FuelConsumptionEditorSheet({
    required this.initialVehicle,
    required this.vehicles,
    required this.activeVehicleIndex,
    required this.saveMode,
    required this.onSaved,
  });

  final Map<String, dynamic> initialVehicle;
  final List<Map<String, dynamic>> vehicles;
  final int activeVehicleIndex;
  final _VehicleSaveMode saveMode;
  final VoidCallback onSaved;

  @override
  State<_FuelConsumptionEditorSheet> createState() =>
      _FuelConsumptionEditorSheetState();
}

class _FuelConsumptionEditorSheetState
    extends State<_FuelConsumptionEditorSheet> {
  static const fuelTypes = ['Gasoline', 'Diesel', 'Premium Gasoline'];
  static const wheelTypes = ['2 wheels', '3 wheels', '4 wheels', '6 wheels'];
  static const useTypes = ['Private', 'Public', 'Business'];

  late final TextEditingController vehicleNameController;
  late final TextEditingController kmPerLiterController;
  late final TextEditingController idleRateController;
  late String selectedWheels;
  late String selectedUse;
  late String selectedFuelType;
  bool isSaving = false;
  String? errorText;

  @override
  void initState() {
    super.initState();
    final vehicle = widget.initialVehicle;
    vehicleNameController = TextEditingController(
      text: _profileValue(vehicle['name'], fallback: ''),
    );
    kmPerLiterController = TextEditingController(
      text: _doubleField(vehicle, 'kmPerLiter')?.toStringAsFixed(1) ?? '',
    );
    idleRateController = TextEditingController(
      text:
          _doubleField(vehicle, 'idleLitersPerHour')?.toStringAsFixed(2) ?? '',
    );
    selectedWheels = _displayOption(
      vehicle['wheels'],
      wheelTypes,
      fallback: '4 wheels',
    );
    selectedUse = _displayOption(vehicle['use'], useTypes, fallback: 'Private');
    selectedFuelType = _displayFuelType(vehicle['preferredFuelType']);
  }

  @override
  void dispose() {
    vehicleNameController.dispose();
    kmPerLiterController.dispose();
    idleRateController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final user = FirebaseAuth.instance.currentUser;
    final vehicleName = vehicleNameController.text.trim();
    final kmPerLiter = _parsePrice(kmPerLiterController.text);
    final idleRate = _parsePrice(idleRateController.text);

    if (user == null) return;
    if (vehicleName.isEmpty) {
      setState(() => errorText = 'Enter a car name or model.');
      return;
    }
    if (kmPerLiter == null || kmPerLiter <= 0) {
      setState(() => errorText = 'Enter a valid km/L value.');
      return;
    }
    if (idleRate == null || idleRate < 0) {
      setState(() => errorText = 'Enter a valid idle fuel rate.');
      return;
    }

    setState(() {
      isSaving = true;
      errorText = null;
    });

    final savedVehicle = <String, dynamic>{
      ...widget.initialVehicle,
      'name': vehicleName,
      'wheels': selectedWheels,
      'use': selectedUse,
      'preferredFuelType': selectedFuelType,
      'kmPerLiter': kmPerLiter,
      'idleLitersPerHour': idleRate,
    };
    final vehicles = widget.vehicles
        .map((vehicle) => Map<String, dynamic>.from(vehicle))
        .toList();
    final activeIndex = widget.saveMode == _VehicleSaveMode.addNew
        ? vehicles.length
        : widget.activeVehicleIndex;

    if (widget.saveMode == _VehicleSaveMode.addNew) {
      vehicles.add(savedVehicle);
    } else if (vehicles.isEmpty) {
      vehicles.add(savedVehicle);
    } else {
      final index = widget.activeVehicleIndex.clamp(0, vehicles.length - 1);
      vehicles[index] = savedVehicle;
    }

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'vehicle': savedVehicle,
      'vehicles': vehicles,
      'activeVehicleIndex': activeIndex,
    }, SetOptions(merge: true));

    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + bottomPadding),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.saveMode == _VehicleSaveMode.addNew
                  ? 'Add Car'
                  : 'Vehicle & Fuel',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Used for route fuel and cost estimates.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: vehicleNameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Car name or model',
                prefixIcon: Icon(Icons.directions_car),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedWheels,
              decoration: const InputDecoration(
                labelText: 'Vehicle type',
                prefixIcon: Icon(Icons.category_outlined),
                border: OutlineInputBorder(),
              ),
              items: wheelTypes
                  .map(
                    (type) => DropdownMenuItem(value: type, child: Text(type)),
                  )
                  .toList(),
              onChanged: isSaving
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => selectedWheels = value);
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedUse,
              decoration: const InputDecoration(
                labelText: 'Use',
                prefixIcon: Icon(Icons.work_outline),
                border: OutlineInputBorder(),
              ),
              items: useTypes
                  .map((use) => DropdownMenuItem(value: use, child: Text(use)))
                  .toList(),
              onChanged: isSaving
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => selectedUse = value);
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: kmPerLiterController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Fuel consumption (km/L)',
                prefixIcon: Icon(Icons.speed),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: idleRateController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Idle fuel use (L/hour)',
                prefixIcon: Icon(Icons.traffic),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedFuelType,
              decoration: const InputDecoration(
                labelText: 'Preferred fuel type',
                prefixIcon: Icon(Icons.local_gas_station),
                border: OutlineInputBorder(),
              ),
              items: fuelTypes
                  .map(
                    (fuel) => DropdownMenuItem(value: fuel, child: Text(fuel)),
                  )
                  .toList(),
              onChanged: isSaving
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => selectedFuelType = value);
                    },
            ),
            if (errorText != null) ...[
              const SizedBox(height: 10),
              Text(
                errorText!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isSaving ? null : save,
                icon: const Icon(Icons.save),
                label: Text(isSaving ? 'Saving...' : 'Save'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1E8E3E),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _displayFuelType(dynamic value) {
    final raw = _profileValue(value, fallback: 'Gasoline').toLowerCase();
    if (raw.contains('diesel')) return 'Diesel';
    if (raw.contains('premium')) return 'Premium Gasoline';
    return 'Gasoline';
  }

  static String _displayOption(
    dynamic value,
    List<String> options, {
    required String fallback,
  }) {
    final raw = _profileValue(value, fallback: fallback);
    return options.contains(raw) ? raw : fallback;
  }
}
