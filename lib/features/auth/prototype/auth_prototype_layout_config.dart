import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

enum AuthPrototypeLayout { mobile, tablet, desktop }

/// 将布局分支的计算集中到一个配置对象里，减少 build 方法复杂度。
class AuthPrototypeLayoutConfig {
  const AuthPrototypeLayoutConfig._({
    required this.layout,
    required this.cardMaxWidth,
    required this.pagePadding,
    required this.cardPadding,
    required this.cardRadius,
  });

  final AuthPrototypeLayout layout;
  final double cardMaxWidth;
  final EdgeInsets pagePadding;
  final EdgeInsets cardPadding;
  final double cardRadius;

  bool get isDesktop => layout == AuthPrototypeLayout.desktop;

  factory AuthPrototypeLayoutConfig.fromWidth({
    required double width,
    required FBreakpoints breakpoints,
  }) {
    final layout = switch (width) {
      _ when width < breakpoints.sm => AuthPrototypeLayout.mobile,
      _ when width < breakpoints.lg => AuthPrototypeLayout.tablet,
      _ => AuthPrototypeLayout.desktop,
    };

    final cardMaxWidth = switch (layout) {
      AuthPrototypeLayout.mobile => double.infinity,
      AuthPrototypeLayout.tablet => 600.0,
      AuthPrototypeLayout.desktop => 900.0,
    };

    final pagePadding = switch (layout) {
      AuthPrototypeLayout.mobile => const EdgeInsets.all(16),
      _ => const EdgeInsets.all(32),
    };

    final cardPadding = switch (layout) {
      AuthPrototypeLayout.mobile => const EdgeInsets.all(20),
      AuthPrototypeLayout.tablet => const EdgeInsets.symmetric(
        horizontal: 28,
        vertical: 30,
      ),
      AuthPrototypeLayout.desktop => EdgeInsets.zero,
    };

    final cardRadius = layout == AuthPrototypeLayout.mobile ? 16.0 : 20.0;

    return AuthPrototypeLayoutConfig._(
      layout: layout,
      cardMaxWidth: cardMaxWidth,
      pagePadding: pagePadding,
      cardPadding: cardPadding,
      cardRadius: cardRadius,
    );
  }
}
