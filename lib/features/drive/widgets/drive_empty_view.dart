import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class DriveEmptyView extends StatelessWidget {
  const DriveEmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FCard.raw(
            style: (style) => style.copyWith(
              decoration: BoxDecoration(
                color: colors.secondary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colors.secondary.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: SizedBox(
              width: 72,
              height: 72,
              child: Icon(
                FIcons.folderOpen,
                size: 34,
                color: colors.foreground,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nothing here',
            style: typography.lg.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.foreground,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Upload something to OneDrive to get started.',
            style: typography.sm.copyWith(
              color: colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}
