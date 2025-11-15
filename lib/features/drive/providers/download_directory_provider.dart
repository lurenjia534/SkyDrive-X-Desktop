import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/services/drive_download_service.dart';

final downloadDirectoryProvider = AsyncNotifierProvider.autoDispose<
  DownloadDirectoryController,
  String
>(DownloadDirectoryController.new);

class DownloadDirectoryController extends AsyncNotifier<String> {
  late final DriveDownloadService _service;

  @override
  Future<String> build() async {
    _service = const DriveDownloadService();
    return _fetch();
  }

  Future<void> refreshDirectory() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> updateDirectory(String path) async {
    state = const AsyncLoading();
    try {
      final value = await _service.updateDownloadDirectory(path);
      state = AsyncValue.data(value);
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      rethrow;
    }
  }

  Future<String> _fetch() {
    return _service.currentDownloadDirectory();
  }
}
