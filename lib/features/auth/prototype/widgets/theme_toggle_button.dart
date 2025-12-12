import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key, required this.colors});

  final FColors colors;

  @override
  Widget build(BuildContext context) {
    // Check if current theme is dark mode based on background luminance
    final isDark = colors.background.computeLuminance() < 0.5;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colors.background,
        shape: BoxShape.circle,
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: colors.barrier.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        onPressed: () {
          // Theme toggle is typically handled at the app level
          // This is just a visual placeholder
        },
        icon: Icon(
          isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          size: 20,
          color: colors.foreground,
        ),
        tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      ),
    );
  }
}
