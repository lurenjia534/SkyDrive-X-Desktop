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

  // UI 希望看到更细腻的速度与进度，因此把轮询间隔调短一些。
  static const _pollInterval = Duration(milliseconds: 900);

  late final DriveDownloadService _service;
  Timer? _pollTimer;
  // 记录每个任务上一次轮询的字节数与时间戳，用来计算瞬时速度。
  final Map<String, _SpeedSnapshot> _speedSnapshots = {};
  final Map<String, double> _speedMeters = {};

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
      _updateSpeeds(updated);
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
    _updateSpeeds(updated);
    state = updated;
  }

  Future<void> removeTask(String itemId) async {
    final updated = await _service.removeTask(itemId);
    _speedSnapshots.remove(itemId);
    _speedMeters.remove(itemId);
    state = updated;
  }

  bool isActive(String itemId) {
    return state.active.any((task) => task.item.id == itemId);
  }

  double? speedFor(String itemId) => _speedMeters[itemId];

  Future<void> _refreshQueue({bool force = false}) async {
    if (!force && state.active.isEmpty) return;
    try {
      final snapshot = await _service.fetchQueue();
      _updateSpeeds(snapshot);
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

  /// 根据最新的队列快照增量计算下载速度，单位 bytes/sec。
  void _updateSpeeds(drive_api.DownloadQueueState snapshot) {
    final now = DateTime.now();
    final activeIds = <String>{};
    for (final task in snapshot.active) {
      final currentBytes = _bigIntToSafeInt(task.bytesDownloaded);
      final last = _speedSnapshots[task.item.id];
      if (last != null) {
        final deltaBytes = currentBytes - last.bytes;
        final deltaMs = now.difference(last.timestamp).inMilliseconds;
        if (deltaMs > 0 && deltaBytes >= 0) {
          _speedMeters[task.item.id] = deltaBytes / (deltaMs / 1000);
        }
      }
      _speedSnapshots[task.item.id] = _SpeedSnapshot(currentBytes, now);
      activeIds.add(task.item.id);
    }
    _speedSnapshots.removeWhere((key, _) => !activeIds.contains(key));
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

class _SpeedSnapshot {
  const _SpeedSnapshot(this.bytes, this.timestamp);
  final int bytes;
  final DateTime timestamp;
}

int _bigIntToSafeInt(BigInt? value) {
  if (value == null) return 0;
  const maxSafeInt = 0x7fffffffffffffff;
  final max = BigInt.from(maxSafeInt);
  if (value > max) {
    return maxSafeInt;
  }
  return value.toInt();
}
