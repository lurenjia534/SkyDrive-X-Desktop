import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/drive/providers/drive_info_provider.dart';
import 'package:skydrivex/features/drive/settings/widgets/settings_card.dart';
import 'package:skydrivex/features/drive/utils/drive_item_formatters.dart';

class DriveInfoTile extends ConsumerWidget {
  const DriveInfoTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driveInfoProvider);
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;

    final refreshAction = FButton.icon(
      onPress: state.isLoading
          ? null
          : () => ref.read(driveInfoProvider.notifier).refreshInfo(),
      style: FButtonStyle.ghost(),
      child: const Icon(FIcons.rotateCw, size: 16),
    );

    Widget body;
    if (state.isLoading) {
      body = Center(
        child: FCircularProgress.loader(
          style: (style) => style.copyWith(
            iconStyle: IconThemeData(color: colors.primary, size: 20),
          ),
        ),
      );
    } else if (state.hasError) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unable to fetch OneDrive info',
            style: typography.base.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            state.error.toString(),
            style: typography.sm.copyWith(color: colors.error),
          ),
          const SizedBox(height: 12),
          FButton(
            onPress: () => ref.read(driveInfoProvider.notifier).refreshInfo(),
            style: FButtonStyle.outline(),
            prefix: const Icon(FIcons.rotateCcw, size: 16),
            child: Text(
              'Retry',
              style: typography.sm.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    } else {
      final info = state.value!;
      final owner = info.owner;
      final ownerName =
          owner?.displayName ?? owner?.userPrincipalName ?? 'Not provided';
      final ownerUpn = owner?.userPrincipalName;
      final accountType = info.driveType ?? 'Unknown';
      final quota = info.quota;
      final quotaState = quota?.state ?? 'Unknown';
      final totalLabel = _formatSize(quota?.total);
      final usedLabel = _formatSize(quota?.used);
      final remainingLabel = _formatSize(quota?.remaining);
      final deletedLabel = _formatSize(quota?.deleted);
      final usedRatio = (quota?.used != null && quota?.total != null)
          ? (quota!.used!.toDouble() / quota.total!.toDouble())
          : null;

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OneDrive Info',
                      style: typography.sm.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Storage quota',
                      style: typography.xl2.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.foreground,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Account type: $accountType',
                      style: typography.sm.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              refreshAction,
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.secondary.withValues(alpha: 0.5),
                ),
                child: Center(
                  child: Icon(
                    FIcons.user,
                    color: colors.foreground.withValues(alpha: 0.7),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ownerName,
                      style: typography.lg.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    if (ownerUpn != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Authenticated User',
                        style: typography.sm.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          LayoutBuilder(
            builder: (context, constraints) {
              final metrics = [
                _QuotaMetricCard(
                  label: 'Total',
                  value: totalLabel,
                  statusLabel: quotaState,
                ),
                _QuotaMetricCard(
                  label: 'Used',
                  value: usedLabel,
                  progress: usedRatio,
                ),
                _QuotaMetricCard(label: 'Remaining', value: remainingLabel),
                _QuotaMetricCard(label: 'Recycle bin', value: deletedLabel),
              ];
              const gap = 16.0;
              final width = constraints.maxWidth;
              final columns = width >= 740
                  ? 4
                  : width >= 420
                  ? 2
                  : 1;
              final cardWidth = (width - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: metrics
                    .map((metric) => SizedBox(width: cardWidth, child: metric))
                    .toList(growable: false),
              );
            },
          ),
        ],
      );
    }

    return SettingsCard(padding: const EdgeInsets.all(24), child: body);
  }
}

class _QuotaMetricCard extends StatelessWidget {
  const _QuotaMetricCard({
    required this.label,
    required this.value,
    this.progress,
    this.statusLabel,
  });

  final String label;
  final String value;
  final double? progress;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    final hasProgress = progress != null;
    final isDark = colors.brightness == Brightness.dark;
    final cardBackground = isDark ? colors.secondary : const Color(0xFFF9FAFB);
    final valueColor = isDark ? colors.foreground : const Color(0xFF111827);
    final labelColor = isDark
        ? colors.mutedForeground
        : const Color(0xFF6B7280);
    final chipBg = isDark ? const Color(0xFF064E3B) : const Color(0xFFDCFCE7);
    final chipFg = isDark ? const Color(0xFF6EE7B7) : const Color(0xFF16A34A);
    final trackColor = isDark ? colors.border : const Color(0xFFE5E7EB);

    return Container(
      height: 140, // Fixed height for uniformity
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(24),
        // border: Border.all(color: colors.border.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: typography.xl2.copyWith(
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: typography.sm.copyWith(
                  color: labelColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (statusLabel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: chipBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FIcons.circleCheck, size: 14, color: chipFg),
                  const SizedBox(width: 6),
                  Text(
                    'Status: $statusLabel',
                    style: typography.xs.copyWith(
                      color: chipFg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else if (hasProgress)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FDeterminateProgress(
                  value: progress!.clamp(0, 1),
                  style: (style) => style.copyWith(
                    constraints: const BoxConstraints.tightFor(height: 8),
                    trackDecoration: BoxDecoration(
                      color: trackColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    fillDecoration: BoxDecoration(
                      color: const Color(0xFF3B82F6), // Blue progress
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            )
          else
            const SizedBox(), // Spacer if nothing else
        ],
      ),
    );
  }
}

String _formatSize(BigInt? value) {
  if (value == null) return 'Unknown';
  return formatFileSize(_bigIntToSafeInt(value));
}

int _bigIntToSafeInt(BigInt value) {
  const maxSafeInt = 0x7fffffffffffffff;
  final max = BigInt.from(maxSafeInt);
  if (value > max) {
    return maxSafeInt;
  }
  return value.toInt();
}
