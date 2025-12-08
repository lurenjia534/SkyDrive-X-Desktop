import 'package:skydrivex/src/rust/api/drive/details.dart' as drive_details_api;
import 'package:skydrivex/src/rust/api/drive/models.dart' as drive_models;

/// 获取文件/文件夹的完整属性。
class DriveItemDetailsService {
  const DriveItemDetailsService();

  Future<drive_models.DriveItemDetails> fetchDetails(String itemId) async {
    try {
      return await drive_details_api.getDriveItemDetails(itemId: itemId);
    } catch (err) {
      throw DriveItemDetailsUnavailable(err.toString());
    }
  }
}

class DriveItemDetailsUnavailable implements Exception {
  const DriveItemDetailsUnavailable(this.message);

  final String message;

  @override
  String toString() => 'DriveItemDetailsUnavailable: $message';
}
