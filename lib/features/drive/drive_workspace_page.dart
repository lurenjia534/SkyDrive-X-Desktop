import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/auth/auth_controller.dart';
import 'package:skydrivex/features/drive/settings/drive_settings_page.dart';
import 'package:skydrivex/src/rust/api/auth/auth.dart' as auth_api;

import 'drive_home_page.dart';
import 'drive_navigation_rail.dart';

class DriveWorkspacePage extends ConsumerStatefulWidget {
  const DriveWorkspacePage({super.key, required this.authPageBuilder});

  final WidgetBuilder authPageBuilder;

  @override
  ConsumerState<DriveWorkspacePage> createState() => _DriveWorkspacePageState();
}

class _DriveWorkspacePageState extends ConsumerState<DriveWorkspacePage> {
  static const double _railBreakpoint = 720;

  final DriveHomePageController _filesController = DriveHomePageController();
  int _selectedSectionIndex = 0;
  bool _isClearingCredentials = false;

  void _handleQuickActionTap() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('快速操作暂未实现，敬请期待。')));
  }

  void _handleNavigationSelection(int index) {
    if (_selectedSectionIndex == index) return;
    setState(() {
      _selectedSectionIndex = index;
    });
  }

  Future<void> _clearCredentials() async {
    if (_isClearingCredentials) return;
    setState(() {
      _isClearingCredentials = true;
    });
    try {
      await auth_api.clearPersistedAuthState();
      if (!mounted) return;
      ref.invalidate(authControllerProvider);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: widget.authPageBuilder),
        (_) => false,
      );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('清除凭据失败：$err')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isClearingCredentials = false;
        });
      }
    }
  }

  Widget _buildSectionContent() {
    switch (_selectedSectionIndex) {
      case 0:
        return DriveHomePage(controller: _filesController);
      case 1:
        return const _DriveSectionPlaceholder(
          icon: Icons.outbox_rounded,
          title: 'Outbox',
          message: 'Outbox 功能正在开发中，敬请期待。',
        );
      case 2:
        return const _DriveSectionPlaceholder(
          icon: Icons.favorite_border_rounded,
          title: 'Favorites',
          message: '你保存的收藏内容会在这里显示。',
        );
      case 3:
        return const DriveSettingsPage();
      default:
        return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sectionContent = _buildSectionContent();
    return Scaffold(
      appBar: AppBar(
        title: const Text('OneDrive 文件'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _selectedSectionIndex == 0
                ? () => _filesController.refresh()
                : null,
          ),
          IconButton(
            tooltip: '注销',
            icon: _isClearingCredentials
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
            onPressed: _isClearingCredentials ? null : _clearCredentials,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showRail = constraints.maxWidth >= _railBreakpoint;
          if (!showRail) {
            return sectionContent;
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DriveNavigationRail(
                selectedIndex: _selectedSectionIndex,
                onQuickAction: _handleQuickActionTap,
                onDestinationSelected: _handleNavigationSelection,
              ),
              const SizedBox(width: 32),
              Expanded(child: sectionContent),
            ],
          );
        },
      ),
    );
  }
}

class _DriveSectionPlaceholder extends StatelessWidget {
  const _DriveSectionPlaceholder({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
