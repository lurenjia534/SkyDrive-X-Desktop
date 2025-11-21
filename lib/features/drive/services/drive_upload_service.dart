import 'package:skydrivex/src/rust/api/drive/upload.dart' as drive_upload_api;
import 'package:skydrivex/src/rust/api/drive.dart' as drive_models;

/// 负责调用 Rust 小文件上传接口的轻量封装。
class DriveUploadService {
  const DriveUploadService();

  Future<drive_models.DriveItemSummary> uploadSmallFile({
    String? parentId,
    required String fileName,
    required List<int> bytes,
    bool overwrite = false,
  }) {
    return drive_upload_api.uploadSmallFile(
      parentId: parentId,
      fileName: fileName,
      content: bytes,
      overwrite: overwrite,
    );
  }
}
