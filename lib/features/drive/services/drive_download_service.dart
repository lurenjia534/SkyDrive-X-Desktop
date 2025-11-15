import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;
import 'package:skydrivex/src/rust/api/drive/download_manager.dart'
    as drive_manager_api;

/// 统一封装下载逻辑：Flutter 只解析保存目录，其余队列管理交由 Rust。
class DriveDownloadService {
  const DriveDownloadService();

  Future<drive_api.DownloadQueueState> enqueue({
    required drive_api.DriveItemSummary item,
    required String targetDir,
    bool overwrite = false,
  }) {
    return drive_manager_api.enqueueDownloadTask(
      item: item,
      targetDir: targetDir,
      overwrite: overwrite,
    );
  }

  Future<drive_api.DownloadQueueState> fetchQueue() {
    return drive_manager_api.downloadQueueState();
  }

  Future<drive_api.DownloadQueueState> clearHistory() {
    return drive_manager_api.clearDownloadHistory();
  }

  Future<drive_api.DownloadQueueState> clearFailedTasks() {
    return drive_manager_api.clearFailedDownloadTasks();
  }

  Future<drive_api.DownloadQueueState> removeTask(String itemId) {
    return drive_manager_api.removeDownloadTask(itemId: itemId);
  }

  Future<drive_api.DownloadQueueState> cancelTask(String itemId) {
    return drive_manager_api.cancelDownloadTask(itemId: itemId);
  }

  Stream<drive_api.DownloadProgressUpdate> progressStream() {
    return drive_manager_api.downloadProgressStream();
  }
}
