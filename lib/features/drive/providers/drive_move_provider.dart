import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/models/drive_breadcrumb.dart';
import 'package:skydrivex/features/drive/services/drive_move_service.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

/// 管理“移动到”面板的浏览状态。
final driveMoveBrowserProvider =
    NotifierProvider.autoDispose<DriveMoveController, DriveMoveState>(
      DriveMoveController.new,
    );

class DriveMoveController extends Notifier<DriveMoveState> {
  late final DriveMoveService _service;

  @override
  DriveMoveState build() {
    _service = const DriveMoveService();
    _loadFolder(folderId: null, breadcrumbs: const []);
    return const DriveMoveState.initial();
  }

  Future<void> refreshCurrent() async {
    await _loadFolder(
      folderId: state.currentFolderId,
      breadcrumbs: state.breadcrumbs,
    );
  }

  Future<void> enterFolder(drive_api.DriveItemSummary folder) async {
    final breadcrumbs = [
      ...state.breadcrumbs,
      DriveBreadcrumbSegment(id: folder.id, name: folder.name),
    ];
    await _loadFolder(folderId: folder.id, breadcrumbs: breadcrumbs);
  }

  Future<void> goBack() async {
    final breadcrumbs = state.breadcrumbs;
    if (breadcrumbs.isEmpty) return;
    final trimmed = breadcrumbs.sublist(0, breadcrumbs.length - 1);
    final parentId = trimmed.isNotEmpty ? trimmed.last.id : null;
    await _loadFolder(folderId: parentId, breadcrumbs: trimmed);
  }

  Future<void> _loadFolder({
    required String? folderId,
    required List<DriveBreadcrumbSegment> breadcrumbs,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final items = await _service.fetchChildren(folderId);
      if (!ref.mounted) return;
      state = state.copyWith(
        currentFolderId: folderId,
        breadcrumbs: breadcrumbs,
        items: items,
        isLoading: false,
        clearError: true,
      );
    } catch (err) {
      if (!ref.mounted) return;
      final message =
          err is DriveMoveBrowseFailure ? err.message : err.toString();
      state = state.copyWith(
        isLoading: false,
        error: message,
      );
    }
  }
}

class DriveMoveState {
  const DriveMoveState({
    required this.currentFolderId,
    required this.breadcrumbs,
    required this.items,
    required this.isLoading,
    required this.error,
  });

  const DriveMoveState.initial()
    : currentFolderId = null,
      breadcrumbs = const [],
      items = const [],
      isLoading = true,
      error = null;

  final String? currentFolderId;
  final List<DriveBreadcrumbSegment> breadcrumbs;
  final List<drive_api.DriveItemSummary> items;
  final bool isLoading;
  final String? error;

  DriveMoveState copyWith({
    String? currentFolderId,
    List<DriveBreadcrumbSegment>? breadcrumbs,
    List<drive_api.DriveItemSummary>? items,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return DriveMoveState(
      currentFolderId: currentFolderId ?? this.currentFolderId,
      breadcrumbs: breadcrumbs ?? this.breadcrumbs,
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
    );
  }
}
