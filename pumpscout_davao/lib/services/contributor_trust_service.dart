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
  final reactionsByReportId = <String, Map<String, String>>{};
  final commentsByReportId = <String, List<CommunityFeedbackComment>>{};
  final repliesByParentId = <String, List<CommunityFeedbackReply>>{};

  final snapshot = await FirebaseFirestore.instance
      .collection('contributionFeedback')
      .get();

  for (final doc in snapshot.docs) {
    final data = doc.data();
    final reportId = _stringField(data, 'reportId');
    if (reportId.isEmpty) continue;

    final type = _stringField(data, 'type');
    final reaction = _stringField(data, 'reaction');
    final comment = _stringField(data, 'comment');
    final existing = aggregates[reportId] ?? const ReportFeedbackAggregate();
    final isLegacyDoc = type.isEmpty;
    final isReactionDoc = type == 'reaction' || isLegacyDoc;
    final isCommentDoc =
        type == 'comment' || (isLegacyDoc && comment.trim().isNotEmpty);
    final isReplyDoc = type == 'reply';

    final userId = _stringField(data, 'userId');
    if (isReactionDoc &&
        userId.isNotEmpty &&
        (reaction == 'like' || reaction == 'disagree')) {
      final reactions = reactionsByReportId.putIfAbsent(
        reportId,
        () => <String, String>{},
      );
      if (type == 'reaction' || !reactions.containsKey(userId)) {
        reactions[userId] = reaction;
      }
    }

    final authorName = _feedbackAuthorName(data);
    if (isCommentDoc) {
      commentsByReportId.putIfAbsent(
        reportId,
        () => <CommunityFeedbackComment>[],
      );
      commentsByReportId[reportId]!.add(
        CommunityFeedbackComment(
          id: doc.id,
          authorName: authorName,
          comment: comment.trim(),
          reaction: reaction,
          replies: _feedbackReplies(data),
          createdAt:
              _dateTimeField(data, 'updatedAt') ??
              _dateTimeField(data, 'createdAt'),
        ),
      );
    }

    if (isReplyDoc && comment.trim().isNotEmpty) {
      final parentCommentId = _stringField(data, 'parentCommentId');
      if (parentCommentId.isNotEmpty) {
        repliesByParentId.putIfAbsent(
          parentCommentId,
          () => <CommunityFeedbackReply>[],
        );
        repliesByParentId[parentCommentId]!.add(
          CommunityFeedbackReply(
            authorName: authorName,
            comment: comment.trim(),
            createdAt:
                _dateTimeField(data, 'updatedAt') ??
                _dateTimeField(data, 'createdAt'),
          ),
        );
      }
    }

    aggregates[reportId] = ReportFeedbackAggregate(
      publicComments: existing.publicComments,
    );
  }

  for (final entry in reactionsByReportId.entries) {
    final reactions = entry.value;
    final likeCount = reactions.values
        .where((reaction) => reaction == 'like')
        .length;
    final disagreeCount = reactions.values
        .where((reaction) => reaction == 'disagree')
        .length;
    final existing = aggregates[entry.key] ?? const ReportFeedbackAggregate();
    aggregates[entry.key] = ReportFeedbackAggregate(
      likeCount: likeCount,
      disagreeCount: disagreeCount,
      feedbackCount: existing.feedbackCount,
      substantiveFeedbackCount: existing.substantiveFeedbackCount,
      myReaction: currentUserId == null ? null : reactions[currentUserId],
      publicComments: existing.publicComments,
    );
  }

  for (final entry in commentsByReportId.entries) {
    final comments =
        entry.value.map((comment) {
          final replies =
              [...comment.replies, ...?repliesByParentId[comment.id]]
                ..sort((a, b) {
                  final aDate =
                      a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  final bDate =
                      b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  return aDate.compareTo(bDate);
                });

          return CommunityFeedbackComment(
            id: comment.id,
            authorName: comment.authorName,
            comment: comment.comment,
            reaction: comment.reaction,
            replies: replies,
            createdAt: comment.createdAt,
          );
        }).toList()..sort((a, b) {
          final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        });

    final existing = aggregates[entry.key] ?? const ReportFeedbackAggregate();
    aggregates[entry.key] = ReportFeedbackAggregate(
      likeCount: existing.likeCount,
      disagreeCount: existing.disagreeCount,
      feedbackCount: comments.fold<int>(
        0,
        (total, comment) => total + 1 + comment.replies.length,
      ),
      substantiveFeedbackCount: comments.length,
      myReaction: existing.myReaction,
      publicComments: comments,
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

List<CommunityFeedbackReply> _feedbackReplies(Map<String, dynamic> data) {
  final rawReplies = data['replies'];
  if (rawReplies is! List) return const <CommunityFeedbackReply>[];

  final replies = <CommunityFeedbackReply>[];
  for (final item in rawReplies) {
    if (item is! Map) continue;
    final reply = Map<String, dynamic>.from(item);
    final comment = _stringField(reply, 'comment');
    if (comment.trim().isEmpty) continue;

    replies.add(
      CommunityFeedbackReply(
        authorName: _feedbackAuthorName(reply),
        comment: comment.trim(),
        createdAt: _dateTimeField(reply, 'createdAt'),
      ),
    );
  }

  replies.sort((a, b) {
    final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return aDate.compareTo(bDate);
  });

  return replies;
}

ContributorTrustBadge computeContributorTrustBadge({
  required int verifiedReportCount,
  DateTime? lastVerifiedReportAt,
  required int communityLikeCount,
  required int communityDisagreeCount,
  required int substantiveFeedbackCount,
  List<String> aiClassifications = const <String>[],
}) {
  final score = (verifiedReportCount * 10).clamp(0, 100);
  final label = 'Trust score';

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
  final nextMilestone = verifiedReportCount >= 10
      ? 'Maximum trust score reached.'
      : '${10 - verifiedReportCount} more approved contribution${10 - verifiedReportCount == 1 ? '' : 's'} to reach 100%.';

  return '$verifiedReportCount admin-approved contribution${verifiedReportCount == 1 ? '' : 's'}. '
      'Trust increases after an admin verifies a submitted fuel price. '
      '$nextMilestone';
}

Future<ContributorTrustBadge> buildContributorTrustBadgeForUser({
  required String contributorId,
  required Map<String, ReportFeedbackAggregate> feedbackByReportId,
}) async {
  if (contributorId.isEmpty) {
    return const ContributorTrustBadge(
      label: 'Trust score',
      score: 0,
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
      label: 'Trust score',
      score: 0,
      reason:
          'Trust score will update after admin-approved contributions are visible.',
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
        (lastVerifiedReportAt == null ||
            createdAt.isAfter(lastVerifiedReportAt))) {
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
