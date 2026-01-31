import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class SettingsCardHeader extends StatelessWidget {
  const SettingsCardHeader({super.key, required this.label, this.action});

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
