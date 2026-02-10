import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

final offlineIndexProvider =
    NotifierProvider<OfflineIndexController, OfflineIndexState>(
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
    required this.records,
    required this.parentByItemId,
  });

  static const initial = OfflineIndexState(
    enabled: false,
    isIndexing: false,
    indexedItems: 0,
    lastIndexedAt: null,
    lastError: null,
    records: <OfflineIndexedRecord>[],
    parentByItemId: <String, String?>{},
  );

  static const _keepLastError = Object();

  final bool enabled;
  final bool isIndexing;
  final int indexedItems;
  final DateTime? lastIndexedAt;
  final String? lastError;
  final List<OfflineIndexedRecord> records;
  final Map<String, String?> parentByItemId;

  bool get hasIndex => records.isNotEmpty;

  OfflineIndexState copyWith({
    bool? enabled,
    bool? isIndexing,
    int? indexedItems,
    DateTime? lastIndexedAt,
    Object? lastError = _keepLastError,
    List<OfflineIndexedRecord>? records,
    Map<String, String?>? parentByItemId,
  }) {
    return OfflineIndexState(
      enabled: enabled ?? this.enabled,
      isIndexing: isIndexing ?? this.isIndexing,
      indexedItems: indexedItems ?? this.indexedItems,
      lastIndexedAt: lastIndexedAt ?? this.lastIndexedAt,
      lastError: identical(lastError, _keepLastError)
          ? this.lastError
          : lastError as String?,
      records: records ?? this.records,
      parentByItemId: parentByItemId ?? this.parentByItemId,
    );
  }
}

@immutable
class OfflineIndexedRecord {
  const OfflineIndexedRecord({required this.item, required this.parentId});

  final drive_api.DriveItemSummary item;
  final String? parentId;
}

@immutable
class OfflineSearchPage {
  const OfflineSearchPage({required this.items, required this.nextPageToken});

  final List<drive_api.DriveItemSummary> items;
  final String? nextPageToken;
}

class OfflineIndexController extends Notifier<OfflineIndexState> {
  static const String _tokenPrefix = 'offline:';
  static const int defaultPageSize = 80;

  @override
  OfflineIndexState build() => OfflineIndexState.initial;

  void setEnabled(bool enabled) {
    if (enabled == state.enabled) return;
    state = state.copyWith(enabled: enabled, lastError: null);
  }

  Future<void> rebuildIndex() async {
    if (state.isIndexing) return;
    state = state.copyWith(isIndexing: true, lastError: null);
    try {
      final snapshot = await _buildSnapshot();
      state = state.copyWith(
        isIndexing: false,
        indexedItems: snapshot.records.length,
        lastIndexedAt: DateTime.now(),
        records: snapshot.records,
        parentByItemId: snapshot.parentByItemId,
        lastError: null,
      );
    } catch (err, stack) {
      state = state.copyWith(isIndexing: false, lastError: err.toString());
      Error.throwWithStackTrace(err, stack);
    }
  }

  OfflineSearchPage searchPage({
    required String query,
    required String? folderId,
    required String? pageToken,
    int? limit,
  }) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty || !state.enabled || !state.hasIndex) {
      return const OfflineSearchPage(items: [], nextPageToken: null);
    }

    final matches = <drive_api.DriveItemSummary>[];
    for (final record in state.records) {
      if (!_isWithinScope(record.parentId, folderId)) continue;
      if (!record.item.name.toLowerCase().contains(normalized)) continue;
      matches.add(record.item);
    }

    matches.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final safeLimit = (limit ?? defaultPageSize).clamp(1, 500);
    final offset = _parseOffset(pageToken);
    if (offset >= matches.length) {
      return const OfflineSearchPage(items: [], nextPageToken: null);
    }
    final end = math.min(offset + safeLimit, matches.length);
    final nextToken = end < matches.length ? '$_tokenPrefix$end' : null;
    return OfflineSearchPage(
      items: matches.sublist(offset, end),
      nextPageToken: nextToken,
    );
  }

  Future<_OfflineIndexSnapshot> _buildSnapshot() async {
    final records = <OfflineIndexedRecord>[];
    final parentByItemId = <String, String?>{};
    final folderQueue = Queue<String?>();
    final visitedFolders = <String>{};
    folderQueue.add(null); // root

    while (folderQueue.isNotEmpty) {
      final folderId = folderQueue.removeFirst();
      if (folderId != null && !visitedFolders.add(folderId)) {
        continue;
      }

      String? nextLink;
      do {
        final page = await drive_api.listDriveChildren(
          folderId: folderId,
          folderPath: null,
          nextLink: nextLink,
        );
        for (final item in page.items) {
          records.add(OfflineIndexedRecord(item: item, parentId: folderId));
          parentByItemId[item.id] = folderId;
          if (item.isFolder) {
            folderQueue.add(item.id);
          }
        }
        nextLink = page.nextLink;
      } while (nextLink != null);
    }

    return _OfflineIndexSnapshot(
      records: List<OfflineIndexedRecord>.unmodifiable(records),
      parentByItemId: Map<String, String?>.unmodifiable(parentByItemId),
    );
  }

  bool _isWithinScope(String? parentId, String? folderId) {
    if (folderId == null) return true;
    var current = parentId;
    while (current != null) {
      if (current == folderId) {
        return true;
      }
      current = state.parentByItemId[current];
    }
    return false;
  }

  int _parseOffset(String? pageToken) {
    if (pageToken == null || !pageToken.startsWith(_tokenPrefix)) {
      return 0;
    }
    final raw = pageToken.substring(_tokenPrefix.length);
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 0) {
      return 0;
    }
    return parsed;
  }
}

class _OfflineIndexSnapshot {
  const _OfflineIndexSnapshot({
    required this.records,
    required this.parentByItemId,
  });

  final List<OfflineIndexedRecord> records;
  final Map<String, String?> parentByItemId;
}
