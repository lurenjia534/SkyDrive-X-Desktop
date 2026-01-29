import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

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
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: FButton(
        onPress: isLoading ? null : onLoadMore,
        style: FButtonStyle.outline(),
        prefix: isLoading
            ? FCircularProgress.loader(
                style: (style) => style.copyWith(
                  iconStyle: IconThemeData(
                    color: colors.primary,
                    size: 16,
                  ),
                ),
              )
            : const Icon(FIcons.chevronDown, size: 16),
        child: Text(
          isLoading ? 'Loading…' : 'Load more',
          style: typography.sm.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class DriveLoadMoreCard extends StatelessWidget {
  const DriveLoadMoreCard({
    super.key,
    required this.isLoading,
    required this.onLoadMore,
  });

  final bool isLoading;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        isLoading
            ? FCircularProgress.loader(
                style: (style) => style.copyWith(
                  iconStyle: IconThemeData(
                    color: colors.primary,
                    size: 18,
                  ),
                ),
              )
            : Icon(
                FIcons.chevronDown,
                color: colors.primary,
                size: 20,
              ),
        const SizedBox(height: 8),
        Text(
          isLoading ? 'Loading…' : 'Load more',
          style: typography.sm.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );

    return Material(
      color: colors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.border.withValues(alpha: 0.7)),
      ),
      child: InkWell(
        onTap: isLoading ? null : onLoadMore,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Center(child: content),
        ),
      ),
    );
  }
}
