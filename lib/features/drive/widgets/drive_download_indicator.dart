import 'package:flutter/material.dart';

class DriveDownloadIndicator extends StatelessWidget {
  const DriveDownloadIndicator({
    super.key,
    required this.isDownloading,
    required this.colorScheme,
  });

  final bool isDownloading;
  final ColorScheme colorScheme;

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
              ),
            )
          : Icon(
              Icons.download_rounded,
              key: const ValueKey('download-icon'),
              color: colorScheme.primary.withOpacity(0.85),
              size: 20,
            ),
    );
  }
}
