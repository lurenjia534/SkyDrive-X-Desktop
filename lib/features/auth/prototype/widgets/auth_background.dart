import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class AuthBackground extends StatelessWidget {
  const AuthBackground({super.key, required this.colors});

  final FColors colors;

  @override
  Widget build(BuildContext context) {
    final gradient = RadialGradient(
      center: const Alignment(0, -0.7),
      radius: 1.6,
      colors: [colors.secondary.withValues(alpha: 0.35), colors.background],
    );

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _DotGridPainter(
                color: colors.border.withValues(alpha: 0.18),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DotGridPainter extends CustomPainter {
  _DotGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 28.0;
    const radius = 1.0;
    final paint = Paint()..color = color;

    for (double y = 0; y <= size.height; y += spacing) {
      for (double x = 0; x <= size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) =>
      oldDelegate.color != color;
}
