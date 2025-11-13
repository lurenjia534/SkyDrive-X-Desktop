import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/services/drive_download_service.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

final driveDownloadManagerProvider =
    NotifierProvider<DriveDownloadManager, drive_api.DownloadQueueState>(
      DriveDownloadManager.new,
    );

typedef DownloadQueueState = drive_api.DownloadQueueState;
typedef DownloadTask = drive_api.DownloadTask;
typedef DownloadStatus = drive_api.DownloadStatus;

class DriveDownloadManager extends Notifier<drive_api.DownloadQueueState> {
  DriveDownloadManager();

  static const _pollInterval = Duration(seconds: 2);

  late final DriveDownloadService _service;
  Timer? _pollTimer;

  @override
  drive_api.DownloadQueueState build() {
    _service = const DriveDownloadService();
    _startPolling();
    ref.onDispose(() => _pollTimer?.cancel());
    unawaited(_refreshQueue(force: true));
    return drive_api.DownloadQueueState(
      active: const <drive_api.DownloadTask>[],
      completed: const <drive_api.DownloadTask>[],
      failed: const <drive_api.DownloadTask>[],
    );
  }

  Future<void> enqueue(
    drive_api.DriveItemSummary item, {
    bool overwrite = false,
  }) async {
    try {
      final updated = await _service.enqueue(item: item, overwrite: overwrite);
      state = updated;
    } on DownloadDirectoryUnavailable {
      rethrow;
    } catch (err, stack) {
      debugPrint('enqueue download failed: $err\n$stack');
      rethrow;
    }
  }

  Future<void> clearHistory() async {
    final updated = await _service.clearHistory();
    state = updated;
  }

  Future<void> removeTask(String itemId) async {
    final updated = await _service.removeTask(itemId);
    state = updated;
  }

  bool isActive(String itemId) {
    return state.active.any((task) => task.item.id == itemId);
  }

  Future<void> _refreshQueue({bool force = false}) async {
    if (!force && state.active.isEmpty) return;
    try {
      final snapshot = await _service.fetchQueue();
      state = snapshot;
    } catch (err, stack) {
      debugPrint('refresh download queue failed: $err\n$stack');
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (state.active.isEmpty) return;
      unawaited(_refreshQueue());
    });
  }
}

extension DownloadQueueStateExt on drive_api.DownloadQueueState {
  bool isActive(String id) {
    return active.any((task) => task.item.id == id);
  }
}
