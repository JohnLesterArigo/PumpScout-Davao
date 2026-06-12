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
    final trustCache = <String, ContributorTrustBadge>{};
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
      return RefreshIndicator(
        color: _psRed,
        onRefresh: _reloadContributions,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _communityFilterBar(),
            const SizedBox(height: 18),
            Center(
              child: Text(
                _communityEmptyMessage(),
                textAlign: TextAlign.center,
                style: TextStyle(color: _psMutedTextColor(context)),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _psRed,
      onRefresh: _reloadContributions,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: _items.length + 1,
        separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 14 : 12),
        itemBuilder: (context, index) {
          if (index == 0) return _communityFilterBar();
          return _communityCard(_items[index - 1]);
        },
      ),
    );
  }

  Widget _communityFilterBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'nearby', label: Text('Nearby')),
              ButtonSegment(value: 'latest', label: Text('Latest')),
              ButtonSegment(value: 'cheapest', label: Text('Cheapest')),
              ButtonSegment(value: 'all', label: Text('All Davao')),
            ],
            selected: {_communityFilter},
            onSelectionChanged: (selection) {
              _setCommunityFilter(selection.first);
            },
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStateProperty.all(
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _communityFilterSubtitle(),
          style: TextStyle(
            color: _psMutedTextColor(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
                      [
                        'by ${item.contributorName}',
                        ?distanceLabel,
                        _formatDateTime(item.createdAt),
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
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _reactionButton(
                icon: Icons.thumb_up_alt_outlined,
                label: item.visibleLikeCount > 0
                    ? '${item.visibleLikeCount}'
                    : 'Like',
                selected: item.myReaction == 'like',
                onPressed: () => saveReaction(item, 'like'),
              ),
              _reactionButton(
                icon: Icons.thumb_down_alt_outlined,
                label: 'Disagree',
                selected: item.myReaction == 'disagree',
                onPressed: () => saveReaction(item, 'disagree'),
              ),
              OutlinedButton.icon(
                onPressed: _isSavingReaction
                    ? null
                    : () => promptFeedback(item),
                icon: const Icon(Icons.chat_bubble_outline, size: 15),
                label: Text(
                  item.commentThreadCount > 0
                      ? 'Comment ${item.commentThreadCount}'
                      : 'Comment',
                ),
                style: _communityActionButtonStyle(
                  foregroundColor: _psPrimaryTextColor(context),
                  borderColor: _psBorderColor(context),
                ),
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
