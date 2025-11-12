import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

/// 构造文件/文件夹副标题，例如“10 项内容 · 更新于 ...”
String buildDriveSubtitle(drive_api.DriveItemSummary item) {
  final pieces = <String>[];
  if (item.isFolder) {
    final count = item.childCount?.toInt();
    if (count != null) {
      pieces.add('$count 项内容');
    }
  } else {
    final size = item.size?.toInt();
    if (size != null) {
      pieces.add(formatFileSize(size));
    }
    if (item.mimeType != null) {
      pieces.add(item.mimeType!);
    }
  }
  if (item.lastModified != null) {
    pieces.add('更新于 ${item.lastModified}');
  }
  if (pieces.isEmpty) return '—';
  return pieces.join(' · ');
}

/// 将字节数格式化为人类可读字符串（B/KB/MB/...）。
String formatFileSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  return unitIndex == 0
      ? '${size.toStringAsFixed(0)} ${units[unitIndex]}'
      : '${size.toStringAsFixed(1)} ${units[unitIndex]}';
}
