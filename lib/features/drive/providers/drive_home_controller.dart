import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/models/drive_breadcrumb.dart';
import 'package:skydrivex/features/drive/providers/offline_index_provider.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;
import 'package:skydrivex/src/rust/api/drive/create_folder.dart'
    as drive_create_api;
import 'package:skydrivex/src/rust/api/drive/search.dart' as drive_search_api;

final driveHomeControllerProvider =
    AsyncNotifierProvider<DriveHomeController, DriveHomeState>(
      DriveHomeController.new,
    );

class DriveHomeController extends AsyncNotifier<DriveHomeState> {
  static const int _offlineSearchPageSize = 120;

  DriveHomeState get _current =>
      state.asData?.value ?? const DriveHomeState.initial();

  String? _folderIdFromBreadcrumbs(List<DriveBreadcrumbSegment> breadcrumbs) {
    if (breadcrumbs.isEmpty) return null;
    return breadcrumbs.last.id;
  }

  bool _isSameContext(DriveHomeState expected, DriveHomeState actual) {
    return _folderIdFromBreadcrumbs(expected.breadcrumbs) ==
            _folderIdFromBreadcrumbs(actual.breadcrumbs) &&
        expected.searchQuery == actual.searchQuery;
  }

  @override
  Future<DriveHomeState> build() async {
    return _fetchFolder(folderId: null, breadcrumbs: const [], searchQuery: '');
  }

  Future<void> refresh({bool showSkeleton = false}) async {
    final current = _current;
    final breadcrumbs = current.breadcrumbs;
    final folderId = _folderIdFromBreadcrumbs(breadcrumbs);
    if (showSkeleton) {
      state = AsyncData(
        _loadingState(breadcrumbs, searchQuery: current.searchQuery),
      );
    } else {
      state = AsyncData(
        current.copyWith(
          isRefreshing: true,
          isLoadingMore: false,
          nextLink: null,
        ),
      );
    }
    final loading = _current;
    try {
      final data = await _fetchFolder(
        folderId: folderId,
        breadcrumbs: breadcrumbs,
        searchQuery: current.searchQuery,
      );
      if (!_isSameContext(loading, _current)) return;
      state = AsyncData(data);
    } catch (err, stack) {
      if (!_isSameContext(loading, _current)) return;
      state = AsyncError(err, stack);
    }
  }

  Future<void> applySearchQuery(String query) async {
    final normalized = query.trim();
    final current = _current;
    if (normalized == current.searchQuery) return;

    final breadcrumbs = current.breadcrumbs;
    final folderId = _folderIdFromBreadcrumbs(breadcrumbs);
    state = AsyncData(
      current.copyWith(
        searchQuery: normalized,
        isRefreshing: true,
        isLoadingMore: false,
        nextLink: null,
      ),
    );
    final loading = _current;

    try {
      final data = await _fetchFolder(
        folderId: folderId,
        breadcrumbs: breadcrumbs,
        searchQuery: normalized,
      );
      if (!_isSameContext(loading, _current)) return;
      state = AsyncData(data);
    } catch (err, stack) {
      if (!_isSameContext(loading, _current)) return;
      state = AsyncError(err, stack);
    }
  }

  Future<void> openFolder(drive_api.DriveItemSummary folder) async {
    final breadcrumbs = [
      ..._current.breadcrumbs,
      DriveBreadcrumbSegment(id: folder.id, name: folder.name),
    ];
    await _loadFolder(
      folderId: folder.id,
      breadcrumbs: breadcrumbs,
      searchQuery: '',
    );
  }

  Future<void> tapBreadcrumb(int? index) async {
    if (index == null) {
      await _loadFolder(folderId: null, breadcrumbs: const [], searchQuery: '');
      return;
    }
    final breadcrumbs = _current.breadcrumbs;
    if (index < 0 || index >= breadcrumbs.length) return;
    if (index == breadcrumbs.length - 1) {
      await refresh();
      return;
    }
    final trimmed = breadcrumbs.sublist(0, index + 1);
    await _loadFolder(
      folderId: trimmed.last.id,
      breadcrumbs: trimmed,
      searchQuery: '',
    );
  }

  Future<void> loadMore() async {
    final current = _current;
    final nextLink = current.nextLink;
    if (nextLink == null || current.isLoadingMore) return;
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final folderId = _folderIdFromBreadcrumbs(current.breadcrumbs);
      final page = current.searchQuery.isEmpty
          ? await drive_api.listDriveChildren(
              folderId: null,
              folderPath: null,
              nextLink: nextLink,
            )
          : current.isOfflineSearch
          ? await ref
                .read(offlineIndexProvider.notifier)
                .searchPage(
                  query: current.searchQuery,
                  folderId: folderId,
                  nextLink: nextLink,
                  limit: _offlineSearchPageSize,
                )
          : await drive_search_api.searchDriveItems(
              query: current.searchQuery,
              folderId: folderId,
              nextLink: nextLink,
              top: null,
            );

      if (!_isSameContext(current, _current)) return;
      final updated = current.copyWith(
        items: [...current.items, ...page.items],
        nextLink: page.nextLink,
        isLoadingMore: false,
        isOfflineSearch: current.isOfflineSearch,
      );
      state = AsyncData(updated);
    } catch (err) {
      if (!_isSameContext(current, _current)) return;
      state = AsyncData(current.copyWith(isLoadingMore: false));
      rethrow;
    }
  }

  Future<drive_api.DriveItemSummary> createFolder(String name) async {
    final current = _current;
    final parentId = current.breadcrumbs.isEmpty
        ? null
        : current.breadcrumbs.last.id;
    final created = await drive_create_api.createDriveFolder(
      name: name,
      parentId: parentId,
      parentPath: null,
      conflictBehavior: null,
    );
    await refresh(showSkeleton: false);
    return created;
  }

  Future<void> _loadFolder({
    required String? folderId,
    required List<DriveBreadcrumbSegment> breadcrumbs,
    required String searchQuery,
  }) async {
    state = AsyncData(_loadingState(breadcrumbs, searchQuery: searchQuery));
    final loading = _current;
    try {
      final data = await _fetchFolder(
        folderId: folderId,
        breadcrumbs: breadcrumbs,
        searchQuery: searchQuery,
      );
      if (!_isSameContext(loading, _current)) return;
      state = AsyncData(data);
    } catch (err, stack) {
      if (!_isSameContext(loading, _current)) return;
      state = AsyncError(err, stack);
    }
  }

  Future<DriveHomeState> _fetchFolder({
    required String? folderId,
    required List<DriveBreadcrumbSegment> breadcrumbs,
    required String searchQuery,
  }) async {
    final normalizedQuery = searchQuery.trim();
    final offlineState =
        ref.read(offlineIndexProvider).value ?? OfflineIndexState.initial;
    final useOfflineSearch =
        normalizedQuery.isNotEmpty &&
        offlineState.enabled &&
        offlineState.hasIndex;
    final page = normalizedQuery.isEmpty
        ? await drive_api.listDriveChildren(
            folderId: folderId,
            folderPath: null,
            nextLink: null,
          )
        : useOfflineSearch
        ? await ref
              .read(offlineIndexProvider.notifier)
              .searchPage(
                query: normalizedQuery,
                folderId: folderId,
                nextLink: null,
                limit: _offlineSearchPageSize,
              )
        : await drive_search_api.searchDriveItems(
            query: normalizedQuery,
            folderId: folderId,
            nextLink: null,
            top: null,
          );
    return DriveHomeState(
      items: page.items,
      nextLink: page.nextLink,
      breadcrumbs: breadcrumbs,
      searchQuery: normalizedQuery,
      isLoadingMore: false,
      isRefreshing: false,
      isOfflineSearch: useOfflineSearch,
    );
  }

  DriveHomeState _loadingState(
    List<DriveBreadcrumbSegment> breadcrumbs, {
    required String searchQuery,
  }) {
    return DriveHomeState(
      items: const [],
      nextLink: null,
      breadcrumbs: breadcrumbs,
      searchQuery: searchQuery.trim(),
      isLoadingMore: false,
      isRefreshing: true,
      isOfflineSearch: false,
    );
  }
}

class DriveHomeState {
  const DriveHomeState({
    required this.items,
    required this.nextLink,
    required this.breadcrumbs,
    required this.searchQuery,
    required this.isLoadingMore,
    required this.isRefreshing,
    required this.isOfflineSearch,
  });

  const DriveHomeState.initial()
    : items = const [],
      nextLink = null,
      breadcrumbs = const [],
      searchQuery = '',
      isLoadingMore = false,
      isRefreshing = false,
      isOfflineSearch = false;

  static const Object _keepNextLink = Object();

  final List<drive_api.DriveItemSummary> items;
  final String? nextLink;
  final List<DriveBreadcrumbSegment> breadcrumbs;
  final String searchQuery;
  final bool isLoadingMore;
  final bool isRefreshing;
  final bool isOfflineSearch;

  DriveHomeState copyWith({
    List<drive_api.DriveItemSummary>? items,
    Object? nextLink = _keepNextLink,
    List<DriveBreadcrumbSegment>? breadcrumbs,
    String? searchQuery,
    bool? isLoadingMore,
    bool? isRefreshing,
    bool? isOfflineSearch,
  }) {
    return DriveHomeState(
      items: items ?? this.items,
      nextLink: identical(nextLink, _keepNextLink)
          ? this.nextLink
          : nextLink as String?,
      breadcrumbs: breadcrumbs ?? this.breadcrumbs,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isOfflineSearch: isOfflineSearch ?? this.isOfflineSearch,
    );
  }
}
