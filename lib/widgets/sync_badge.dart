import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/cloud_sync_service.dart';
import '../state/providers.dart';
import '../theme.dart';

class SyncBadge extends ConsumerWidget {
  const SyncBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final (label, icon, color) = switch (status) {
      SyncStatus.localOnly => (
          'Local',
          Icons.cloud_off_outlined,
          AppColors.muted
        ),
      SyncStatus.syncing => ('Syncing', Icons.sync_rounded, AppColors.blue),
      SyncStatus.synced => (
          'Synced',
          Icons.cloud_done_outlined,
          AppColors.green
        ),
      SyncStatus.error => (
          'Sync error',
          Icons.cloud_off_rounded,
          AppColors.red
        ),
    };

    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
