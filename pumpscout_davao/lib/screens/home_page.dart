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

    await mapKey.currentState?.showRouteToPlace(
      destination,
      startNavigation: true,
    );
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
