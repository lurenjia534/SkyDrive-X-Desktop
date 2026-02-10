import 'package:flutter_riverpod/flutter_riverpod.dart';

final driveSearchQueryProvider =
    NotifierProvider<DriveSearchQueryNotifier, String>(
      DriveSearchQueryNotifier.new,
    );

class DriveSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
  }

  void clear() {
    state = '';
  }
}
