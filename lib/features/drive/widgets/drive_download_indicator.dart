import 'package:flutter/material.dart';

class DriveDownloadIndicator extends StatelessWidget {
  const DriveDownloadIndicator({
    super.key,
    required this.isDownloading,
    required this.colorScheme,
    this.progress,
  });

  final bool isDownloading;
  final ColorScheme colorScheme;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: isDownloading
          ? SizedBox(
              key: const ValueKey('download-progress'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
                value: progress?.clamp(0, 1),
              ),
            )
          : Icon(
              Icons.download_rounded,
              key: const ValueKey('download-icon'),
              color: colorScheme.primary.withValues(alpha: 0.85),
              size: 20,
            ),
    );
  }
}
