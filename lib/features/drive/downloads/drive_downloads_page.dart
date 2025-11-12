import 'package:flutter/material.dart';

/// 下载管理器页面的占位实现，后续会接入真正的下载队列。
class DriveDownloadsPage extends StatelessWidget {
  const DriveDownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_download_rounded,
            size: 80,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Download Manager',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              '下载队列和历史记录即将上线。在此之前，你仍可在文件列表中发起单个下载。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
