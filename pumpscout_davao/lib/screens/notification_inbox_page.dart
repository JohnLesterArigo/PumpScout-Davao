part of '../main.dart';

class _NotificationInboxPage extends StatefulWidget {
  const _NotificationInboxPage();

  @override
  State<_NotificationInboxPage> createState() => _NotificationInboxPageState();
}

class _NotificationInboxPageState extends State<_NotificationInboxPage> {
  bool isMarkingAllRead = false;
  bool isDeletingRead = false;
  late Future<List<UserNotification>> notificationsFuture;

  @override
  void initState() {
    super.initState();
    notificationsFuture = loadNotifications();
  }

  void refreshNotifications() {
    setState(() {
      notificationsFuture = loadNotifications();
    });
  }

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

    if (mounted) refreshNotifications();
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
      setState(() {
        isMarkingAllRead = false;
        notificationsFuture = loadNotifications();
      });
    }
  }

  Future<void> deleteReadNotifications(
    List<UserNotification> notifications,
  ) async {
    final readNotifications = notifications
        .where((item) => item.isRead)
        .toList();
    if (readNotifications.isEmpty || isDeletingRead) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete read notifications?'),
          content: Text(
            'This will delete ${readNotifications.length} notification${readNotifications.length == 1 ? '' : 's'} that you already read. Unread notifications will stay in your inbox.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete read'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true || !mounted) return;

    setState(() => isDeletingRead = true);

    try {
      var batch = FirebaseFirestore.instance.batch();
      var batchCount = 0;
      for (final notification in readNotifications) {
        batch.delete(
          FirebaseFirestore.instance
              .collection('notifications')
              .doc(notification.id),
        );
        batchCount++;

        if (batchCount == 450) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          batchCount = 0;
        }
      }

      if (batchCount > 0) {
        await batch.commit();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Deleted ${readNotifications.length} read notification${readNotifications.length == 1 ? '' : 's'}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete notifications: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isDeletingRead = false;
          notificationsFuture = loadNotifications();
        });
      }
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
            future: notificationsFuture,
            builder: (context, snapshot) {
              final notifications = snapshot.data ?? const <UserNotification>[];
              final hasUnread = notifications.any((item) => !item.isRead);
              final hasRead = notifications.any((item) => item.isRead);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: hasUnread && !isMarkingAllRead
                        ? () => markAllRead(notifications)
                        : null,
                    child: const Text('Mark all read'),
                  ),
                  IconButton(
                    tooltip: 'Delete read notifications',
                    onPressed: hasRead && !isDeletingRead
                        ? () => deleteReadNotifications(notifications)
                        : null,
                    icon: isDeletingRead
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_sweep_outlined),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<UserNotification>>(
          future: notificationsFuture,
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
                        'No Notifications yet.',
                        style: TextStyle(
                          color: _psPrimaryTextColor(context),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Notifications will appear here.',
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
