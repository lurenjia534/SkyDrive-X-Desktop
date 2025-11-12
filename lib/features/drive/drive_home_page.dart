import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/dialogs/drive_download_dialog.dart';
import 'package:skydrivex/features/drive/models/drive_breadcrumb.dart';
import 'package:skydrivex/features/drive/services/drive_download_service.dart';
import 'package:skydrivex/features/drive/utils/drive_item_formatters.dart';
import 'package:skydrivex/features/drive/widgets/drive_breadcrumb_bar.dart';
import 'package:skydrivex/features/drive/widgets/drive_download_indicator.dart';
import 'package:skydrivex/features/drive/widgets/drive_empty_view.dart';
import 'package:skydrivex/features/drive/widgets/drive_error_view.dart';
import 'package:skydrivex/features/drive/widgets/drive_inline_progress_indicator.dart';
import 'package:skydrivex/features/drive/widgets/drive_item_tile.dart';
import 'package:skydrivex/features/drive/widgets/drive_load_more_tile.dart';
import 'package:skydrivex/features/drive/widgets/drive_loading_list.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

class DriveHomePageController {
  _DriveHomePageState? _state;
  List<DriveBreadcrumbSegment> _cachedStack = [];

  Future<void> refresh({bool showSkeleton = false}) async {
    final state = _state;
    if (state != null) {
      await state._loadCurrentFolder(showSkeleton: showSkeleton);
    }
  }

  bool get isLoading => _state?._isLoading ?? true;

  List<DriveBreadcrumbSegment> get cachedStack =>
      List.unmodifiable(_cachedStack);

  void _cacheStack(List<DriveBreadcrumbSegment> stack) {
    _cachedStack = List<DriveBreadcrumbSegment>.from(stack);
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
  final List<DriveBreadcrumbSegment> _folderStack = [];
  final Set<String> _activeDownloads = <String>{};
  final DriveDownloadService _downloadService = const DriveDownloadService();

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
        _folderStack.add(DriveBreadcrumbSegment(id: item.id, name: item.name));
      });
      widget.controller?._cacheStack(_folderStack);
      _loadCurrentFolder(showSkeleton: true);
      return;
    }
    unawaited(_downloadFile(item));
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

  Future<void> _downloadFile(drive_api.DriveItemSummary item) async {
    if (_activeDownloads.contains(item.id)) return;
    _setDownloadFlag(item.id, true);

    var dialogShown = false;
    if (mounted) {
      dialogShown = true;
      // ignore: discarded_futures
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DriveDownloadDialog(fileName: item.name),
      );
    }

    try {
      final result = await _downloadService.download(item: item);
      if (!mounted) return;
      final downloadedBytes =
          _bigIntToSafeInt(result.expectedSize) ??
          _bigIntToSafeInt(result.bytesDownloaded);
      final sizeLabel = downloadedBytes != null
          ? '（${formatFileSize(downloadedBytes)}）'
          : '';
      _showSnack('已下载 ${result.fileName}$sizeLabel\n${result.savedPath}');
    } on DownloadDirectoryUnavailable catch (err) {
      _showSnack('无法确定下载目录：${err.message}');
    } catch (err) {
      _showSnack('下载失败：$err');
    } finally {
      if (dialogShown && mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
      _setDownloadFlag(item.id, false);
    }
  }

  void _setDownloadFlag(String itemId, bool isActive) {
    if (mounted) {
      setState(() {
        if (isActive) {
          _activeDownloads.add(itemId);
        } else {
          _activeDownloads.remove(itemId);
        }
      });
    } else {
      if (isActive) {
        _activeDownloads.add(itemId);
      } else {
        _activeDownloads.remove(itemId);
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  int? _bigIntToSafeInt(BigInt? value) {
    if (value == null) return null;
    const maxSafeInt = 0x7fffffffffffffff;
    final max = BigInt.from(maxSafeInt);
    if (value > max) {
      return null;
    }
    return value.toInt();
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
          child: DriveBreadcrumbBar(
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
                      ? const DriveInlineProgressIndicator(
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
      return const DriveLoadingList(key: ValueKey('drive-loading'));
    }
    if (_error != null) {
      return DriveErrorView(
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
              child: DriveEmptyView(),
            );
          }
          if (index >= _items.length) {
            return DriveLoadMoreTile(
              isLoading: _isLoadingMore,
              onLoadMore: _loadMore,
            );
          }
          final item = _items[index];
          final subtitle = buildDriveSubtitle(item);
          final trailing = item.isFolder
              ? null
              : DriveDownloadIndicator(
                  isDownloading: _activeDownloads.contains(item.id),
                  colorScheme: colorScheme,
                );
          return DriveItemTile(
            item: item,
            subtitle: subtitle,
            colorScheme: colorScheme,
            onTap: () => _handleItemTap(item),
            trailing: trailing,
          );
        },
      ),
    );
  }
}
