part of '../main.dart';

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
  static const double _nearbyCommunityRadiusMeters = 10000;

  List<CommunityContribution> _items = const [];
  bool _isLoading = true;
  bool _isSavingReaction = false;
  String _communityFilter = 'nearby';
  geo.Position? _communityLocation;
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
    final location = await _locationForCommunityFilter();
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
    final experienceCache = <String, ContributorExperience>{};
    final items = <CommunityContribution>[];

    for (final doc in docs) {
      final reportData = doc.data();
      final contributorId = _stringField(reportData, 'userId');
      if (_communityFilter == 'nearby' &&
          !_isNearbyCommunityReport(reportData, location)) {
        continue;
      }

      final feedback =
          feedbackByReportId[doc.id] ?? const ReportFeedbackAggregate();

      if (!experienceCache.containsKey(contributorId)) {
        experienceCache[contributorId] =
            await buildContributorExperienceForUser(
              contributorId: contributorId,
              feedbackByReportId: feedbackByReportId,
            );
      }

      items.add(
        CommunityContribution.fromFirestore(
          doc: doc,
          experience: experienceCache[contributorId]!,
          likeCount: feedback.likeCount,
          disagreeCount: feedback.disagreeCount,
          feedbackCount: feedback.feedbackCount,
          myReaction: feedback.myReaction,
          publicComments: feedback.publicComments,
        ),
      );
    }

    items.sort((a, b) => _compareCommunityItems(a, b, location));
    return items.take(40).toList();
  }

  Future<geo.Position?> _locationForCommunityFilter() async {
    if (_communityFilter != 'nearby') return _communityLocation;
    if (_communityLocation != null) return _communityLocation;

    try {
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.denied ||
          permission == geo.LocationPermission.deniedForever) {
        return null;
      }

      _communityLocation = await geo.Geolocator.getCurrentPosition();
      return _communityLocation;
    } catch (error) {
      debugPrint('Community location load failed: $error');
      return null;
    }
  }

  bool _isNearbyCommunityReport(
    Map<String, dynamic> data,
    geo.Position? location,
  ) {
    if (location == null) return false;
    final lat = _doubleField(data, 'lat');
    final lng = _doubleField(data, 'lng');
    if (lat == null || lng == null) return false;

    return geo.Geolocator.distanceBetween(
          location.latitude,
          location.longitude,
          lat,
          lng,
        ) <=
        _nearbyCommunityRadiusMeters;
  }

  int _compareCommunityItems(
    CommunityContribution a,
    CommunityContribution b,
    geo.Position? location,
  ) {
    switch (_communityFilter) {
      case 'cheapest':
        final priceCompare = (_lowestCommunityPrice(
          a,
        )).compareTo(_lowestCommunityPrice(b));
        if (priceCompare != 0) return priceCompare;
        return b.createdAt.compareTo(a.createdAt);
      case 'nearby':
        final distanceCompare = _communityDistanceMeters(
          a,
          location,
        ).compareTo(_communityDistanceMeters(b, location));
        if (distanceCompare != 0) return distanceCompare;
        return b.createdAt.compareTo(a.createdAt);
      case 'all':
      case 'latest':
      default:
        return b.createdAt.compareTo(a.createdAt);
    }
  }

  double _lowestCommunityPrice(CommunityContribution item) {
    final prices = <double>[
      ?item.gasoline,
      ?item.diesel,
      ?item.premium,
    ].where((price) => price > 0).toList();
    if (prices.isEmpty) return double.infinity;
    return prices.reduce(math.min);
  }

  double _communityDistanceMeters(
    CommunityContribution item,
    geo.Position? location,
  ) {
    if (location == null || item.lat == 0 || item.lng == 0) {
      return double.infinity;
    }
    return geo.Geolocator.distanceBetween(
      location.latitude,
      location.longitude,
      item.lat,
      item.lng,
    );
  }

  String _communityFilterSubtitle() {
    switch (_communityFilter) {
      case 'nearby':
        return _communityLocation == null
            ? 'Nearby needs location access'
            : 'Verified reports within 10 km';
      case 'cheapest':
        return 'Verified reports sorted by lowest available price';
      case 'all':
        return 'All verified reports across Davao';
      case 'latest':
      default:
        return 'Newest verified reports first';
    }
  }

  void _setCommunityFilter(String filter) {
    if (_communityFilter == filter) return;
    setState(() => _communityFilter = filter);
    _reloadContributions();
  }

  Future<void> _notifyReportOwner(
    CommunityContribution item, {
    required String actorUserId,
    required String actorName,
    required String title,
    required String message,
    required String type,
  }) async {
    final ownerId = item.userId?.trim() ?? '';
    if (ownerId.isEmpty || ownerId == actorUserId) return;

    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': ownerId,
        'title': title,
        'message': message,
        'type': type,
        'reportId': item.id,
        'stationName': _communityStationTitle(item),
        'actorUserId': actorUserId,
        'actorName': actorName,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      debugPrint('Community notification failed: $error');
    }
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
      final existingReaction = existing.data()?['reaction']?.toString();
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
      if (existingReaction != reaction) {
        final isLike = reaction == 'like';
        await _notifyReportOwner(
          item,
          actorUserId: user.uid,
          actorName: authorName,
          title: isLike ? 'Someone liked your report' : 'Someone disagreed',
          message:
              '$authorName ${isLike ? 'liked' : 'disagreed with'} your report for ${_communityStationTitle(item)}.',
          type: isLike ? 'community_like' : 'community_disagree',
        );
      }

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
      await _notifyReportOwner(
        item,
        actorUserId: user.uid,
        actorName: authorName,
        title: 'New comment on your report',
        message:
            '$authorName commented on your report for ${_communityStationTitle(item)}.',
        type: 'community_comment',
      );

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
      await _notifyReportOwner(
        item,
        actorUserId: user.uid,
        actorName: authorName,
        title: 'New reply on your report',
        message:
            '$authorName replied on your report for ${_communityStationTitle(item)}.',
        type: 'community_reply',
      );

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
      body: SafeArea(child: _buildBody()),
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

    return Stack(
      children: [
        RefreshIndicator(
          color: _psRed,
          onRefresh: _reloadContributions,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 112),
            itemCount: _items.length + 2,
            separatorBuilder: (_, index) =>
                SizedBox(height: index <= 1 ? 12 : 8),
            itemBuilder: (context, index) {
              if (index == 0) return _communityHeader();
              if (index == 1) {
                return _items.isEmpty
                    ? _communityEmptyCard()
                    : _communityInfoBanner();
              }
              return _communityCard(_items[index - 2]);
            },
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 10,
          child: _reportFuelPricePanel(),
        ),
      ],
    );
  }

  Widget _communityHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Community',
                    style: TextStyle(
                      color: _psPrimaryTextColor(context),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'Real fuel prices from real drivers',
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
        const SizedBox(height: 12),
        _communityFilterBar(),
      ],
    );
  }

  Widget _communityInfoBanner() {
    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _psPanelColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _psBorderColor(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _psFilledActionColor(context),
              borderRadius: BorderRadius.circular(12),
              border: _psIsDark(context)
                  ? Border.all(color: _psBorderColor(context))
                  : null,
            ),
            child: const Icon(Icons.verified, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _communityFilterSubtitle(),
                  style: TextStyle(
                    color: _psIsDark(context)
                        ? _psPrimaryTextColor(context)
                        : const Color(0xFF2563EB),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Help the community save more',
                  style: TextStyle(
                    color: _psMutedTextColor(context),
                    fontSize: 11,
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

  Widget _communityEmptyCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _psPanelColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _psBorderColor(context)),
      ),
      child: Text(
        _communityEmptyMessage(),
        textAlign: TextAlign.center,
        style: TextStyle(color: _psMutedTextColor(context)),
      ),
    );
  }

  Widget _communityFilterBar() {
    final filters = [
      ('nearby', Icons.location_on, 'Nearby'),
      ('latest', Icons.schedule, 'Latest'),
      ('cheapest', Icons.local_offer, 'Cheapest'),
      ('all', Icons.apartment, 'All Davao'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in filters) ...[
            _communityFilterChip(
              value: filter.$1,
              icon: filter.$2,
              label: filter.$3,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _communityFilterChip({
    required String value,
    required IconData icon,
    required String label,
  }) {
    final selected = _communityFilter == value;
    return InkWell(
      onTap: () => _setCommunityFilter(value),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? _psFilledActionColor(context)
              : _psPanelColor(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected && !_psIsDark(context)
                ? const Color(0xFF2563EB)
                : _psBorderColor(context),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.10 : 0.04),
              blurRadius: selected ? 14 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : _psMutedTextColor(context),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : _psPrimaryTextColor(context),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportFuelPricePanel() {
    return InkWell(
      onTap: _openReportMap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 62,
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _psIsDark(context)
                ? const [_psSoftPanel, _psPanelBlue]
                : const [Color(0xFF2563EB), Color(0xFF0EA5E9)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: _psIsDark(context)
              ? Border.all(color: _psBorderColor(context))
              : null,
          boxShadow: [
            BoxShadow(
              color: _psIsDark(context)
                  ? Colors.black.withValues(alpha: 0.18)
                  : const Color(0xFF2563EB).withValues(alpha: 0.28),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _psIsDark(context)
                    ? const Color(0xFF3A3F48)
                    : Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add,
                color: _psIsDark(context)
                    ? Colors.white
                    : const Color(0xFF2563EB),
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Report fuel price',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'Help others save',
                    style: TextStyle(
                      color: Color(0xDFFFFFFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Image.asset(
              'assets/images/car.png',
              width: 88,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) {
                return const Icon(
                  Icons.directions_car,
                  color: Colors.white,
                  size: 36,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openReportMap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) {
          return Scaffold(
            backgroundColor: _psPageColor(context),
            appBar: AppBar(
              title: const Text('Report fuel price'),
              backgroundColor: _psPageColor(context),
              foregroundColor: _psPrimaryTextColor(context),
              elevation: 0,
            ),
            body: MapContainer(isDarkMode: _psIsDark(context)),
          );
        },
      ),
    );
  }

  String _communityEmptyMessage() {
    if (_communityFilter == 'nearby' && _communityLocation == null) {
      return 'Allow location access to see nearby verified reports, or switch to Latest / All Davao.';
    }
    if (_communityFilter == 'nearby') {
      return 'No verified community reports within 10 km yet.';
    }
    return 'No public verified contributions yet.';
  }

  String? _communityDistanceLabel(CommunityContribution item) {
    if (_communityLocation == null) return null;
    final distance = _communityDistanceMeters(item, _communityLocation);
    if (!distance.isFinite) return null;
    return distance >= 1000
        ? '${(distance / 1000).toStringAsFixed(1)} km away'
        : '${distance.round()} m away';
  }

  Widget _communityCard(CommunityContribution item) {
    final distanceLabel = _communityDistanceLabel(item);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _psPanelColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _psBorderColor(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 340;
              final details = Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _communityStationTitle(item),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _psPrimaryTextColor(context),
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified,
                          color: Color(0xFF2563EB),
                          size: 16,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        'by ${item.contributorName}',
                        ?distanceLabel,
                        _formatDateTime(item.createdAt),
                      ].join(' • '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _psMutedTextColor(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _communityBrandLogo(item),
                      const SizedBox(width: 10),
                      details,
                      if (!compact) ...[
                        const SizedBox(width: 8),
                        _communityLevelPill(item),
                      ],
                    ],
                  ),
                  if (compact) ...[
                    const SizedBox(height: 8),
                    _communityLevelPill(item),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          if (item.photoUrl?.isNotEmpty == true) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
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
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 360 ? 2 : 3;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: columns == 2 ? 2.4 : 2.25,
                children: [
                  for (final fuel in _communityFuelItems(item))
                    _communityPriceChip(fuel),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 390;
              final buttons = [
                _reactionButton(
                  icon: item.myReaction == 'like'
                      ? Icons.favorite
                      : Icons.favorite_border,
                  label: item.myReaction == 'like'
                      ? 'Liked (${item.visibleLikeCount})'
                      : 'Like (${item.visibleLikeCount})',
                  selected: item.myReaction == 'like',
                  onPressed: () => saveReaction(item, 'like'),
                ),
                _reactionButton(
                  icon: Icons.thumb_down_alt_outlined,
                  label: 'Disagree (${item.disagreeCount})',
                  selected: item.myReaction == 'disagree',
                  onPressed: () => saveReaction(item, 'disagree'),
                ),
                OutlinedButton.icon(
                  onPressed: _isSavingReaction
                      ? null
                      : () => promptFeedback(item),
                  icon: const Icon(Icons.chat_bubble_outline, size: 14),
                  label: Text('Comment (${item.commentThreadCount})'),
                  style: _communityActionButtonStyle(
                    foregroundColor: _psPrimaryTextColor(context),
                    borderColor: _psBorderColor(context),
                  ),
                ),
              ];

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < buttons.length; index++) ...[
                      SizedBox(width: double.infinity, child: buttons[index]),
                      if (index < buttons.length - 1)
                        const SizedBox(height: 6),
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  for (var index = 0; index < buttons.length; index++) ...[
                    Expanded(child: buttons[index]),
                    if (index < buttons.length - 1)
                      const SizedBox(width: 6),
                  ],
                ],
              );
            },
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

  Widget _communityBrandLogo(CommunityContribution item) {
    final logoPath = _communityBrandLogoAsset(item.brand);
    return Container(
      width: 46,
      height: 46,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: _psBorderColor(context)),
      ),
      child: logoPath == null
          ? Center(
              child: Text(
                _communityBrandInitial(item),
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                ),
              ),
            )
          : ClipOval(
              child: Image.asset(
                logoPath,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Center(
                  child: Text(
                    _communityBrandInitial(item),
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  String _communityBrandInitial(CommunityContribution item) {
    final source = item.brand.trim().isNotEmpty
        ? item.brand.trim()
        : item.stationName.trim();
    if (source.isEmpty) return 'P';
    return source.characters.first.toUpperCase();
  }

  Widget _communityLevelPill(CommunityContribution item) {
    const color = Color(0xFF2563EB);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_outlined, color: color, size: 13),
          const SizedBox(width: 4),
          Text(
            'Level ${item.experience.level}',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
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

  List<_CommunityFuelDisplayItem> _communityFuelItems(
    CommunityContribution item,
  ) {
    final fuels = <_CommunityFuelDisplayItem>[];

    for (final entry in item.fuelProducts.entries) {
      if (entry.value <= 0) continue;
      fuels.add(
        _CommunityFuelDisplayItem(
          label: entry.key,
          price: entry.value,
          category: _communityFuelCategory(entry.key),
        ),
      );
    }

    if (fuels.isEmpty) {
      void addBase(String key, double? value) {
        if (value == null || value <= 0) return;
        fuels.add(
          _CommunityFuelDisplayItem(
            label: _communityFuelLabelForBrand(item.brand, key),
            price: value,
            category: key,
          ),
        );
      }

      addBase('gasoline', item.gasoline);
      addBase('diesel', item.diesel);
      addBase('premium', item.premium);
    }

    return fuels;
  }

  String _communityFuelLabelForBrand(String brand, String fuelType) {
    final normalized = brand.toLowerCase();
    if (normalized.contains('shell')) {
      return switch (fuelType) {
        'diesel' => 'FuelSave Diesel',
        'premium' => 'V-Power Gasoline',
        _ => 'FuelSave Gasoline',
      };
    }
    if (normalized.contains('petron')) {
      return switch (fuelType) {
        'diesel' => 'Turbo Diesel',
        'premium' => 'Blaze 100',
        _ => 'Xtra Advance',
      };
    }
    if (normalized.contains('seaoil') || normalized.contains('sea oil')) {
      return switch (fuelType) {
        'diesel' => 'Exceed Diesel',
        'premium' => 'Extreme 95',
        _ => 'Extreme U',
      };
    }
    if (normalized.contains('caltex') || normalized.contains('caltext')) {
      return switch (fuelType) {
        'diesel' => 'Caltex Diesel',
        'premium' => 'Platinum',
        _ => 'Silver',
      };
    }
    if (normalized.contains('unioil')) {
      return switch (fuelType) {
        'diesel' => 'Euro 5 Diesel',
        'premium' => 'Premium',
        _ => 'Euro 5 Gasoline',
      };
    }
    return switch (fuelType) {
      'diesel' => 'Diesel',
      'premium' => 'Premium',
      _ => 'Gasoline',
    };
  }

  String _communityFuelCategory(String label) {
    final normalized = label.toLowerCase();
    if (normalized.contains('diesel')) return 'diesel';
    if (normalized.contains('premium') ||
        normalized.contains('v-power') ||
        normalized.contains('blaze') ||
        normalized.contains('platinum') ||
        normalized.contains('extreme 95')) {
      return 'premium';
    }
    return 'gasoline';
  }

  String? _communityBrandLogoAsset(String brand) {
    final normalized = brand.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normalized.contains('shell')) return 'assets/images/Shell_logo.png';
    if (normalized.contains('petron')) return 'assets/images/petron_logo.jpg';
    if (normalized.contains('seaoil')) {
      return 'assets/images/seaOil_Logo.png';
    }
    if (normalized.contains('caltex') || normalized.contains('caltext')) {
      return 'assets/images/caltext_logo.jpg';
    }
    if (normalized.contains('unioil')) return 'assets/images/uniOil_logo.png';
    if (normalized.contains('mygas')) return 'assets/images/myGas_logo.png';
    if (normalized.contains('phoenix')) return 'assets/images/phoenix_logo.jpg';
    return null;
  }

  Widget _communityPriceChip(_CommunityFuelDisplayItem item) {
    final color = switch (item.category) {
      'diesel' => const Color(0xFF2563EB),
      'premium' => const Color(0xFFF97316),
      _ => const Color(0xFF10B981),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.local_gas_station, color: color, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _psMutedTextColor(context),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'PHP ${item.price.toStringAsFixed(2)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _psPrimaryTextColor(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
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
      style: _communityActionButtonStyle(
        foregroundColor: selected ? Colors.white : _psPrimaryTextColor(context),
        backgroundColor: selected ? _psRed : null,
        borderColor: selected ? _psRed : _psBorderColor(context),
      ),
    );
  }

  ButtonStyle _communityActionButtonStyle({
    required Color foregroundColor,
    required Color borderColor,
    Color? backgroundColor,
  }) {
    return OutlinedButton.styleFrom(
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      side: BorderSide(color: borderColor),
      minimumSize: const ui.Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
    );
  }
}

class _CommunityFuelDisplayItem {
  const _CommunityFuelDisplayItem({
    required this.label,
    required this.price,
    required this.category,
  });

  final String label;
  final double price;
  final String category;
}
