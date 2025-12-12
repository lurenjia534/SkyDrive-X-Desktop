import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_prototype_view_model.dart';
import 'prototype/auth_prototype_view.dart';

/// 认证页容器：只负责副作用监听（导航）与把事件交给 ViewModel。
class AuthPrototypePage extends ConsumerWidget {
  const AuthPrototypePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AuthPrototypeUiState>(authPrototypeViewModelProvider, (
      previous,
      next,
    ) {
      if (!context.mounted) return;
      if (next.shouldNavigateToDrive &&
          previous?.shouldNavigateToDrive != true) {
        Navigator.of(context).pushReplacementNamed('/drive');
        ref
            .read(authPrototypeViewModelProvider.notifier)
            .clearNavigationIntent();
      }
    });

    final uiState = ref.watch(authPrototypeViewModelProvider);
    return AuthPrototypeView(
      uiState: uiState,
      onSignIn: (clientId) => ref
          .read(authPrototypeViewModelProvider.notifier)
          .signInWithClientId(clientId),
    );
  }
}
