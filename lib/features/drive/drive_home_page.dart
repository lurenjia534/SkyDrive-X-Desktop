import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/main.dart';

class DriveHomePage extends ConsumerWidget {
  const DriveHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(authControllerProvider).tokens;

    return Scaffold(
      appBar: AppBar(title: const Text('OneDrive 文件')),
      body: Center(
        child: tokens != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.folder, size: 64),
                  SizedBox(height: 16),
                  Text('这里将展示 OneDrive 文件列表'),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
