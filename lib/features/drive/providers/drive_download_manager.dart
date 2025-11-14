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

  // 主更新路径改成 Stream 推送，轮询仅作为兜底机制即可。
  static const _pollInterval = Duration(seconds: 5);

  late final DriveDownloadService _service;
  Timer? _pollTimer;
  StreamSubscription<drive_api.DownloadProgressUpdate>? _progressSub;
  final Map<String, double> _speedMeters = {};

  @override
  drive_api.DownloadQueueState build() {
    _service = const DriveDownloadService();
    _startPolling();
    _subscribeProgressStream();
    ref.onDispose(() {
      _pollTimer?.cancel();
      _progressSub?.cancel();
    });
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
      _pruneSpeeds(updated.active);
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
    _pruneSpeeds(updated.active);
    state = updated;
  }

  Future<void> removeTask(String itemId) async {
    final updated = await _service.removeTask(itemId);
    _speedMeters.remove(itemId);
    _pruneSpeeds(updated.active);
    state = updated;
  }

  Future<void> cancelTask(String itemId) async {
    final updated = await _service.cancelTask(itemId);
    _pruneSpeeds(updated.active);
    state = updated;
  }

  Future<void> clearFailedTasks() async {
    try {
      final updated = await _service.clearFailedTasks();
      state = updated;
    } catch (err, stack) {
      debugPrint('clear failed download tasks failed: $err\n$stack');
      rethrow;
    }
  }

  bool isActive(String itemId) {
    return state.active.any((task) => task.item.id == itemId);
  }

  double? speedFor(String itemId) => _speedMeters[itemId];

  Future<void> _refreshQueue({bool force = false}) async {
    if (!force && state.active.isEmpty) return;
    try {
      final snapshot = await _service.fetchQueue();
      _pruneSpeeds(snapshot.active);
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

  void _subscribeProgressStream() {
    _progressSub?.cancel();
    _progressSub = _service.progressStream().listen(
      _handleProgressUpdate,
      onError: (err, stack) =>
          debugPrint('progress stream failed: $err\n$stack'),
    );
  }

  void _handleProgressUpdate(drive_api.DownloadProgressUpdate update) {
    final updatedActive = <drive_api.DownloadTask>[];
    var touched = false;
    for (final task in state.active) {
      if (task.item.id == update.itemId) {
        touched = true;
        updatedActive.add(_mergeTaskWithProgress(task, update));
      } else {
        updatedActive.add(task);
      }
    }
    if (!touched) return;

    if (update.speedBps != null) {
      _speedMeters[update.itemId] = update.speedBps!.toDouble();
    }
    _pruneSpeeds(updatedActive);
    state = drive_api.DownloadQueueState(
      active: updatedActive,
      completed: state.completed,
      failed: state.failed,
    );
  }

  drive_api.DownloadTask _mergeTaskWithProgress(
    drive_api.DownloadTask task,
    drive_api.DownloadProgressUpdate update,
  ) {
    return drive_api.DownloadTask(
      item: task.item,
      status: task.status,
      startedAt: task.startedAt,
      completedAt: task.completedAt,
      savedPath: task.savedPath,
      sizeLabel: update.expectedSize ?? task.sizeLabel,
      bytesDownloaded: update.bytesDownloaded,
      errorMessage: task.errorMessage,
    );
  }

  void _pruneSpeeds(Iterable<drive_api.DownloadTask> activeTasks) {
    final activeIds = activeTasks.map((e) => e.item.id).toSet();
    _speedMeters.removeWhere((key, _) => !activeIds.contains(key));
  }
}

extension DownloadQueueStateExt on drive_api.DownloadQueueState {
  bool isActive(String id) {
    return active.any((task) => task.item.id == id);
  }
}

extension DownloadTaskExt on drive_api.DownloadTask {
  double? get progressRatio {
    final downloaded = bytesDownloaded;
    final total = sizeLabel;
    if (downloaded == null || total == null || total == BigInt.zero) {
      return null;
    }
    return downloaded.toDouble() / total.toDouble();
  }
}
