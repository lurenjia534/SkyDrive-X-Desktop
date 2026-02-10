import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/drive/providers/drive_download_manager.dart';
import 'package:skydrivex/features/drive/providers/drive_home_controller.dart';
import 'package:skydrivex/features/drive/providers/drive_search_query_provider.dart';
import 'package:skydrivex/features/drive/providers/drive_view_mode_provider.dart';
import 'package:skydrivex/features/drive/services/drive_item_action_service.dart';
import 'package:skydrivex/features/drive/utils/drive_item_formatters.dart';
import 'package:skydrivex/features/drive/widgets/drive_background_context_menu.dart';
import 'package:skydrivex/features/drive/widgets/drive_breadcrumb_bar.dart';
import 'package:skydrivex/features/drive/widgets/drive_download_indicator.dart';
import 'package:skydrivex/features/drive/widgets/drive_empty_view.dart';
import 'package:skydrivex/features/drive/widgets/drive_error_view.dart';
import 'package:skydrivex/features/drive/widgets/drive_item_context_menu.dart';
import 'package:skydrivex/features/drive/widgets/drive_inline_progress_indicator.dart';
import 'package:skydrivex/features/drive/widgets/drive_item_tile.dart';
import 'package:skydrivex/features/drive/widgets/drive_load_more_tile.dart';
import 'package:skydrivex/features/drive/widgets/drive_loading_list.dart';
import 'package:skydrivex/features/drive/widgets/drive_view_mode_toggle.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;
import 'package:skydrivex/utils/toast.dart';

class DriveHomePage extends ConsumerWidget {
  const DriveHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(driveHomeControllerProvider);

    return asyncState.when(
      data: (data) => _DriveHomeView(state: data, isRefreshing: false),
      loading: () {
        final previous = asyncState.value;
        if (previous != null) {
          return _DriveHomeView(state: previous, isRefreshing: true);
        }
        return const _DriveHomeLoadingView();
      },
      error: (error, _) {
        final previous = asyncState.value;
        if (previous != null) {
          return _DriveHomeView(state: previous, isRefreshing: false);
        }
        return DriveErrorView(
          message: error.toString(),
          onRetry: () => ref
              .read(driveHomeControllerProvider.notifier)
              .refresh(showSkeleton: true),
        );
      },
    );
  }
}

class _DriveHomeLoadingView extends ConsumerWidget {
  const _DriveHomeLoadingView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(driveHomeControllerProvider.notifier);
    final viewMode = ref.watch(driveItemViewModeProvider);
    final viewModeController = ref.read(driveItemViewModeProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: DriveBreadcrumbBar(
                  segments: const [],
                  onRootTap: () => controller.tapBreadcrumb(null),
                  onSegmentTap: (_) {},
                ),
              ),
              const SizedBox(width: 12),
              DriveViewModeToggle(
                mode: viewMode,
                onChanged: viewModeController.setMode,
              ),
              const SizedBox(width: 12),
              FButton(
                onPress: () => DriveItemActionService.promptCreateFolder(
                  context: context,
                  ref: ref,
                ),
                style: _driveToolbarActionButtonStyle(context),
                prefix: const Icon(FIcons.folderPlus, size: 16),
                child: const Text('New folder'),
              ),
            ],
          ),
        ),
        const Expanded(child: DriveLoadingList(key: ValueKey('drive-loading'))),
      ],
    );
  }
}

class _DriveHomeView extends ConsumerStatefulWidget {
  const _DriveHomeView({required this.state, required this.isRefreshing});

  final DriveHomeState state;
  final bool isRefreshing;

  @override
  ConsumerState<_DriveHomeView> createState() => _DriveHomeViewState();
}

class _DriveHomeViewState extends ConsumerState<_DriveHomeView> {
  DateTime? _suppressBackgroundMenuUntil;
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};

  bool get _isBackgroundMenuSuppressed {
    final until = _suppressBackgroundMenuUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  void _markSuppressBackgroundMenu() {
    _suppressBackgroundMenuUntil = DateTime.now().add(
      const Duration(milliseconds: 120),
    );
  }

  @override
  void didUpdateWidget(covariant _DriveHomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousFolderId = _folderIdFor(oldWidget.state);
    final nextFolderId = _folderIdFor(widget.state);
    if (previousFolderId != nextFolderId) {
      _exitSelectionMode();
      ref.read(driveSearchQueryProvider.notifier).clear();
      return;
    }
    if (_selectedIds.isEmpty) return;
    final ids = widget.state.items.map((item) => item.id).toSet();
    final removed = _selectedIds.where((id) => !ids.contains(id)).toList();
    if (removed.isNotEmpty) {
      setState(() {
        _selectedIds.removeAll(removed);
      });
    }
  }

  String? _folderIdFor(DriveHomeState state) {
    if (state.breadcrumbs.isEmpty) return null;
    return state.breadcrumbs.last.id;
  }

  void _enterSelectionMode() {
    if (_selectionMode) return;
    setState(() {
      _selectionMode = true;
      _selectedIds.clear();
    });
  }

  void _exitSelectionMode() {
    if (!_selectionMode && _selectedIds.isEmpty) return;
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(drive_api.DriveItemSummary item) {
    _setSelected(item, !_selectedIds.contains(item.id));
  }

  void _setSelected(drive_api.DriveItemSummary item, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(item.id);
      } else {
        _selectedIds.remove(item.id);
      }
    });
  }

  List<drive_api.DriveItemSummary> _searchItems(
    List<drive_api.DriveItemSummary> items,
    String searchQuery,
  ) {
    final query = searchQuery.trim();
    if (query.isEmpty) return items;
    final lowerQuery = query.toLowerCase();
    return items
        .where((item) => item.name.toLowerCase().contains(lowerQuery))
        .toList(growable: false);
  }

  Future<void> _handleBatchDelete(DriveHomeState viewState) async {
    final selectedItems = viewState.items
        .where((item) => _selectedIds.contains(item.id))
        .toList();
    if (selectedItems.isEmpty) {
      _showSnack(context, 'No items selected');
      return;
    }
    final failedIds = await DriveItemActionService.confirmAndDeleteBatch(
      context: context,
      ref: ref,
      items: selectedItems,
    );
    if (!mounted || failedIds == null) return;
    setState(() {
      if (failedIds.isEmpty) {
        _selectionMode = false;
        _selectedIds.clear();
      } else {
        _selectionMode = true;
        _selectedIds
          ..clear()
          ..addAll(failedIds);
      }
    });
  }

  Future<void> _handleBatchDownload(DriveHomeState viewState) async {
    final selectedItems = viewState.items
        .where((item) => _selectedIds.contains(item.id))
        .toList();
    if (selectedItems.isEmpty) {
      _showSnack(context, 'No items selected');
      return;
    }
    final remainingIds = await DriveItemActionService.enqueueBatchDownload(
      context: context,
      ref: ref,
      items: selectedItems,
    );
    if (!mounted || remainingIds == null) return;
    setState(() {
      if (remainingIds.isEmpty) {
        _selectionMode = false;
        _selectedIds.clear();
      } else {
        _selectionMode = true;
        _selectedIds
          ..clear()
          ..addAll(remainingIds);
      }
    });
  }

  Future<void> _handleItemTap(drive_api.DriveItemSummary item) async {
    final controller = ref.read(driveHomeControllerProvider.notifier);
    if (item.isFolder) {
      await controller.openFolder(item);
      return;
    }
    await DriveItemActionService.showPropertiesSheet(
      context: context,
      ref: ref,
      item: item,
    );
  }

  Future<void> _handleItemContextMenu(
    drive_api.DriveItemSummary item,
    TapDownDetails details,
  ) async {
    _markSuppressBackgroundMenu();
    unawaited(closeDriveBackgroundContextMenu());
    final selected = await showDriveItemContextMenu(
      context: context,
      item: item,
      globalPosition: details.globalPosition,
    );

    if (selected == null) return;
    if (!mounted) return;
    switch (selected) {
      case DriveContextAction.createFolder:
        await DriveItemActionService.promptCreateFolder(
          context: context,
          ref: ref,
        );
        break;
      case DriveContextAction.uploadFiles:
        await DriveItemActionService.promptUploadFiles(
          context: context,
          ref: ref,
          parentId: item.id,
        );
        break;
      case DriveContextAction.download:
        await DriveItemActionService.handleDownload(
          context: context,
          ref: ref,
          item: item,
        );
        break;
      case DriveContextAction.delete:
        await DriveItemActionService.confirmAndDelete(
          context: context,
          ref: ref,
          item: item,
        );
        break;
      case DriveContextAction.share:
        await DriveItemActionService.showShareDialog(
          context: context,
          ref: ref,
          item: item,
        );
        break;
      case DriveContextAction.move:
        await DriveItemActionService.showMoveSheet(
          context: context,
          ref: ref,
          item: item,
        );
        break;
      case DriveContextAction.rename:
        await DriveItemActionService.promptRename(
          context: context,
          ref: ref,
          item: item,
        );
        break;
      case DriveContextAction.properties:
        await DriveItemActionService.showPropertiesSheet(
          context: context,
          ref: ref,
          item: item,
        );
        break;
    }
  }

  Future<void> _handleBackgroundPointerDown(PointerDownEvent event) async {
    if (_selectionMode) return;
    if (event.buttons & kSecondaryMouseButton == 0) return;
    if (_isBackgroundMenuSuppressed) return;
    final selected = await showDriveBackgroundContextMenu(
      context: context,
      globalPosition: event.position,
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case DriveBackgroundAction.createFolder:
        await DriveItemActionService.promptCreateFolder(
          context: context,
          ref: ref,
        );
        break;
      case DriveBackgroundAction.uploadFiles:
        await DriveItemActionService.promptUploadFiles(
          context: context,
          ref: ref,
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewState = widget.state;
    final controller = ref.read(driveHomeControllerProvider.notifier);
    final downloadQueue = ref.watch(driveDownloadManagerProvider);
    final viewMode = ref.watch(driveItemViewModeProvider);
    final viewModeController = ref.read(driveItemViewModeProvider.notifier);
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    final selectedCount = _selectedIds.length;
    final canDelete = selectedCount > 0;
    final canDownload = selectedCount > 0;
    final showInlineLoadingBar =
        (widget.isRefreshing || viewState.isRefreshing) &&
        viewState.items.isNotEmpty;
    final showLoadingState =
        viewState.items.isEmpty &&
        (widget.isRefreshing || viewState.isRefreshing);
    final showEmptyState = viewState.items.isEmpty && !showLoadingState;
    final hasMore = viewState.nextLink != null;
    final searchQuery = ref.watch(driveSearchQueryProvider);
    final visibleItems = _searchItems(viewState.items, searchQuery);
    final hasSearchQuery = searchQuery.isNotEmpty;
    final showSearchEmptyState =
        hasSearchQuery && visibleItems.isEmpty && !showLoadingState;
    final hasMoreResults = hasMore && !hasSearchQuery;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: DriveBreadcrumbBar(
                  segments: viewState.breadcrumbs,
                  onRootTap: () => controller.tapBreadcrumb(null),
                  onSegmentTap: controller.tapBreadcrumb,
                ),
              ),
              const SizedBox(width: 12),
              DriveViewModeToggle(
                mode: viewMode,
                onChanged: viewModeController.setMode,
              ),
              const SizedBox(width: 12),
              if (!_selectionMode) ...[
                FButton(
                  onPress: () => DriveItemActionService.promptCreateFolder(
                    context: context,
                    ref: ref,
                  ),
                  style: _driveToolbarActionButtonStyle(context),
                  prefix: const Icon(FIcons.folderPlus, size: 16),
                  child: const Text('New folder'),
                ),
                const SizedBox(width: 12),
                FButton(
                  onPress: _enterSelectionMode,
                  style: _driveToolbarActionButtonStyle(context),
                  prefix: const Icon(FIcons.check, size: 16),
                  child: const Text('Select'),
                ),
              ] else ...[
                Text(
                  '$selectedCount selected',
                  style: typography.sm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.mutedForeground,
                  ),
                ),
                const SizedBox(width: 12),
                FButton(
                  onPress: canDownload
                      ? () => _handleBatchDownload(viewState)
                      : null,
                  style: FButtonStyle.outline(),
                  prefix: const Icon(FIcons.cloudDownload, size: 16),
                  child: const Text('Download'),
                ),
                const SizedBox(width: 8),
                FButton(
                  onPress: canDelete
                      ? () => _handleBatchDelete(viewState)
                      : null,
                  style: FButtonStyle.destructive(),
                  prefix: const Icon(FIcons.trash2, size: 16),
                  child: const Text('Delete'),
                ),
                const SizedBox(width: 8),
                FButton(
                  onPress: _exitSelectionMode,
                  style: FButtonStyle.outline(),
                  prefix: const Icon(FIcons.x, size: 16),
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              RefreshIndicator(
                key: ValueKey('drive-content-${viewMode.name}'),
                onRefresh: () => controller.refresh(),
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _handleBackgroundPointerDown,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return _buildDriveContent(
                        context,
                        constraints: constraints,
                        controller: controller,
                        viewState: viewState,
                        downloadQueue: downloadQueue,
                        visibleItems: visibleItems,
                        viewMode: viewMode,
                        showLoadingState: showLoadingState,
                        showEmptyState: showEmptyState,
                        showSearchEmptyState: showSearchEmptyState,
                        searchQuery: searchQuery,
                        hasMore: hasMoreResults,
                      );
                    },
                  ),
                ),
              ),
              if (showInlineLoadingBar)
                const Positioned(
                  top: 0,
                  left: 20,
                  right: 20,
                  child: DriveInlineProgressIndicator(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDriveContent(
    BuildContext context, {
    required BoxConstraints constraints,
    required DriveHomeController controller,
    required DriveHomeState viewState,
    required DownloadQueueState downloadQueue,
    required List<drive_api.DriveItemSummary> visibleItems,
    required DriveItemViewMode viewMode,
    required bool showLoadingState,
    required bool showEmptyState,
    required bool showSearchEmptyState,
    required String searchQuery,
    required bool hasMore,
  }) {
    if (showLoadingState) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 120),
            child: DriveLoadingList(),
          ),
        ],
      );
    }

    if (showEmptyState) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: DriveEmptyView(),
          ),
        ],
      );
    }

    if (showSearchEmptyState) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: _buildSearchEmptyResult(context, searchQuery),
          ),
        ],
      );
    }

    if (viewMode == DriveItemViewMode.list) {
      final itemCount = visibleItems.length + (hasMore ? 1 : 0);
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index >= visibleItems.length) {
            return DriveLoadMoreTile(
              isLoading: viewState.isLoadingMore,
              onLoadMore: () async {
                try {
                  await controller.loadMore();
                } catch (err) {
                  if (!context.mounted) return;
                  _showSnack(context, 'Failed to load more: $err');
                }
              },
            );
          }
          final item = visibleItems[index];
          final subtitle = buildDriveSubtitle(item);
          final activeTask = _findActiveTask(downloadQueue, item);
          final trailing = item.isFolder
              ? null
              : DriveDownloadIndicator(
                  isDownloading: activeTask != null,
                  progress: activeTask?.progressRatio,
                );
          final isSelected = _selectedIds.contains(item.id);
          return DriveItemTile(
            item: item,
            subtitle: subtitle,
            onTap: _selectionMode
                ? () => _toggleSelection(item)
                : () => _handleItemTap(item),
            onSecondaryTapDown: _selectionMode
                ? null
                : (details) => _handleItemContextMenu(item, details),
            trailing: trailing,
            selectionMode: _selectionMode,
            isSelected: isSelected,
            onSelected: (value) => _setSelected(item, value),
          );
        },
      );
    }

    final rawCount = (constraints.maxWidth / 160).floor();
    final crossAxisCount = rawCount.clamp(3, 7).toInt();
    final itemCount = visibleItems.length + (hasMore ? 1 : 0);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.22,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= visibleItems.length) {
          return DriveLoadMoreCard(
            isLoading: viewState.isLoadingMore,
            onLoadMore: () async {
              try {
                await controller.loadMore();
              } catch (err) {
                if (!context.mounted) return;
                _showSnack(context, 'Failed to load more: $err');
              }
            },
          );
        }
        final item = visibleItems[index];
        final subtitle = buildDriveSubtitle(item);
        final activeTask = _findActiveTask(downloadQueue, item);
        final trailing = item.isFolder
            ? null
            : DriveDownloadIndicator(
                isDownloading: activeTask != null,
                progress: activeTask?.progressRatio,
              );
        final isSelected = _selectedIds.contains(item.id);
        return DriveItemGridTile(
          item: item,
          subtitle: subtitle,
          onTap: _selectionMode
              ? () => _toggleSelection(item)
              : () => _handleItemTap(item),
          onSecondaryTapDown: _selectionMode
              ? null
              : (details) => _handleItemContextMenu(item, details),
          trailing: trailing,
          selectionMode: _selectionMode,
          isSelected: isSelected,
          onSelected: (value) => _setSelected(item, value),
        );
      },
    );
  }

  Widget _buildSearchEmptyResult(BuildContext context, String searchQuery) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 32,
            color: colors.mutedForeground,
          ),
          const SizedBox(height: 14),
          Text(
            'No matching items',
            style: typography.base.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.foreground,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try another keyword for "$searchQuery".',
            style: typography.sm.copyWith(color: colors.mutedForeground),
          ),
        ],
      ),
    );
  }

  drive_api.DownloadTask? _findActiveTask(
    DownloadQueueState queue,
    drive_api.DriveItemSummary item,
  ) {
    for (final task in queue.active) {
      if (task.item.id == item.id && task.status == DownloadStatus.inProgress) {
        return task;
      }
    }
    return null;
  }
}

void _showSnack(BuildContext context, String message) {
  showToast(context, message);
}

FBaseButtonStyle Function(FButtonStyle style) _driveToolbarActionButtonStyle(
  BuildContext context,
) {
  final colors = context.theme.colors;
  final typography = context.theme.typography;
  return FButtonStyle.outline(
    (style) => style.copyWith(
      decoration: FWidgetStateMap({
        WidgetState.disabled: BoxDecoration(
          color: colors.disable(colors.background),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border.withValues(alpha: 0.45)),
        ),
        WidgetState.hovered | WidgetState.pressed: BoxDecoration(
          color: colors.secondary.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border.withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(
              color: colors.barrier.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        WidgetState.any: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border.withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(
              color: colors.barrier.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
      }),
      contentStyle: (contentStyle) => contentStyle.copyWith(
        textStyle: FWidgetStateMap.all(
          typography.sm.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.foreground,
          ),
        ),
        iconStyle: FWidgetStateMap.all(
          IconThemeData(
            color: colors.mutedForeground,
            size: 16,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        spacing: 8,
      ),
    ),
  );
}
