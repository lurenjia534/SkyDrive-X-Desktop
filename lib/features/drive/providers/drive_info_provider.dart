import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/services/drive_info_service.dart';
import 'package:skydrivex/src/rust/api/drive/models.dart' as drive_models;

/// 提供 OneDrive 概览信息的异步状态。
final driveInfoProvider =
    AsyncNotifierProvider.autoDispose<DriveInfoController, drive_models.DriveInfo>(
  DriveInfoController.new,
);

class DriveInfoController extends AsyncNotifier<drive_models.DriveInfo> {
  late final DriveInfoService _service;

  @override
  Future<drive_models.DriveInfo> build() async {
    _service = const DriveInfoService();
    return _fetch();
  }

  Future<void> refreshInfo() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<drive_models.DriveInfo> _fetch() {
    return _service.fetchOverview();
  }
}
