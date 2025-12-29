import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
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
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    final divider = Icon(
      FIcons.chevronRight,
      size: 14,
      color: colors.mutedForeground,
    );

    final items = <FBreadcrumbItem>[
      if (segments.isEmpty)
        FBreadcrumbItem(
          current: true,
          child: Text(
            '所有文件',
            style: typography.sm.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.foreground,
            ),
          ),
        )
      else
        FBreadcrumbItem(
          onPress: onRootTap,
          child: Text(
            '所有文件',
            style: typography.sm.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.mutedForeground,
            ),
          ),
        ),
    ];

    if (segments.length > 2) {
      final collapsedItems = <FItem>[
        for (var i = 0; i < segments.length - 2; i++)
          FItem(
            title: Text(segments[i].name),
            onPress: () => onSegmentTap(i),
          ),
      ];
      items.add(
        FBreadcrumbItem.collapsed(
          menu: [
            FItemGroup(children: collapsedItems),
          ],
          offset: Offset.zero,
          traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
        ),
      );
      items.add(
        FBreadcrumbItem(
          onPress: () => onSegmentTap(segments.length - 2),
          child: Text(
            segments[segments.length - 2].name,
            style: typography.sm.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.mutedForeground,
            ),
          ),
        ),
      );
      items.add(
        FBreadcrumbItem(
          current: true,
          child: Text(
            segments.last.name,
            style: typography.sm.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.foreground,
            ),
          ),
        ),
      );
    } else {
      for (var i = 0; i < segments.length; i++) {
        final isCurrent = i == segments.length - 1;
        items.add(
          FBreadcrumbItem(
            current: isCurrent,
            onPress: isCurrent ? null : () => onSegmentTap(i),
            child: Text(
              segments[i].name,
              style: typography.sm.copyWith(
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                color: isCurrent ? colors.foreground : colors.mutedForeground,
              ),
            ),
          ),
        );
      }
    }

    return FBreadcrumb(
      divider: divider,
      children: items,
    );
  }
}
