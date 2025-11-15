import 'package:skydrivex/src/rust/api/settings/download_directory.dart'
    as settings_api;

/// 专门负责下载目录的读写，避免与下载队列耦合。
class DownloadDirectoryService {
  const DownloadDirectoryService();

  Future<String> currentDirectory() async {
    try {
      return await settings_api.getDownloadDirectory();
    } catch (err) {
      throw DownloadDirectoryUnavailable(err.toString());
    }
  }

  Future<String> updateDirectory(String path) async {
    try {
      return await settings_api.setDownloadDirectory(path: path);
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
