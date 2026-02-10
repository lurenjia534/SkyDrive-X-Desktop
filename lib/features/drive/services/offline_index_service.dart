import 'package:skydrivex/src/rust/api/drive/models.dart' as drive_api;
import 'package:skydrivex/src/rust/api/drive/offline_index.dart'
    as drive_offline_index_api;
import 'package:skydrivex/src/rust/api/settings/offline_index.dart'
    as settings_api;

class OfflineIndexService {
  const OfflineIndexService();

  Future<bool> getEnabled() async {
    try {
      return await settings_api.getOfflineIndexEnabled();
    } catch (err) {
      throw OfflineIndexUnavailable(err.toString());
    }
  }

  Future<bool> setEnabled(bool value) async {
    try {
      return await settings_api.setOfflineIndexEnabled(value: value);
    } catch (err) {
      throw OfflineIndexUnavailable(err.toString());
    }
  }

  Future<drive_api.OfflineIndexStatus> fetchStatus() async {
    try {
      return await drive_offline_index_api.getOfflineIndexStatus();
    } catch (err) {
      throw OfflineIndexUnavailable(err.toString());
    }
  }

  Future<drive_api.OfflineIndexStatus> rebuild() async {
    try {
      return await drive_offline_index_api.rebuildOfflineIndex();
    } catch (err) {
      throw OfflineIndexUnavailable(err.toString());
    }
  }

  Future<drive_api.DrivePage> search({
    required String query,
    String? folderId,
    String? nextLink,
    int? top,
  }) async {
    try {
      return await drive_offline_index_api.searchOfflineIndex(
        query: query,
        folderId: folderId,
        nextLink: nextLink,
        top: top,
      );
    } catch (err) {
      throw OfflineIndexUnavailable(err.toString());
    }
  }
}

class OfflineIndexUnavailable implements Exception {
  const OfflineIndexUnavailable(this.message);

  final String message;

  @override
  String toString() => 'OfflineIndexUnavailable: $message';
}
