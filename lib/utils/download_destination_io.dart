import 'dart:io';

/// Resolve a writable directory for saving downloaded files.
///
/// Preference order:
/// 1. `$XDG_DOWNLOAD_DIR` if available (with `~` expanded).
/// 2. `<home or user profile>/Downloads`.
/// 3. System temporary directory.
///
/// The Skydrivex-specific subfolder is appended automatically.
String defaultDownloadDirectory() {
  final homeEnv = Platform.environment['HOME'];
  final userProfile = Platform.environment['USERPROFILE'];
  final resolvedXdg = _expandHome(
    Platform.environment['XDG_DOWNLOAD_DIR'],
    homeEnv ?? userProfile,
  );

  final primaryHome = Platform.isWindows
      ? (userProfile?.trim().isNotEmpty ?? false
            ? userProfile!.trim()
            : homeEnv)
      : (homeEnv?.trim().isNotEmpty ?? false ? homeEnv!.trim() : userProfile);

  final downloadsBase =
      _firstNonEmpty([
        resolvedXdg,
        primaryHome != null ? _joinSegments(primaryHome, ['Downloads']) : null,
      ]) ??
      Directory.systemTemp.path;

  final appFolder = Platform.isWindows ? 'Skydrivex' : 'skydrivex';
  return _joinSegments(downloadsBase, [appFolder]);
}

String? _firstNonEmpty(List<String?> candidates) {
  for (final candidate in candidates) {
    if (candidate == null) continue;
    final trimmed = candidate.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

String? _expandHome(String? path, String? home) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('~')) {
    if (home == null || home.isEmpty) {
      return path;
    }
    return path.replaceFirst('~', home);
  }
  return path;
}

String _joinSegments(String root, List<String> segments) {
  var current = root;
  final separator = Platform.pathSeparator;
  for (final segment in segments) {
    if (segment.isEmpty) continue;
    if (!current.endsWith(separator)) {
      current += separator;
    }
    current += segment;
  }
  return current;
}
