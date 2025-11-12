import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/services/drive_download_service.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

final driveDownloadManagerProvider =
    NotifierProvider<DriveDownloadManager, DownloadQueueState>(
      DriveDownloadManager.new,
    );

class DriveDownloadManager extends Notifier<DownloadQueueState> {
  DriveDownloadManager();

  final Map<String, Completer<void>> _taskCompleters = {};
  late final DriveDownloadService _service;

  @override
  DownloadQueueState build() {
    _service = const DriveDownloadService();
    return const DownloadQueueState();
  }

  Future<void> enqueue(drive_api.DriveItemSummary item) async {
    if (state.isActive(item.id)) return;
    _taskCompleters[item.id] = Completer<void>();
    state = state.copyWith(
      active: {
        ...state.active,
        item.id: DownloadTask(
          item: item,
          status: DownloadStatus.inProgress,
          startedAt: DateTime.now(),
        ),
      },
    );
    unawaited(_runDownload(item));
  }

  Future<void> _runDownload(drive_api.DriveItemSummary item) async {
    try {
      final result = await _service.download(item: item);
      state = state.withTaskCompleted(item.id, result);
    } on DownloadDirectoryUnavailable catch (err) {
      state = state.withTaskFailed(item.id, err.message);
    } catch (err) {
      state = state.withTaskFailed(item.id, err.toString());
    } finally {
      _taskCompleters.remove(item.id)?.complete();
    }
  }

  Future<void> waitFor(String itemId) async {
    await _taskCompleters[itemId]?.future;
  }

  void clearHistory() {
    state = state.copyWith(completed: const [], failed: const []);
  }

  void removeTask(String itemId) {
    final active = Map.of(state.active)..remove(itemId);
    final failed = state.failed.where((t) => t.item.id != itemId).toList();
    final completed = state.completed
        .where((t) => t.item.id != itemId)
        .toList();
    state = state.copyWith(
      active: active,
      failed: failed,
      completed: completed,
    );
  }
}

class DownloadQueueState {
  const DownloadQueueState({
    this.active = const {},
    this.completed = const [],
    this.failed = const [],
  });

  final Map<String, DownloadTask> active;
  final List<DownloadTask> completed;
  final List<DownloadTask> failed;

  bool isActive(String id) => active.containsKey(id);

  DownloadQueueState copyWith({
    Map<String, DownloadTask>? active,
    List<DownloadTask>? completed,
    List<DownloadTask>? failed,
  }) {
    return DownloadQueueState(
      active: active ?? this.active,
      completed: completed ?? this.completed,
      failed: failed ?? this.failed,
    );
  }

  DownloadQueueState withTaskCompleted(
    String id,
    drive_api.DriveDownloadResult result,
  ) {
    final task = active[id];
    if (task == null) return this;
    final newTask = task.copyWith(
      status: DownloadStatus.completed,
      completedAt: DateTime.now(),
      savedPath: result.savedPath,
      sizeLabel: result.expectedSize ?? result.bytesDownloaded,
    );
    final updatedActive = Map.of(active)..remove(id);
    return DownloadQueueState(
      active: updatedActive,
      completed: [newTask, ...completed],
      failed: failed,
    );
  }

  DownloadQueueState withTaskFailed(String id, String message) {
    final task = active[id];
    if (task == null) return this;
    final failedTask = task.copyWith(
      status: DownloadStatus.failed,
      completedAt: DateTime.now(),
      errorMessage: message,
    );
    final updatedActive = Map.of(active)..remove(id);
    return DownloadQueueState(
      active: updatedActive,
      completed: completed,
      failed: [failedTask, ...failed],
    );
  }
}

class DownloadTask {
  const DownloadTask({
    required this.item,
    required this.status,
    required this.startedAt,
    this.completedAt,
    this.savedPath,
    this.sizeLabel,
    this.errorMessage,
  });

  final drive_api.DriveItemSummary item;
  final DownloadStatus status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? savedPath;
  final BigInt? sizeLabel;
  final String? errorMessage;

  DownloadTask copyWith({
    DownloadStatus? status,
    DateTime? completedAt,
    String? savedPath,
    BigInt? sizeLabel,
    String? errorMessage,
  }) {
    return DownloadTask(
      item: item,
      status: status ?? this.status,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      savedPath: savedPath ?? this.savedPath,
      sizeLabel: sizeLabel ?? this.sizeLabel,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

enum DownloadStatus { inProgress, completed, failed }
