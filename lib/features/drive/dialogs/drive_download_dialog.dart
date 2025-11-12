import 'package:flutter/material.dart';

class DriveDownloadDialog extends StatelessWidget {
  const DriveDownloadDialog({super.key, required this.fileName});

  final String fileName;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('正在下载'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(),
          ),
          const SizedBox(height: 16),
          Text(
            fileName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
