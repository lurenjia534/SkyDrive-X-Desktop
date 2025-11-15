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

/// 下载队列的前端状态管理器：负责连接 Rust 服务、接收进度流并向 UI 分发最新状态。
class DriveDownloadManager extends Notifier<drive_api.DownloadQueueState> {
  DriveDownloadManager();

  // 主更新路径改成 Stream 推送，轮询仅作为兜底机制即可。
  static const _pollInterval = Duration(seconds: 5);

  late final DriveDownloadService _service;
  Timer? _pollTimer;
  StreamSubscription<drive_api.DownloadProgressUpdate>? _progressSub;
  /// 缓存每个任务最近一次的速度估算，UI 读取即可得到实时速率。
  final Map<String, double> _speedMeters = {};

  /// 正在等待 Rust 确认取消的任务列表，用于给 UI 提供“取消中”的即时反馈。
  final Set<String> _pendingCancel = {};

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

  /// 入队新的下载任务，并立即刷新状态以驱动 UI。
  Future<void> enqueue(
    drive_api.DriveItemSummary item, {
    required String targetDirectory,
    bool overwrite = false,
  }) async {
    try {
      final updated = await _service.enqueue(
        item: item,
        targetDir: targetDirectory,
        overwrite: overwrite,
      );
      _pruneSpeeds(updated.active);
      state = updated;
    } catch (err, stack) {
      debugPrint('enqueue download failed: $err\n$stack');
      rethrow;
    }
  }

  /// 清理所有历史记录（完成/失败），Active 列表保持不动。
  Future<void> clearHistory() async {
    final updated = await _service.clearHistory();
    _pruneSpeeds(updated.active);
    state = updated;
  }

  /// 从队列中移除任意状态的任务，通常用于手动清除条目。
  Future<void> removeTask(String itemId) async {
    final updated = await _service.removeTask(itemId);
    _speedMeters.remove(itemId);
    _pruneSpeeds(updated.active);
    state = updated;
  }

  /// 发送取消指令给 Rust，同时做乐观更新，避免按钮出现延迟。
  Future<void> cancelTask(String itemId) async {
    _pendingCancel.add(itemId);
    state = drive_api.DownloadQueueState(
      active: state.active,
      completed: state.completed,
      failed: state.failed,
    );
    final updated = await _service.cancelTask(itemId);
    _pruneSpeeds(updated.active);
    state = updated;
    _pendingCancel.remove(itemId);
  }

  /// 查询指定任务是否处于“等待取消确认”状态。
  bool isCancelling(String itemId) => _pendingCancel.contains(itemId);

  /// 一键清理所有失败记录，由 Rust 批量执行删除操作。
  Future<void> clearFailedTasks() async {
    try {
      final updated = await _service.clearFailedTasks();
      state = updated;
    } catch (err, stack) {
      debugPrint('clear failed download tasks failed: $err\n$stack');
      rethrow;
    }
  }

  /// 判断某个 item 是否仍在 active 队列中。
  bool isActive(String itemId) {
    return state.active.any((task) => task.item.id == itemId);
  }

  /// 返回缓存的实时速度，若任务未记录速度则返回 null。
  double? speedFor(String itemId) => _speedMeters[itemId];

  /// 强制刷新 Rust 队列快照，兜底进度流异常或应用刚启动时的状态。
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

  /// 定时轮询下载队列，仅在 active 不为空时工作。
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (state.active.isEmpty) return;
      unawaited(_refreshQueue());
    });
  }

  /// 订阅 Rust 推送的进度事件，按需更新本地状态。
  void _subscribeProgressStream() {
    _progressSub?.cancel();
    _progressSub = _service.progressStream().listen(
      _handleProgressUpdate,
      onError: (err, stack) =>
          debugPrint('progress stream failed: $err\n$stack'),
    );
  }

  /// 处理单条进度更新并刷新 active 队列，同时维护速度缓存。
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

  /// 将进度增量合并到现有任务，用于构造新的队列快照。
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

  /// 清理已完成/删除任务对应的速度缓存，防止内存泄漏。
  void _pruneSpeeds(Iterable<drive_api.DownloadTask> activeTasks) {
    final activeIds = activeTasks.map((e) => e.item.id).toSet();
    _speedMeters.removeWhere((key, _) => !activeIds.contains(key));
  }
}

/// 一些常用的扩展方法，避免在 UI 层重复编写查询/运算逻辑。
extension DownloadQueueStateExt on drive_api.DownloadQueueState {
  /// 判断给定 ID 是否存在于 active 队列，可用于禁用重复点击。
  bool isActive(String id) {
    return active.any((task) => task.item.id == id);
  }
}

extension DownloadTaskExt on drive_api.DownloadTask {
  /// 计算下载进度的比例值，若缺失 size 或尚未开始则返回 null。
  double? get progressRatio {
    final downloaded = bytesDownloaded;
    final total = sizeLabel;
    if (downloaded == null || total == null || total == BigInt.zero) {
      return null;
    }
    return downloaded.toDouble() / total.toDouble();
  }
}
