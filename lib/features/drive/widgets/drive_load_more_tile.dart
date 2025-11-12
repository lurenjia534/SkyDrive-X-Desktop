import 'package:flutter/material.dart';

class DriveLoadMoreTile extends StatelessWidget {
  const DriveLoadMoreTile({
    super.key,
    required this.isLoading,
    required this.onLoadMore,
  });

  final bool isLoading;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: OutlinedButton.icon(
        onPressed: isLoading ? null : onLoadMore,
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.expand_more),
        label: Text(isLoading ? '加载中…' : '加载更多'),
      ),
    );
  }
}
