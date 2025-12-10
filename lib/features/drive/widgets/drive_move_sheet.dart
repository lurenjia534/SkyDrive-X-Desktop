import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/models/drive_breadcrumb.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

/// 侧边抽屉式的“移动到”选择器，使用独立的浏览状态，不影响主界面。
class DriveMoveSheet extends ConsumerStatefulWidget {
  const DriveMoveSheet({super.key, required this.item, required this.onMove});

  final drive_api.DriveItemSummary item;
  final Future<void> Function(String? targetFolderId) onMove;

  @override
  ConsumerState<DriveMoveSheet> createState() => _DriveMoveSheetState();
}

class _DriveMoveSheetState extends ConsumerState<DriveMoveSheet> {
  String? _currentFolderId;
  List<DriveBreadcrumbSegment> _breadcrumbs = const [];
  bool _loading = true;
  List<drive_api.DriveItemSummary> _items = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFolder(null, const []);
  }

  Future<void> _loadFolder(
    String? folderId,
    List<DriveBreadcrumbSegment> breadcrumbs,
  ) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await drive_api.listDriveChildren(
        folderId: folderId,
        folderPath: null,
        nextLink: null,
      );
      setState(() {
        _currentFolderId = folderId;
        _breadcrumbs = breadcrumbs;
        _items = page.items;
        _loading = false;
      });
    } catch (err) {
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  void _enterFolder(drive_api.DriveItemSummary folder) {
    final nextBreadcrumbs = [
      ..._breadcrumbs,
      DriveBreadcrumbSegment(id: folder.id, name: folder.name),
    ];
    _loadFolder(folder.id, nextBreadcrumbs);
  }

  void _goBack() {
    if (_breadcrumbs.isEmpty) return;
    final trimmed = _breadcrumbs.sublist(0, _breadcrumbs.length - 1);
    final parentId = trimmed.isNotEmpty ? trimmed.last.id : null;
    _loadFolder(parentId, trimmed);
  }

  @override
  Widget build(BuildContext context) {
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
                    onPressed: _breadcrumbs.isEmpty ? null : _goBack,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '移动 “${widget.item.name}”',
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
                  _breadcrumbs.isEmpty
                      ? '当前位置：根目录'
                      : _breadcrumbText(_breadcrumbs),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline_rounded),
                                const SizedBox(height: 8),
                                Text(
                                  '加载失败：$_error',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _loadFolder(
                                    _currentFolderId,
                                    _breadcrumbs,
                                  ),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('重试'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final entry = _items[index];
                            if (!entry.isFolder) {
                              return const SizedBox.shrink();
                            }
                            final isSelf = entry.id == widget.item.id;
                            return ListTile(
                              leading: const Icon(Icons.folder_rounded),
                              title: Text(entry.name),
                              enabled: !isSelf,
                              subtitle: entry.childCount != null
                                  ? Text('${entry.childCount} 项')
                                  : null,
                              onTap: isSelf ? null : () => _enterFolder(entry),
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
                    final target = _breadcrumbs.isEmpty
                        ? null
                        : _breadcrumbs.last.id;
                    widget.onMove(target);
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
