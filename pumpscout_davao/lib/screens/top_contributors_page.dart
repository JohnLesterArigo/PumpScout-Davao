part of '../main.dart';

enum _LeaderboardPeriod { allTime, month, week }

class _TopContributorsPage extends StatefulWidget {
  const _TopContributorsPage();

  @override
  State<_TopContributorsPage> createState() => _TopContributorsPageState();
}

class _TopContributorsPageState extends State<_TopContributorsPage> {
  static const _communityBlue = Color(0xFF2563EB);

  _LeaderboardPeriod _period = _LeaderboardPeriod.allTime;
  late Future<List<ContributorSummary>> _contributorsFuture;

  @override
  void initState() {
    super.initState();
    _contributorsFuture = _loadContributors();
  }

  void _setPeriod(_LeaderboardPeriod period) {
    if (_period == period) return;
    setState(() {
      _period = period;
      _contributorsFuture = _loadContributors();
    });
  }

  Future<List<ContributorSummary>> _loadContributors() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final contributors = <String, _LeaderboardAccumulator>{};

    if (currentUser != null) {
      contributors[currentUser.uid] = _LeaderboardAccumulator(
        currentUser.displayName?.trim().isNotEmpty == true
            ? currentUser.displayName!.trim()
            : currentUser.email ?? 'You',
      );
    }

    try {
      final users = await FirebaseFirestore.instance.collection('users').get();
      for (final doc in users.docs) {
        final data = doc.data();
        final id = _stringField(data, 'uid', fallback: doc.id);
        contributors.putIfAbsent(
          id,
          () => _LeaderboardAccumulator(
            _stringField(
              data,
              'displayName',
              fallback: _stringField(
                data,
                'email',
                fallback: 'PumpScout User',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      debugPrint('Leaderboard users load failed: $error');
    }

    final feedback = await loadFeedbackAggregatesByReportId();
    final reports = await FirebaseFirestore.instance
        .collection('priceReports')
        .where('status', isEqualTo: 'verified')
        .get();
    final periodStart = _periodStart();

    for (final doc in reports.docs) {
      final data = doc.data();
      final userId = _stringField(
        data,
        'userId',
        fallback: _stringField(data, 'userEmail', fallback: 'anonymous'),
      );
      final name = _stringField(
        data,
        'userDisplayName',
        fallback: _stringField(data, 'userEmail', fallback: 'PumpScout User'),
      );
      final item = contributors.putIfAbsent(
        userId,
        () => _LeaderboardAccumulator(name),
      );
      final helpfulVotes = feedback[doc.id]?.likeCount ?? 0;

      item.totalReports += 1;
      item.totalHelpfulVotes += helpfulVotes;

      final createdAt = _dateTimeField(data, 'createdAt');
      if (periodStart == null ||
          (createdAt != null && !createdAt.isBefore(periodStart))) {
        item.periodReports += 1;
        item.periodHelpfulVotes += helpfulVotes;
      }
    }

    final summaries = contributors.entries
        .map((entry) {
          final item = entry.value;
          return ContributorSummary(
            userId: entry.key,
            name: item.name,
            reportCount: item.periodReports,
            helpfulVoteCount: item.periodHelpfulVotes,
            experience: computeContributorExperience(
              verifiedReportCount: item.totalReports,
              helpfulVoteCount: item.totalHelpfulVotes,
            ),
          );
        })
        .where(
          (item) =>
              _period == _LeaderboardPeriod.allTime ||
              item.reportCount > 0 ||
              item.userId == currentUser?.uid,
        )
        .toList()
      ..sort((a, b) {
        final aPeriodXp =
            a.reportCount * _xpPerVerifiedReport +
            a.helpfulVoteCount * _xpPerHelpfulVote;
        final bPeriodXp =
            b.reportCount * _xpPerVerifiedReport +
            b.helpfulVoteCount * _xpPerHelpfulVote;
        final xpCompare = bPeriodXp.compareTo(aPeriodXp);
        if (xpCompare != 0) return xpCompare;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return summaries;
  }

  DateTime? _periodStart() {
    final now = DateTime.now();
    return switch (_period) {
      _LeaderboardPeriod.allTime => null,
      _LeaderboardPeriod.month => DateTime(now.year, now.month),
      _LeaderboardPeriod.week => DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1)),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _psPageColor(context),
      appBar: AppBar(
        backgroundColor: _psPageColor(context),
        foregroundColor: _psPrimaryTextColor(context),
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Top Contributors',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            Text(
              'Thanks to our community heroes!',
              style: TextStyle(
                color: _psMutedTextColor(context),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _showHowItWorks,
              icon: const Icon(Icons.info_outline, size: 17),
              label: const Text('How it works'),
              style: TextButton.styleFrom(
                foregroundColor: _psPrimaryTextColor(context),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<ContributorSummary>>(
        future: _contributorsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _errorState(snapshot.error);
          }

          final contributors =
              snapshot.data ?? const <ContributorSummary>[];
          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    final future = _loadContributors();
                    setState(() => _contributorsFuture = future);
                    await future;
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                    children: [
                      if (contributors.isNotEmpty)
                        _heroCard(contributors.first),
                      const SizedBox(height: 12),
                      _periodTabs(),
                      const SizedBox(height: 10),
                      if (contributors.isEmpty)
                        _emptyState()
                      else
                        _leaderboard(contributors),
                    ],
                  ),
                ),
              ),
              _newReportBanner(),
            ],
          );
        },
      ),
    );
  }

  Widget _heroCard(ContributorSummary leader) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isCurrentUser = currentUser?.uid == leader.userId;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: _psPanelColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _psBorderColor(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: _psIsDark(context) ? 0.18 : 0.06,
            ),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            height: 100,
            child: Image.asset(
              'assets/images/trophy.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Most Valuable Contributor',
                  style: TextStyle(
                    color: _psMutedTextColor(context),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isCurrentUser ? '${leader.name} (You)' : leader.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _psPrimaryTextColor(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: _heroMetric(
                        Icons.description_outlined,
                        '${leader.reportCount}',
                        'Reports',
                      ),
                    ),
                    Expanded(
                      child: _heroMetric(
                        Icons.thumb_up_alt_outlined,
                        '${leader.helpfulVoteCount}',
                        'Helpful Votes',
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 42,
                      color: _psBorderColor(context),
                    ),
                    const SizedBox(width: 10),
                    _heroLevel(leader.experience),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroMetric(IconData icon, String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: _communityBlue, size: 16),
            const SizedBox(width: 5),
            Text(
              value,
              style: TextStyle(
                color: _psPrimaryTextColor(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(color: _psMutedTextColor(context), fontSize: 9),
        ),
      ],
    );
  }

  Widget _heroLevel(ContributorExperience experience) {
    return SizedBox(
      width: 58,
      child: Column(
        children: [
          const Icon(Icons.workspace_premium, color: Color(0xFFFFD85A)),
          Text(
            'Level ${experience.level}',
            style: TextStyle(
              color: _psPrimaryTextColor(context),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            experience.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _psMutedTextColor(context), fontSize: 8),
          ),
        ],
      ),
    );
  }

  Widget _periodTabs() {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: _psPanelColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _psBorderColor(context)),
      ),
      child: Row(
        children: [
          _periodTab('All Time', _LeaderboardPeriod.allTime),
          _periodTab('This Month', _LeaderboardPeriod.month),
          _periodTab('This Week', _LeaderboardPeriod.week),
        ],
      ),
    );
  }

  Widget _periodTab(String label, _LeaderboardPeriod period) {
    final selected = _period == period;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _setPeriod(period),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? _communityBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : _psPrimaryTextColor(context),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _leaderboard(List<ContributorSummary> contributors) {
    return Container(
      decoration: BoxDecoration(
        color: _psPanelColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _psBorderColor(context)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < contributors.length; index++)
            _contributorTile(
              contributors[index],
              rank: index + 1,
              showDivider: index < contributors.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _contributorTile(
    ContributorSummary contributor, {
    required int rank,
    required bool showDivider,
  }) {
    final isCurrentUser =
        FirebaseAuth.instance.currentUser?.uid == contributor.userId;
    final colors = [
      const Color(0xFFFF6B9B),
      const Color(0xFF30B884),
      const Color(0xFFD2A24A),
      const Color(0xFF3E7DD9),
      const Color(0xFF2563EB),
    ];
    final avatarColor = colors[(rank - 1) % colors.length];

    return Container(
      decoration: BoxDecoration(
        color: isCurrentUser ? _psSoftPanelColor(context) : null,
        border: showDivider
            ? Border(bottom: BorderSide(color: _psBorderColor(context)))
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          SizedBox(width: 34, child: _rankAsset(rank)),
          CircleAvatar(
            radius: 18,
            backgroundColor: avatarColor.withValues(alpha: 0.15),
            child: Icon(Icons.person, color: avatarColor, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isCurrentUser
                            ? '${contributor.name} (You)'
                            : contributor.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _psPrimaryTextColor(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (isCurrentUser) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDDF8E9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'You',
                          style: TextStyle(
                            color: Color(0xFF148653),
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Level ${contributor.experience.level} - ${contributor.experience.title}',
                  style: TextStyle(
                    color: _psMutedTextColor(context),
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: contributor.experience.progress,
                    minHeight: 3,
                    backgroundColor: _communityBlue.withValues(alpha: 0.12),
                    valueColor: const AlwaysStoppedAnimation(_communityBlue),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${contributor.reportCount}',
                style: TextStyle(
                  color: _psPrimaryTextColor(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                contributor.reportCount == 1 ? 'Report' : 'Reports',
                style: TextStyle(
                  color: _psMutedTextColor(context),
                  fontSize: 8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${contributor.experience.xp} XP',
                style: TextStyle(
                  color: _psMutedTextColor(context),
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: _psMutedTextColor(context), size: 18),
        ],
      ),
    );
  }

  Widget _rankAsset(int rank) {
    final asset = switch (rank) {
      1 => 'assets/images/1st_place.png',
      2 => 'assets/images/2nd_place.png',
      3 => 'assets/images/3rd_place.png',
      _ => null,
    };
    if (asset != null) {
      return Image.asset(asset, width: 27, height: 32, fit: BoxFit.contain);
    }
    return Text(
      '$rank',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: _psPrimaryTextColor(context),
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _newReportBanner() {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: _psPanelColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _psBorderColor(context)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: _communityBlue.withValues(alpha: 0.12),
              child: const Icon(
                Icons.groups_2_outlined,
                color: _communityBlue,
                size: 19,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Keep sharing, keep helping!',
                    style: TextStyle(
                      color: _psPrimaryTextColor(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'Verified reports earn XP and help the community.',
                    style: TextStyle(
                      color: _psMutedTextColor(context),
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _openReportMap,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New Report'),
              style: FilledButton.styleFrom(
                backgroundColor: _communityBlue,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Text(
          'No verified contributions for this period yet.',
          style: TextStyle(color: _psMutedTextColor(context)),
        ),
      ),
    );
  }

  Widget _errorState(Object? error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 42),
            const SizedBox(height: 10),
            const Text('Could not load contributors.'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                setState(() => _contributorsFuture = _loadContributors());
              },
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  void _showHowItWorks() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Earn experience',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            _xpRule(Icons.verified_outlined, 'Verified fuel report', '100 XP'),
            _xpRule(Icons.thumb_up_alt_outlined, 'Helpful vote', '10 XP'),
            const SizedBox(height: 14),
            const Text(
              'Only admin-verified reports count. Earn XP to level up from New Contributor to PumpScout Legend.',
              style: TextStyle(height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _xpRule(IconData icon, String label, String xp) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: _communityBlue),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(
            xp,
            style: TextStyle(
              color: _psPrimaryTextColor(context),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  void _openReportMap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          backgroundColor: _psPageColor(context),
          appBar: AppBar(
            title: const Text('Report fuel price'),
            backgroundColor: _psPageColor(context),
            foregroundColor: _psPrimaryTextColor(context),
            elevation: 0,
          ),
          body: MapContainer(isDarkMode: _psIsDark(context)),
        ),
      ),
    );
  }
}

class _LeaderboardAccumulator {
  _LeaderboardAccumulator(this.name);

  final String name;
  int totalReports = 0;
  int totalHelpfulVotes = 0;
  int periodReports = 0;
  int periodHelpfulVotes = 0;
}
