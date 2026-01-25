import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/auth/auth_prototype_page.dart';
import 'package:skydrivex/features/drive/drive_workspace_page.dart';
import 'package:skydrivex/src/rust/frb_generated.dart';
import 'package:skydrivex/theme/app_theme_provider.dart';
import 'package:skydrivex/theme/theme.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(appThemeProvider);
    final lightTheme = zincLight;
    final darkTheme = zincDark;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      supportedLocales: FLocalizations.supportedLocales,
      localizationsDelegates: const [...FLocalizations.localizationsDelegates],
      builder: (context, child) {
        final brightness = Theme.of(context).brightness;
        final theme = brightness == Brightness.dark ? darkTheme : lightTheme;
        return FAnimatedTheme(
          data: theme,
          child: FToaster(child: child!),
        );
      },
      theme: lightTheme.toApproximateMaterialTheme(),
      darkTheme: darkTheme.toApproximateMaterialTheme(),
      themeMode: themeState.themeMode,
      initialRoute: '/auth',
      routes: {
        '/auth': (_) => const AuthPrototypePage(),
        '/drive': (_) => DriveWorkspacePage(
          authPageBuilder: (_) => const AuthPrototypePage(),
        ),
      },
    );
  }
}
