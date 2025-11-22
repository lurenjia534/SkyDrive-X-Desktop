import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;
import 'package:skydrivex/src/rust/api/drive/upload_manager.dart'
    as upload_manager_api;

// 全局上传队列 Provider，UI 直接订阅 UploadQueueState。
final driveUploadManagerProvider =
    NotifierProvider<DriveUploadManager, drive_api.UploadQueueState>(
  DriveUploadManager.new,
);

typedef UploadQueueState = drive_api.UploadQueueState;
typedef UploadTask = drive_api.UploadTask;
typedef UploadStatus = drive_api.UploadStatus;

/// 上传队列管理：订阅 Rust 进度流、兜底拉取、维护速度缓存。
/// 责任：
/// - 入队/取消/移除/清理失败任务
/// - 订阅 upload_progress_stream 及时更新 UI
/// - 兜底轮询 upload_queue_state，防止进度流异常时状态不同步
/// - 维护速度估算，提供给 UI 展示
class DriveUploadManager extends Notifier<drive_api.UploadQueueState> {
  DriveUploadManager();

  static const _pollInterval = Duration(seconds: 5);

  Timer? _pollTimer;
  StreamSubscription<drive_api.UploadProgressUpdate>? _progressSub;
  final Map<String, double> _speedMeters = {};
  final Set<String> _pendingCancel = {};

  @override
  drive_api.UploadQueueState build() {
    // 初始化时即启动轮询与进度订阅，防止 FRB 流偶发丢失导致 UI 不更新。
    _startPolling();
    _subscribeProgressStream();
    ref.onDispose(() {
      _pollTimer?.cancel();
      _progressSub?.cancel();
    });
    unawaited(_refreshQueue(force: true));
    return const drive_api.UploadQueueState(
      active: <drive_api.UploadTask>[],
      completed: <drive_api.UploadTask>[],
      failed: <drive_api.UploadTask>[],
    );
  }

  /// 入队新上传任务。
  Future<void> enqueue({
    required String fileName,
    required String localPath,
    required Uint8List content,
    String? parentId,
    bool overwrite = false,
  }) async {
    // 直接调用 Rust 入队。失败时抛出给 UI 处理（例如 SnackBar）。
    try {
      final updated = await upload_manager_api.enqueueUploadTask(
        parentId: parentId,
        fileName: fileName,
        localPath: localPath,
        content: content,
        overwrite: overwrite,
      );
      _pruneSpeeds(updated.active);
      state = updated;
    } catch (err, stack) {
      debugPrint('enqueue upload failed: $err\n$stack');
      rethrow;
    }
  }

  Future<void> clearHistory() async {
    final updated = await upload_manager_api.clearUploadHistory();
    _pruneSpeeds(updated.active);
    state = updated;
  }

  Future<void> clearFailedTasks() async {
    try {
      final updated = await upload_manager_api.clearFailedUploadTasks();
      state = updated;
    } catch (err, stack) {
      debugPrint('clear failed upload tasks failed: $err\n$stack');
      rethrow;
    }
  }

  Future<void> removeTask(String taskId) async {
    final updated = await upload_manager_api.removeUploadTask(taskId: taskId);
    _speedMeters.remove(taskId);
    _pruneSpeeds(updated.active);
    state = updated;
  }

  Future<void> cancelTask(String taskId) async {
    // 标记取消中，防止重复点击；完成后清理状态。
    _pendingCancel.add(taskId);
    state = drive_api.UploadQueueState(
      active: state.active,
      completed: state.completed,
      failed: state.failed,
    );
    final updated = await upload_manager_api.cancelUploadTask(taskId: taskId);
    _pruneSpeeds(updated.active);
    state = updated;
    _pendingCancel.remove(taskId);
  }

  bool isCancelling(String taskId) => _pendingCancel.contains(taskId);

  bool isActive(String taskId) {
    return state.active.any((task) => task.taskId == taskId);
  }

  double? speedFor(String taskId) => _speedMeters[taskId];

  Future<void> _refreshQueue({bool force = false}) async {
    if (!force && state.active.isEmpty) return;
    try {
      final snapshot = await upload_manager_api.uploadQueueState();
      _pruneSpeeds(snapshot.active);
      state = snapshot;
    } catch (err, stack) {
      debugPrint('refresh upload queue failed: $err\n$stack');
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
    _progressSub = upload_manager_api.uploadProgressStream().listen(
          _handleProgressUpdate,
          onError: (err, stack) =>
              debugPrint('upload progress stream failed: $err\n$stack'),
        );
  }

  void _handleProgressUpdate(drive_api.UploadProgressUpdate update) {
    // 只更新命中的任务，避免无关重建。
    final updatedActive = <drive_api.UploadTask>[];
    var touched = false;
    for (final task in state.active) {
      if (task.taskId == update.taskId) {
        touched = true;
        updatedActive.add(_mergeTaskWithProgress(task, update));
      } else {
        updatedActive.add(task);
      }
    }
    if (!touched) return;

    if (update.speedBps != null) {
      _speedMeters[update.taskId] = update.speedBps!.toDouble();
    }
    _pruneSpeeds(updatedActive);
    state = drive_api.UploadQueueState(
      active: updatedActive,
      completed: state.completed,
      failed: state.failed,
    );
  }

  drive_api.UploadTask _mergeTaskWithProgress(
    drive_api.UploadTask task,
    drive_api.UploadProgressUpdate update,
  ) {
    // Rust 端只推进度，因此保留其他字段。
    return drive_api.UploadTask(
      taskId: task.taskId,
      fileName: task.fileName,
      localPath: task.localPath,
      size: update.expectedSize ?? task.size,
      mimeType: task.mimeType,
      parentId: task.parentId,
      remoteId: task.remoteId,
      status: task.status,
      startedAt: task.startedAt,
      completedAt: task.completedAt,
      bytesUploaded: update.bytesUploaded,
      errorMessage: task.errorMessage,
      sessionUrl: task.sessionUrl,
    );
  }

  void _pruneSpeeds(Iterable<drive_api.UploadTask> activeTasks) {
    final activeIds = activeTasks.map((e) => e.taskId).toSet();
    _speedMeters.removeWhere((key, _) => !activeIds.contains(key));
  }
}

/// 一些常用的扩展方法，避免在 UI 层重复逻辑。
extension UploadQueueStateExt on drive_api.UploadQueueState {
  bool isActive(String id) {
    return active.any((task) => task.taskId == id);
  }
}

extension UploadTaskExt on drive_api.UploadTask {
  /// 上传进度比例，若总大小未知则返回 null。
  double? get progressRatio {
    final uploaded = bytesUploaded;
    final total = size;
    if (uploaded == null || total == null || total == BigInt.zero) {
      return null;
    }
    return uploaded.toDouble() / total.toDouble();
  }
}
