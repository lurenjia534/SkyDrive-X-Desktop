import 'dart:io';

Future<bool> revealInFileManager(String path) async {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return false;

  final file = File(trimmed);
  final exists = await file.exists();
  final filePath = file.path;
  final directoryPath = file.parent.path;

  try {
    if (Platform.isMacOS) {
      final args = exists ? ['-R', filePath] : [directoryPath];
      final result = await Process.run('open', args);
      return result.exitCode == 0;
    }
    if (Platform.isWindows) {
      final args = exists ? ['/select,', filePath] : [directoryPath];
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
