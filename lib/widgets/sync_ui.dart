import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/sync_service.dart';

/// Signs in to Google and, if the cloud and this phone disagree, asks which to keep.
Future<void> connectGoogle(BuildContext context) async {
  final sync = context.read<SyncService>();
  final messenger = ScaffoldMessenger.of(context);
  final err = await sync.signIn();
  if (err != null) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(err)));
    return;
  }
  if (sync.conflict && context.mounted) await askWhichToKeep(context);
}

Future<void> askWhichToKeep(BuildContext context) async {
  final sync = context.read<SyncService>();
  final useCloud = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      icon: const Icon(Icons.cloud_sync_rounded, size: 34),
      title: const Text('Two versions of your data'),
      content: const Text('Your Google account already has data, and this phone has '
          'different data too. Which one should be kept? The other one is replaced.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep this phone')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Use cloud data')),
      ],
    ),
  );
  if (useCloud != null) await sync.resolve(useCloud: useCloud);
}

/// Profile and backup status at the top of the More page.
class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final avatar = CircleAvatar(
      radius: 28,
      backgroundColor: cs.primaryContainer,
      foregroundImage: sync.photoUrl != null && sync.photoUrl!.isNotEmpty
          ? NetworkImage(sync.photoUrl!)
          : null,
      child: Icon(Icons.person_rounded, size: 30, color: cs.onPrimaryContainer),
    );

    final String status;
    final IconData statusIcon;
    Color? statusColor;
    if (!sync.signedIn) {
      status = 'Sign in to back up and sync your data.';
      statusIcon = Icons.cloud_off_rounded;
    } else if (sync.conflict) {
      status = 'Cloud and phone differ. Tap to choose.';
      statusIcon = Icons.warning_amber_rounded;
      statusColor = cs.error;
    } else if (sync.syncing) {
      status = 'Syncing…';
      statusIcon = Icons.cloud_sync_rounded;
    } else if (sync.error != null) {
      status = sync.error!;
      statusIcon = Icons.error_outline_rounded;
      statusColor = cs.error;
    } else {
      status = sync.lastSync == null ? 'Not synced yet' : 'Synced ${_ago(sync.lastSync!)}';
      statusIcon = Icons.cloud_done_rounded;
      statusColor = Colors.green;
    }

    final title = sync.signedIn
        ? (sync.name?.isNotEmpty == true ? sync.name! : 'Google account')
        : 'Guest User';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                avatar,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(sync.signedIn ? sync.email! : 'Not signed in',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (!sync.signedIn && SyncService.supported)
                  // The theme's buttons are full width, which a Row cannot give.
                  FilledButton(
                    onPressed: () => connectGoogle(context),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 20)),
                    child: const Text('Sign in'),
                  ),
              ],
            ),
            if (SyncService.supported) ...[
              const Divider(height: 28),
              InkWell(
                onTap: sync.conflict ? () => askWhichToKeep(context) : null,
                child: Row(
                  children: [
                    Icon(statusIcon, size: 22, color: statusColor ?? cs.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(status,
                          style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                    if (sync.signedIn && !sync.conflict)
                      TextButton(
                          onPressed: sync.syncing ? null : sync.backupNow,
                          child: const Text('Back up now')),
                  ],
                ),
              ),
              if (sync.signedIn)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _confirmSignOut(context),
                    child: const Text('Sign out'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final sync = context.read<SyncService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('Your data stays on this phone and in your Google Drive, '
            'but it will stop syncing until you sign in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) await sync.signOut();
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}
