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
