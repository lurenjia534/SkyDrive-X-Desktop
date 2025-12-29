import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class DriveDownloadIndicator extends StatelessWidget {
  const DriveDownloadIndicator({
    super.key,
    required this.isDownloading,
    this.progress,
  });

  final bool isDownloading;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: isDownloading
          ? SizedBox(
              key: const ValueKey('download-progress'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.primary,
                value: progress?.clamp(0, 1),
              ),
            )
          : Icon(
              Icons.download_rounded,
              key: const ValueKey('download-icon'),
              color: colors.primary.withValues(alpha: 0.85),
              size: 20,
            ),
    );
  }
}
