import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/drive/settings/widgets/settings_card.dart';

class ThemeSettingsTile extends StatelessWidget {
  const ThemeSettingsTile({
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
    return SettingsCard(
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
