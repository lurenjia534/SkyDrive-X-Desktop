import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/drive/providers/download_concurrency_provider.dart';
import 'package:skydrivex/features/drive/providers/download_directory_provider.dart';
import 'package:skydrivex/features/drive/providers/drive_info_provider.dart';
import 'package:skydrivex/features/drive/utils/drive_item_formatters.dart';
import 'package:skydrivex/theme/app_theme_provider.dart';
import 'package:skydrivex/utils/download_destination.dart';
import 'package:skydrivex/utils/toast.dart';

class DriveSettingsPage extends ConsumerStatefulWidget {
  const DriveSettingsPage({super.key});

  @override
  ConsumerState<DriveSettingsPage> createState() => _DriveSettingsPageState();
}

class _DriveSettingsPageState extends ConsumerState<DriveSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final themeAsync = ref.watch(appThemeProvider);
    final themeState = themeAsync.value ?? AppThemeState.defaults;
    final themeLoading = themeAsync.isLoading;
    final themeController = ref.read(appThemeProvider.notifier);
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth =
            constraints.maxWidth >= 1200 ? 1080.0 : constraints.maxWidth;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentWidth),
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(24, 20, 24, 4),
                    child: _SettingsHeader(),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentWidth),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _SettingsSectionTitle(
                          title: 'Account & storage',
                          subtitle: 'Manage OneDrive quota and account details.',
                        ),
                        const SizedBox(height: 16),
                        const _DriveInfoTile(),
                        const SizedBox(height: 28),
                        const _SettingsSectionTitle(
                          title: 'Experience',
                          subtitle:
                              'Personalize visuals and monitor sync status.',
                        ),
                        const SizedBox(height: 16),
                        _SettingsGrid(
                          minTileWidth: 460,
                          children: [
                            _ThemeSettingsTile(
                              followSystem: themeState.followSystem,
                              manualMode: themeState.manualMode,
                              enabled: !themeLoading,
                              onFollowSystemChanged: (value) =>
                                  unawaited(
                                    themeController.setFollowSystem(value),
                                  ),
                              onManualModeChanged: (mode) =>
                                  unawaited(themeController.setManualMode(mode)),
                            ),
                            const _SettingsSyncTile(),
                          ],
                        ),
                        const SizedBox(height: 28),
                        const _SettingsSectionTitle(
                          title: 'Downloads',
                          subtitle:
                              'Control where files land and how many tasks run.',
                        ),
                        const SizedBox(height: 16),
                        const _SettingsGrid(
                          minTileWidth: 460,
                          children: [
                            _DownloadDirectoryTile(),
                            _DownloadConcurrencyTile(),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FCard.raw(
      style: (style) => style.copyWith(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: colors.barrier.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
      ),
      child: Padding(
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: child,
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Settings',
          style: typography.xl3.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.foreground,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Tune your OneDrive workspace for desktop use.',
          style: typography.sm.copyWith(color: colors.mutedForeground),
        ),
      ],
    );
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: typography.base.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.foreground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: typography.sm.copyWith(
            color: colors.mutedForeground,
          ),
        ),
      ],
    );
  }
}

class _SettingsGrid extends StatelessWidget {
  const _SettingsGrid({
    required this.children,
    this.minTileWidth = 420,
    this.gap = 16,
  });

  final List<Widget> children;
  final double minTileWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = (width / minTileWidth).floor().clamp(1, 2);
        final tileWidth = (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: children
              .map((child) => SizedBox(width: tileWidth, child: child))
              .toList(growable: false),
        );
      },
    );
  }
}

class _SettingsCardHeader extends StatelessWidget {
  const _SettingsCardHeader({required this.label, this.action});

  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: typography.sm.copyWith(
              color: colors.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class _ThemeSettingsTile extends StatelessWidget {
  const _ThemeSettingsTile({
    required this.followSystem,
    required this.manualMode,
    required this.onFollowSystemChanged,
    required this.onManualModeChanged,
    this.enabled = true,
  });

  final bool followSystem;
  final ThemeMode manualMode;
  final ValueChanged<bool> onFollowSystemChanged;
  final ValueChanged<ThemeMode> onManualModeChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    return _SettingsCard(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
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
                  FIcons.palette,
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
                      'Appearance',
                      style: typography.base.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Control the theme and keep it in sync with your system.',
                      style: typography.sm.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final followCard = Container(
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
                        'Follow system theme',
                        style: typography.base.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.foreground,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Automatically match light or dark mode.',
                        style: typography.sm.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                FSwitch(
                  value: followSystem,
                  enabled: enabled,
                  onChange: enabled ? onFollowSystemChanged : null,
                ),
              ],
            ),
          );

          final modeButtons = Row(
            children: [
              Expanded(
                child: FButton(
                  onPress: enabled
                      ? () => onManualModeChanged(ThemeMode.light)
                      : null,
                  style: manualMode == ThemeMode.light
                      ? FButtonStyle.primary(
                          (style) => style.copyWith(
                            decoration: FWidgetStateMap.all(
                              BoxDecoration(
                                color: colors.foreground,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            contentStyle: (contentStyle) =>
                                contentStyle.copyWith(
                                  textStyle: FWidgetStateMap.all(
                                    typography.sm.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: colors.background,
                                    ),
                                  ),
                                ),
                          ),
                        )
                      : FButtonStyle.outline(
                          (style) => style.copyWith(
                            decoration: FWidgetStateMap.all(
                              BoxDecoration(
                                color: colors.background,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: colors.border.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                          ),
                        ),
                  child: const Text('Light'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FButton(
                  onPress: enabled
                      ? () => onManualModeChanged(ThemeMode.dark)
                      : null,
                  style: manualMode == ThemeMode.dark
                      ? FButtonStyle.primary(
                          (style) => style.copyWith(
                            decoration: FWidgetStateMap.all(
                              BoxDecoration(
                                color: colors.foreground,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            contentStyle: (contentStyle) =>
                                contentStyle.copyWith(
                                  textStyle: FWidgetStateMap.all(
                                    typography.sm.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: colors.background,
                                    ),
                                  ),
                                ),
                          ),
                        )
                      : FButtonStyle.outline(
                          (style) => style.copyWith(
                            decoration: FWidgetStateMap.all(
                              BoxDecoration(
                                color: colors.background,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: colors.border.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                          ),
                        ),
                  child: const Text('Dark'),
                ),
              ),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 16),
              followCard,
              if (!followSystem) ...[
                const SizedBox(height: 16),
                Text(
                  'Theme mode',
                  style: typography.sm.copyWith(
                    color: colors.mutedForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                if (compact)
                  Column(
                    children: [
                      modeButtons,
                    ],
                  )
                else
                  modeButtons,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SettingsSyncTile extends StatelessWidget {
  const _SettingsSyncTile();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    final pillBackground = colors.muted;
    final pillForeground = colors.mutedForeground;
    return _SettingsCard(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final actionButton = FButton(
            onPress: () {},
            style: FButtonStyle.primary(
              (style) => style.copyWith(
                decoration: FWidgetStateMap.all(
                  BoxDecoration(
                    color: colors.foreground,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                contentStyle: (contentStyle) => contentStyle.copyWith(
                  textStyle: FWidgetStateMap.all(
                    typography.sm.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.background,
                      height: 1,
                    ),
                  ),
                  iconStyle: FWidgetStateMap.all(
                    IconThemeData(size: 16, color: colors.background),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  spacing: 8,
                ),
              ),
            ),
            prefix: const Icon(FIcons.rotateCw),
            child: const Text('Sync now'),
          );

          final status = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Sync status',
                    style: typography.xl.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.foreground,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF34D399), // Green dot
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: pillBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Last sync: just now · Interval: 15 min',
                  style: typography.sm.copyWith(
                    color: pillForeground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sync',
                style: typography.sm.copyWith(color: colors.mutedForeground),
              ),
              const SizedBox(height: 16),
              if (compact) ...[
                status,
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: actionButton,
                ),
              ] else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: status),
                    const SizedBox(width: 16),
                    actionButton,
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DriveInfoTile extends ConsumerWidget {
  const _DriveInfoTile();

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

    return _SettingsCard(padding: const EdgeInsets.all(24), child: body);
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

class _DownloadDirectoryTile extends ConsumerWidget {
  const _DownloadDirectoryTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadDirectoryProvider);
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;

    final refreshAction = FButton.icon(
      onPress: state.isLoading
          ? null
          : () =>
                ref.read(downloadDirectoryProvider.notifier).refreshDirectory(),
      style: FButtonStyle.ghost(),
      child: const Icon(FIcons.refreshCcw, size: 16),
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
            'Unable to fetch download path',
            style: typography.base.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            state.error.toString(),
            style: typography.sm.copyWith(color: colors.error),
          ),
          const SizedBox(height: 12),
          FButton(
            onPress: () =>
                ref.read(downloadDirectoryProvider.notifier).refreshDirectory(),
            style: FButtonStyle.outline(),
            prefix: const Icon(FIcons.refreshCcw, size: 16),
            child: Text(
              'Retry',
              style: typography.sm.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    } else {
      final path = state.value ?? '';
      body = LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final pathBox = Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colors.secondary.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border.withValues(alpha: 0.4)),
            ),
            child: SelectableText(
              path,
              style: typography.base.copyWith(
                color: colors.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          );

          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.secondary.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      FIcons.folderOpen,
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
                          'Download directory',
                          style: typography.base.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.foreground,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Default location for all downloaded files.',
                          style: typography.sm.copyWith(
                            color: colors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              pathBox,
            ],
          );

          final actions = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FButton(
                onPress: () => _promptForPath(context, ref, path),
                style: FButtonStyle.primary(),
                prefix: const Icon(FIcons.mapPin, size: 16),
                child: Text(
                  'Change path',
                  style: typography.sm.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 10),
              FButton(
                onPress: () => _restoreDefault(context, ref),
                style: FButtonStyle.ghost(),
                prefix: const Icon(FIcons.undo, size: 16),
                child: Text(
                  'Restore default',
                  style: typography.sm.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: 16),
                actions,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: info),
              const SizedBox(width: 20),
              SizedBox(width: 180, child: actions),
            ],
          );
        },
      );
    }

    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsCardHeader(
            label: 'Download location',
            action: refreshAction,
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }

  Future<void> _promptForPath(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Change download folder'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Folder path'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (result == null || result.isEmpty) return;
    try {
      await ref
          .read(downloadDirectoryProvider.notifier)
          .updateDirectory(result);
      if (context.mounted) {
        showToast(context, 'Download path updated');
      }
    } catch (err) {
      if (context.mounted) {
        showToast(context, 'Update failed: $err');
      }
    }
  }

  Future<void> _restoreDefault(BuildContext context, WidgetRef ref) async {
    final defaultPath = defaultDownloadDirectory();
    try {
      await ref
          .read(downloadDirectoryProvider.notifier)
          .updateDirectory(defaultPath);
      if (context.mounted) {
        showToast(context, 'Restored default download path');
      }
    } catch (err) {
      if (context.mounted) {
        showToast(context, 'Operation failed: $err');
      }
    }
  }
}

class _DownloadConcurrencyTile extends ConsumerWidget {
  const _DownloadConcurrencyTile();

  static const _options = [1, 2, 3, 4, 5, 6, 7, 8];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadConcurrencyProvider);
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;

    final refreshAction = FButton.icon(
      onPress: state.isLoading
          ? null
          : () => ref.read(downloadConcurrencyProvider.notifier).refreshLimit(),
      style: FButtonStyle.ghost(),
      child: const Icon(FIcons.refreshCcw, size: 16),
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
            'Unable to fetch download concurrency',
            style: typography.base.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            state.error.toString(),
            style: typography.sm.copyWith(color: colors.error),
          ),
          const SizedBox(height: 12),
          FButton(
            onPress: () =>
                ref.read(downloadConcurrencyProvider.notifier).refreshLimit(),
            style: FButtonStyle.outline(),
            prefix: const Icon(FIcons.refreshCcw, size: 16),
            child: Text(
              'Retry',
              style: typography.sm.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    } else {
      final value = state.value ?? _options.first;
      body = LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final accent = colors.primary.withValues(alpha: 0.12);

          Widget buildQuickOption(int option) {
            final selected = option == value;
            return FButton(
              onPress: () {
                if (option == value) return;
                unawaited(
                  ref
                      .read(downloadConcurrencyProvider.notifier)
                      .updateLimit(option),
                );
              },
              style: selected
                  ? FButtonStyle.primary(
                      (style) => style.copyWith(
                        decoration: FWidgetStateMap.all(
                          BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: colors.primary.withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                        contentStyle: (contentStyle) => contentStyle.copyWith(
                          textStyle: FWidgetStateMap.all(
                            typography.sm.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.primary,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                      ),
                    )
                  : FButtonStyle.outline(
                      (style) => style.copyWith(
                        decoration: FWidgetStateMap.all(
                          BoxDecoration(
                            color: colors.background,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: colors.border.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        contentStyle: (contentStyle) => contentStyle.copyWith(
                          textStyle: FWidgetStateMap.all(
                            typography.sm.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.foreground,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
              child: Text('$option tasks'),
            );
          }

          final selector = FSelect<int>(
            items: {
              for (final option in _options)
                '$option task${option == 1 ? '' : 's'}': option,
            },
            control: FSelectControl.lifted(
              value: value,
              onChange: (selected) {
                if (selected != null && selected != value) {
                  unawaited(
                    ref
                        .read(downloadConcurrencyProvider.notifier)
                        .updateLimit(selected),
                  );
                }
              },
            ),
            hint: 'Select task count',
          );

          final statusCard = Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current limit',
                  style: typography.xs.copyWith(
                    color: colors.mutedForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '$value',
                      style: typography.xl.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'tasks',
                      style: typography.sm.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
                  FIcons.layers,
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
                      'Concurrent download tasks',
                      style: typography.base.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Limit background concurrent downloads to avoid saturating bandwidth.',
                      style: typography.sm.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              if (!compact) statusCard,
            ],
          );

          final controls = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Limit',
                style: typography.sm.copyWith(
                  color: colors.mutedForeground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              selector,
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [2, 4, 6, 8].map(buildQuickOption).toList(),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: 16),
                statusCard,
                const SizedBox(height: 16),
                controls,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 18),
              controls,
            ],
          );
        },
      );
    }

    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsCardHeader(
            label: 'Download concurrency',
            action: refreshAction,
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }
}
