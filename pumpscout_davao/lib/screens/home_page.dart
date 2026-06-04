part of '../main.dart';

const _psDeepBlue = ui.Color.fromARGB(255, 0, 0, 0);
const _psPanelBlue = Color(0xFF0E2238);
const _psSoftPanel = Color(0xFF132A43);
const _psRed = Color(0xFFE94B5A);
const _psMutedText = Color(0xB8FFFFFF);
const _psLightPanel = Color(0xFFFFFFFF);
const _psLightSoftPanel = Color(0xFFF6F8FB);
const _psLightMutedText = Color(0xFF5F6F85);
const _psLightBorder = Color(0xFFE3E8EF);

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
    _psIsDark(context) ? Colors.white.withValues(alpha: 0.08) : _psLightBorder;

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
  List<DestinationPlace> destinationSuggestions = [];
  DestinationPlace? selectedDestination;
  bool isSearchingDestination = false;
  bool isDestinationSearchOpen = false;

  @override
  void dispose() {
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
                      20,
                      18,
                      20,
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
                            const SizedBox(height: 12),
                            _profileInfoRow(
                              context,
                              'Model',
                              _profileValue(
                                vehicle['name'],
                                fallback: 'Not set',
                              ),
                            ),
                            _profileInfoRow(
                              context,
                              'Type',
                              _profileValue(
                                vehicle['wheels'],
                                fallback: 'Not set',
                              ),
                            ),
                            _profileInfoRow(
                              context,
                              'Use',
                              _profileValue(
                                vehicle['use'],
                                fallback: 'Not set',
                              ),
                            ),
                            _profileInfoRow(
                              context,
                              'Fuel',
                              _profileValue(
                                vehicle['preferredFuelType'],
                                fallback: 'Not set',
                              ),
                            ),
                            _profileInfoRow(
                              context,
                              'Consumption',
                              kmPerLiter == null
                                  ? 'Not set'
                                  : '${kmPerLiter.toStringAsFixed(1)} km/L',
                            ),
                            _profileInfoRow(
                              context,
                              'Idle rate',
                              idleRate == null
                                  ? 'Not set'
                                  : '${idleRate.toStringAsFixed(2)} L/hr',
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
                                      foregroundColor: _psPrimaryTextColor(
                                        context,
                                      ),
                                      side: const BorderSide(color: _psRed),
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
                                      backgroundColor: _psRed,
                                      foregroundColor: Colors.white,
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
                              activeThumbColor: _psRed,
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
                                    backgroundColor: _psRed,
                                    foregroundColor: Colors.white,
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
                                  foregroundColor: _psPrimaryTextColor(context),
                                  side: const BorderSide(color: _psRed),
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
                              backgroundColor: _psRed,
                              foregroundColor: Colors.white,
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
    final currentUser = FirebaseAuth.instance.currentUser;

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) {
          return FutureBuilder<List<ContributorSummary>>(
            future: loadContributorSummaries(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  appBar: _FullScreenSheetAppBar(title: 'Top Contributors'),
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.hasError) {
                debugPrint('Contributor load failed: ${snapshot.error}');
              }

              final contributors =
                  snapshot.data ?? const <ContributorSummary>[];

              return Scaffold(
                appBar: const _FullScreenSheetAppBar(title: 'Top Contributors'),
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Text(
                            'Most Contributor Users',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Divider(thickness: 2, color: Colors.black),
                        if (snapshot.hasError)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Center(
                              child: Text(
                                'Could not load contributors.\n${snapshot.error}',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        else if (contributors.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Center(
                              child: Text('No registered users yet.'),
                            ),
                          )
                        else
                          Expanded(
                            child: ListView.separated(
                              itemCount: contributors.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 4),
                              itemBuilder: (context, index) {
                                final contributor = contributors[index];
                                return _contributorRow(
                                  contributor,
                                  rank: index + 1,
                                  isCurrentUser:
                                      currentUser != null &&
                                      contributor.userId == currentUser.uid,
                                );
                              },
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

  Future<List<ContributorSummary>> loadContributorSummaries() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final contributors = <String, _ContributorAccumulator>{};

    if (currentUser != null) {
      contributors[currentUser.uid] = _ContributorAccumulator(
        currentUser.displayName?.trim().isNotEmpty == true
            ? currentUser.displayName!.trim()
            : currentUser.email ?? 'You',
        reportCount: 0,
      );
    }

    try {
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();

      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final userId = _stringField(data, 'uid', fallback: doc.id);
        final displayName = _stringField(
          data,
          'displayName',
          fallback: _stringField(data, 'email', fallback: 'PumpScout User'),
        );

        contributors[userId] = _ContributorAccumulator(
          displayName,
          reportCount: contributors[userId]?.reportCount ?? 0,
        );
      }
    } catch (error) {
      debugPrint('Users leaderboard load failed: $error');
    }

    try {
      final reportsSnapshot = await FirebaseFirestore.instance
          .collection('priceReports')
          .where('status', isEqualTo: 'verified')
          .get();

      for (final doc in reportsSnapshot.docs) {
        final data = doc.data();
        final userId = _stringField(
          data,
          'userId',
          fallback: _stringField(data, 'userEmail', fallback: 'anonymous'),
        );
        final displayName = _stringField(
          data,
          'userDisplayName',
          fallback: _stringField(
            data,
            'userEmail',
            fallback: userId == 'anonymous'
                ? 'Anonymous user'
                : 'PumpScout User',
          ),
        );

        contributors.update(userId, (item) {
          item.reportCount += 1;
          return item;
        }, ifAbsent: () => _ContributorAccumulator(displayName));
      }
    } catch (error) {
      debugPrint('Price report leaderboard load failed: $error');
    }

    final summaries =
        contributors.entries
            .map(
              (entry) => ContributorSummary(
                userId: entry.key,
                name: entry.value.name,
                reportCount: entry.value.reportCount,
              ),
            )
            .toList()
          ..sort((a, b) {
            final countCompare = b.reportCount.compareTo(a.reportCount);
            if (countCompare != 0) return countCompare;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });

    return summaries;
  }

  Widget _contributorRow(
    ContributorSummary contributor, {
    required int rank,
    required bool isCurrentUser,
  }) {
    final rowContent = Row(
      children: [
        SizedBox(width: 54, child: _rankBadge(rank)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            isCurrentUser ? '${contributor.name} (you)' : contributor.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: isCurrentUser ? FontWeight.w800 : FontWeight.w600,
              color: isCurrentUser ? Colors.white : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${contributor.reportCount}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isCurrentUser ? Colors.white : const Color(0xFF1E8E3E),
          ),
        ),
      ],
    );

    if (!isCurrentUser) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: rowContent,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF7457F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: rowContent,
    );
  }

  Widget _rankBadge(int rank) {
    final asset = switch (rank) {
      1 => 'assets/images/11st.png',
      2 => 'assets/images/22nd image.png',
      3 => 'assets/images/33rd.png',
      _ => null,
    };

    if (asset != null) {
      return Image.asset(
        asset,
        width: 48,
        height: 48,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Text(
          '$rank',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      );
    }

    return Text(
      '$rank',
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
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
    final trustBadge = await buildContributorTrustBadgeForUser(
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
      trustBadge: trustBadge,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _psPanelColor(context),
        borderRadius: BorderRadius.circular(18),
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
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _psRed.withValues(alpha: 0.12),
              border: Border.all(color: _psRed.withValues(alpha: 0.55)),
            ),
            child: Icon(
              Icons.person,
              color: _psIsDark(context) ? Colors.white : _psRed,
              size: 34,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: _psPrimaryTextColor(context),
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  profile.isAdmin
                      ? 'PumpScout admin account'
                      : 'PumpScout account',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ).copyWith(color: _psMutedTextColor(context)),
                ),
                const SizedBox(height: 10),
                buildContributorTrustBadgeChip(context, profile.trustBadge),
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
        border: Border.all(color: _psRed.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _psRed.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.directions_car, color: _psRed),
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
                  color: _psRed.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _psRed, size: 20),
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
    if (query.length < 3) return;

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

    await mapKey.currentState?.showRouteToPlace(destination);
  }

  Future<void> analyzeCheapestGasDetour() async {
    final destination = selectedDestination;
    if (destination == null) {
      await searchDestination();
      return;
    }

    await mapKey.currentState?.showCheapestDetourAnalysis(destination);
  }

  Widget _destinationSearchOverlay() {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final keyboardOpen = keyboardHeight > 0;

    if (!isDestinationSearchOpen) {
      return Positioned(
        left: 12,
        bottom: 12,
        child: SafeArea(
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              tooltip: 'Search destination',
              onPressed: () {
                setState(() {
                  isDestinationSearchOpen = true;
                });
              },
              icon: const Icon(Icons.search),
            ),
          ),
        ),
      );
    }

    return Positioned(
      left: 12,
      right: 12,
      top: keyboardOpen ? 12 : null,
      bottom: keyboardOpen ? null : 12,
      child: SafeArea(
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 5,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: destinationController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => searchDestination(),
                        decoration: InputDecoration(
                          hintText: 'Search destination',
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
                                  onPressed: searchDestination,
                                  icon: const Icon(Icons.arrow_forward),
                                ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Navigate',
                      onPressed: navigateToSelectedDestination,
                      icon: const Icon(Icons.navigation_outlined),
                    ),
                    IconButton(
                      tooltip: 'Compare refuel stops',
                      onPressed: analyzeCheapestGasDetour,
                      icon: const Icon(Icons.local_gas_station),
                      color: const Color(0xFF1E8E3E),
                    ),
                    IconButton(
                      tooltip: 'Close search',
                      onPressed: () {
                        setState(() {
                          isDestinationSearchOpen = false;
                          destinationSuggestions = [];
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (destinationSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: destinationSuggestions.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final place = destinationSuggestions[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.place_outlined),
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
                          onTap: () => selectDestination(place),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        title: Text(
          'PumpScout',
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        actions: [
          StreamBuilder<int>(
            stream: unreadNotificationCountStream(),
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: 'Inbox',
                    onPressed: showNotificationInbox,
                    icon: const Icon(Icons.notifications_none),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 7,
                      top: 7,
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 17,
                          minHeight: 17,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: _psRed,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            tooltip: 'Top contributors',
            onPressed: showContributorsFrame,
            icon: const Icon(Icons.emoji_events_outlined),
          ),
          IconButton(
            tooltip: 'Community contributions',
            onPressed: showCommunityContributionsPage,
            icon: const Icon(Icons.forum_outlined),
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: showProfileSheet,
            icon: const Icon(Icons.account_circle_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // Menu Grid Row converted to interactive Buttons
            Row(
              children: [
                _buildMenuCard(
                  title: 'Nearby',

                  imagePath: 'assets/images/map.png',
                  onTap: () => mapKey.currentState?.showNearbyStationsPanel(),
                ),
                _buildMenuCard(
                  title: 'Cheapest',
                  imagePath: 'assets/images/cheapest.png',
                  onTap: () => mapKey.currentState?.showCheapestStationsPanel(),
                ),
                _buildMenuCard(
                  title: 'Calculator',
                  imagePath: 'assets/images/calculator.png',
                  onTap: () => showFuelCalculatorPanel(context),
                ),
                _buildMenuCard(
                  title: 'Saved',
                  imagePath: 'assets/images/placeholder.png',
                  onTap: () => mapKey.currentState?.showSavedStationsPanel(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: MapContainer(
                        key: mapKey,
                        isDarkMode: widget.isDarkMode,
                      ),
                    ),
                  ),
                  _destinationSearchOverlay(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Updated Helper method with Image and InkWell (Button functionality)
  Widget _buildMenuCard({
    required String title,
    required String imagePath,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Card(
        elevation: 2,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.grey.shade300),
        ),
        color: Colors.white,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Replaces the emoji with an Image widget
                Image.asset(
                  imagePath,
                  height: 40,
                  width: 40,
                  fit: BoxFit.contain,
                  // Fallback if image isn't found during development
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.image, size: 40),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommunityFeedbackDialog extends StatefulWidget {
  const _CommunityFeedbackDialog({
    required this.stationName,
    this.title = 'Add comment',
  });

  final String stationName;
  final String title;

  @override
  State<_CommunityFeedbackDialog> createState() =>
      _CommunityFeedbackDialogState();
}

class _CommunityFeedbackDialogState extends State<_CommunityFeedbackDialog> {
  final controller = TextEditingController();
  String? errorText;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final comment = controller.text.trim();
    if (comment.length < 8) {
      setState(() {
        errorText = 'Please add at least 8 characters of comment.';
      });
      return;
    }

    Navigator.of(context).pop(comment);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.stationName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Share what looks accurate or needs checking.',
              border: const OutlineInputBorder(),
              errorText: errorText,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: submit, child: const Text('Submit')),
      ],
    );
  }
}

class _CommunityContributionsPage extends StatefulWidget {
  const _CommunityContributionsPage();

  @override
  State<_CommunityContributionsPage> createState() =>
      _CommunityContributionsPageState();
}

class _CommunityContributionsPageState
    extends State<_CommunityContributionsPage> {
  List<CommunityContribution> _items = const [];
  bool _isLoading = true;
  bool _isSavingReaction = false;
  String? _errorMessage;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _communityReportsSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _communityFeedbackSubscription;
  Timer? _communityRefreshDebounce;

  @override
  void initState() {
    super.initState();
    _reloadContributions();
    _startCommunityListeners();
  }

  @override
  void dispose() {
    _communityReportsSubscription?.cancel();
    _communityFeedbackSubscription?.cancel();
    _communityRefreshDebounce?.cancel();
    super.dispose();
  }

  void _startCommunityListeners() {
    _communityReportsSubscription = FirebaseFirestore.instance
        .collection('priceReports')
        .where('status', isEqualTo: 'verified')
        .snapshots()
        .listen((_) => _scheduleBackgroundCommunityRefresh());

    _communityFeedbackSubscription = FirebaseFirestore.instance
        .collection('contributionFeedback')
        .snapshots()
        .listen((_) => _scheduleBackgroundCommunityRefresh());
  }

  void _scheduleBackgroundCommunityRefresh() {
    _communityRefreshDebounce?.cancel();
    _communityRefreshDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || _isLoading) return;
      _reloadContributions(showLoading: false);
    });
  }

  Future<void> _reloadContributions({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }

    try {
      final items = await _loadCommunityContributions();
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        if (showLoading) _isLoading = false;
      });
    }
  }

  Future<List<CommunityContribution>> _loadCommunityContributions() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final snapshot = await FirebaseFirestore.instance
        .collection('priceReports')
        .where('status', isEqualTo: 'verified')
        .get();

    final docs = snapshot.docs
      ..sort((a, b) {
        final aDate = _dateTimeField(a.data(), 'createdAt') ?? DateTime(1970);
        final bDate = _dateTimeField(b.data(), 'createdAt') ?? DateTime(1970);
        return bDate.compareTo(aDate);
      });

    final feedbackByReportId = await loadFeedbackAggregatesByReportId(
      currentUserId: currentUser?.uid,
    );
    final trustCache = <String, ContributorTrustBadge>{};
    final items = <CommunityContribution>[];

    for (final doc in docs.take(40)) {
      final reportData = doc.data();
      final contributorId = _stringField(reportData, 'userId');
      final feedback =
          feedbackByReportId[doc.id] ?? const ReportFeedbackAggregate();

      if (!trustCache.containsKey(contributorId)) {
        trustCache[contributorId] = await buildContributorTrustBadgeForUser(
          contributorId: contributorId,
          feedbackByReportId: feedbackByReportId,
        );
      }

      items.add(
        CommunityContribution.fromFirestore(
          doc: doc,
          trustBadge: trustCache[contributorId]!,
          likeCount: feedback.likeCount,
          disagreeCount: feedback.disagreeCount,
          feedbackCount: feedback.feedbackCount,
          myReaction: feedback.myReaction,
          publicComments: feedback.publicComments,
        ),
      );
    }

    return items;
  }

  Future<void> saveReaction(CommunityContribution item, String reaction) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to agree, disagree, or leave a comment.'),
        ),
      );
      return;
    }
    if (_isSavingReaction) return;

    _applyOptimisticReaction(item, reaction);
    setState(() => _isSavingReaction = true);
    final feedbackId = '${item.id}_${user.uid}_reaction';
    final displayName = user.displayName?.trim();
    final authorName = displayName != null && displayName.isNotEmpty
        ? displayName
        : (user.email?.split('@').first ?? 'PumpScout user');

    try {
      final docRef = FirebaseFirestore.instance
          .collection('contributionFeedback')
          .doc(feedbackId);
      final existing = await docRef.get();
      final payload = <String, Object?>{
        'reportId': item.id,
        'type': 'reaction',
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'userDisplayName': authorName,
        'reaction': reaction,
        'comment': '',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!existing.exists) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }

      await docRef.set(payload, SetOptions(merge: true));

      if (!mounted) return;
      await _reloadContributions(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reaction failed: $error')));
    } finally {
      if (mounted) setState(() => _isSavingReaction = false);
    }
  }

  void _applyOptimisticReaction(CommunityContribution item, String reaction) {
    final updated = _withUpdatedReaction(item, reaction);
    setState(() {
      _items = [
        for (final existing in _items)
          if (existing.id == item.id) updated else existing,
      ];
    });
  }

  CommunityContribution _withUpdatedReaction(
    CommunityContribution item,
    String reaction,
  ) {
    var likeCount = item.likeCount;
    var disagreeCount = item.disagreeCount;

    if (item.myReaction == 'like') likeCount = math.max(0, likeCount - 1);
    if (item.myReaction == 'disagree') {
      disagreeCount = math.max(0, disagreeCount - 1);
    }

    if (reaction == 'like') likeCount += 1;
    if (reaction == 'disagree') disagreeCount += 1;

    return item.copyWith(
      likeCount: likeCount,
      disagreeCount: disagreeCount,
      myReaction: reaction,
    );
  }

  Future<void> promptFeedback(CommunityContribution item) async {
    final comment = await showDialog<String>(
      context: context,
      builder: (_) => _CommunityFeedbackDialog(
        stationName: item.stationName,
        title: 'Add comment',
      ),
    );
    if (comment == null || comment.trim().isEmpty) return;
    await saveComment(item, comment.trim());
  }

  Future<void> saveComment(CommunityContribution item, String comment) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to leave a comment.')),
      );
      return;
    }
    if (_isSavingReaction) return;

    setState(() => _isSavingReaction = true);
    final displayName = user.displayName?.trim();
    final authorName = displayName != null && displayName.isNotEmpty
        ? displayName
        : (user.email?.split('@').first ?? 'PumpScout user');

    final docRef = FirebaseFirestore.instance
        .collection('contributionFeedback')
        .doc();
    final optimisticComment = CommunityFeedbackComment(
      id: docRef.id,
      authorName: authorName,
      comment: comment,
      reaction: '',
      createdAt: DateTime.now(),
    );

    setState(() {
      _items = [
        for (final existing in _items)
          if (existing.id == item.id)
            existing.copyWith(
              feedbackCount: existing.feedbackCount + 1,
              myReaction: existing.myReaction,
              publicComments: [optimisticComment, ...existing.publicComments],
            )
          else
            existing,
      ];
    });

    try {
      await docRef.set({
        'reportId': item.id,
        'type': 'comment',
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'userDisplayName': authorName,
        'reaction': '',
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      await _reloadContributions(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Comment failed: $error')));
    } finally {
      if (mounted) setState(() => _isSavingReaction = false);
    }
  }

  Future<void> promptReply(
    CommunityContribution item,
    CommunityFeedbackComment entry,
  ) async {
    final reply = await showDialog<String>(
      context: context,
      builder: (_) => _CommunityFeedbackDialog(
        stationName: item.stationName,
        title: 'Reply to ${entry.authorName}',
      ),
    );
    if (reply == null || reply.trim().isEmpty) return;
    await saveReply(item, entry, reply.trim());
  }

  Future<void> saveReply(
    CommunityContribution item,
    CommunityFeedbackComment entry,
    String reply,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to reply to comments.')),
      );
      return;
    }
    if (_isSavingReaction) return;

    setState(() => _isSavingReaction = true);
    final displayName = user.displayName?.trim();
    final authorName = displayName != null && displayName.isNotEmpty
        ? displayName
        : (user.email?.split('@').first ?? 'PumpScout user');

    final docRef = FirebaseFirestore.instance
        .collection('contributionFeedback')
        .doc();
    final optimisticReply = CommunityFeedbackReply(
      authorName: authorName,
      comment: reply,
      createdAt: DateTime.now(),
    );

    setState(() {
      _items = [
        for (final existing in _items)
          if (existing.id == item.id)
            existing.copyWith(
              feedbackCount: existing.feedbackCount + 1,
              myReaction: existing.myReaction,
              publicComments: [
                for (final comment in existing.publicComments)
                  if (comment.id == entry.id)
                    CommunityFeedbackComment(
                      id: comment.id,
                      authorName: comment.authorName,
                      comment: comment.comment,
                      reaction: comment.reaction,
                      replies: [...comment.replies, optimisticReply],
                      createdAt: comment.createdAt,
                    )
                  else
                    comment,
              ],
            )
          else
            existing,
      ];
    });

    try {
      await docRef.set({
        'reportId': item.id,
        'type': 'reply',
        'parentCommentId': entry.id,
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'userDisplayName': authorName,
        'reaction': '',
        'comment': reply,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      await _reloadContributions(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reply failed: $error')));
    } finally {
      if (mounted) setState(() => _isSavingReaction = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _psPageColor(context),
      appBar: const _FullScreenSheetAppBar(title: 'Community'),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _psRed));
    }

    if (_errorMessage != null) {
      final isPermissionError = _errorMessage!.contains('permission-denied');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            isPermissionError
                ? 'Could not load community data (permission denied).\nRun: firebase deploy --only firestore:rules\nThen fully restart the app.'
                : 'Could not load community contributions.\n$_errorMessage',
            textAlign: TextAlign.center,
            style: TextStyle(color: _psMutedTextColor(context)),
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Text(
          'No public verified contributions yet.',
          style: TextStyle(color: _psMutedTextColor(context)),
        ),
      );
    }

    return RefreshIndicator(
      color: _psRed,
      onRefresh: _reloadContributions,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _communityCard(_items[index]),
      ),
    );
  }

  Widget _communityCard(CommunityContribution item) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _psPanelColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _psBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _communityStationTitle(item),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _psPrimaryTextColor(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'by ${item.contributorName} • ${_formatDateTime(item.createdAt)}',
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
              buildContributorTrustBadgeChip(context, item.trustBadge),
            ],
          ),
          const SizedBox(height: 12),
          if (item.photoUrl?.isNotEmpty == true) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  item.photoUrl!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: _psSoftPanelColor(context),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: _psMutedTextColor(context),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _communityPriceChip('Gas', item.gasoline),
              _communityPriceChip('Diesel', item.diesel),
              _communityPriceChip('Premium', item.premium),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              _reactionButton(
                icon: Icons.thumb_up_alt_outlined,
                label: item.visibleLikeCount > 0
                    ? '${item.visibleLikeCount}'
                    : 'Like',
                selected: item.myReaction == 'like',
                onPressed: () => saveReaction(item, 'like'),
              ),
              const SizedBox(width: 2),
              _reactionButton(
                icon: Icons.thumb_down_alt_outlined,
                label: 'Disagree',
                selected: item.myReaction == 'disagree',
                onPressed: () => saveReaction(item, 'disagree'),
              ),
              const SizedBox(width: 2),
              OutlinedButton.icon(
                onPressed: _isSavingReaction
                    ? null
                    : () => promptFeedback(item),
                icon: const Icon(Icons.chat_bubble_outline, size: 15),
                label: Text('Comments ${item.commentThreadCount}'),
              ),
            ],
          ),
          if (item.publicComments.isNotEmpty) ...[
            const SizedBox(height: 1),
            Text(
              'Community comments',
              style: TextStyle(
                color: _psPrimaryTextColor(context),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            ...item.publicComments.map(
              (entry) => _communityCommentTile(item, entry),
            ),
          ],
        ],
      ),
    );
  }

  Widget _communityCommentTile(
    CommunityContribution item,
    CommunityFeedbackComment entry,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _psSoftPanelColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _psBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.authorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _psPrimaryTextColor(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            entry.comment,
            style: TextStyle(
              color: _psMutedTextColor(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _isSavingReaction
                  ? null
                  : () => promptReply(item, entry),
              icon: const Icon(Icons.reply, size: 16),
              label: const Text('Reply'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const ui.Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          if (entry.replies.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...entry.replies.map(_communityReplyTile),
          ],
        ],
      ),
    );
  }

  String _communityStationTitle(CommunityContribution item) {
    final station = item.stationName.trim();
    final brand = item.brand.trim();
    if (brand.isEmpty || station.toLowerCase().contains(brand.toLowerCase())) {
      return station.isEmpty ? 'Fuel station' : station;
    }
    return '$brand $station';
  }

  Widget _communityReplyTile(CommunityFeedbackReply reply) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 18, top: 6),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: _psPanelColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _psBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reply.authorName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _psPrimaryTextColor(context),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            reply.comment,
            style: TextStyle(
              color: _psMutedTextColor(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _communityPriceChip(String label, double? value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _psSoftPanelColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _psBorderColor(context)),
      ),
      child: Text(
        '$label: ${value == null ? '--' : 'PHP ${value.toStringAsFixed(2)}'}',
        style: TextStyle(
          color: _psPrimaryTextColor(context),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _reactionButton({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: _isSavingReaction ? null : onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? Colors.white : _psPrimaryTextColor(context),
        backgroundColor: selected ? _psRed : null,
        side: BorderSide(color: selected ? _psRed : _psBorderColor(context)),
      ),
    );
  }
}

class _NotificationInboxPage extends StatefulWidget {
  const _NotificationInboxPage();

  @override
  State<_NotificationInboxPage> createState() => _NotificationInboxPageState();
}

class _NotificationInboxPageState extends State<_NotificationInboxPage> {
  bool isMarkingAllRead = false;

  Future<List<UserNotification>> loadNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const <UserNotification>[];

    final snapshot = await FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .get();

    final notifications =
        snapshot.docs.map(UserNotification.fromFirestore).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return notifications;
  }

  Future<void> markNotificationRead(UserNotification notification) async {
    if (notification.isRead) return;

    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(notification.id)
        .set({
          'isRead': true,
          'readAt': Timestamp.now(),
        }, SetOptions(merge: true));

    if (mounted) setState(() {});
  }

  Future<void> markAllRead(List<UserNotification> notifications) async {
    final unread = notifications.where((item) => !item.isRead).toList();
    if (unread.isEmpty || isMarkingAllRead) return;

    setState(() => isMarkingAllRead = true);
    final batch = FirebaseFirestore.instance.batch();
    final now = Timestamp.now();
    for (final notification in unread) {
      batch.set(
        FirebaseFirestore.instance
            .collection('notifications')
            .doc(notification.id),
        {'isRead': true, 'readAt': now},
        SetOptions(merge: true),
      );
    }
    await batch.commit();
    if (mounted) {
      setState(() => isMarkingAllRead = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _psPageColor(context),
      appBar: _FullScreenSheetAppBar(
        title: 'Inbox',
        actions: [
          FutureBuilder<List<UserNotification>>(
            future: loadNotifications(),
            builder: (context, snapshot) {
              final notifications = snapshot.data ?? const <UserNotification>[];
              final hasUnread = notifications.any((item) => !item.isRead);
              return TextButton(
                onPressed: hasUnread && !isMarkingAllRead
                    ? () => markAllRead(notifications)
                    : null,
                child: const Text('Mark all read'),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<UserNotification>>(
          future: loadNotifications(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _psRed),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Text(
                    'Could not load inbox.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _psMutedTextColor(context)),
                  ),
                ),
              );
            }

            final notifications = snapshot.data ?? const <UserNotification>[];
            if (notifications.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_none,
                        color: _psMutedTextColor(context),
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No messages yet.',
                        style: TextStyle(
                          color: _psPrimaryTextColor(context),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Contribution review updates will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _psMutedTextColor(context)),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              itemCount: notifications.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return _notificationTile(notification);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _notificationTile(UserNotification notification) {
    final verified = notification.type == 'contribution_verified';
    final icon = verified ? Icons.verified_outlined : Icons.cancel_outlined;
    final iconColor = verified ? const Color(0xFF1E8E3E) : _psRed;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => markNotificationRead(notification),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notification.isRead
              ? _psPanelColor(context)
              : _psRed.withValues(alpha: _psIsDark(context) ? 0.18 : 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: notification.isRead
                ? _psBorderColor(context)
                : _psRed.withValues(alpha: 0.34),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _psPrimaryTextColor(context),
                            fontWeight: notification.isRead
                                ? FontWeight.w800
                                : FontWeight.w900,
                          ),
                        ),
                      ),
                      if (!notification.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: _psRed,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    notification.message,
                    style: TextStyle(
                      color: _psMutedTextColor(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDateTime(notification.createdAt),
                    style: TextStyle(
                      color: _psMutedTextColor(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyContributionsPage extends StatelessWidget {
  const _MyContributionsPage();

  Future<List<UserContribution>> loadContributions() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const <UserContribution>[];

    final snapshot = await FirebaseFirestore.instance
        .collection('priceReports')
        .where('userId', isEqualTo: user.uid)
        .get();

    final contributions =
        snapshot.docs.map(UserContribution.fromFirestore).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return contributions.take(100).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _psPageColor(context),
      appBar: const _FullScreenSheetAppBar(title: 'My Contributions'),
      body: SafeArea(
        child: FutureBuilder<List<UserContribution>>(
          future: loadContributions(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _psRed),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Text(
                    'Could not load contributions.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _psMutedTextColor(context)),
                  ),
                ),
              );
            }

            final contributions = snapshot.data ?? const <UserContribution>[];
            if (contributions.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history,
                        color: _psMutedTextColor(context),
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No contributions yet.',
                        style: TextStyle(
                          color: _psPrimaryTextColor(context),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              itemCount: contributions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                return _contributionTile(context, contributions[index]);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _contributionTile(BuildContext context, UserContribution item) {
    final color = switch (item.status) {
      'verified' => const Color(0xFF1E8E3E),
      'rejected' => _psRed,
      _ => const Color(0xFFFFA000),
    };
    final icon = switch (item.status) {
      'verified' => Icons.verified_outlined,
      'rejected' => Icons.cancel_outlined,
      _ => Icons.hourglass_top,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _psPanelColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _psBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.stationName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _psPrimaryTextColor(context),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDateTime(item.createdAt),
                      style: TextStyle(
                        color: _psMutedTextColor(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.status,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _contributionPrice(context, 'Gasoline', item.gasoline),
              _contributionPrice(context, 'Diesel', item.diesel),
              _contributionPrice(context, 'Premium', item.premium),
            ],
          ),
          if (item.status == 'rejected' &&
              item.rejectionReason?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              'Reason: ${item.rejectionReason!}',
              style: TextStyle(
                color: _psMutedTextColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _contributionPrice(BuildContext context, String label, double? value) {
    return Text(
      '$label: ${value == null ? '--' : 'PHP ${value.toStringAsFixed(2)}'}',
      style: TextStyle(color: _psMutedTextColor(context), fontSize: 12),
    );
  }
}

class _ContributorAccumulator {
  _ContributorAccumulator(this.name, {this.reportCount = 1});

  final String name;
  int reportCount;
}

class _RejectContributionDialog extends StatefulWidget {
  const _RejectContributionDialog({required this.stationName});

  final String stationName;

  @override
  State<_RejectContributionDialog> createState() =>
      _RejectContributionDialogState();
}

class _RejectContributionDialogState extends State<_RejectContributionDialog> {
  final controller = TextEditingController();
  String? errorText;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final reason = controller.text.trim();
    if (reason.isEmpty) {
      setState(() => errorText = 'Please enter a rejection reason.');
      return;
    }

    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject contribution'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.stationName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Reason for rejection',
              hintText: 'Example: Photo is unclear or prices do not match.',
              border: const OutlineInputBorder(),
              errorText: errorText,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: submit,
          style: FilledButton.styleFrom(
            backgroundColor: _psRed,
            foregroundColor: Colors.white,
          ),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}

class _AdminDashboardPage extends StatefulWidget {
  const _AdminDashboardPage({required this.onChanged});

  final Future<void> Function() onChanged;

  @override
  State<_AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<_AdminDashboardPage> {
  String activeTab = 'pending';
  bool isWorking = false;

  Future<List<AdminContribution>> loadContributions(String status) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('priceReports')
        .where('status', isEqualTo: status)
        .get();
    final reports = snapshot.docs.map(AdminContribution.fromFirestore).toList()
      ..sort((a, b) {
        if (status == 'pending') {
          final rankCompare = _screeningRank(
            a.aiClassification,
          ).compareTo(_screeningRank(b.aiClassification));
          if (rankCompare != 0) return rankCompare;
        }
        return b.createdAt.compareTo(a.createdAt);
      });
    return reports.take(50).toList();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadUsers() async {
    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    return snapshot.docs.toList()..sort((a, b) {
      final aName = _stringField(a.data(), 'displayName').toLowerCase();
      final bName = _stringField(b.data(), 'displayName').toLowerCase();
      return aName.compareTo(bName);
    });
  }

  Future<void> verifyContribution(AdminContribution report) async {
    await reviewContribution(report, status: 'verified');
  }

  Future<void> rejectContribution(AdminContribution report) async {
    final reason = await promptRejectReason(report);
    if (reason == null || reason.isEmpty) return;
    await reviewContribution(
      report,
      status: 'rejected',
      rejectionReason: reason,
    );
  }

  Future<void> reviewContribution(
    AdminContribution report, {
    required String status,
    String? rejectionReason,
  }) async {
    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null || isWorking) return;

    setState(() => isWorking = true);
    final now = Timestamp.now();

    try {
      final reportRef = FirebaseFirestore.instance
          .collection('priceReports')
          .doc(report.id);

      if (status == 'verified') {
        final updateData = <String, Object?>{
          'name': report.stationName,
          'brand': report.brand,
          'lat': report.lat,
          'lng': report.lng,
          'updatedAt': now,
          'updatedBy': admin.uid,
          'verifiedFromReportId': report.id,
        };
        if (report.gasoline != null) updateData['gasoline'] = report.gasoline;
        if (report.diesel != null) updateData['diesel'] = report.diesel;
        if (report.premium != null) updateData['premium'] = report.premium;

        await FirebaseFirestore.instance
            .collection('stations')
            .doc(report.stationId)
            .set(updateData, SetOptions(merge: true));
      }

      final reviewData = <String, Object?>{
        'status': status,
        'reviewedAt': now,
        'reviewedBy': admin.uid,
        'reviewedByEmail': admin.email,
        'updatedAt': now,
      };
      if (status == 'rejected') {
        reviewData['rejectionReason'] = rejectionReason;
      } else {
        reviewData['rejectionReason'] = FieldValue.delete();
      }

      await reportRef.set(reviewData, SetOptions(merge: true));

      await notifyContributor(
        report,
        status: status,
        reviewedAt: now,
        rejectionReason: rejectionReason,
      );

      if (status == 'verified') {
        final contributorId = report.userId;
        if (contributorId != null && contributorId.isNotEmpty) {
          await persistContributorTrustForUser(contributorId);
        }
        await widget.onChanged();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Contribution marked as $status.')),
      );
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Review failed: $error')));
    } finally {
      if (mounted) setState(() => isWorking = false);
    }
  }

  Future<String?> promptRejectReason(AdminContribution report) async {
    return showDialog<String>(
      context: context,
      builder: (_) =>
          _RejectContributionDialog(stationName: report.stationName),
    );
  }

  Future<void> notifyContributor(
    AdminContribution report, {
    required String status,
    required Timestamp reviewedAt,
    String? rejectionReason,
  }) async {
    final userId = report.userId;
    if (userId == null || userId.isEmpty) return;

    final verified = status == 'verified';
    await FirebaseFirestore.instance.collection('notifications').add({
      'userId': userId,
      'title': verified ? 'Contribution verified' : 'Contribution rejected',
      'message': verified
          ? 'Your price update for ${report.stationName} is now verified and visible to PumpScout users.'
          : 'Your price update for ${report.stationName} was rejected. Reason: ${rejectionReason ?? 'No reason provided.'}',
      'type': verified ? 'contribution_verified' : 'contribution_rejected',
      'status': status,
      'rejectionReason': rejectionReason,
      'reportId': report.id,
      'stationId': report.stationId,
      'stationName': report.stationName,
      'isRead': false,
      'createdAt': reviewedAt,
    });
  }

  Future<void> setUserRole(String uid, String role) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'role': role,
      'roleUpdatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _psPageColor(context),
      body: SafeArea(
        child: Row(
          children: [
            Container(
              width: 132,
              decoration: BoxDecoration(
                color: _psPanelColor(context),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                border: Border(
                  right: BorderSide(color: _psBorderColor(context)),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 14),
                  Image.asset(
                    'assets/images/pslogo_transparent.png',
                    height: 84,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.admin_panel_settings,
                      color: Colors.white,
                      size: 56,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _adminNavButton('pending', 'Pending\nVerification'),
                  _adminNavButton('verified', 'Verified\nContribution'),
                  _adminNavButton('rejected', 'Rejected\nContribution'),
                  _adminNavButton('users', 'Users'),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _psPrimaryTextColor(context),
                        side: BorderSide(color: _psBorderColor(context)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: const Icon(Icons.close, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Admin Dashboard',
                                style: TextStyle(
                                  color: _psPrimaryTextColor(context),
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Review reports and manage PumpScout users.',
                                style: TextStyle(
                                  color: _psMutedTextColor(context),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isWorking)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: _psRed,
                              strokeWidth: 2.4,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: activeTab == 'users'
                        ? _usersPanel()
                        : _contributionPanel(activeTab),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adminNavButton(String tab, String label) {
    final selected = activeTab == tab;
    final unselectedFill = _psIsDark(context)
        ? Colors.white.withValues(alpha: 0.04)
        : _psLightSoftPanel;
    final unselectedBorder = _psIsDark(context)
        ? Colors.white.withValues(alpha: 0.08)
        : _psLightBorder;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => activeTab = tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? _psRed : unselectedFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? _psRed : unselectedBorder),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : _psPrimaryTextColor(context),
              fontSize: 11,
              height: 1.18,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _contributionPanel(String status) {
    return FutureBuilder<List<AdminContribution>>(
      future: loadContributions(status),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _psRed));
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'Could not load $status contributions.\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: TextStyle(color: _psMutedTextColor(context)),
              ),
            ),
          );
        }

        final reports = snapshot.data ?? const <AdminContribution>[];
        if (reports.isEmpty) {
          return Center(
            child: Text(
              'No $status contributions.',
              style: TextStyle(color: _psMutedTextColor(context)),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
          itemCount: reports.length,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (context, index) => _contributionCard(reports[index]),
        );
      },
    );
  }

  Widget _contributionCard(AdminContribution report) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _psPanelColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _psBorderColor(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: _psIsDark(context) ? 0.14 : 0.05,
            ),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 142,
            width: double.infinity,
            decoration: BoxDecoration(
              color: _psSoftPanelColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _psRed.withValues(alpha: 0.36)),
            ),
            clipBehavior: Clip.antiAlias,
            child: report.photoUrl == null || report.photoUrl!.isEmpty
                ? const Center(
                    child: Icon(Icons.image_outlined, color: _psRed, size: 42),
                  )
                : Image.network(
                    report.photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Center(child: Icon(Icons.broken_image, size: 42)),
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            report.stationName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
            ).copyWith(color: _psPrimaryTextColor(context)),
          ),
          const SizedBox(height: 8),
          _aiScreeningBadge(report),
          const SizedBox(height: 6),
          Wrap(
            spacing: 18,
            runSpacing: 4,
            children: [
              _adminPriceText(context, 'diesel', report.diesel),
              _adminPriceText(context, 'gasoline', report.gasoline),
              _adminPriceText(context, 'premium', report.premium),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            report.userDisplayName?.isNotEmpty == true
                ? 'by ${report.userDisplayName}'
                : report.userEmail?.isNotEmpty == true
                ? 'by ${report.userEmail}'
                : 'by unknown user',
            style: TextStyle(color: _psMutedTextColor(context), fontSize: 12),
          ),
          if (report.aiReasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            _aiScreeningReasons(report),
          ],
          if (report.status == 'rejected' &&
              report.rejectionReason?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _psRed.withValues(
                  alpha: _psIsDark(context) ? 0.16 : 0.08,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _psRed.withValues(alpha: 0.28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rejection reason',
                    style: TextStyle(
                      color: _psPrimaryTextColor(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    report.rejectionReason!,
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
          if (report.status == 'pending') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isWorking
                        ? null
                        : () => verifyContribution(report),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    style: FilledButton.styleFrom(
                      backgroundColor: _psRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    label: const Text('Verify'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isWorking
                        ? null
                        : () => rejectContribution(report),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _psRed,
                      side: BorderSide(color: _psRed.withValues(alpha: 0.82)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    label: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _aiScreeningBadge(AdminContribution report) {
    final label = report.aiClassification ?? 'needs_review';
    final config = _aiScreeningConfig(label);
    final confidence = report.aiConfidence;
    final confidenceText = confidence == null
        ? ''
        : ' ${(confidence * 100).round()}%';

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: config.color.withValues(
            alpha: _psIsDark(context) ? 0.18 : 0.1,
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: config.color.withValues(alpha: 0.42)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(config.icon, size: 15, color: config.color),
            const SizedBox(width: 6),
            Text(
              'AI screen: ${config.label}$confidenceText',
              style: TextStyle(
                color: config.color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aiScreeningReasons(AdminContribution report) {
    final firstReasons = {...report.aiReasons}.take(3).join(' ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _psSoftPanelColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _psBorderColor(context)),
      ),
      child: Text(
        firstReasons,
        style: TextStyle(
          color: _psMutedTextColor(context),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
      ),
    );
  }

  _AiScreeningConfig _aiScreeningConfig(String label) {
    switch (label) {
      case 'usable':
        return const _AiScreeningConfig(
          label: 'Usable',
          icon: Icons.verified_outlined,
          color: Color(0xFF168A4A),
        );
      case 'spam':
        return const _AiScreeningConfig(
          label: 'Likely spam',
          icon: Icons.report_gmailerrorred_outlined,
          color: Color(0xFFD92D20),
        );
      case 'needs_review':
      default:
        return const _AiScreeningConfig(
          label: 'Needs review',
          icon: Icons.manage_search_outlined,
          color: Color(0xFFB54708),
        );
    }
  }

  int _screeningRank(String? label) {
    switch (label) {
      case 'spam':
        return 0;
      case 'needs_review':
        return 1;
      case 'usable':
        return 2;
      default:
        return 1;
    }
  }

  Widget _usersPanel() {
    return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: loadUsers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _psRed));
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'Could not load users.\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: TextStyle(color: _psMutedTextColor(context)),
              ),
            ),
          );
        }

        final users =
            snapshot.data ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        if (users.isEmpty) {
          return Center(
            child: Text(
              'No user profiles found.',
              style: TextStyle(color: _psMutedTextColor(context)),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
          itemCount: users.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = users[index];
            final data = doc.data();
            final role = _stringField(data, 'role', fallback: 'user');
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _psPanelColor(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _psBorderColor(context)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _psRed.withValues(alpha: 0.15),
                    child: Icon(
                      Icons.person,
                      color: _psIsDark(context) ? Colors.white : _psRed,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _stringField(
                            data,
                            'displayName',
                            fallback: 'PumpScout User',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _psPrimaryTextColor(context),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _stringField(data, 'email'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _psMutedTextColor(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DropdownButton<String>(
                    value: role == 'admin' ? 'admin' : 'user',
                    dropdownColor: _psSoftPanelColor(context),
                    style: TextStyle(color: _psPrimaryTextColor(context)),
                    iconEnabledColor: _psPrimaryTextColor(context),
                    underline: Container(height: 1, color: _psRed),
                    items: const [
                      DropdownMenuItem(value: 'user', child: Text('user')),
                      DropdownMenuItem(value: 'admin', child: Text('admin')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setUserRole(doc.id, value);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _adminPriceText(BuildContext context, String label, double? value) {
    return Text(
      '$label: ${value == null ? '--' : value.toStringAsFixed(2)}',
      style: TextStyle(color: _psPrimaryTextColor(context), fontSize: 12),
    );
  }
}

Widget buildContributorTrustBadgeChip(
  BuildContext context,
  ContributorTrustBadge badge,
) {
  final color = badge.score >= 80
      ? const Color(0xFF168A4A)
      : badge.score >= 60
      ? const Color(0xFF1D70B8)
      : badge.score >= 40
      ? const Color(0xFFB54708)
      : _psRed;

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: _psIsDark(context) ? 0.18 : 0.1),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.36)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.auto_awesome, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          'Trust score ${badge.score}%',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

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
