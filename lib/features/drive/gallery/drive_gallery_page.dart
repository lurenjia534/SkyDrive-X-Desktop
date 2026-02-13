import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

class DriveGalleryPage extends ConsumerWidget {
  const DriveGalleryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;

    // Placeholder empty state until the gallery data source is wired up.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: FCard.raw(
          style: (style) => style.copyWith(
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: colors.border.withValues(alpha: 0.7)),
              boxShadow: [
                BoxShadow(
                  color: colors.barrier.withValues(alpha: 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: colors.secondary.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(
                    FIcons.imageOff,
                    size: 34,
                    color: colors.foreground,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'No photos yet',
                  style: typography.lg.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.foreground,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your gallery will show images stored in OneDrive once they are available.',
                  textAlign: TextAlign.center,
                  style: typography.sm.copyWith(
                    color: colors.mutedForeground,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
