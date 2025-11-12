import 'package:flutter/material.dart';

class DriveEmptyView extends StatelessWidget {
  const DriveEmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.inbox_rounded, size: 72),
          SizedBox(height: 16),
          Text('空空如也，赶紧去 OneDrive 上传点内容吧。'),
        ],
      ),
    );
  }
}
