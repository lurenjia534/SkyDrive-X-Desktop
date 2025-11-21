import 'package:flutter/material.dart';

class DriveUploadsPage extends StatelessWidget {
  const DriveUploadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_upload_rounded,
            size: 72,
            color: colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            '上传管理器',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '这里将显示正在上传和已完成的任务。当前仅支持小文件上传，后续会接入完整队列管理。',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
