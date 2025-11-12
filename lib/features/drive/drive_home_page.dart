import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

class DriveHomePageController {
  _DriveHomePageState? _state;
  List<_FolderNode> _cachedStack = [];

  Future<void> refresh({bool showSkeleton = false}) async {
    final state = _state;
    if (state != null) {
      await state._loadCurrentFolder(showSkeleton: showSkeleton);
    }
  }

  bool get isLoading => _state?._isLoading ?? true;

  List<_FolderNode> get cachedStack => List.unmodifiable(_cachedStack);

  void _cacheStack(List<_FolderNode> stack) {
    _cachedStack = List<_FolderNode>.from(stack);
  }

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
  final List<_FolderNode> _folderStack = [];

  String? get _currentFolderId =>
      _folderStack.isEmpty ? null : _folderStack.last.id;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    final cached = widget.controller?.cachedStack ?? const [];
    if (cached.isNotEmpty) {
      _folderStack.addAll(cached);
    }
    _loadCurrentFolder(showSkeleton: true);
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

  Future<void> _loadCurrentFolder({bool showSkeleton = false}) async {
    if (!mounted) return;
    setState(() {
      if (showSkeleton) {
        _items.clear();
        _nextLink = null;
      }
      _isLoading = true;
      _error = null;
    });
    try {
      final page = await drive_api.listDriveChildren(
        folderId: _currentFolderId,
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
      widget.controller?._cacheStack(_folderStack);
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
        folderId: null,
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

  void _handleItemTap(drive_api.DriveItemSummary item) {
    if (item.isFolder) {
      setState(() {
        _folderStack.add(_FolderNode(id: item.id, name: item.name));
      });
      widget.controller?._cacheStack(_folderStack);
      _loadCurrentFolder(showSkeleton: true);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('暂不支持文件操作，敬请期待。')));
  }

  void _handleBreadcrumbTap(int? index) {
    if (index == null) {
      if (_folderStack.isEmpty) {
        _loadCurrentFolder();
        return;
      }
      setState(() {
        _folderStack.clear();
      });
      widget.controller?._cacheStack(_folderStack);
      _loadCurrentFolder(showSkeleton: true);
      return;
    }
    if (index < 0 || index >= _folderStack.length) return;
    if (index == _folderStack.length - 1) {
      _loadCurrentFolder();
      return;
    }
    setState(() {
      _folderStack.removeRange(index + 1, _folderStack.length);
    });
    widget.controller?._cacheStack(_folderStack);
    _loadCurrentFolder(showSkeleton: true);
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isInitialLoading = _isLoading && _items.isEmpty && _error == null;
    final showInlineLoadingBar = _isLoading && _items.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: _DriveBreadcrumbBar(
            segments: _folderStack,
            onRootTap: () => _handleBreadcrumbTap(null),
            onSegmentTap: (segmentIndex) => _handleBreadcrumbTap(segmentIndex),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _buildBody(colorScheme, isInitialLoading),
              ),
              Positioned(
                top: 0,
                left: 20,
                right: 20,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: showInlineLoadingBar
                      ? const _DriveInlineProgressIndicator(
                          key: ValueKey('drive-inline-loading'),
                        )
                      : const SizedBox(key: ValueKey('drive-inline-idle')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody(ColorScheme colorScheme, bool isInitialLoading) {
    if (isInitialLoading) {
      return const _DriveLoadingList(key: ValueKey('drive-loading'));
    }
    if (_error != null) {
      return _DriveErrorView(
        key: const ValueKey('drive-error'),
        message: _error!,
        onRetry: () => _loadCurrentFolder(showSkeleton: true),
      );
    }
    final showEmptyState = _items.isEmpty;
    final listItemCount =
        _items.length + (_nextLink != null ? 1 : 0) + (showEmptyState ? 1 : 0);

    return RefreshIndicator(
      key: const ValueKey('drive-content'),
      onRefresh: () => _loadCurrentFolder(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: listItemCount,
        itemBuilder: (context, index) {
          if (showEmptyState && index == 0) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: _DriveEmptyView(),
            );
          }
          if (index >= _items.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
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
            onTap: () => _handleItemTap(item),
          );
        },
      ),
    );
  }
}

class _DriveEmptyView extends StatelessWidget {
  const _DriveEmptyView({super.key});

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
  const _DriveErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

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

class _DriveLoadingList extends StatelessWidget {
  const _DriveLoadingList({super.key});

  static const _itemCount = 8;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _itemCount,
      itemBuilder: (context, index) => _DriveSkeletonTile(index: index),
    );
  }
}

class _DriveSkeletonTile extends StatelessWidget {
  const _DriveSkeletonTile({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = colorScheme.surfaceVariant.withOpacity(0.35);
    final highlightColor = colorScheme.onSurface.withOpacity(0.08);

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _DriveSkeletonBlock(width: 44, height: 44, radius: 14),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _DriveSkeletonBlock(width: double.infinity, height: 16),
                SizedBox(height: 8),
                _DriveSkeletonBlock(width: 180, height: 12),
              ],
            ),
          ),
        ],
      ),
    );

    return row
        .animate(delay: Duration(milliseconds: 60 * index))
        .fadeIn(duration: 260.ms, curve: Curves.easeOutCubic)
        .shimmer(duration: 1200.ms, color: highlightColor)
        .tint(color: baseColor.withOpacity(0.15));
  }
}

class _DriveSkeletonBlock extends StatelessWidget {
  const _DriveSkeletonBlock({
    this.width,
    required this.height,
    this.radius = 12,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _DriveInlineProgressIndicator extends StatelessWidget {
  const _DriveInlineProgressIndicator({super.key});

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

class _DriveBreadcrumbBar extends StatelessWidget {
  const _DriveBreadcrumbBar({
    required this.segments,
    required this.onRootTap,
    required this.onSegmentTap,
  });

  final List<_FolderNode> segments;
  final VoidCallback onRootTap;
  final ValueChanged<int> onSegmentTap;

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[
      _BreadcrumbChip(
        label: '所有文件',
        isActive: segments.isEmpty,
        onTap: onRootTap,
      ),
    ];
    for (var i = 0; i < segments.length; i++) {
      widgets.add(const Icon(Icons.chevron_right_rounded, size: 18));
      widgets.add(
        _BreadcrumbChip(
          label: segments[i].name,
          isActive: i == segments.length - 1,
          onTap: () => onSegmentTap(i),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: widgets,
    );
  }
}

class _BreadcrumbChip extends StatelessWidget {
  const _BreadcrumbChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: isActive ? null : onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        backgroundColor: isActive
            ? colorScheme.primary.withOpacity(0.12)
            : null,
        foregroundColor: isActive
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant,
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _FolderNode {
  const _FolderNode({required this.id, required this.name});

  final String id;
  final String name;
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
    final hasThumbnail = item.thumbnailUrl != null && !isFolder;
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
              SizedBox(
                width: 44,
                height: 44,
                child: hasThumbnail
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          item.thumbnailUrl!,
                          fit: BoxFit.cover,
                        ),
                      )
                    : _DriveTileIcon(
                        icon: iconData,
                        background: iconBackground,
                        iconColor: iconColor,
                      ),
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

class _DriveTileIcon extends StatelessWidget {
  const _DriveTileIcon({
    required this.icon,
    required this.background,
    required this.iconColor,
  });

  final IconData icon;
  final Color background;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: iconColor),
    );
  }
}
