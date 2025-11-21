import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/features/auth/auth_controller.dart';
import 'package:skydrivex/features/drive/downloads/drive_downloads_page.dart';
import 'package:skydrivex/features/drive/providers/drive_home_controller.dart';
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
    _showQuickActionSideSheet(context);
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

/// 右侧弹出的 Side Sheet，提供快捷操作入口。
Future<void> _showQuickActionSideSheet(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;
  final maxWidth = 420.0;

  return showGeneralDialog(
    context: context,
    barrierLabel: '关闭快捷操作',
    barrierColor: Colors.black.withOpacity(0.35),
    barrierDismissible: true,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, animation, secondary) {
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Container(
                  width: maxWidth,
                  height: constraints.maxHeight,
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      bottomLeft: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withOpacity(0.18),
                        blurRadius: 30,
                        offset: const Offset(-12, 12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight - 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Quick Actions',
                                  style: textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '关闭',
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () => Navigator.of(context).maybePop(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '快速上传照片或新建项目，稍后可在前端接入实际逻辑。',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _QuickActionButton(
                              icon: Icons.image_outlined,
                              label: '上传照片/小文件',
                              description: '选择本地图片并上传到当前目录',
                              onPressed: () {
                                Navigator.of(context).maybePop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('上传入口待接入前端逻辑')),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            _QuickActionButton(
                              icon: Icons.create_new_folder_outlined,
                              label: '新建文件夹',
                              description: '在当前视图下创建一个子文件夹',
                              onPressed: () {
                                Navigator.of(context).maybePop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('新建文件夹入口待接入前端逻辑')),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            _QuickActionButton(
                              icon: Icons.insert_drive_file_outlined,
                              label: '上传文档',
                              description: '适合小体积的文档即时上传',
                              onPressed: () {
                                Navigator.of(context).maybePop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('上传文档入口待接入前端逻辑')),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '后续可将这些入口与实际上传/创建逻辑绑定。',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(curved),
        child: FadeTransition(
          opacity: Tween<double>(begin: 0, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
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
