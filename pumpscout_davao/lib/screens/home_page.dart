part of '../main.dart';

const _psDeepBlue = Color(0xFF191B20);
const _psPanelBlue = Color(0xFF23262C);
const _psSoftPanel = Color(0xFF2C3037);
const _psRed = Color(0xFFE94B5A);
const _psMutedText = Color(0xFFADB4BF);
const _psLightPanel = Color(0xFFFFFFFF);
const _psLightSoftPanel = Color(0xFFF6F8FB);
const _psLightMutedText = Color(0xFF5F6F85);
const _psLightBorder = Color(0xFFE3E8EF);
const _psDarkBorder = Color(0xFF3A3F48);

bool _psIsDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color _psPageColor(BuildContext context) =>
    _psIsDark(context) ? _psDeepBlue : Colors.white;

Color _psPanelColor(BuildContext context) =>
    _psIsDark(context) ? _psPanelBlue : _psLightPanel;

Color _psSoftPanelColor(BuildContext context) =>
    _psIsDark(context) ? _psSoftPanel : _psLightSoftPanel;

Color _psPrimaryTextColor(BuildContext context) =>
    _psIsDark(context) ? Colors.white : _psDeepBlue;

Color _psMutedTextColor(BuildContext context) =>
    _psIsDark(context) ? _psMutedText : _psLightMutedText;

Color _psBorderColor(BuildContext context) =>
    _psIsDark(context) ? _psDarkBorder : _psLightBorder;

Color _psActionColor(BuildContext context) =>
    _psIsDark(context) ? const Color(0xFFD7DBE2) : const Color(0xFF2563EB);

Color _psFilledActionColor(BuildContext context) =>
    _psIsDark(context) ? _psSoftPanel : const Color(0xFF2563EB);

Color _psDecorativeColor(BuildContext context, Color lightColor) =>
    _psIsDark(context) ? const Color(0xFFB8BEC8) : lightColor;

Color _psLevelProgressColor(double progress) {
  if (progress < 0.25) return const Color(0xFFE5B832);
  if (progress < 0.75) return const Color(0xFF9BC53D);
  return const Color(0xFF22A65A);
}

class HomePage extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback toggleTheme;
  const HomePage({
    super.key,
    required this.isDarkMode,
    required this.toggleTheme,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final mapKey = GlobalKey<_MapContainerState>();
  final destinationController = TextEditingController();
  final PageController fuelInsightsController = PageController();
  List<DestinationPlace> destinationSuggestions = [];
  DestinationPlace? selectedDestination;
  DestinationPlace? activeHomeRoutePlace;
  bool isSearchingDestination = false;
  Timer? fuelInsightsTimer;
  Future<List<_HomeFuelInsight>>? fuelInsightsFuture;
  Future<List<StationMarkerDetails>>? cheapestStationsFuture;
  bool isExpandedMapOpen = false;

  @override
  void initState() {
    super.initState();
    fuelInsightsFuture = loadHomeFuelInsights();
    cheapestStationsFuture = loadHomeStationDetails();
    fuelInsightsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!fuelInsightsController.hasClients) return;
      final nextPage = (fuelInsightsController.page?.round() ?? 0) + 1;
      fuelInsightsController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    fuelInsightsTimer?.cancel();
    fuelInsightsController.dispose();
    destinationController.dispose();
    super.dispose();
  }

  void showProfileSheet() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final toggleTheme = widget.toggleTheme;

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) {
          return FutureBuilder<UserProfileSummary>(
            future: loadProfileSummary(user),
            builder: (context, snapshot) {
              final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

              if (snapshot.connectionState == ConnectionState.waiting) {
                return Scaffold(
                  backgroundColor: _psPageColor(context),
                  appBar: const _FullScreenSheetAppBar(title: 'Profile'),
                  body: const Center(
                    child: CircularProgressIndicator(color: _psRed),
                  ),
                );
              }

              if (snapshot.hasError || snapshot.data == null) {
                return Scaffold(
                  backgroundColor: _psPageColor(context),
                  appBar: const _FullScreenSheetAppBar(title: 'Profile'),
                  body: Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 28 + bottomPadding),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Profile could not be loaded.',
                          style: TextStyle(
                            color: _psPrimaryTextColor(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _psPrimaryTextColor(context),
                            side: const BorderSide(color: _psRed),
                          ),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final profile = snapshot.data!;
              final vehicle = profile.vehicle;
              final vehicles = profile.vehicles;
              final kmPerLiter = _doubleField(vehicle, 'kmPerLiter');
              final idleRate = _doubleField(vehicle, 'idleLitersPerHour');
              final activeVehicleName = _profileValue(
                vehicle['name'],
                fallback: 'Current vehicle',
              );

              return Scaffold(
                backgroundColor: _psPageColor(context),
                appBar: const _FullScreenSheetAppBar(title: 'Profile'),
                body: SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      24 + bottomPadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _profileHeader(context, profile),
                        const SizedBox(height: 20),
                        _profileSection(
                          context,
                          title: 'Personal Details',
                          icon: Icons.badge_outlined,
                          children: [
                            _profileInfoRow(
                              context,
                              'Name',
                              profile.displayName,
                            ),
                            _profileInfoRow(context, 'Email', profile.email),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _profileSection(
                          context,
                          title: 'Vehicle & Fuel',
                          icon: Icons.local_gas_station_outlined,
                          children: [
                            _activeVehicleCard(
                              context,
                              activeVehicleName,
                              vehicle,
                            ),
                            if (vehicles.length > 1) ...[
                              const SizedBox(height: 10),
                              DropdownButtonFormField<int>(
                                initialValue: profile.activeVehicleIndex,
                                decoration: const InputDecoration(
                                  labelText: 'Currently using',
                                  prefixIcon: Icon(Icons.directions_car),
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  for (var i = 0; i < vehicles.length; i++)
                                    DropdownMenuItem<int>(
                                      value: i,
                                      child: Text(
                                        _profileValue(
                                          vehicles[i]['name'],
                                          fallback: 'Vehicle ${i + 1}',
                                        ),
                                      ),
                                    ),
                                ],
                                onChanged: (index) async {
                                  if (index == null ||
                                      index == profile.activeVehicleIndex) {
                                    return;
                                  }
                                  Navigator.of(context).pop();
                                  await setActiveVehicle(index, vehicles);
                                  await Future<void>.delayed(
                                    const Duration(milliseconds: 220),
                                  );
                                  if (!mounted) return;
                                  showProfileSheet();
                                },
                              ),
                            ],
                            const SizedBox(height: 14),
                            GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              childAspectRatio: 2.55,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              children: [
                                _profileVehicleDetail(
                                  context,
                                  icon: Icons.directions_car_outlined,
                                  label: 'Model',
                                  value: _profileValue(
                                    vehicle['name'],
                                    fallback: 'Not set',
                                  ),
                                  color: const Color(0xFF2563EB),
                                ),
                                _profileVehicleDetail(
                                  context,
                                  icon: Icons.tire_repair_outlined,
                                  label: 'Type',
                                  value: _profileValue(
                                    vehicle['wheels'],
                                    fallback: 'Not set',
                                  ),
                                  color: const Color(0xFF7C3AED),
                                ),
                                _profileVehicleDetail(
                                  context,
                                  icon: Icons.person_outline,
                                  label: 'Use',
                                  value: _profileValue(
                                    vehicle['use'],
                                    fallback: 'Not set',
                                  ),
                                  color: const Color(0xFF059669),
                                ),
                                _profileVehicleDetail(
                                  context,
                                  icon: Icons.local_gas_station_outlined,
                                  label: 'Fuel',
                                  value: _profileValue(
                                    vehicle['preferredFuelType'],
                                    fallback: 'Not set',
                                  ),
                                  color: const Color(0xFFF59E0B),
                                ),
                                _profileVehicleDetail(
                                  context,
                                  icon: Icons.trending_up,
                                  label: 'Consumption',
                                  value: kmPerLiter == null
                                      ? 'Not set'
                                      : '${kmPerLiter.toStringAsFixed(1)} km/L',
                                  color: const Color(0xFFEA580C),
                                ),
                                _profileVehicleDetail(
                                  context,
                                  icon: Icons.speed_outlined,
                                  label: 'Idle rate',
                                  value: idleRate == null
                                      ? 'Not set'
                                      : '${idleRate.toStringAsFixed(2)} L/hr',
                                  color: const Color(0xFF8B5CF6),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      Navigator.of(context).pop();
                                      await Future<void>.delayed(
                                        const Duration(milliseconds: 220),
                                      );
                                      if (!mounted) return;
                                      showFuelConsumptionEditor(
                                        this.context,
                                        profile,
                                      );
                                    },
                                    icon: const Icon(Icons.tune),
                                    label: const Text('Edit car'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _psActionColor(context),
                                      side: BorderSide(
                                        color: _psIsDark(context)
                                            ? _psBorderColor(context)
                                            : _psActionColor(context),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () async {
                                      Navigator.of(context).pop();
                                      await Future<void>.delayed(
                                        const Duration(milliseconds: 220),
                                      );
                                      if (!mounted) return;
                                      showVehicleAddSheet(
                                        this.context,
                                        profile,
                                      );
                                    },
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add car'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _psFilledActionColor(
                                        context,
                                      ),
                                      foregroundColor: Colors.white,
                                      side: _psIsDark(context)
                                          ? BorderSide(
                                              color: _psBorderColor(context),
                                            )
                                          : null,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _profileSection(
                          context,
                          title: 'Accessibility',
                          icon: Icons.accessibility_new_outlined,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Dark mode',
                                style: TextStyle(
                                  color: _psPrimaryTextColor(context),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                'Use a darker map and app interface.',
                                style: TextStyle(
                                  color: _psMutedTextColor(context),
                                ),
                              ),
                              value:
                                  Theme.of(context).brightness ==
                                  Brightness.dark,
                              onChanged: (_) => toggleTheme(),
                              activeThumbColor: _psActionColor(context),
                            ),
                          ],
                        ),
                        if (profile.isAdmin) ...[
                          const SizedBox(height: 14),
                          _profileSection(
                            context,
                            title: 'Admin',
                            icon: Icons.admin_panel_settings_outlined,
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () =>
                                      showAdminDashboard(context, profile),
                                  icon: const Icon(Icons.verified_user),
                                  label: const Text('Open admin dashboard'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _psFilledActionColor(
                                      context,
                                    ),
                                    foregroundColor: Colors.white,
                                    side: _psIsDark(context)
                                        ? BorderSide(
                                            color: _psBorderColor(context),
                                          )
                                        : null,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        _profileSection(
                          context,
                          title: 'Contributions',
                          icon: Icons.emoji_events_outlined,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _profileMetricCard(
                                    context,
                                    label: 'Price reports',
                                    value: '${profile.reportCount}',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _profileMetricCard(
                                    context,
                                    label: 'Last report',
                                    value: profile.lastReportAt == null
                                        ? 'None'
                                        : _formatDateTime(
                                            profile.lastReportAt!,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: showMyContributions,
                                icon: const Icon(Icons.history),
                                label: const Text('My contributions'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _psActionColor(context),
                                  side: BorderSide(
                                    color: _psIsDark(context)
                                        ? _psBorderColor(context)
                                        : _psActionColor(context),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await FirebaseAuth.instance.signOut();
                            },
                            icon: const Icon(Icons.logout),
                            label: const Text('Sign out'),
                            style: FilledButton.styleFrom(
                              backgroundColor: _psFilledActionColor(context),
                              foregroundColor: Colors.white,
                              side: _psIsDark(context)
                                  ? BorderSide(color: _psBorderColor(context))
                                  : null,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void showCommunityContributionsPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _CommunityContributionsPage(),
      ),
    );
  }

  void showFuelConsumptionEditor(
    BuildContext profileContext,
    UserProfileSummary profile,
  ) {
    final pageContext = profileContext;
    showModalBottomSheet(
      context: pageContext,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _FuelConsumptionEditorSheet(
          initialVehicle: profile.vehicle,
          vehicles: profile.vehicles,
          activeVehicleIndex: profile.activeVehicleIndex,
          saveMode: _VehicleSaveMode.updateActive,
          onSaved: () {
            if (!mounted) return;
            ScaffoldMessenger.of(
              pageContext,
            ).showSnackBar(const SnackBar(content: Text('Vehicle saved.')));
          },
        );
      },
    );
  }

  void showVehicleAddSheet(
    BuildContext profileContext,
    UserProfileSummary profile,
  ) {
    final pageContext = profileContext;
    showModalBottomSheet(
      context: pageContext,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _FuelConsumptionEditorSheet(
          initialVehicle: const <String, dynamic>{},
          vehicles: profile.vehicles,
          activeVehicleIndex: profile.activeVehicleIndex,
          saveMode: _VehicleSaveMode.addNew,
          onSaved: () {
            if (!mounted) return;
            ScaffoldMessenger.of(pageContext).showSnackBar(
              const SnackBar(content: Text('Car added and selected.')),
            );
          },
        );
      },
    );
  }

  Future<void> setActiveVehicle(
    int index,
    List<Map<String, dynamic>> vehicles,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || index < 0 || index >= vehicles.length) return;

    final activeVehicle = Map<String, dynamic>.from(vehicles[index]);
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'vehicle': activeVehicle,
      'vehicles': vehicles,
      'activeVehicleIndex': index,
    }, SetOptions(merge: true));
  }

  void showContributorsFrame() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _TopContributorsPage(),
      ),
    );
  }

  void showNotificationInbox() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _NotificationInboxPage(),
      ),
    );
  }

  void showMyContributions() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _MyContributionsPage(),
      ),
    );
  }

  Stream<int> unreadNotificationCountStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream<int>.value(0);

    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  void showAdminDashboard(
    BuildContext profileContext,
    UserProfileSummary profile,
  ) {
    if (!profile.isAdmin) return;

    Navigator.of(profileContext).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _AdminDashboardPage(
          onChanged: () async {
            await mapKey.currentState?.refreshPriceMarkersFromFirestore();
          },
        ),
      ),
    );
  }

  Future<UserProfileSummary> loadProfileSummary(User user) async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final reportsSnapshot = await FirebaseFirestore.instance
        .collection('priceReports')
        .where('userId', isEqualTo: user.uid)
        .get();
    final userData = userDoc.data() ?? <String, dynamic>{};
    final vehicleData = userData['vehicle'];
    final vehicle = vehicleData is Map<String, dynamic>
        ? Map<String, dynamic>.from(vehicleData)
        : <String, dynamic>{};
    final vehicles = _profileVehicles(userData, vehicle);
    final activeVehicleIndex = _activeVehicleIndex(
      userData['activeVehicleIndex'],
      vehicles.length,
    );
    final activeVehicle = vehicles.isEmpty
        ? vehicle
        : vehicles[activeVehicleIndex];
    DateTime? lastReportAt;
    var verifiedReportCount = 0;

    for (final doc in reportsSnapshot.docs) {
      final data = doc.data();
      if (_stringField(data, 'status', fallback: 'pending') != 'verified') {
        continue;
      }
      verifiedReportCount += 1;
      final createdAt = _dateTimeField(data, 'createdAt');
      if (createdAt == null) continue;
      if (lastReportAt == null || createdAt.isAfter(lastReportAt)) {
        lastReportAt = createdAt;
      }
    }

    final feedbackByReportId = await loadFeedbackAggregatesByReportId();
    final experience = await buildContributorExperienceForUser(
      contributorId: user.uid,
      feedbackByReportId: feedbackByReportId,
    );

    return UserProfileSummary(
      displayName: _stringField(
        userData,
        'displayName',
        fallback: user.displayName ?? 'PumpScout User',
      ),
      email: _stringField(userData, 'email', fallback: user.email ?? ''),
      vehicle: activeVehicle,
      vehicles: vehicles,
      activeVehicleIndex: activeVehicleIndex,
      reportCount: verifiedReportCount,
      role: _stringField(userData, 'role', fallback: 'user'),
      lastReportAt: lastReportAt,
      experience: experience,
    );
  }

  List<Map<String, dynamic>> _profileVehicles(
    Map<String, dynamic> userData,
    Map<String, dynamic> fallbackVehicle,
  ) {
    final rawVehicles = userData['vehicles'];
    final vehicles = <Map<String, dynamic>>[];

    if (rawVehicles is List) {
      for (final item in rawVehicles) {
        if (item is Map) {
          vehicles.add(Map<String, dynamic>.from(item));
        }
      }
    }

    if (vehicles.isEmpty && fallbackVehicle.isNotEmpty) {
      vehicles.add(Map<String, dynamic>.from(fallbackVehicle));
    }

    return vehicles;
  }

  int _activeVehicleIndex(dynamic value, int vehicleCount) {
    final index = value is int ? value : 0;
    if (vehicleCount <= 0) return 0;
    if (index < 0 || index >= vehicleCount) return 0;
    return index;
  }

  Widget _profileHeader(BuildContext context, UserProfileSummary profile) {
    final accent = _psActionColor(context);
    final experience = profile.experience;
    final progressColor = _psLevelProgressColor(experience.progress);
    final lastReport = profile.lastReportAt == null
        ? 'None'
        : _formatDateTime(profile.lastReportAt!);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _psPanelColor(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _psBorderColor(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: _psIsDark(context) ? 0.18 : 0.06,
            ),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.10),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.28),
                        width: 2,
                      ),
                    ),
                    child: Icon(Icons.person_rounded, color: accent, size: 46),
                  ),
                  Positioned(
                    right: -2,
                    bottom: 1,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _psPanelColor(context),
                        shape: BoxShape.circle,
                        border: Border.all(color: _psBorderColor(context)),
                      ),
                      child: Icon(
                        Icons.camera_alt_outlined,
                        color: accent,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: _psPrimaryTextColor(context),
                            letterSpacing: -0.4,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.isAdmin
                                ? 'PumpScout Admin'
                                : 'PumpScout Contributor',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _psMutedTextColor(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(Icons.verified_rounded, color: accent, size: 17),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Level ${experience.level}  •  ${experience.title}',
                        style: TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '${experience.xp} XP',
                style: TextStyle(
                  color: _psPrimaryTextColor(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                '${experience.xpToNextLevel} XP to next level',
                style: TextStyle(
                  color: _psMutedTextColor(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: experience.progress,
              backgroundColor: _psIsDark(context)
                  ? _psDarkBorder
                  : progressColor.withValues(alpha: 0.14),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: _psSoftPanelColor(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _psBorderColor(context)),
            ),
            child: Row(
              children: [
                _profileHeroStat(
                  context,
                  icon: Icons.local_gas_station_outlined,
                  value: '${profile.reportCount}',
                  label: 'Price reports',
                  color: accent,
                ),
                _profileStatDivider(context),
                _profileHeroStat(
                  context,
                  icon: Icons.history_rounded,
                  value: lastReport,
                  label: 'Last report',
                  color: const Color(0xFF7C3AED),
                ),
                _profileStatDivider(context),
                _profileHeroStat(
                  context,
                  icon: Icons.emoji_events_outlined,
                  value: experience.title,
                  label: 'Contributor',
                  color: const Color(0xFFF59E0B),
                ),
                _profileStatDivider(context),
                _profileHeroStat(
                  context,
                  icon: Icons.verified_user_outlined,
                  value: 'Verified',
                  label: 'Account',
                  color: const Color(0xFF059669),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeVehicleCard(
    BuildContext context,
    String vehicleName,
    Map<String, dynamic> vehicle,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _psSoftPanelColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _psIsDark(context)
              ? _psBorderColor(context)
              : const Color(0xFF2563EB).withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _psDecorativeColor(
                context,
                const Color(0xFF2563EB),
              ).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.directions_car,
              color: _psDecorativeColor(context, const Color(0xFF2563EB)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Currently using',
                  style: TextStyle(
                    color: _psMutedTextColor(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  vehicleName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _psPrimaryTextColor(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    _profileValue(
                      vehicle['preferredFuelType'],
                      fallback: 'Fuel not set',
                    ),
                    _profileValue(vehicle['wheels'], fallback: 'Type not set'),
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _psMutedTextColor(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _psPanelColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _psBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _psActionColor(context).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _psActionColor(context), size: 20),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: _psPrimaryTextColor(context),
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _profileHeroStat(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    final displayColor = _psDecorativeColor(context, color);
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: displayColor.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: displayColor, size: 19),
          ),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _psPrimaryTextColor(context),
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _psMutedTextColor(context),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileStatDivider(BuildContext context) {
    return Container(width: 1, height: 54, color: _psBorderColor(context));
  }

  Widget _profileVehicleDetail(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final displayColor = _psDecorativeColor(context, color);
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: displayColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: displayColor, size: 20),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _psMutedTextColor(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _psPrimaryTextColor(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _profileInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                color: _psMutedTextColor(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: _psPrimaryTextColor(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileMetricCard(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _psSoftPanelColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _psBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: _psMutedTextColor(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: _psPrimaryTextColor(context),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> searchDestination() async {
    final query = destinationController.text.trim();
    if (query.length < 3) {
      setState(() {
        destinationSuggestions = [];
        selectedDestination = null;
        isSearchingDestination = false;
      });
      return;
    }

    setState(() {
      isSearchingDestination = true;
      selectedDestination = null;
    });

    final results = await fetchPlaceSuggestions(query);
    if (!mounted) return;

    setState(() {
      destinationSuggestions = results;
      isSearchingDestination = false;
    });
  }

  void selectDestination(DestinationPlace place) {
    setState(() {
      selectedDestination = place;
      destinationController.text = place.name;
      destinationSuggestions = [];
    });
  }

  Future<void> navigateToSelectedDestination() async {
    final destination = selectedDestination;
    if (destination == null) {
      await searchDestination();
      return;
    }

    setState(() {
      activeHomeRoutePlace = destination;
    });

    await showExpandedMap(
      afterOpen: (mapState) =>
          mapState.showRouteToPlace(destination, startNavigation: true),
    );
  }

  Future<void> analyzeCheapestGasDetour() async {
    final destination = selectedDestination;
    if (destination == null) {
      await searchDestination();
      return;
    }

    await showExpandedMap(
      afterOpen: (mapState) => mapState.showCheapestDetourAnalysis(destination),
    );
  }

  Future<void> showDestinationSearchSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> runSearch() async {
              setSheetState(() {
                isSearchingDestination = true;
              });
              await searchDestination();
              if (sheetContext.mounted) setSheetState(() {});
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                4,
                16,
                18 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Search destination',
                    style: Theme.of(sheetContext).textTheme.titleMedium
                        ?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _psPrimaryTextColor(sheetContext),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose a result, then press Navigate.',
                    style: TextStyle(
                      color: _psMutedTextColor(sheetContext),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: destinationController,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => runSearch(),
                    decoration: InputDecoration(
                      hintText: 'Search station, location...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: isSearchingDestination
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : IconButton(
                              tooltip: 'Search',
                              onPressed: runSearch,
                              icon: const Icon(Icons.arrow_forward),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (destinationSuggestions.isNotEmpty)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight:
                            MediaQuery.of(sheetContext).size.height * 0.34,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: destinationSuggestions.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final place = destinationSuggestions[index];
                          final isSelected =
                              selectedDestination?.name == place.name &&
                              selectedDestination?.lat == place.lat &&
                              selectedDestination?.lng == place.lng;
                          return ListTile(
                            dense: true,
                            selected: isSelected,
                            leading: Icon(
                              isSelected
                                  ? Icons.check_circle
                                  : Icons.place_outlined,
                              color: isSelected
                                  ? const Color(0xFF2563EB)
                                  : null,
                            ),
                            title: Text(
                              place.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              place.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              selectDestination(place);
                              setSheetState(() {});
                            },
                          );
                        },
                      ),
                    ),
                  if (!isSearchingDestination &&
                      destinationController.text.trim().length >= 3 &&
                      destinationSuggestions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'No results yet. Try a more specific Davao location.',
                        style: TextStyle(
                          color: _psMutedTextColor(sheetContext),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: selectedDestination == null
                          ? null
                          : () async {
                              Navigator.of(sheetContext).pop();
                              await navigateToSelectedDestination();
                            },
                      icon: const Icon(Icons.navigation),
                      label: const Text('Navigate'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<List<StationMarkerDetails>> loadHomeStationDetails() async {
    final stations = await fetchStationPrices();
    final details = stations
        .where((station) => station.lat != 0 && station.lng != 0)
        .map(
          (station) => StationMarkerDetails(
            name: station.name,
            brand: station.brand,
            lat: station.lat,
            lng: station.lng,
            distanceMeters: null,
            price: station,
          ),
        )
        .toList();

    details.sort((a, b) {
      final aPrice = _homeLowestPrice(a.price);
      final bPrice = _homeLowestPrice(b.price);
      return (aPrice ?? double.infinity).compareTo(bPrice ?? double.infinity);
    });
    return details;
  }

  Future<List<_HomeFuelInsight>> loadHomeFuelInsights() async {
    final details = await loadHomeStationDetails();
    final stats = await RegionalPriceModel.load();
    final insights = <_HomeFuelInsight>[];

    for (final station in details.take(12)) {
      final price = station.price;
      if (price == null) continue;

      final fuelTypes = <String>[
        if (price.diesel != null) 'diesel',
        if (price.gasoline != null) 'gasoline',
        if (price.premium != null) 'premium',
      ];

      for (final fuelType in fuelTypes) {
        final currentPrice = _homeFuelPrice(price, fuelType);
        if (currentPrice == null) continue;

        FuelPriceForecast? forecast;
        try {
          final reports = await fetchPriceReports(station);
          forecast = await TrainedPriceForecastService.forecastFuelPrice(
            reports: reports,
            station: station,
            fuelType: fuelType,
            regionalStats: stats,
          );
          forecast ??= forecastFuelPrice(
            reports,
            fuelType,
            regionalStats: stats,
          );
        } catch (error) {
          debugPrint('Home forecast load failed: $error');
        }

        if (forecast == null) continue;

        insights.add(
          _HomeFuelInsight(
            station: station,
            fuelType: fuelType,
            currentPrice: currentPrice,
            predictedPrice: forecast.predictedPrice,
            confidencePercent: forecast.confidencePercent,
            history: forecast.history,
            hasForecast: true,
          ),
        );
      }
    }

    return insights;
  }

  double? _homeFuelPrice(StationPrice price, String fuelType) {
    return switch (fuelType) {
      'diesel' => price.diesel,
      'premium' => price.premium,
      _ => price.gasoline,
    };
  }

  double? _homeLowestPrice(StationPrice? price) {
    if (price == null) return null;
    final values = [
      price.gasoline,
      price.diesel,
      price.premium,
    ].whereType<double>().where((value) => value > 0).toList();
    if (values.isEmpty) return null;
    return values.reduce(math.min);
  }

  Future<void> showExpandedMap({
    Future<void> Function(_MapContainerState mapState)? afterOpen,
  }) async {
    if (isExpandedMapOpen) return;
    setState(() => isExpandedMapOpen = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final expandedMapKey = GlobalKey<_MapContainerState>();
    final routeToRestore = activeHomeRoutePlace;
    final actionToRun =
        afterOpen ??
        (routeToRestore == null
            ? null
            : (_MapContainerState mapState) => mapState.showRouteToPlace(
                routeToRestore,
                startNavigation: true,
              ));

    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) {
            if (actionToRun != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _runExpandedMapAction(expandedMapKey, actionToRun);
              });
            }

            return Scaffold(
              backgroundColor: _psPageColor(context),
              appBar: AppBar(
                title: const Text('PumpScout Map'),
                backgroundColor: _psPageColor(context),
                foregroundColor: _psPrimaryTextColor(context),
                elevation: 0,
              ),
              body: MapContainer(
                key: expandedMapKey,
                isDarkMode: widget.isDarkMode,
                onRouteCancelled: clearHomeRoute,
              ),
            );
          },
        ),
      );
    } finally {
      if (mounted) setState(() => isExpandedMapOpen = false);
    }
  }

  void clearHomeRoute() {
    if (!mounted) return;
    setState(() {
      activeHomeRoutePlace = null;
      selectedDestination = null;
      destinationController.clear();
    });
  }

  Future<void> _runExpandedMapAction(
    GlobalKey<_MapContainerState> expandedMapKey,
    Future<void> Function(_MapContainerState mapState) action,
  ) async {
    for (var attempt = 0; attempt < 24; attempt++) {
      final mapState = expandedMapKey.currentState;
      if (mapState != null && mapState.mapboxMap != null && mapState.mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (mapState.mounted) {
          await action(mapState);
        }
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: _psPageColor(context),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _homeContent(context)),
            Positioned(
              left: 18,
              right: 18,
              bottom: 12,
              child: _homeBottomNav(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _homeContent(BuildContext context) {
    try {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 108),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _homeHeader(context),
            const SizedBox(height: 18),
            _homeSearchBar(context),
            const SizedBox(height: 18),
            _homeShortcutPanel(context),
            const SizedBox(height: 18),
            _fuelInsightsSection(context),
            const SizedBox(height: 18),
            _nearbyMapPreview(context),
            const SizedBox(height: 18),
            _cheapestNearYouSection(context),
          ],
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('HomePage build failed: $error\n$stackTrace');
      return _homeBuildError(context, error);
    }
  }

  Widget _homeBuildError(BuildContext context, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFE94B5A), size: 44),
            const SizedBox(height: 12),
            Text(
              'Home page could not load',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _psPrimaryTextColor(context),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(color: _psMutedTextColor(context), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _homeHeader(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim().split(' ').first
        : 'PumpScout';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greetingText(),
                style: TextStyle(
                  color: _psMutedTextColor(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _psPrimaryTextColor(context),
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Save more on every trip',
                style: TextStyle(
                  color: _psMutedTextColor(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        _notificationButton(context),
        const SizedBox(width: 8),
        InkWell(
          onTap: showProfileSheet,
          borderRadius: BorderRadius.circular(999),
          child: CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFEAF2FF),
            child: Icon(
              Icons.person_outline,
              color: _psPrimaryTextColor(context),
              size: 26,
            ),
          ),
        ),
      ],
    );
  }

  String _greetingText() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  Widget _notificationButton(BuildContext context) {
    return StreamBuilder<int>(
      stream: unreadNotificationCountStream(),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: _psPanelColor(context),
              elevation: 5,
              shadowColor: Colors.black.withValues(alpha: 0.08),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Inbox',
                onPressed: showNotificationInbox,
                icon: const Icon(Icons.notifications_none),
              ),
            ),
            if (unreadCount > 0)
              Positioned(
                top: -2,
                right: -1,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: const BoxDecoration(
                    color: _psRed,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    unreadCount > 9 ? '9+' : '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _homeSearchBar(BuildContext context) {
    return Material(
      color: _psPanelColor(context),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: showDestinationSearchSheet,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Icon(Icons.search, color: _psMutedTextColor(context), size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  selectedDestination?.name ?? 'Search station, location...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _psMutedTextColor(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeShortcutPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: _homeCardDecoration(context),
      child: Row(
        children: [
          _buildMenuCard(
            title: 'Nearby',
            imagePath: 'assets/images/map.png',
            color: const Color(0xFF2563EB),
            onTap: () => showExpandedMap(
              afterOpen: (mapState) async {
                await mapState.moveToCurrentLocation();
                mapState.showNearbyStationsPanel();
              },
            ),
          ),
          _buildMenuCard(
            title: 'Cheapest',
            imagePath: 'assets/images/cheapest.png',
            color: const Color(0xFF16A34A),
            onTap: () => showExpandedMap(
              afterOpen: (mapState) async {
                mapState.showCheapestStationsPanel();
              },
            ),
          ),
          _buildMenuCard(
            title: 'Calculator',
            imagePath: 'assets/images/calculator.png',
            color: const Color(0xFFF59E0B),
            onTap: () => showFuelCalculatorPanel(context),
          ),
          _buildMenuCard(
            title: 'Saved',
            imagePath: 'assets/images/placeholder.png',
            color: const Color(0xFFE11D48),
            onTap: () => showExpandedMap(
              afterOpen: (mapState) async {
                mapState.showSavedStationsPanel();
              },
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _homeCardDecoration(BuildContext context) {
    return BoxDecoration(
      color: _psPanelColor(context),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _psBorderColor(context)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  Widget _buildMenuCard({
    required String title,
    required String imagePath,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color.withValues(alpha: 0.86), color],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.32),
                      blurRadius: 14,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(13),
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.local_gas_station,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _psPrimaryTextColor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fuelInsightsSection(BuildContext context) {
    return FutureBuilder<List<_HomeFuelInsight>>(
      future: fuelInsightsFuture,
      builder: (context, snapshot) {
        final insights = snapshot.data ?? const <_HomeFuelInsight>[];
        return Container(
          height: 260,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: _psIsDark(context)
                  ? const [_psPanelBlue, _psSoftPanel]
                  : const [Color(0xFFEAF4FF), Color(0xFFF7FBFF)],
            ),
            border: Border.all(
              color: _psIsDark(context)
                  ? _psDarkBorder
                  : const Color(0xFF93C5FD),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withValues(alpha: 0.10),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: snapshot.connectionState == ConnectionState.waiting
              ? const Center(child: CircularProgressIndicator())
              : insights.isEmpty
              ? _emptyFuelInsights(context)
              : PageView.builder(
                  controller: fuelInsightsController,
                  itemBuilder: (context, index) {
                    final insight = insights[index % insights.length];
                    return _fuelInsightCard(context, insight);
                  },
                ),
        );
      },
    );
  }

  Widget _emptyFuelInsights(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, 'Fuel Forecast', icon: Icons.insights),
          const Spacer(),
          Text(
            'No forecast is available yet.',
            style: TextStyle(
              color: _psPrimaryTextColor(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A station needs at least three verified price reports for the same fuel.',
            style: TextStyle(color: _psMutedTextColor(context)),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                fuelInsightsFuture = loadHomeFuelInsights();
              });
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry forecast'),
          ),
        ],
      ),
    );
  }

  Widget _fuelInsightCard(BuildContext context, _HomeFuelInsight insight) {
    final change = insight.predictedPrice - insight.currentPrice;
    final isDown = change < 0;
    final changeColor = isDown ? const Color(0xFF16A34A) : _psRed;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            flex: 9,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(
                  context,
                  'Fuel Forecast',
                  logoPath: _stationLogoAsset(insight.brandLabel),
                ),
                const SizedBox(height: 8),
                Text(
                  insight.stationTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _psPrimaryTextColor(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  insight.brandLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _psMutedTextColor(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  insight.fuelLabel.toUpperCase(),
                  style: TextStyle(
                    color: _psMutedTextColor(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'PHP ${insight.currentPrice.toStringAsFixed(2)}/L',
                    style: TextStyle(
                      color: _psPrimaryTextColor(context),
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      isDown ? Icons.arrow_downward : Icons.arrow_upward,
                      color: changeColor,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${change.abs().toStringAsFixed(2)} next week',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: changeColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 8,
            child: Column(
              children: [
                Expanded(
                  child: CustomPaint(
                    painter: _HomeInsightChartPainter(
                      values: insight.chartValues,
                      color: const Color(0xFF2563EB),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F8EE),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Prediction',
                              style: TextStyle(
                                color: Color(0xFF334155),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'PHP ${insight.predictedPrice.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isDown ? Icons.trending_down : Icons.trending_up,
                        color: const Color(0xFF16A34A),
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(
    BuildContext context,
    String title, {
    IconData icon = Icons.local_gas_station,
    String? logoPath,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: logoPath == null ? const Color(0xFF2563EB) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: logoPath == null
                ? null
                : Border.all(color: _psBorderColor(context)),
            boxShadow: logoPath == null
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          padding: EdgeInsets.all(logoPath == null ? 0 : 5),
          child: logoPath == null
              ? Icon(icon, color: Colors.white, size: 22)
              : Image.asset(
                  logoPath,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) {
                    return Icon(icon, color: Colors.white, size: 22);
                  },
                ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _psPrimaryTextColor(context),
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _nearbyMapPreview(BuildContext context) {
    return Container(
      height: 360,
      decoration: _homeCardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Map',
                    style: TextStyle(
                      color: _psPrimaryTextColor(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: showExpandedMap,
                  icon: const Icon(Icons.open_in_full, size: 16),
                  label: const Text('Expand Map'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [Positioned.fill(child: _homeMapPreviewBody(context))],
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeMapPreviewBody(BuildContext context) {
    if (accessToken.trim().isEmpty) {
      return Container(
        color: _psSoftPanelColor(context),
        padding: const EdgeInsets.all(18),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.map_outlined,
                color: _psMutedTextColor(context),
                size: 34,
              ),
              const SizedBox(height: 8),
              Text(
                'Map token missing',
                style: TextStyle(
                  color: _psPrimaryTextColor(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Run the app with MAPBOX_ACCESS_TOKEN to load the map.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _psMutedTextColor(context),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _liveMiniMapPreview(context);
  }

  Widget _liveMiniMapPreview(BuildContext context) {
    if (isExpandedMapOpen) {
      return ColoredBox(color: _psSoftPanelColor(context));
    }

    return Stack(
      children: [
        Positioned.fill(
          child: MapContainer(
            key: mapKey,
            isDarkMode: widget.isDarkMode,
            showRecenterControl: false,
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Material(
            color: Colors.white,
            elevation: 4,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Locate me',
              onPressed: () => mapKey.currentState?.moveToCurrentLocation(),
              icon: const Icon(Icons.my_location, color: Color(0xFF2563EB)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cheapestNearYouSection(BuildContext context) {
    return FutureBuilder<List<StationMarkerDetails>>(
      future: cheapestStationsFuture,
      builder: (context, snapshot) {
        final stations = (snapshot.data ?? const <StationMarkerDetails>[])
            .where((station) => _homeLowestPrice(station.price) != null)
            .take(3)
            .toList();

        return Container(
          decoration: _homeCardDecoration(context),
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cheapest Around Davao',
                      style: TextStyle(
                        color: _psPrimaryTextColor(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => showExpandedMap(
                      afterOpen: (mapState) async {
                        mapState.showCheapestStationsPanel();
                      },
                    ),
                    child: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (stations.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'No station prices available yet.',
                    style: TextStyle(color: _psMutedTextColor(context)),
                  ),
                )
              else
                for (final station in stations)
                  _cheapestStationTile(context, station),
            ],
          ),
        );
      },
    );
  }

  Widget _cheapestStationTile(
    BuildContext context,
    StationMarkerDetails station,
  ) {
    final price = _homeLowestPrice(station.price)!;
    final brand = station.brand.trim().isEmpty ? station.name : station.brand;
    return InkWell(
      onTap: () => showExpandedMap(
        afterOpen: (mapState) async {
          mapState.showStationDetailSheet(station);
        },
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _psBorderColor(context)),
        ),
        child: Row(
          children: [
            _stationBrandLogoBadge(context, brand),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    station.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _psPrimaryTextColor(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    brand,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _psMutedTextColor(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'PHP ${price.toStringAsFixed(2)}/L',
                  style: const TextStyle(
                    color: Color(0xFF16A34A),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 32,
                  child: FilledButton.icon(
                    onPressed: () => showExpandedMap(
                      afterOpen: (mapState) => mapState.showInAppRoute(
                        station,
                        closeCurrentSheet: false,
                      ),
                    ),
                    icon: const Icon(Icons.navigation, size: 15),
                    label: const Text(
                      'Navigate',
                      style: TextStyle(fontSize: 11),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      backgroundColor: _psFilledActionColor(context),
                      foregroundColor: Colors.white,
                      side: _psIsDark(context)
                          ? BorderSide(color: _psBorderColor(context))
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stationBrandLogoBadge(BuildContext context, String brand) {
    final logoPath = _stationLogoAsset(brand);
    return Container(
      width: 44,
      height: 44,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: _psBorderColor(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: logoPath == null
          ? Center(
              child: Text(
                brand.characters.take(1).toString().toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            )
          : ClipOval(
              child: Image.asset(
                logoPath,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) {
                  return Center(
                    child: Text(
                      brand.characters.take(1).toString().toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  String? _stationLogoAsset(String brand) {
    final normalized = brand.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normalized.contains('shell')) return 'assets/images/Shell_logo.png';
    if (normalized.contains('petron')) return 'assets/images/petron_logo.jpg';
    if (normalized.contains('seaoil')) return 'assets/images/seaOil_Logo.png';
    if (normalized.contains('caltex') || normalized.contains('caltext')) {
      return 'assets/images/caltext_logo.jpg';
    }
    if (normalized.contains('unioil')) return 'assets/images/uniOil_logo.png';
    if (normalized.contains('mygas')) return 'assets/images/myGas_logo.png';
    if (normalized.contains('phoenix')) return 'assets/images/phoenix_logo.jpg';
    return null;
  }

  Widget _homeBottomNav(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _psPanelColor(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _psBorderColor(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _bottomNavItem(context, Icons.home_rounded, 'Home', () {}),
          _bottomNavItem(
            context,
            Icons.receipt_long_outlined,
            'Rank',
            showContributorsFrame,
          ),
          _bottomNavItem(
            context,
            Icons.map_outlined,
            'Explore',
            showExpandedMap,
          ),
          _bottomNavItem(
            context,
            Icons.forum_outlined,
            'Community',
            showCommunityContributionsPage,
          ),
          _bottomNavItem(
            context,
            Icons.person_outline,
            'Profile',
            showProfileSheet,
          ),
        ],
      ),
    );
  }

  Widget _bottomNavItem(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) {
    final color = active ? const Color(0xFF2563EB) : _psMutedTextColor(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: active ? 27 : 23),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: active ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeFuelInsight {
  const _HomeFuelInsight({
    required this.station,
    required this.fuelType,
    required this.currentPrice,
    required this.predictedPrice,
    required this.history,
    required this.hasForecast,
    this.confidencePercent,
  });

  final StationMarkerDetails station;
  final String fuelType;
  final double currentPrice;
  final double predictedPrice;
  final List<double> history;
  final bool hasForecast;
  final int? confidencePercent;

  String get fuelLabel {
    return switch (fuelType) {
      'diesel' => 'Diesel',
      'premium' => 'Premium',
      _ => 'Regular',
    };
  }

  String get stationTitle {
    final brand = station.brand.trim();
    if (brand.isEmpty || brand == station.name) return station.name;
    return '$brand - ${station.name}';
  }

  String get brandLabel {
    final brand = station.brand.trim();
    return brand.isEmpty ? 'Fuel station' : brand;
  }

  List<double> get chartValues {
    if (history.length >= 2) return [...history, predictedPrice];
    return [currentPrice, (currentPrice + predictedPrice) / 2, predictedPrice];
  }
}

class _HomeInsightChartPainter extends CustomPainter {
  const _HomeInsightChartPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = math.max(maxValue - minValue, 1);
    final topPadding = size.height * 0.12;
    final bottomPadding = size.height * 0.22;
    final chartHeight = size.height - topPadding - bottomPadding;

    final gridPaint = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final baselineY = topPadding + chartHeight * 0.72;
    canvas.drawLine(
      Offset(0, baselineY),
      Offset(size.width, baselineY),
      gridPaint,
    );

    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? size.width / 2
          : (index / (values.length - 1)) * size.width;
      final normalized = (values[index] - minValue) / range;
      final y = topPadding + chartHeight * (1 - normalized);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? size.width / 2
          : (index / (values.length - 1)) * size.width;
      final normalized = (values[index] - minValue) / range;
      final y = topPadding + chartHeight * (1 - normalized);
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HomeInsightChartPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}
