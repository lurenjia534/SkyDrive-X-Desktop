import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    required this.typography,
    required this.colors,
  });

  final FTypography typography;
  final FColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        MicrosoftLogo(colors: colors, size: 56),
        const SizedBox(height: 20),
        Text(
          'Welcome\nback',
          textAlign: TextAlign.center,
          style: typography.xl3.copyWith(
            fontWeight: FontWeight.w800,
            color: colors.foreground,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Enter your User ID to securely connect\nto your Microsoft services.',
          textAlign: TextAlign.center,
          style: typography.sm.copyWith(
            color: colors.mutedForeground,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class BrandPanel extends StatelessWidget {
  const BrandPanel({
    super.key,
    required this.typography,
    required this.colors,
    required this.radius,
  });

  final FTypography typography;
  final FColors colors;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondary.withValues(alpha: 0.5),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(radius),
          bottomLeft: Radius.circular(radius),
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MicrosoftLogo(colors: colors, size: 64),
              const SizedBox(height: 28),
              Text(
                'Welcome\nback',
                textAlign: TextAlign.center,
                style: typography.xl4.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: colors.foreground,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Enter your User ID to securely connect\nto your Microsoft services.',
                textAlign: TextAlign.center,
                style: typography.sm.copyWith(
                  color: colors.mutedForeground,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Microsoft-style logo with 4-dot grid icon
class MicrosoftLogo extends StatelessWidget {
  const MicrosoftLogo({super.key, required this.colors, required this.size});

  final FColors colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: _FourDotGrid(
          dotSize: size * 0.16,
          spacing: size * 0.08,
          color: colors.primaryForeground,
        ),
      ),
    );
  }
}

/// 4-dot grid pattern similar to the design mockup
class _FourDotGrid extends StatelessWidget {
  const _FourDotGrid({
    required this.dotSize,
    required this.spacing,
    required this.color,
  });

  final double dotSize;
  final double spacing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(size: dotSize, color: color),
            SizedBox(width: spacing),
            _Dot(size: dotSize, color: color),
          ],
        ),
        SizedBox(height: spacing),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(size: dotSize, color: color),
            SizedBox(width: spacing),
            _Dot(size: dotSize, color: color),
          ],
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
    );
  }
}
