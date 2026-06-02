part of '../main.dart';

class ReportFeedbackAggregate {
  const ReportFeedbackAggregate({
    this.likeCount = 0,
    this.disagreeCount = 0,
    this.feedbackCount = 0,
    this.substantiveFeedbackCount = 0,
    this.myReaction,
    List<CommunityFeedbackComment>? publicComments,
  }) : _publicComments = publicComments;

  final int likeCount;
  final int disagreeCount;
  final int feedbackCount;
  final int substantiveFeedbackCount;
  final String? myReaction;
  final List<CommunityFeedbackComment>? _publicComments;

  List<CommunityFeedbackComment> get publicComments =>
      _publicComments ?? const <CommunityFeedbackComment>[];
}

Future<Map<String, ReportFeedbackAggregate>> loadFeedbackAggregatesByReportId({
  String? currentUserId,
}) async {
  final aggregates = <String, ReportFeedbackAggregate>{};

  final snapshot = await FirebaseFirestore.instance
      .collection('contributionFeedback')
      .get();

  for (final doc in snapshot.docs) {
    final data = doc.data();
    final reportId = _stringField(data, 'reportId');
    if (reportId.isEmpty) continue;

    final reaction = _stringField(data, 'reaction');
    final comment = _stringField(data, 'comment');
    final existing = aggregates[reportId] ?? const ReportFeedbackAggregate();

    var likeCount = existing.likeCount;
    var disagreeCount = existing.disagreeCount;
    var substantiveFeedbackCount = existing.substantiveFeedbackCount;
    var myReaction = existing.myReaction;
    final publicComments = List<CommunityFeedbackComment>.from(
      existing.publicComments,
      growable: true,
    );

    if (reaction == 'like') likeCount += 1;
    if (reaction == 'disagree') disagreeCount += 1;
    if (comment.trim().length >= 8) substantiveFeedbackCount += 1;

    final userId = _stringField(data, 'userId');
    if (currentUserId != null && userId == currentUserId && reaction.isNotEmpty) {
      myReaction = reaction;
    }

    final authorName = _feedbackAuthorName(data);
    if (comment.trim().isNotEmpty) {
      publicComments.add(
        CommunityFeedbackComment(
          authorName: authorName,
          comment: comment.trim(),
          reaction: reaction,
          createdAt: _dateTimeField(data, 'updatedAt') ??
              _dateTimeField(data, 'createdAt'),
        ),
      );
    }

    publicComments.sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    aggregates[reportId] = ReportFeedbackAggregate(
      likeCount: likeCount,
      disagreeCount: disagreeCount,
      feedbackCount: existing.feedbackCount + 1,
      substantiveFeedbackCount: substantiveFeedbackCount,
      myReaction: myReaction,
      publicComments: publicComments,
    );
  }

  return aggregates;
}

String _feedbackAuthorName(Map<String, dynamic> data) {
  final displayName = _stringField(data, 'userDisplayName');
  if (displayName.isNotEmpty) return displayName;

  final email = _stringField(data, 'userEmail');
  if (email.contains('@')) {
    return email.split('@').first;
  }

  return 'Community member';
}

ContributorTrustBadge computeContributorTrustBadge({
  required int verifiedReportCount,
  DateTime? lastVerifiedReportAt,
  required int communityLikeCount,
  required int communityDisagreeCount,
  required int substantiveFeedbackCount,
  List<String> aiClassifications = const <String>[],
}) {
  final activeBonus =
      lastVerifiedReportAt != null &&
          DateTime.now().difference(lastVerifiedReportAt).inDays <= 30
      ? 10
      : 0;

  var aiAdjustment = 0;
  for (final label in aiClassifications) {
    switch (label.toLowerCase()) {
      case 'usable':
        aiAdjustment += 3;
      case 'needs_review':
        aiAdjustment -= 5;
      case 'spam':
        aiAdjustment -= 18;
      default:
        aiAdjustment -= 2;
    }
  }

  final score = (35 +
          (verifiedReportCount * 9) +
          activeBonus +
          (communityLikeCount * 5) +
          (substantiveFeedbackCount * 3) +
          aiAdjustment -
          (communityDisagreeCount * 10))
      .clamp(0, 100);

  final label = score >= 80
      ? 'AI Trusted'
      : score >= 60
      ? 'Reliable'
      : score >= 40
      ? 'New Scout'
      : 'Needs Proof';

  final reason = buildContributorTrustReason(
    verifiedReportCount: verifiedReportCount,
    communityLikeCount: communityLikeCount,
    communityDisagreeCount: communityDisagreeCount,
    substantiveFeedbackCount: substantiveFeedbackCount,
    aiClassifications: aiClassifications,
  );

  return ContributorTrustBadge(label: label, score: score, reason: reason);
}

String buildContributorTrustReason({
  required int verifiedReportCount,
  required int communityLikeCount,
  required int communityDisagreeCount,
  required int substantiveFeedbackCount,
  List<String> aiClassifications = const <String>[],
}) {
  final usableCount = aiClassifications
      .where((label) => label.toLowerCase() == 'usable')
      .length;
  final reviewCount = aiClassifications
      .where((label) => label.toLowerCase() == 'needs_review')
      .length;
  final spamCount = aiClassifications
      .where((label) => label.toLowerCase() == 'spam')
      .length;

  return '$verifiedReportCount approved contribution${verifiedReportCount == 1 ? '' : 's'}, '
      '$communityLikeCount agree${communityLikeCount == 1 ? '' : 's'}, '
      '$communityDisagreeCount disagree${communityDisagreeCount == 1 ? '' : 's'}, '
      '$substantiveFeedbackCount detailed feedback note${substantiveFeedbackCount == 1 ? '' : 's'}. '
      'AI checks: $usableCount clean, $reviewCount needs review, $spamCount flagged.';
}

Future<ContributorTrustBadge> buildContributorTrustBadgeForUser({
  required String contributorId,
  required Map<String, ReportFeedbackAggregate> feedbackByReportId,
}) async {
  if (contributorId.isEmpty) {
    return const ContributorTrustBadge(
      label: 'Unrated',
      score: 35,
      reason: 'Contributor identity is incomplete.',
    );
  }

  QuerySnapshot<Map<String, dynamic>> reports;
  try {
    reports = await FirebaseFirestore.instance
        .collection('priceReports')
        .where('userId', isEqualTo: contributorId)
        .where('status', isEqualTo: 'verified')
        .get();
  } catch (error) {
    debugPrint('Contributor trust query failed: $error');
    return const ContributorTrustBadge(
      label: 'New Scout',
      score: 40,
      reason:
          'Trust score will update after more approved contributions are visible.',
    );
  }

  var communityLikeCount = 0;
  var communityDisagreeCount = 0;
  var substantiveFeedbackCount = 0;
  DateTime? lastVerifiedReportAt;
  final aiClassifications = <String>[];

  for (final doc in reports.docs) {
    final data = doc.data();
    final createdAt = _dateTimeField(data, 'createdAt');
    if (createdAt != null &&
        (lastVerifiedReportAt == null || createdAt.isAfter(lastVerifiedReportAt))) {
      lastVerifiedReportAt = createdAt;
    }

    final aiLabel = _stringField(
      data,
      'aiClassification',
      fallback: 'needs_review',
    );
    if (aiLabel.isNotEmpty) aiClassifications.add(aiLabel);

    final feedback = feedbackByReportId[doc.id];
    if (feedback == null) continue;
    communityLikeCount += feedback.likeCount;
    communityDisagreeCount += feedback.disagreeCount;
    substantiveFeedbackCount += feedback.substantiveFeedbackCount;
  }

  return computeContributorTrustBadge(
    verifiedReportCount: reports.docs.length,
    lastVerifiedReportAt: lastVerifiedReportAt,
    communityLikeCount: communityLikeCount,
    communityDisagreeCount: communityDisagreeCount,
    substantiveFeedbackCount: substantiveFeedbackCount,
    aiClassifications: aiClassifications,
  );
}

Future<void> persistContributorTrustForUser(String contributorId) async {
  if (contributorId.isEmpty) return;

  final feedbackByReportId = await loadFeedbackAggregatesByReportId();
  final trust = await buildContributorTrustBadgeForUser(
    contributorId: contributorId,
    feedbackByReportId: feedbackByReportId,
  );

  await FirebaseFirestore.instance.collection('users').doc(contributorId).set({
    'trustScore': trust.score,
    'trustLabel': trust.label,
    'trustReason': trust.reason,
    'trustUpdatedAt': Timestamp.now(),
    'verifiedReportCount': await _verifiedReportCount(contributorId),
  }, SetOptions(merge: true));
}

Future<int> _verifiedReportCount(String contributorId) async {
  final snapshot = await FirebaseFirestore.instance
      .collection('priceReports')
      .where('userId', isEqualTo: contributorId)
      .where('status', isEqualTo: 'verified')
      .get();
  return snapshot.docs.length;
}
