import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class DriveLoadingList extends StatelessWidget {
  const DriveLoadingList({super.key});

  static const _itemCount = 8;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _itemCount,
      itemBuilder: (context, index) => DriveSkeletonTile(index: index),
    );
  }
}

class DriveSkeletonTile extends StatelessWidget {
  const DriveSkeletonTile({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = colorScheme.surfaceVariant.withOpacity(0.35);
    final highlightColor = colorScheme.onSurface.withOpacity(0.08);

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const DriveSkeletonBlock(width: 44, height: 44, radius: 14),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                DriveSkeletonBlock(width: double.infinity, height: 16),
                SizedBox(height: 8),
                DriveSkeletonBlock(width: 180, height: 12),
              ],
            ),
          ),
        ],
      ),
    );

    return row
        .animate(delay: Duration(milliseconds: 60 * index))
        .fadeIn(duration: 260.ms, curve: Curves.easeOutCubic)
        .shimmer(duration: 1200.ms, color: highlightColor)
        .tint(color: baseColor.withOpacity(0.15));
  }
}

class DriveSkeletonBlock extends StatelessWidget {
  const DriveSkeletonBlock({
    super.key,
    this.width,
    required this.height,
    this.radius = 12,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
