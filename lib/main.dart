import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/auth/auth_prototype_page.dart';
import 'package:skydrivex/src/rust/frb_generated.dart';
import 'package:skydrivex/theme/theme.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = zincLight;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      supportedLocales: FLocalizations.supportedLocales,
      localizationsDelegates: const [...FLocalizations.localizationsDelegates],
      builder: (_, child) => FAnimatedTheme(
        data: theme,
        child: child!,
      ),
      theme: theme.toApproximateMaterialTheme(),
      home: const AuthPrototypePage(),
    );
  }
}
