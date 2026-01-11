import 'dart:io';

Future<bool> revealInFileManager(String path) async {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return false;

  final entityType = await FileSystemEntity.type(
    trimmed,
    followLinks: true,
  );
  final isDirectory = entityType == FileSystemEntityType.directory;
  final file = File(trimmed);
  final filePath = file.path;
  final directoryPath = isDirectory ? trimmed : file.parent.path;
  final exists = isDirectory ? true : await file.exists();

  try {
    if (Platform.isMacOS) {
      final args = (!isDirectory && exists)
          ? ['-R', filePath]
          : [directoryPath];
      final result = await Process.run('open', args);
      return result.exitCode == 0;
    }
    if (Platform.isWindows) {
      final args = (!isDirectory && exists)
          ? ['/select,', filePath]
          : [directoryPath];
      final result = await Process.run('explorer.exe', args);
      return result.exitCode == 0;
    }
    if (Platform.isLinux) {
      final result = await Process.run('xdg-open', [directoryPath]);
      return result.exitCode == 0;
    }
  } catch (_) {
    return false;
  }

  return false;
}
