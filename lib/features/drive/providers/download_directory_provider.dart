import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/services/download_directory_service.dart';

final downloadDirectoryProvider = AsyncNotifierProvider.autoDispose<
  DownloadDirectoryController,
  String
>(DownloadDirectoryController.new);

class DownloadDirectoryController extends AsyncNotifier<String> {
  late final DownloadDirectoryService _service;

  @override
  Future<String> build() async {
    _service = const DownloadDirectoryService();
    return _fetch();
  }

  Future<void> refreshDirectory() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> updateDirectory(String path) async {
    state = const AsyncLoading();
    try {
      final value = await _service.updateDirectory(path);
      state = AsyncValue.data(value);
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      rethrow;
    }
  }

  Future<String> _fetch() {
    return _service.currentDirectory();
  }
}
