import 'package:skydrivex/src/rust/api/settings/download_concurrency.dart'
    as settings_api;

class DownloadConcurrencyService {
  const DownloadConcurrencyService();

  Future<int> currentLimit() async {
    try {
      final value = await settings_api.getDownloadConcurrency();
      return value;
    } catch (err) {
      throw DownloadConcurrencyUnavailable(err.toString());
    }
  }

  /// 将用户设置的最大并行下载数写入 Rust 设置，并立即生效。
  Future<int> updateLimit(int limit) async {
    try {
      final updated = await settings_api.setDownloadConcurrency(limit: limit);
      return updated;
    } catch (err) {
      throw DownloadConcurrencyUnavailable(err.toString());
    }
  }
}

class DownloadConcurrencyUnavailable implements Exception {
  const DownloadConcurrencyUnavailable(this.message);

  final String message;

  @override
  String toString() => 'DownloadConcurrencyUnavailable: $message';
}
