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

const int _xpPerVerifiedReport = 100;
const int _xpPerHelpfulVote = 10;

Future<void> syncPublicLeaderboardProfile(
  User user, {
  String? displayName,
}) async {
  final resolvedName = displayName?.trim().isNotEmpty == true
      ? displayName!.trim()
      : user.displayName?.trim().isNotEmpty == true
      ? user.displayName!.trim()
      : 'PumpScout User';

  await FirebaseFirestore.instance
      .collection('leaderboardProfiles')
      .doc(user.uid)
      .set({
        'uid': user.uid,
        'displayName': resolvedName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}

ContributorExperience computeContributorExperience({
  required int verifiedReportCount,
  required int helpfulVoteCount,
}) {
  final xp =
      verifiedReportCount * _xpPerVerifiedReport +
      helpfulVoteCount * _xpPerHelpfulVote;
  var level = 1;
  var currentLevelXp = 0;
  var nextLevelXp = 250;

  while (xp >= nextLevelXp) {
    level += 1;
    currentLevelXp = nextLevelXp;
    nextLevelXp += 250 + ((level - 2) * 100);
  }

  return ContributorExperience(
    xp: xp,
    level: level,
    title: contributorLevelTitle(level),
    currentLevelXp: currentLevelXp,
    nextLevelXp: nextLevelXp,
  );
}

String contributorLevelTitle(int level) {
  if (level >= 10) return 'Legend';
  if (level >= 7) return 'Pathfinder';
  if (level >= 5) return 'Expert Scout';
  if (level >= 3) return 'Rising Contributor';
  if (level >= 2) return 'Active Contributor';
  return 'New Contributor';
}

int contributorXpRequiredForLevel(int targetLevel) {
  if (targetLevel <= 1) return 0;

  var level = 1;
  var nextLevelXp = 250;
  while (level < targetLevel) {
    level += 1;
    if (level == targetLevel) return nextLevelXp;
    nextLevelXp += 250 + ((level - 2) * 100);
  }

  return nextLevelXp;
}

Future<ContributorExperience> buildContributorExperienceForUser({
  required String contributorId,
  required Map<String, ReportFeedbackAggregate> feedbackByReportId,
}) async {
  if (contributorId.isEmpty) {
    return computeContributorExperience(
      verifiedReportCount: 0,
      helpfulVoteCount: 0,
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
    debugPrint('Contributor experience query failed: $error');
    return computeContributorExperience(
      verifiedReportCount: 0,
      helpfulVoteCount: 0,
    );
  }

  var helpfulVoteCount = 0;

  for (final doc in reports.docs) {
    final feedback = feedbackByReportId[doc.id];
    if (feedback == null) continue;
    helpfulVoteCount += feedback.likeCount;
  }

  return computeContributorExperience(
    verifiedReportCount: reports.docs.length,
    helpfulVoteCount: helpfulVoteCount,
  );
}

Future<void> persistContributorExperienceForUser(String contributorId) async {
  if (contributorId.isEmpty) return;

  final feedbackByReportId = await loadFeedbackAggregatesByReportId();
  final experience = await buildContributorExperienceForUser(
    contributorId: contributorId,
    feedbackByReportId: feedbackByReportId,
  );

  await FirebaseFirestore.instance.collection('users').doc(contributorId).set({
    'experiencePoints': experience.xp,
    'contributorLevel': experience.level,
    'contributorTitle': experience.title,
    'experienceUpdatedAt': Timestamp.now(),
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
