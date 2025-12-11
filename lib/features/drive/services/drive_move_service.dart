import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

/// 为“移动到”浏览逻辑提供的数据获取能力。
class DriveMoveService {
  const DriveMoveService();

  Future<List<drive_api.DriveItemSummary>> fetchChildren(
    String? folderId,
  ) async {
    try {
      final page = await drive_api.listDriveChildren(
        folderId: folderId,
        folderPath: null,
        nextLink: null,
      );
      return page.items;
    } catch (err) {
      throw DriveMoveBrowseFailure(err.toString());
    }
  }
}

class DriveMoveBrowseFailure implements Exception {
  const DriveMoveBrowseFailure(this.message);

  final String message;

  @override
  String toString() => 'DriveMoveBrowseFailure: $message';
}
