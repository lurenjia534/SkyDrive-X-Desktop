import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/drive/providers/download_directory_provider.dart';
import 'package:skydrivex/features/drive/settings/widgets/settings_async_body.dart';
import 'package:skydrivex/features/drive/settings/widgets/settings_card.dart';
import 'package:skydrivex/features/drive/settings/widgets/settings_card_header.dart';
import 'package:skydrivex/utils/download_destination.dart';
import 'package:skydrivex/utils/toast.dart';

class DownloadDirectoryTile extends ConsumerWidget {
  const DownloadDirectoryTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadDirectoryProvider);
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;

    final refreshAction = FButton.icon(
      onPress: state.isLoading
          ? null
          : () =>
                ref.read(downloadDirectoryProvider.notifier).refreshDirectory(),
      style: FButtonStyle.ghost(),
      child: const Icon(FIcons.refreshCcw, size: 16),
    );

    Widget content = const SizedBox.shrink();
    if (state.hasValue) {
      final path = state.value ?? '';
      content = LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final pathBox = Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colors.secondary.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border.withValues(alpha: 0.4)),
            ),
            child: SelectableText(
              path,
              style: typography.base.copyWith(
                color: colors.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          );

          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.secondary.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      FIcons.folderOpen,
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
                          'Download directory',
                          style: typography.base.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.foreground,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Default location for all downloaded files.',
                          style: typography.sm.copyWith(
                            color: colors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              pathBox,
            ],
          );

          final actions = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FButton(
                onPress: () => _promptForPath(context, ref, path),
                style: FButtonStyle.primary(),
                prefix: const Icon(FIcons.mapPin, size: 16),
                child: Text(
                  'Change path',
                  style: typography.sm.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 10),
              FButton(
                onPress: () => _restoreDefault(context, ref),
                style: FButtonStyle.ghost(),
                prefix: const Icon(FIcons.undo, size: 16),
                child: Text(
                  'Restore default',
                  style: typography.sm.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: 16),
                actions,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: info),
              const SizedBox(width: 20),
              SizedBox(width: 180, child: actions),
            ],
          );
        },
      );
    }

    final body = SettingsAsyncBody(
      isLoading: state.isLoading,
      error: state.hasError ? state.error : null,
      errorTitle: 'Unable to fetch download path',
      onRetry: () =>
          ref.read(downloadDirectoryProvider.notifier).refreshDirectory(),
      retryIcon: FIcons.refreshCcw,
      child: content,
    );

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsCardHeader(
            label: 'Download location',
            action: refreshAction,
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }

  Future<void> _promptForPath(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Change download folder'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Folder path'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (result == null || result.isEmpty) return;
    try {
      await ref
          .read(downloadDirectoryProvider.notifier)
          .updateDirectory(result);
      if (context.mounted) {
        showToast(context, 'Download path updated');
      }
    } catch (err) {
      if (context.mounted) {
        showToast(context, 'Update failed: $err');
      }
    }
  }

  Future<void> _restoreDefault(BuildContext context, WidgetRef ref) async {
    final defaultPath = defaultDownloadDirectory();
    try {
      await ref
          .read(downloadDirectoryProvider.notifier)
          .updateDirectory(defaultPath);
      if (context.mounted) {
        showToast(context, 'Restored default download path');
      }
    } catch (err) {
      if (context.mounted) {
        showToast(context, 'Operation failed: $err');
      }
    }
  }
}
