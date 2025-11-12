import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;
import 'package:skydrivex/utils/download_destination.dart';

/// 统一封装下载流程，确保目录解析与 Rust API 调用逻辑集中管理。
class DriveDownloadService {
  const DriveDownloadService();

  /// 返回下载结果；如果无法解析下载目录会抛出 [DownloadDirectoryUnavailable]。
  Future<drive_api.DriveDownloadResult> download({
    required drive_api.DriveItemSummary item,
    bool overwrite = false,
  }) async {
    final targetDir = _resolveDownloadDirectory();
    return drive_api.downloadDriveItem(
      itemId: item.id,
      targetDir: targetDir,
      overwrite: overwrite,
    );
  }

  String _resolveDownloadDirectory() {
    try {
      return defaultDownloadDirectory();
    } catch (err) {
      throw DownloadDirectoryUnavailable(err.toString());
    }
  }
}

class DownloadDirectoryUnavailable implements Exception {
  const DownloadDirectoryUnavailable(this.message);

  final String message;

  @override
  String toString() => 'DownloadDirectoryUnavailable: $message';
}
