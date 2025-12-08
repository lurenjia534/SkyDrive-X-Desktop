import 'package:skydrivex/src/rust/api/drive/info.dart' as drive_info_api;
import 'package:skydrivex/src/rust/api/drive/models.dart' as drive_models;

/// 负责获取 OneDrive 概览信息，供设置页使用。
class DriveInfoService {
  const DriveInfoService();

  Future<drive_models.DriveInfo> fetchOverview() async {
    try {
      return await drive_info_api.getDriveOverview();
    } catch (err) {
      throw DriveInfoUnavailable(err.toString());
    }
  }
}

class DriveInfoUnavailable implements Exception {
  const DriveInfoUnavailable(this.message);

  final String message;

  @override
  String toString() => 'DriveInfoUnavailable: $message';
}
