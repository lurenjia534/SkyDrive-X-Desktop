import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/auth/auth_controller.dart';
import 'package:skydrivex/features/drive/providers/drive_download_manager.dart';
import 'package:skydrivex/features/drive/providers/drive_home_controller.dart';
import 'package:skydrivex/features/drive/providers/drive_info_provider.dart';
import 'package:skydrivex/features/drive/providers/drive_upload_manager.dart';
import 'package:skydrivex/features/drive/services/drive_info_service.dart';
import 'package:skydrivex/src/rust/api/auth/auth.dart' as auth_api;

final accountManagementControllerProvider =
    NotifierProvider.autoDispose<AccountManagementController, AccountManagementState>(
  AccountManagementController.new,
);

enum AccountManagementAction { activate, remove }

class AccountManagementState {
  const AccountManagementState({
    this.busyAccountId,
    this.busyAction,
    this.hydratedAccountId,
    this.isHydratingProfile = false,
  });

  final String? busyAccountId;
  final AccountManagementAction? busyAction;
  final String? hydratedAccountId;
  final bool isHydratingProfile;

  AccountManagementState copyWith({
    String? busyAccountId,
    AccountManagementAction? busyAction,
    String? hydratedAccountId,
    bool? isHydratingProfile,
    bool clearBusy = false,
  }) {
    return AccountManagementState(
      busyAccountId: clearBusy ? null : (busyAccountId ?? this.busyAccountId),
      busyAction: clearBusy ? null : (busyAction ?? this.busyAction),
      hydratedAccountId: hydratedAccountId ?? this.hydratedAccountId,
      isHydratingProfile: isHydratingProfile ?? this.isHydratingProfile,
    );
  }
}

class AccountManagementController extends Notifier<AccountManagementState> {
  final DriveInfoService _driveInfoService = const DriveInfoService();

  @override
  AccountManagementState build() => const AccountManagementState();

  Future<bool> addAccount(String clientId) async {
    final ok = await ref
        .read(authControllerProvider.notifier)
        .authenticateWithClientId(clientId);
    if (!ref.mounted) return false;
    if (!ok) return false;
    await _hydrateActiveAccountProfile();
    _invalidateDriveCaches();
    return true;
  }

  Future<bool> activateAccount(AuthAccount account) async {
    if (state.busyAccountId != null) return false;
    state = state.copyWith(
      busyAccountId: account.accountId,
      busyAction: AccountManagementAction.activate,
    );
    final ok = await ref
        .read(authControllerProvider.notifier)
        .setActiveAccount(account.accountId);
    if (!ref.mounted) return false;
    state = state.copyWith(clearBusy: true);
    if (!ok) return false;
    await _hydrateActiveAccountProfile(accountId: account.accountId);
    _invalidateDriveCaches();
    return true;
  }

  Future<bool> removeAccount(AuthAccount account) async {
    if (state.busyAccountId != null) return false;
    state = state.copyWith(
      busyAccountId: account.accountId,
      busyAction: AccountManagementAction.remove,
    );
    final ok = await ref.read(authControllerProvider.notifier).removeAccount(
          account.accountId,
          wasActive: account.isActive,
        );
    if (!ref.mounted) return false;
    state = state.copyWith(clearBusy: true);
    if (!ok) return false;
    if (account.isActive) {
      _invalidateDriveCaches();
    }
    return true;
  }

  void ensureActiveProfileHydrated(AuthState authState) {
    if (state.isHydratingProfile) return;
    if (authState.isAuthenticating || authState.isLoadingAccounts) return;
    final activeAccount = authState.accounts
        .cast<AuthAccount?>()
        .firstWhere((account) => account?.isActive ?? false, orElse: () => null);
    if (activeAccount == null) return;
    if (activeAccount.displayName != null &&
        activeAccount.userPrincipalName != null) {
      return;
    }
    if (state.hydratedAccountId == activeAccount.accountId) return;
    final targetAccountId = activeAccount.accountId;
    // Defer provider writes until after current build/lifecycle turn.
    Future<void>.microtask(() async {
      if (!ref.mounted) return;
      if (state.isHydratingProfile) return;
      if (state.hydratedAccountId == targetAccountId) return;
      await _hydrateActiveAccountProfile(accountId: targetAccountId);
    });
  }

  Future<void> _hydrateActiveAccountProfile({String? accountId}) async {
    if (state.isHydratingProfile) return;
    final activeId = accountId ?? await _loadActiveAccountId();
    if (activeId == null) return;
    if (state.hydratedAccountId == activeId) return;
    state = state.copyWith(isHydratingProfile: true);
    try {
      final info = await _driveInfoService.fetchOverview();
      final owner = info.owner;
      final name = owner?.displayName;
      final upn = owner?.userPrincipalName;
      if (name == null && upn == null) return;
      await auth_api.updateAuthAccountProfile(
        accountId: activeId,
        displayName: name,
        userPrincipalName: upn,
      );
      state = state.copyWith(hydratedAccountId: activeId);
      await ref.read(authControllerProvider.notifier).refreshAccounts();
    } catch (_) {
      // Best-effort; ignore profile hydration failures.
    } finally {
      if (ref.mounted) {
        state = state.copyWith(isHydratingProfile: false);
      }
    }
  }

  Future<String?> _loadActiveAccountId() async {
    try {
      final persisted = await auth_api.loadPersistedAuthState();
      return persisted?.accountId;
    } catch (_) {
      return null;
    }
  }

  void _invalidateDriveCaches() {
    ref.invalidate(driveHomeControllerProvider);
    ref.invalidate(driveInfoProvider);
    ref.invalidate(driveDownloadManagerProvider);
    ref.invalidate(driveUploadManagerProvider);
  }
}
