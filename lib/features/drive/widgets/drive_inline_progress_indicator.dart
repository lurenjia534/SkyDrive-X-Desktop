import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class DriveInlineProgressIndicator extends StatelessWidget {
  const DriveInlineProgressIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final widget = ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        minHeight: 3,
        color: colorScheme.primary,
        backgroundColor: colorScheme.primary.withOpacity(0.2),
      ),
    );
    return widget.animate().fadeIn(
      duration: 200.ms,
      curve: Curves.easeOutCubic,
    );
  }
}
