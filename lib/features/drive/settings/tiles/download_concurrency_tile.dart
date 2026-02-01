import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/drive/providers/download_concurrency_provider.dart';
import 'package:skydrivex/features/drive/settings/widgets/settings_card.dart';
import 'package:skydrivex/features/drive/settings/widgets/settings_card_header.dart';

class DownloadConcurrencyTile extends ConsumerWidget {
  const DownloadConcurrencyTile();

  static const _options = [1, 2, 3, 4, 5, 6, 7, 8];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadConcurrencyProvider);
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;

    final refreshAction = FButton.icon(
      onPress: state.isLoading
          ? null
          : () => ref.read(downloadConcurrencyProvider.notifier).refreshLimit(),
      style: FButtonStyle.ghost(),
      child: const Icon(FIcons.refreshCcw, size: 16),
    );

    Widget body;
    if (state.isLoading) {
      body = Center(
        child: FCircularProgress.loader(
          style: (style) => style.copyWith(
            iconStyle: IconThemeData(color: colors.primary, size: 20),
          ),
        ),
      );
    } else if (state.hasError) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unable to fetch download concurrency',
            style: typography.base.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            state.error.toString(),
            style: typography.sm.copyWith(color: colors.error),
          ),
          const SizedBox(height: 12),
          FButton(
            onPress: () =>
                ref.read(downloadConcurrencyProvider.notifier).refreshLimit(),
            style: FButtonStyle.outline(),
            prefix: const Icon(FIcons.refreshCcw, size: 16),
            child: Text(
              'Retry',
              style: typography.sm.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    } else {
      final value = state.value ?? _options.first;
      body = LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final accent = colors.primary.withValues(alpha: 0.12);

          Widget buildQuickOption(int option) {
            final selected = option == value;
            return FButton(
              onPress: () {
                if (option == value) return;
                unawaited(
                  ref
                      .read(downloadConcurrencyProvider.notifier)
                      .updateLimit(option),
                );
              },
              style: selected
                  ? FButtonStyle.primary(
                      (style) => style.copyWith(
                        decoration: FWidgetStateMap.all(
                          BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: colors.primary.withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                        contentStyle: (contentStyle) => contentStyle.copyWith(
                          textStyle: FWidgetStateMap.all(
                            typography.sm.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.primary,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                      ),
                    )
                  : FButtonStyle.outline(
                      (style) => style.copyWith(
                        decoration: FWidgetStateMap.all(
                          BoxDecoration(
                            color: colors.background,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: colors.border.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        contentStyle: (contentStyle) => contentStyle.copyWith(
                          textStyle: FWidgetStateMap.all(
                            typography.sm.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.foreground,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
              child: Text('$option tasks'),
            );
          }

          final selector = FSelect<int>(
            items: {
              for (final option in _options)
                '$option task${option == 1 ? '' : 's'}': option,
            },
            control: FSelectControl.lifted(
              value: value,
              onChange: (selected) {
                if (selected != null && selected != value) {
                  unawaited(
                    ref
                        .read(downloadConcurrencyProvider.notifier)
                        .updateLimit(selected),
                  );
                }
              },
            ),
            hint: 'Select task count',
          );

          final statusCard = Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current limit',
                  style: typography.xs.copyWith(
                    color: colors.mutedForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '$value',
                      style: typography.xl.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'tasks',
                      style: typography.sm.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );

          final header = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  FIcons.layers,
                  size: 20,
                  color: colors.foreground,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Concurrent download tasks',
                      style: typography.base.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Limit background concurrent downloads to avoid saturating bandwidth.',
                      style: typography.sm.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              if (!compact) statusCard,
            ],
          );

          final controls = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Limit',
                style: typography.sm.copyWith(
                  color: colors.mutedForeground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              selector,
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [2, 4, 6, 8].map(buildQuickOption).toList(),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: 16),
                statusCard,
                const SizedBox(height: 16),
                controls,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 18),
              controls,
            ],
          );
        },
      );
    }

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsCardHeader(
            label: 'Download concurrency',
            action: refreshAction,
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }
}
