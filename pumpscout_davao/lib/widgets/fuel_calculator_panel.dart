part of '../main.dart';

void showFuelCalculatorPanel(BuildContext context) {
  FocusManager.instance.primaryFocus?.unfocus();

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      return const _FuelCalculatorSheet();
    },
  );
}

class _FuelCalculatorSheet extends StatefulWidget {
  const _FuelCalculatorSheet();

  @override
  State<_FuelCalculatorSheet> createState() => _FuelCalculatorSheetState();
}

class _FuelCalculatorSheetState extends State<_FuelCalculatorSheet> {
  final tankCapacityController = TextEditingController();
  final currentFuelController = TextEditingController();
  final pricePerLiterController = TextEditingController();

  double? litersNeeded;
  double? totalCost;

  @override
  void dispose() {
    tankCapacityController.dispose();
    currentFuelController.dispose();
    pricePerLiterController.dispose();
    super.dispose();
  }

  void calculate() {
    final tankCapacity = _parsePrice(tankCapacityController.text);
    final currentFuel = _parsePrice(currentFuelController.text);
    final pricePerLiter = _parsePrice(pricePerLiterController.text);

    setState(() {
      if (tankCapacity == null ||
          currentFuel == null ||
          pricePerLiter == null ||
          tankCapacity <= 0 ||
          currentFuel < 0 ||
          currentFuel > tankCapacity ||
          pricePerLiter <= 0) {
        litersNeeded = null;
        totalCost = null;
        return;
      }

      litersNeeded = tankCapacity - currentFuel;
      totalCost = litersNeeded! * pricePerLiter;
    });
  }

  void reset() {
    tankCapacityController.clear();
    currentFuelController.clear();
    pricePerLiterController.clear();
    setState(() {
      litersNeeded = null;
      totalCost = null;
    });
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
              'Fuel Cost Calculator',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Estimate how much it costs to fill your tank.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _calculatorField(
              controller: tankCapacityController,
              label: 'Car tank capacity',
              suffix: 'L',
              onChanged: calculate,
            ),
            _calculatorField(
              controller: currentFuelController,
              label: 'Current fuel level',
              suffix: 'L',
              onChanged: calculate,
            ),
            _calculatorField(
              controller: pricePerLiterController,
              label: 'Price per liter',
              prefix: 'PHP ',
              suffix: '/ L',
              onChanged: calculate,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estimated fill-up cost',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    totalCost == null
                        ? 'Enter valid values to calculate.'
                        : 'PHP ${totalCost!.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: totalCost == null
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : const Color(0xFF00A152),
                    ),
                  ),
                  if (litersNeeded != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${litersNeeded!.toStringAsFixed(2)} liters needed to fill the tank.',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: reset,
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _calculatorField({
  required TextEditingController controller,
  required String label,
  required String suffix,
  required VoidCallback onChanged,
  String? prefix,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}
