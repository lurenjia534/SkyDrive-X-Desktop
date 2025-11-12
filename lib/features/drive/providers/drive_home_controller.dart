import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/models/drive_breadcrumb.dart';
import 'package:skydrivex/features/drive/services/drive_download_service.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

final driveHomeControllerProvider =
    AsyncNotifierProvider<DriveHomeController, DriveHomeState>(
      DriveHomeController.new,
    );

class DriveHomeController extends AsyncNotifier<DriveHomeState> {
  DriveHomeState get _current =>
      state.asData?.value ?? const DriveHomeState.initial();
  final DriveDownloadService _downloadService = const DriveDownloadService();

  @override
  Future<DriveHomeState> build() async {
    return _fetchFolder(folderId: null, breadcrumbs: const []);
  }

  Future<void> refresh({bool showSkeleton = false}) async {
    final current = _current;
    final breadcrumbs = current.breadcrumbs;
    final folderId = breadcrumbs.isEmpty ? null : breadcrumbs.last.id;
    if (showSkeleton) {
      state = const AsyncLoading();
    } else {
      state = AsyncData(current.copyWith(isRefreshing: true));
    }
    try {
      final data = await _fetchFolder(
        folderId: folderId,
        breadcrumbs: breadcrumbs,
      );
      state = AsyncData(
        data.copyWith(
          activeDownloads: current.activeDownloads,
          isRefreshing: false,
        ),
      );
    } catch (err, stack) {
      state = AsyncError(err, stack);
    }
  }

  Future<void> openFolder(drive_api.DriveItemSummary folder) async {
    final breadcrumbs = [
      ..._current.breadcrumbs,
      DriveBreadcrumbSegment(id: folder.id, name: folder.name),
    ];
    await _loadFolder(folderId: folder.id, breadcrumbs: breadcrumbs);
  }

  Future<void> tapBreadcrumb(int? index) async {
    if (index == null) {
      await _loadFolder(folderId: null, breadcrumbs: const []);
      return;
    }
    final breadcrumbs = _current.breadcrumbs;
    if (index < 0 || index >= breadcrumbs.length) return;
    if (index == breadcrumbs.length - 1) {
      await refresh();
      return;
    }
    final trimmed = breadcrumbs.sublist(0, index + 1);
    await _loadFolder(folderId: trimmed.last.id, breadcrumbs: trimmed);
  }

  Future<void> loadMore() async {
    final current = _current;
    final nextLink = current.nextLink;
    if (nextLink == null || current.isLoadingMore) return;
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final page = await drive_api.listDriveChildren(
        folderId: null,
        folderPath: null,
        nextLink: nextLink,
      );
      final updated = current.copyWith(
        items: [...current.items, ...page.items],
        nextLink: page.nextLink,
        isLoadingMore: false,
      );
      state = AsyncData(updated);
    } catch (err) {
      state = AsyncData(current.copyWith(isLoadingMore: false));
      rethrow;
    }
  }

  bool isDownloading(String itemId) {
    return _current.activeDownloads.contains(itemId);
  }

  Future<drive_api.DriveDownloadResult> downloadFile(
    drive_api.DriveItemSummary item,
  ) async {
    if (isDownloading(item.id)) {
      throw StateError('Download already in progress');
    }
    _updateActiveDownloads(item.id, true);
    try {
      final result = await _downloadService.download(item: item);
      return result;
    } finally {
      _updateActiveDownloads(item.id, false);
    }
  }

  Future<void> _loadFolder({
    required String? folderId,
    required List<DriveBreadcrumbSegment> breadcrumbs,
  }) async {
    state = const AsyncLoading();
    try {
      final data = await _fetchFolder(
        folderId: folderId,
        breadcrumbs: breadcrumbs,
      );
      state = AsyncData(
        data.copyWith(activeDownloads: _current.activeDownloads),
      );
    } catch (err, stack) {
      state = AsyncError(err, stack);
    }
  }

  Future<DriveHomeState> _fetchFolder({
    required String? folderId,
    required List<DriveBreadcrumbSegment> breadcrumbs,
  }) async {
    final page = await drive_api.listDriveChildren(
      folderId: folderId,
      folderPath: null,
      nextLink: null,
    );
    return DriveHomeState(
      items: page.items,
      nextLink: page.nextLink,
      breadcrumbs: breadcrumbs,
      isLoadingMore: false,
      activeDownloads: _current.activeDownloads,
      isRefreshing: false,
    );
  }

  void _updateActiveDownloads(String itemId, bool isActive) {
    state = state.whenData((data) {
      final updated = {...data.activeDownloads};
      if (isActive) {
        updated.add(itemId);
      } else {
        updated.remove(itemId);
      }
      return data.copyWith(activeDownloads: updated);
    });
  }
}

class DriveHomeState {
  const DriveHomeState({
    required this.items,
    required this.nextLink,
    required this.breadcrumbs,
    required this.isLoadingMore,
    required this.activeDownloads,
    required this.isRefreshing,
  });

  const DriveHomeState.initial()
    : items = const [],
      nextLink = null,
      breadcrumbs = const [],
      isLoadingMore = false,
      activeDownloads = const {},
      isRefreshing = false;

  final List<drive_api.DriveItemSummary> items;
  final String? nextLink;
  final List<DriveBreadcrumbSegment> breadcrumbs;
  final bool isLoadingMore;
  final Set<String> activeDownloads;
  final bool isRefreshing;

  DriveHomeState copyWith({
    List<drive_api.DriveItemSummary>? items,
    String? nextLink,
    List<DriveBreadcrumbSegment>? breadcrumbs,
    bool? isLoadingMore,
    Set<String>? activeDownloads,
    bool? isRefreshing,
  }) {
    return DriveHomeState(
      items: items ?? this.items,
      nextLink: nextLink ?? this.nextLink,
      breadcrumbs: breadcrumbs ?? this.breadcrumbs,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      activeDownloads: activeDownloads ?? this.activeDownloads,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}
