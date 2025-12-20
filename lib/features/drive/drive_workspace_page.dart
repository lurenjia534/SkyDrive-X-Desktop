import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/auth/auth_controller.dart';
import 'package:skydrivex/features/drive/downloads/drive_downloads_page.dart';
import 'package:skydrivex/features/drive/providers/drive_home_controller.dart';
import 'package:skydrivex/features/drive/providers/drive_upload_manager.dart';
import 'package:skydrivex/features/drive/settings/drive_settings_page.dart';
import 'package:skydrivex/features/drive/widgets/quick_action_side_sheet.dart';
import 'package:skydrivex/features/drive/uploads/drive_uploads_page.dart';
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
  static const int _simpleUploadMaxBytes = 250 * 1024 * 1024;

  int _selectedSectionIndex = 0;
  bool _isClearingCredentials = false;
  bool _isUploading = false;
  late final List<Widget> _sections;

  @override
  void initState() {
    super.initState();
    _sections = [
      const DriveHomePage(),
      const DriveDownloadsPage(),
      const DriveUploadsPage(),
      const DriveSettingsPage(),
    ];
  }

  void _handleQuickActionTap() {
    if (!mounted) return;
    showQuickActionSideSheet(
      context,
      onUploadPhoto: _pickAndUploadSmallFile,
      onCreateFolder: () => _showPlaceholder('新建文件夹入口待接入前端逻辑'),
      onUploadDoc: _pickAndUploadSmallFile,
      onUploadLarge: _pickAndUploadLargeFile,
    );
  }

  void _showPlaceholder(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
    final colors = context.theme.colors;
    final logoutIcon = _isClearingCredentials
        ? SizedBox(
            width: 18,
            height: 18,
            child: FCircularProgress.loader(
              style: (style) => style.copyWith(
                iconStyle: IconThemeData(
                  color: colors.mutedForeground,
                  size: 18,
                ),
              ),
            ),
          )
        : const Icon(FIcons.logOut);

    return FScaffold(
      childPad: false,
      header: FHeader(
        title: const Text('OneDrive 文件'),
        suffixes: [
          FHeaderAction(
            icon: const Icon(FIcons.refreshCcw),
            onPress: _selectedSectionIndex == 0
                ? () => ref
                      .read(driveHomeControllerProvider.notifier)
                      .refresh(showSkeleton: true)
                : null,
          ),
          FHeaderAction(
            icon: logoutIcon,
            onPress: _isClearingCredentials ? null : _clearCredentials,
          ),
        ],
      ),
      child: LayoutBuilder(
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

  Future<void> _pickAndUploadSmallFile() async {
    if (_isUploading) return;
    setState(() {
      _isUploading = true;
    });
    try {
      final typeGroup = const XTypeGroup(
        label: 'images',
        extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > _simpleUploadMaxBytes) {
        _showPlaceholder('文件超过 250MB，请使用分片上传');
        return;
      }
      final breadcrumbs =
          ref.read(driveHomeControllerProvider).asData?.value.breadcrumbs ?? [];
      final parentId = breadcrumbs.isNotEmpty ? breadcrumbs.last.id : null;
      final manager = ref.read(driveUploadManagerProvider.notifier);
      await manager.enqueue(
        parentId: parentId,
        fileName: file.name,
        localPath: file.path,
        content: bytes,
        overwrite: false,
      );
      _showPlaceholder('已加入上传队列：${file.name}');
      await ref.read(driveHomeControllerProvider.notifier).refresh();
    } catch (err) {
      _showPlaceholder('上传失败：$err');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  /// 选择本地任意文件，走分片上传（避免一次性读入内存）。
  Future<void> _pickAndUploadLargeFile() async {
    if (_isUploading) return;
    setState(() {
      _isUploading = true;
    });
    try {
      final file = await openFile();
      if (file == null) return;
      final fileSize = await file.length();
      final breadcrumbs =
          ref.read(driveHomeControllerProvider).asData?.value.breadcrumbs ?? [];
      final parentId = breadcrumbs.isNotEmpty ? breadcrumbs.last.id : null;
      final manager = ref.read(driveUploadManagerProvider.notifier);
      await manager.enqueueLarge(
        parentId: parentId,
        fileName: file.name,
        localPath: file.path,
        overwrite: false,
      );
      _showPlaceholder(
        '已加入分片上传队列：${file.name}（${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB）',
      );
      await ref.read(driveHomeControllerProvider.notifier).refresh();
    } catch (err) {
      _showPlaceholder('上传失败：$err');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
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
            visible: i == activeIndex,
            child: sections[i],
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
