import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/models/drive_breadcrumb.dart';
import 'package:skydrivex/features/drive/providers/drive_move_provider.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

/// 侧边抽屉式的“移动到”选择器，使用独立的浏览状态，不影响主界面。
class DriveMoveSheet extends ConsumerWidget {
  const DriveMoveSheet({super.key, required this.item, required this.onMove});

  final drive_api.DriveItemSummary item;
  final Future<void> Function(String? targetFolderId) onMove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driveMoveBrowserProvider);
    final controller = ref.read(driveMoveBrowserProvider.notifier);
    final breadcrumbs = state.breadcrumbs;
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface,
      elevation: 12,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: '返回上一级',
                    onPressed: breadcrumbs.isEmpty ? null : controller.goBack,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '移动 “${item.name}”',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  breadcrumbs.isEmpty
                      ? '当前位置：根目录'
                      : _breadcrumbText(breadcrumbs),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: state.isLoading
                      ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : state.error != null
                          ? Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.error_outline_rounded),
                                    const SizedBox(height: 8),
                                    Text(
                                      '加载失败：${state.error}',
                                      textAlign: TextAlign.center,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 8),
                                    OutlinedButton.icon(
                                      onPressed: controller.refreshCurrent,
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: const Text('重试'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: state.items.length,
                              itemBuilder: (context, index) {
                                final entry = state.items[index];
                                if (!entry.isFolder) {
                                  return const SizedBox.shrink();
                                }
                                final isSelf = entry.id == item.id;
                                return ListTile(
                                  leading: const Icon(Icons.folder_rounded),
                                  title: Text(entry.name),
                                  enabled: !isSelf,
                                  subtitle: entry.childCount != null
                                      ? Text('${entry.childCount} 项')
                                      : null,
                                  onTap: isSelf
                                      ? null
                                      : () => controller.enterFolder(entry),
                                );
                              },
                            ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                child: FilledButton(
                  onPressed: () {
                    final target = breadcrumbs.isEmpty
                        ? null
                        : breadcrumbs.last.id;
                    onMove(target);
                  },
                  child: const Text('移动到当前目录'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _breadcrumbText(List<DriveBreadcrumbSegment> segments) {
  return segments.map((s) => s.name).join(' / ');
}
