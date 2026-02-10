import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/services/offline_index_service.dart';
import 'package:skydrivex/src/rust/api/drive/models.dart' as drive_api;

final offlineIndexProvider =
    AsyncNotifierProvider<OfflineIndexController, OfflineIndexState>(
      OfflineIndexController.new,
    );

@immutable
class OfflineIndexState {
  const OfflineIndexState({
    required this.enabled,
    required this.isIndexing,
    required this.indexedItems,
    required this.lastIndexedAt,
    required this.lastError,
  });

  static const initial = OfflineIndexState(
    enabled: false,
    isIndexing: false,
    indexedItems: 0,
    lastIndexedAt: null,
    lastError: null,
  );

  static const _keepLastError = Object();

  final bool enabled;
  final bool isIndexing;
  final int indexedItems;
  final DateTime? lastIndexedAt;
  final String? lastError;

  bool get hasIndex => indexedItems > 0;

  OfflineIndexState copyWith({
    bool? enabled,
    bool? isIndexing,
    int? indexedItems,
    DateTime? lastIndexedAt,
    Object? lastError = _keepLastError,
  }) {
    return OfflineIndexState(
      enabled: enabled ?? this.enabled,
      isIndexing: isIndexing ?? this.isIndexing,
      indexedItems: indexedItems ?? this.indexedItems,
      lastIndexedAt: lastIndexedAt ?? this.lastIndexedAt,
      lastError: identical(lastError, _keepLastError)
          ? this.lastError
          : lastError as String?,
    );
  }
}

class OfflineIndexController extends AsyncNotifier<OfflineIndexState> {
  late final OfflineIndexService _service;

  @override
  Future<OfflineIndexState> build() async {
    _service = const OfflineIndexService();
    final enabled = await _service.getEnabled();
    final status = await _service.fetchStatus();
    return OfflineIndexState(
      enabled: enabled,
      isIndexing: false,
      indexedItems: status.indexedItems,
      lastIndexedAt: _parseTimestamp(status.lastIndexedAtMillis),
      lastError: null,
    );
  }

  OfflineIndexState _fallbackState() {
    return state.value ?? OfflineIndexState.initial;
  }

  Future<void> setEnabled(bool enabled) async {
    final previous = _fallbackState();
    final next = previous.copyWith(enabled: enabled, lastError: null);
    state = AsyncValue.data(next);
    try {
      await _service.setEnabled(enabled);
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      state = AsyncValue.data(previous);
      rethrow;
    }
  }

  Future<void> rebuildIndex() async {
    final previous = _fallbackState();
    state = AsyncValue.data(
      previous.copyWith(isIndexing: true, lastError: null),
    );
    try {
      final status = await _service.rebuild();
      state = AsyncValue.data(
        previous.copyWith(
          isIndexing: false,
          indexedItems: status.indexedItems,
          lastIndexedAt: _parseTimestamp(status.lastIndexedAtMillis),
          lastError: null,
        ),
      );
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      state = AsyncValue.data(
        previous.copyWith(isIndexing: false, lastError: err.toString()),
      );
      rethrow;
    }
  }

  Future<drive_api.DrivePage> searchPage({
    required String query,
    required String? folderId,
    required String? nextLink,
    int? limit,
  }) {
    return _service.search(
      query: query,
      folderId: folderId,
      nextLink: nextLink,
      top: limit,
    );
  }

  DateTime? _parseTimestamp(int? millis) {
    if (millis == null || millis <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
}
