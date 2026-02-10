import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/drive/providers/offline_index_provider.dart';
import 'package:skydrivex/features/drive/settings/widgets/settings_card.dart';
import 'package:skydrivex/utils/toast.dart';

class OfflineIndexTile extends ConsumerWidget {
  const OfflineIndexTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    final state = ref.watch(offlineIndexProvider);
    final controller = ref.read(offlineIndexProvider.notifier);
    final status = _buildStatus(state);
    final lastIndexedLabel = state.lastIndexedAt == null
        ? 'Never'
        : _formatDateTime(state.lastIndexedAt!);

    return SettingsCard(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final actionButton = FButton(
            onPress: state.enabled && !state.isIndexing
                ? () => unawaited(_startIndexing(context, ref))
                : null,
            style: FButtonStyle.primary(
              (style) => style.copyWith(
                decoration: FWidgetStateMap.all(
                  BoxDecoration(
                    color: colors.foreground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                contentStyle: (contentStyle) => contentStyle.copyWith(
                  textStyle: FWidgetStateMap.all(
                    typography.sm.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.background,
                    ),
                  ),
                  iconStyle: FWidgetStateMap.all(
                    IconThemeData(color: colors.background, size: 16),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  spacing: 8,
                ),
              ),
            ),
            prefix: Icon(
              state.isIndexing ? Icons.hourglass_top_rounded : Icons.play_arrow,
            ),
            child: Text(state.isIndexing ? 'Indexing...' : 'Start indexing'),
          );

          final header = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.manage_search_rounded,
                  size: 20,
                  color: colors.foreground,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Offline index',
                      style: typography.base.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Build a local metadata index to speed up filename search.',
                      style: typography.sm.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final enableCard = Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors.secondary.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Enable offline search index',
                        style: typography.base.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.foreground,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'If disabled, search continues using OneDrive online APIs.',
                        style: typography.sm.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                FSwitch(value: state.enabled, onChange: controller.setEnabled),
              ],
            ),
          );

          final statusCard = Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border.withValues(alpha: 0.55)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  style: typography.sm.copyWith(
                    color: colors.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Indexed items: ${state.indexedItems}',
                  style: typography.sm.copyWith(color: colors.mutedForeground),
                ),
                const SizedBox(height: 4),
                Text(
                  'Last indexed: $lastIndexedLabel',
                  style: typography.sm.copyWith(color: colors.mutedForeground),
                ),
                if (state.lastError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    state.lastError!,
                    style: typography.xs.copyWith(color: colors.destructive),
                  ),
                ],
              ],
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 16),
              enableCard,
              const SizedBox(height: 12),
              statusCard,
              const SizedBox(height: 12),
              if (compact)
                actionButton
              else
                Row(
                  children: [
                    actionButton,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Run indexing after big file moves to keep local search fresh.',
                        style: typography.sm.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  String _buildStatus(OfflineIndexState state) {
    if (state.isIndexing) {
      return 'Indexing in progress...';
    }
    if (!state.enabled) {
      return 'Offline index disabled';
    }
    if (!state.hasIndex) {
      return 'No index snapshot yet';
    }
    return 'Offline index ready';
  }

  Future<void> _startIndexing(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(offlineIndexProvider.notifier);
    try {
      await controller.rebuildIndex();
      if (!context.mounted) return;
      final count = ref.read(offlineIndexProvider).indexedItems;
      showToast(context, 'Offline index updated: $count items');
    } catch (err) {
      if (!context.mounted) return;
      showToast(context, 'Offline indexing failed: $err');
    }
  }

  String _formatDateTime(DateTime timestamp) {
    final local = timestamp.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}
