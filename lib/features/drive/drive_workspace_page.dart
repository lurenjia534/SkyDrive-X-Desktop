import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/auth/auth_controller.dart';
import 'package:skydrivex/features/drive/downloads/drive_downloads_page.dart';
import 'package:skydrivex/features/drive/providers/drive_home_controller.dart';
import 'package:skydrivex/features/drive/settings/drive_settings_page.dart';
import 'package:skydrivex/features/drive/widgets/quick_action_side_sheet.dart';
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

  int _selectedSectionIndex = 0;
  bool _isClearingCredentials = false;
  late final List<Widget> _sections;

  @override
  void initState() {
    super.initState();
    _sections = [
      const DriveHomePage(),
      const DriveDownloadsPage(),
      const _DriveSectionPlaceholder(
        icon: Icons.favorite_border_rounded,
        title: 'Favorites',
        message: '你保存的收藏内容会在这里显示。',
      ),
      const DriveSettingsPage(),
    ];
  }

  void _handleQuickActionTap() {
    if (!mounted) return;
    showQuickActionSideSheet(
      context,
      onUploadPhoto: () => _showPlaceholder('上传入口待接入前端逻辑'),
      onCreateFolder: () => _showPlaceholder('新建文件夹入口待接入前端逻辑'),
      onUploadDoc: () => _showPlaceholder('上传文档入口待接入前端逻辑'),
    );
  }

  void _showPlaceholder(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OneDrive 文件'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _selectedSectionIndex == 0
                ? () => ref
                      .read(driveHomeControllerProvider.notifier)
                      .refresh(showSkeleton: true)
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
          final body = _DriveSectionStack(
            sections: _sections,
            activeIndex: _selectedSectionIndex,
          );
          if (!showRail) {
            return body;
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
              Expanded(child: body),
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

class _DriveSectionStack extends StatelessWidget {
  const _DriveSectionStack({required this.sections, required this.activeIndex});

  final List<Widget> sections;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) return const SizedBox.shrink();
    return Stack(
      children: [
        for (var i = 0; i < sections.length; i++)
          _DriveSectionPanel(
            key: ValueKey('drive-section-$i'),
            child: sections[i],
            visible: i == activeIndex,
          ),
      ],
    );
  }
}

class _DriveSectionPanel extends StatelessWidget {
  const _DriveSectionPanel({
    super.key,
    required this.child,
    required this.visible,
  });

  final Widget child;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutQuad,
          child: child,
        ),
      ),
    );
  }
}
