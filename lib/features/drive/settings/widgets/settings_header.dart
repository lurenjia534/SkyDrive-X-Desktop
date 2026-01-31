import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class SettingsHeader extends StatelessWidget {
  const SettingsHeader({super.key});

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
