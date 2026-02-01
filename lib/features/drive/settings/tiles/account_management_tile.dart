import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/auth/auth_controller.dart';
import 'package:skydrivex/features/drive/providers/drive_download_manager.dart';
import 'package:skydrivex/features/drive/providers/drive_home_controller.dart';
import 'package:skydrivex/features/drive/providers/drive_info_provider.dart';
import 'package:skydrivex/features/drive/providers/drive_upload_manager.dart';
import 'package:skydrivex/features/drive/services/drive_info_service.dart';
import 'package:skydrivex/features/drive/settings/widgets/settings_card.dart';
import 'package:skydrivex/src/rust/api/auth/auth.dart' as auth_api;
import 'package:skydrivex/utils/toast.dart';

enum _AccountAction { activate, remove }

class AccountManagementTile extends ConsumerStatefulWidget {
  const AccountManagementTile();

  @override
  ConsumerState<AccountManagementTile> createState() =>
      _AccountManagementTileState();
}

class _AccountManagementTileState extends ConsumerState<AccountManagementTile> {
  String? _busyAccountId;
  _AccountAction? _busyAction;
  late final TextEditingController _addAccountController;
  final DriveInfoService _driveInfoService = const DriveInfoService();
  String? _hydratedAccountId;
  bool _isHydratingProfile = false;

  @override
  void initState() {
    super.initState();
    _addAccountController = TextEditingController();
  }

  @override
  void dispose() {
    _addAccountController.dispose();
    super.dispose();
  }

  Future<void> _promptAddAccount() async {
    _addAccountController.text = '';
    final result = await showFDialog<String>(
      context: context,
      barrierLabel: 'Add account',
      builder: (dialogContext, style, animation) {
        final theme = dialogContext.theme;
        final colors = theme.colors;
        final typography = theme.typography;
        return FDialog(
          animation: animation,
          title: Text(
            'Add account',
            style: typography.lg.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.foreground,
            ),
          ),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Use the same Client ID you registered in Azure.',
                style: typography.sm.copyWith(
                  color: colors.mutedForeground,
                ),
              ),
              const SizedBox(height: 12),
              FTextField(
                control: FTextFieldControl.managed(
                  controller: _addAccountController,
                ),
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmit: (_) =>
                    Navigator.of(dialogContext).pop(_addAccountController.text),
              ),
            ],
          ),
          direction: Axis.horizontal,
          actions: [
            FButton(
              onPress: () => Navigator.of(dialogContext).pop(),
              style: FButtonStyle.outline(),
              child: const Text('Cancel'),
            ),
            FButton(
              onPress: () =>
                  Navigator.of(dialogContext).pop(_addAccountController.text),
              style: FButtonStyle.primary(),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    final trimmed = result.trim();
    if (trimmed.isEmpty) {
      showToast(context, 'Client ID is required.');
      return;
    }
    final ok = await ref
        .read(authControllerProvider.notifier)
        .authenticateWithClientId(trimmed);
    if (!mounted) return;
    if (!ok) {
      final message =
          ref.read(authControllerProvider).error ?? 'Failed to add account.';
      showToast(context, message);
      return;
    }
    await _hydrateActiveAccountProfile();
    _invalidateDriveCaches();
  }

  Future<void> _activateAccount(AuthAccount account) async {
    if (_busyAccountId != null) return;
    setState(() {
      _busyAccountId = account.accountId;
      _busyAction = _AccountAction.activate;
    });
    final ok = await ref
        .read(authControllerProvider.notifier)
        .setActiveAccount(account.accountId);
    if (!mounted) return;
    setState(() {
      _busyAccountId = null;
      _busyAction = null;
    });
    if (!ok) {
      final message =
          ref.read(authControllerProvider).error ?? 'Failed to switch account.';
      showToast(context, message);
      return;
    }
    await _hydrateActiveAccountProfile(accountId: account.accountId);
    _invalidateDriveCaches();
  }

  Future<void> _removeAccount(AuthAccount account) async {
    if (_busyAccountId != null) return;
    final confirmed = await showFDialog<bool>(
      context: context,
      barrierLabel: 'Remove account',
      builder: (dialogContext, style, animation) {
        final theme = dialogContext.theme;
        final colors = theme.colors;
        final typography = theme.typography;
        final displayName = _accountTitle(account);
        return FDialog(
          animation: animation,
          title: Text(
            'Remove account',
            style: typography.lg.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.foreground,
            ),
          ),
          body: Text(
            'Sign out of $displayName on this device. You can add it back later.',
            style: typography.sm.copyWith(
              color: colors.mutedForeground,
            ),
          ),
          direction: Axis.horizontal,
          actions: [
            FButton(
              onPress: () => Navigator.of(dialogContext).pop(false),
              style: FButtonStyle.outline(),
              child: const Text('Cancel'),
            ),
            FButton(
              onPress: () => Navigator.of(dialogContext).pop(true),
              style: FButtonStyle.primary(),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busyAccountId = account.accountId;
      _busyAction = _AccountAction.remove;
    });
    final ok = await ref
        .read(authControllerProvider.notifier)
        .removeAccount(account.accountId, wasActive: account.isActive);
    if (!mounted) return;
    setState(() {
      _busyAccountId = null;
      _busyAction = null;
    });
    if (!ok) {
      final message =
          ref.read(authControllerProvider).error ?? 'Failed to remove account.';
      showToast(context, message);
      return;
    }
    final remaining = ref.read(authControllerProvider).accounts;
    if (remaining.isEmpty) {
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (_) => false);
      return;
    }
    if (account.isActive) {
      _invalidateDriveCaches();
    }
  }

  Future<void> _hydrateActiveAccountProfile({String? accountId}) async {
    if (_isHydratingProfile) return;
    final activeId = accountId ?? await _loadActiveAccountId();
    if (activeId == null) return;
    if (_hydratedAccountId == activeId) return;
    _isHydratingProfile = true;
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
      _hydratedAccountId = activeId;
      await ref.read(authControllerProvider.notifier).refreshAccounts();
    } catch (_) {
      // Best-effort; ignore profile hydration failures.
    } finally {
      if (mounted) {
        setState(() {
          _isHydratingProfile = false;
        });
      } else {
        _isHydratingProfile = false;
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

  String _accountTitle(AuthAccount account) {
    final accountId = account.accountId;
    final shortId = accountId.length > 6 ? accountId.substring(0, 6) : accountId;
    return account.displayName ??
        account.userPrincipalName ??
        'Account $shortId';
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    final accounts = authState.accounts;
    final isBusy =
        authState.isAuthenticating || authState.isLoadingAccounts;
    final activeAccount = accounts
        .cast<AuthAccount?>()
        .firstWhere((account) => account?.isActive ?? false, orElse: () => null);
    if (activeAccount != null &&
        (activeAccount!.displayName == null ||
            activeAccount.userPrincipalName == null) &&
        !_isHydratingProfile &&
        !isBusy) {
      Future.microtask(() {
        if (mounted) {
          _hydrateActiveAccountProfile(accountId: activeAccount.accountId);
        }
      });
    }

    Widget body;
    if (authState.isLoadingAccounts) {
      body = Center(
        child: FCircularProgress.loader(
          style: (style) => style.copyWith(
            iconStyle: IconThemeData(color: colors.primary, size: 20),
          ),
        ),
      );
    } else if (accounts.isEmpty) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No accounts linked yet.',
            style: typography.base.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Add a Microsoft account to start syncing OneDrive.',
            style: typography.sm.copyWith(color: colors.mutedForeground),
          ),
        ],
      );
    } else {
      final items = accounts.map((account) {
      final isActive = account.isActive;
      final isRowBusy = _busyAccountId == account.accountId;
      final isRemoving = isRowBusy && _busyAction == _AccountAction.remove;
      final isSwitching = isRowBusy && _busyAction == _AccountAction.activate;
      final subtitle = account.userPrincipalName ??
          'Client ID: ${account.clientId}';
        return FItem(
          enabled: !isBusy && !isRowBusy,
          onPress: isActive || isBusy || isRowBusy
              ? null
              : () => _activateAccount(account),
          prefix: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.secondary.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              FIcons.user,
              size: 18,
              color: colors.foreground,
            ),
          ),
          title: Text(_accountTitle(account)),
          subtitle: Text(subtitle),
          suffix: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isActive)
                _ActiveBadge(colors: colors, typography: typography)
              else
                FButton(
                  onPress: isBusy || isRowBusy
                      ? null
                      : () => _activateAccount(account),
                  style: FButtonStyle.outline(),
                  child: Text(
                    isSwitching ? 'Switching…' : 'Activate',
                    style: typography.xs.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(width: 8),
              FButton.icon(
                onPress:
                    isBusy || isRowBusy ? null : () => _removeAccount(account),
                style: FButtonStyle.ghost(),
                child: isRemoving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: FCircularProgress.loader(
                          style: (style) => style.copyWith(
                            iconStyle: IconThemeData(
                              color: colors.mutedForeground,
                              size: 16,
                            ),
                          ),
                        ),
                      )
                    : const Icon(FIcons.trash2, size: 16),
              ),
            ],
          ),
        );
      }).toList();

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FItemGroup(
            divider: FItemDivider.full,
            children: items,
          ),
          if (authState.error != null && !authState.isAuthenticating) ...[
            const SizedBox(height: 12),
            Text(
              authState.error!,
              style: typography.sm.copyWith(color: colors.error),
            ),
          ],
        ],
      );
    }

    final addLabel = authState.isAuthenticating ? 'Connecting…' : 'Add account';
    final addStyle =
        accounts.isEmpty ? FButtonStyle.primary() : FButtonStyle.outline();

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Accounts',
                    style: typography.base.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.foreground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Switch, add, or remove linked OneDrive accounts.',
                    style: typography.sm.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ),
              FButton(
                onPress: isBusy ? null : _promptAddAccount,
                style: addStyle,
                prefix: const Icon(FIcons.plus, size: 16),
                child: Text(
                  addLabel,
                  style: typography.sm.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          body,
        ],
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge({
    required this.colors,
    required this.typography,
  });

  final FColors colors;
  final FTypography typography;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Active',
        style: typography.xs.copyWith(
          color: colors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
