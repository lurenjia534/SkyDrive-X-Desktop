import 'package:flutter/material.dart';
import 'package:skydrivex/features/drive/models/drive_breadcrumb.dart';

class DriveBreadcrumbBar extends StatelessWidget {
  const DriveBreadcrumbBar({
    super.key,
    required this.segments,
    required this.onRootTap,
    required this.onSegmentTap,
  });

  final List<DriveBreadcrumbSegment> segments;
  final VoidCallback onRootTap;
  final ValueChanged<int> onSegmentTap;

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[
      _BreadcrumbChip(
        label: '所有文件',
        isActive: segments.isEmpty,
        onTap: onRootTap,
      ),
    ];
    for (var i = 0; i < segments.length; i++) {
      widgets.add(const Icon(Icons.chevron_right_rounded, size: 18));
      widgets.add(
        _BreadcrumbChip(
          label: segments[i].name,
          isActive: i == segments.length - 1,
          onTap: () => onSegmentTap(i),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: widgets,
    );
  }
}

class _BreadcrumbChip extends StatelessWidget {
  const _BreadcrumbChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: isActive ? null : onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        backgroundColor: isActive
            ? colorScheme.primary.withValues(alpha: 0.12)
            : null,
        foregroundColor: isActive
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant,
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}
