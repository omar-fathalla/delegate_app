import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/services/sync_manager.dart';
import 'package:delegate_app/core/widgets/app_loading_indicator.dart';
import 'package:delegate_app/injection_container.dart' as di;

class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    SyncManager syncManager;
    try {
      syncManager = di.sl<SyncManager>();
    } catch (_) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<SyncState>(
      valueListenable: syncManager.statusNotifier,
      builder: (context, syncState, _) {
        if (syncState.pendingCount == 0 && !syncState.isSyncing) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        if (syncState.isSyncing) {
          final progress = syncState.totalToSync > 0
              ? syncState.syncedCount / syncState.totalToSync
              : null;

          return Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    AppLoadingIndicator(
                      size: 20,
                      color: colorScheme.primary,
                      style: AppLoadingStyle.threeArchedCircle,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        syncState.totalToSync > 0
                            ? AppLocalizations.of(context)!.syncingPhotosXofY(syncState.syncedCount, syncState.totalToSync)
                            : AppLocalizations.of(context)!.syncingRemainingPhotos,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                if (progress != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        // Pending offline photos waiting for sync
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.amber.shade300,
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_off_rounded,
                  color: Colors.amber.shade900,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.photosSavedOnPhone(syncState.pendingCount),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context)!.waitingToUpload,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.amber.shade900.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () {
                  syncManager.syncPendingPhotos();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.amber.shade200,
                  foregroundColor: Colors.amber.shade900,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sync_rounded, size: 16),
                    SizedBox(width: 4),
                    Text(
                      AppLocalizations.of(context)!.syncNow,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
