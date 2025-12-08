import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/services/drive_item_details_service.dart';
import 'package:skydrivex/src/rust/api/drive/models.dart' as drive_models;

/// 按 itemId 提供 drive item 详情。
final driveItemDetailsProvider = FutureProvider.autoDispose
    .family<drive_models.DriveItemDetails, String>((ref, itemId) {
  final service = const DriveItemDetailsService();
  return service.fetchDetails(itemId);
});
