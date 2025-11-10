import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

class DriveHomePageController {
  _DriveHomePageState? _state;

  Future<void> refresh() async {
    final state = _state;
    if (state != null) {
      await state._loadInitial();
    }
  }

  bool get isLoading => _state?._isLoading ?? true;

  void _attach(_DriveHomePageState state) {
    _state = state;
  }

  void _detach(_DriveHomePageState state) {
    if (_state == state) {
      _state = null;
    }
  }
}

class DriveHomePage extends ConsumerStatefulWidget {
  const DriveHomePage({super.key, this.controller});

  final DriveHomePageController? controller;

  @override
  ConsumerState<DriveHomePage> createState() => _DriveHomePageState();
}

class _DriveHomePageState extends ConsumerState<DriveHomePage> {
  final List<drive_api.DriveItemSummary> _items = [];
  String? _nextLink;
  String? _error;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _loadInitial();
  }

  @override
  void didUpdateWidget(covariant DriveHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    super.dispose();
  }

  Future<void> _loadInitial() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final page = await drive_api.listDriveChildren(
        folderPath: null,
        nextLink: null,
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _nextLink = page.nextLink;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    final link = _nextLink;
    if (link == null || _isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
    });
    try {
      final page = await drive_api.listDriveChildren(
        folderPath: null,
        nextLink: link,
      );
      setState(() {
        _items.addAll(page.items);
        _nextLink = page.nextLink;
      });
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载更多失败：$err')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  String _buildSubtitle(drive_api.DriveItemSummary item) {
    final pieces = <String>[];
    if (item.isFolder) {
      final count = item.childCount?.toInt();
      if (count != null) {
        pieces.add('$count 项内容');
      }
    } else {
      final size = item.size?.toInt();
      if (size != null) {
        pieces.add(_formatSize(size));
      }
      if (item.mimeType != null) {
        pieces.add(item.mimeType!);
      }
    }
    if (item.lastModified != null) {
      pieces.add('更新于 ${item.lastModified}');
    }
    if (pieces.isEmpty) return '—';
    return pieces.join(' · ');
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return unitIndex == 0
        ? '${size.toStringAsFixed(0)} ${units[unitIndex]}'
        : '${size.toStringAsFixed(1)} ${units[unitIndex]}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _DriveErrorView(message: _error!, onRetry: _loadInitial);
    }
    if (_items.isEmpty) {
      return const _DriveEmptyView();
    }

    final listItemCount = _items.length + (_nextLink != null ? 1 : 0);

    return RefreshIndicator(
      onRefresh: _loadInitial,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        itemCount: listItemCount,
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return Padding(
              padding: EdgeInsets.zero,
              child: _DriveLoadMoreTile(
                isLoading: _isLoadingMore,
                onLoadMore: _loadMore,
              ),
            );
          }
          final item = _items[index];
          final subtitle = _buildSubtitle(item);
          return _DriveItemTile(
            item: item,
            subtitle: subtitle,
            colorScheme: colorScheme,
            onTap: () {
              if (item.isFolder) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('暂不支持子文件夹浏览，敬请期待。')),
                );
              }
            },
          );
        },
      ),
    );
  }
}

class _DriveEmptyView extends StatelessWidget {
  const _DriveEmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.inbox_rounded, size: 72),
          SizedBox(height: 16),
          Text('空空如也，赶紧去 OneDrive 上传点内容吧。'),
        ],
      ),
    );
  }
}

class _DriveErrorView extends StatelessWidget {
  const _DriveErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriveLoadMoreTile extends StatelessWidget {
  const _DriveLoadMoreTile({required this.isLoading, required this.onLoadMore});

  final bool isLoading;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: OutlinedButton.icon(
        onPressed: isLoading ? null : onLoadMore,
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.expand_more),
        label: Text(isLoading ? '加载中…' : '加载更多'),
      ),
    );
  }
}

class _DriveItemTile extends StatelessWidget {
  const _DriveItemTile({
    required this.item,
    required this.subtitle,
    required this.colorScheme,
    required this.onTap,
  });

  final drive_api.DriveItemSummary item;
  final String subtitle;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isFolder = item.isFolder;
    final iconData = isFolder
        ? Icons.folder_rounded
        : Icons.insert_drive_file_rounded;
    final iconBackground = isFolder
        ? colorScheme.primaryContainer.withOpacity(0.6)
        : colorScheme.surfaceVariant.withOpacity(0.6);
    final iconColor = isFolder
        ? colorScheme.onPrimaryContainer
        : colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        hoverColor: colorScheme.primary.withOpacity(0.05),
        splashColor: colorScheme.primary.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(iconData, color: iconColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
