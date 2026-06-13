part of '../main.dart';

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
