import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;
import 'package:skydrivex/src/rust/api/drive/gallery.dart' as drive_gallery_api;

final driveGalleryControllerProvider =
    AsyncNotifierProvider<DriveGalleryController, DriveGalleryState>(
      DriveGalleryController.new,
    );

class DriveGalleryController extends AsyncNotifier<DriveGalleryState> {
  static const int _defaultPageTop = 120;
  int _generation = 0;

  DriveGalleryState get _current =>
      state.asData?.value ?? const DriveGalleryState.initial();

  @override
  Future<DriveGalleryState> build() async {
    final page = await drive_gallery_api.listDriveGalleryItems(
      top: _defaultPageTop,
    );
    return DriveGalleryState(
      items: page.items,
      nextLink: page.nextLink,
      isLoadingMore: false,
      isRefreshing: false,
    );
  }

  Future<void> refresh({bool showSkeleton = false}) async {
    final token = ++_generation;
    final current = _current;
    if (showSkeleton) {
      state = const AsyncData(
        DriveGalleryState(
          items: [],
          nextLink: null,
          isLoadingMore: false,
          isRefreshing: true,
        ),
      );
    } else {
      state = AsyncData(
        current.copyWith(isRefreshing: true, isLoadingMore: false),
      );
    }
    final loading = _current;
    try {
      final page = await drive_gallery_api.listDriveGalleryItems(
        top: _defaultPageTop,
      );
      if (token != _generation) return;
      if (!_isSameContext(loading, _current)) return;
      state = AsyncData(
        DriveGalleryState(
          items: page.items,
          nextLink: page.nextLink,
          isLoadingMore: false,
          isRefreshing: false,
        ),
      );
    } catch (err, stack) {
      if (token != _generation) return;
      if (!_isSameContext(loading, _current)) return;
      state = AsyncError(err, stack);
    }
  }

  Future<void> loadMore() async {
    final current = _current;
    final token = _generation;
    final nextLink = current.nextLink;
    if (current.isLoadingMore || current.isRefreshing || nextLink == null) {
      return;
    }
    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final page = await drive_gallery_api.listDriveGalleryItems(
        nextLink: nextLink,
      );
      if (token != _generation) return;
      if (!_isSameContext(current, _current)) return;
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...page.items],
          nextLink: page.nextLink,
          isLoadingMore: false,
          isRefreshing: false,
        ),
      );
    } catch (_) {
      if (token != _generation) return;
      if (!_isSameContext(current, _current)) return;
      state = AsyncData(current.copyWith(isLoadingMore: false));
      rethrow;
    }
  }

  bool _isSameContext(DriveGalleryState expected, DriveGalleryState actual) {
    return expected.nextLink == actual.nextLink &&
        expected.items.length == actual.items.length;
  }
}

class DriveGalleryState {
  static const Object _noChange = Object();

  const DriveGalleryState({
    required this.items,
    required this.nextLink,
    required this.isLoadingMore,
    required this.isRefreshing,
  });

  const DriveGalleryState.initial()
    : items = const [],
      nextLink = null,
      isLoadingMore = false,
      isRefreshing = true;

  final List<drive_api.DriveItemSummary> items;
  final String? nextLink;
  final bool isLoadingMore;
  final bool isRefreshing;

  DriveGalleryState copyWith({
    List<drive_api.DriveItemSummary>? items,
    Object? nextLink = _noChange,
    bool? isLoadingMore,
    bool? isRefreshing,
  }) {
    return DriveGalleryState(
      items: items ?? this.items,
      nextLink: identical(nextLink, _noChange)
          ? this.nextLink
          : nextLink as String?,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}
