import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DriveItemViewMode { list, grid }

final driveItemViewModeProvider =
    NotifierProvider<DriveViewModeController, DriveItemViewMode>(
  DriveViewModeController.new,
);

class DriveViewModeController extends Notifier<DriveItemViewMode> {
  @override
  DriveItemViewMode build() => DriveItemViewMode.list;

  void setMode(DriveItemViewMode mode) {
    if (state == mode) return;
    state = mode;
  }
}
