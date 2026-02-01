import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class SettingsAsyncBody extends StatelessWidget {
  const SettingsAsyncBody({
    super.key,
    required this.isLoading,
    required this.errorTitle,
    required this.child,
    this.error,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.retryIcon,
  });

  final bool isLoading;
  final Object? error;
  final String errorTitle;
  final Widget child;
  final VoidCallback? onRetry;
  final String retryLabel;
  final IconData? retryIcon;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;

    if (isLoading) {
      return Center(
        child: FCircularProgress.loader(
          style: (style) => style.copyWith(
            iconStyle: IconThemeData(color: colors.primary, size: 20),
          ),
        ),
      );
    }

    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            errorTitle,
            style: typography.base.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: typography.sm.copyWith(color: colors.error),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FButton(
              onPress: onRetry,
              style: FButtonStyle.outline(),
              prefix: Icon(retryIcon ?? FIcons.refreshCcw, size: 16),
              child: Text(
                retryLabel,
                style: typography.sm.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      );
    }

    return child;
  }
}
