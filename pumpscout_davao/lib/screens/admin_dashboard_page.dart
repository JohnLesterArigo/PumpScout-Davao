part of '../main.dart';

class _AdminDashboardPage extends StatefulWidget {
  const _AdminDashboardPage({required this.onChanged});

  final Future<void> Function() onChanged;

  @override
  State<_AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<_AdminDashboardPage> {
  static const int _adminContributionFetchLimit = 80;
  static const int _adminContributionDisplayLimit = 50;

  String activeTab = 'pending';
  bool isWorking = false;

  Future<List<AdminContribution>> loadContributions(String status) async {
    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await FirebaseFirestore.instance
          .collection('priceReports')
          .where('status', isEqualTo: status)
          .orderBy('createdAt', descending: true)
          .limit(_adminContributionFetchLimit)
          .get();
    } on FirebaseException catch (error) {
      if (error.code != 'failed-precondition') rethrow;
      debugPrint('Admin contribution optimized query needs index: $error');
      snapshot = await FirebaseFirestore.instance
          .collection('priceReports')
          .where('status', isEqualTo: status)
          .get();
    }

    final reports =
        snapshot.docs
            .where((doc) => doc.data()['adminArchived'] != true)
            .map(AdminContribution.fromFirestore)
            .toList()
          ..sort((a, b) {
            if (status == 'pending') {
              final rankCompare = _screeningRank(
                a.aiClassification,
              ).compareTo(_screeningRank(b.aiClassification));
              if (rankCompare != 0) return rankCompare;
            }
            return b.createdAt.compareTo(a.createdAt);
          });
    return reports.take(_adminContributionDisplayLimit).toList();
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

  Future<void> archiveContribution(AdminContribution report) async {
    if (isWorking || report.status == 'pending') return;

    final shouldArchive = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Archive contribution?'),
          content: Text(
            'This hides ${report.stationName} from the admin ${report.status} list, but keeps the record for user history, experience progress, and audit review.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: _psRed,
                foregroundColor: Colors.white,
              ),
              child: const Text('Archive'),
            ),
          ],
        );
      },
    );
    if (shouldArchive != true || !mounted) return;

    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) return;

    setState(() => isWorking = true);
    try {
      await FirebaseFirestore.instance
          .collection('priceReports')
          .doc(report.id)
          .set({
            'adminArchived': true,
            'adminArchivedAt': Timestamp.now(),
            'adminArchivedBy': admin.uid,
          }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Contribution archived.')));
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Archive failed: $error')));
    } finally {
      if (mounted) setState(() => isWorking = false);
    }
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
        if (report.fuelProducts.isNotEmpty) {
          updateData['fuelProducts'] = report.fuelProducts;
        }

        await FirebaseFirestore.instance
            .collection('stations')
            .doc(report.stationId)
            .set(updateData, SetOptions(merge: true));
      }

      final reviewData = <String, Object?>{
        'status': status,
        'adminArchived': false,
        'adminArchivedAt': FieldValue.delete(),
        'adminArchivedBy': FieldValue.delete(),
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
          await persistContributorExperienceForUser(contributorId);
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
                                'Showing latest 50 active records per tab.',
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
          ] else ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isWorking ? null : () => archiveContribution(report),
                icon: const Icon(Icons.archive_outlined, size: 18),
                label: const Text('Archive'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _psPrimaryTextColor(context),
                  side: BorderSide(color: _psBorderColor(context)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
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

Widget buildContributorLevelChip(
  BuildContext context,
  ContributorExperience experience,
) {
  const color = Color(0xFF2563EB);

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
        Icon(Icons.workspace_premium_outlined, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          'Level ${experience.level} - ${experience.title}',
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
