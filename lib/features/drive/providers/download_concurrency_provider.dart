import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/services/download_concurrency_service.dart';

/// 并行下载数的全局状态，读取/写入 Rust 端设置，并供设置页使用。
final downloadConcurrencyProvider =
    AsyncNotifierProvider.autoDispose<DownloadConcurrencyController, int>(
  DownloadConcurrencyController.new,
);

class DownloadConcurrencyController extends AsyncNotifier<int> {
  late final DownloadConcurrencyService _service;

  @override
  Future<int> build() async {
    _service = const DownloadConcurrencyService();
    return _fetch();
  }

  /// 手动刷新当前并行下载数。
  Future<void> refreshLimit() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  /// 更新并行下载数，写入 Rust 设置并刷新 UI。
  Future<void> updateLimit(int value) async {
    state = const AsyncLoading();
    try {
      final updated = await _service.updateLimit(value);
      state = AsyncValue.data(updated);
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      rethrow;
    }
  }

  Future<int> _fetch() {
    return _service.currentLimit();
  }
}
