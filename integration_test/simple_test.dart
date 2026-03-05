import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/drive/drive_workspace_page.dart';
import 'package:skydrivex/main.dart';
import 'package:skydrivex/src/rust/api/simple.dart';
import 'package:skydrivex/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

  testWidgets('Boot app and call rust bridge', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyApp()));

    // Avoid pumpAndSettle() here: the app may have ongoing animations/tickers,
    // but we only care that it boots to a usable screen (auth or drive).
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final onAuth = find.textContaining('CLIENT ID').evaluate().isNotEmpty;
      final onDrive = find.byType(DriveWorkspacePage).evaluate().isNotEmpty;
      if (onAuth || onDrive) break;
    }

    final onAuth = find.textContaining('CLIENT ID').evaluate().isNotEmpty;
    final onDrive = find.byType(DriveWorkspacePage).evaluate().isNotEmpty;
    expect(
      onAuth || onDrive,
      isTrue,
      reason: 'Expected to boot into auth (CLIENT ID) or drive workspace.',
    );
    // Just validate the bridge roundtrip works; exact wording may change.
    expect(greet(name: 'Tom'), contains('Tom'));
  });
}
