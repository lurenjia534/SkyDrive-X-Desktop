import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/drive/settings/widgets/settings_card.dart';

class SettingsSyncTile extends StatelessWidget {
  const SettingsSyncTile();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    final pillBackground = colors.muted;
    final pillForeground = colors.mutedForeground;
    return SettingsCard(
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
