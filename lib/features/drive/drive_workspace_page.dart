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
import 'package:skydrivex/utils/toast.dart';

import 'drive_home_page.dart';

class DriveWorkspacePage extends ConsumerStatefulWidget {
  const DriveWorkspacePage({super.key, required this.authPageBuilder});

  final WidgetBuilder authPageBuilder;

  @override
  ConsumerState<DriveWorkspacePage> createState() => _DriveWorkspacePageState();
}

class _DriveWorkspacePageState extends ConsumerState<DriveWorkspacePage> {
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
      onCreateFolder: () =>
          _showPlaceholder('Create folder is not wired yet.'),
      onUploadDoc: _pickAndUploadSmallFile,
      onUploadLarge: _pickAndUploadLargeFile,
    );
  }

  void _showPlaceholder(String message) {
    if (!mounted) return;
    showToast(context, message);
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
        showToast(context, 'Failed to clear credentials: $err');
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
    final typography = context.theme.typography;
    final baseStyle = context.theme.style;
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
        style: (style) => style.copyWith(
          titleTextStyle: typography.xl2.copyWith(
            color: colors.foreground,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
          actionStyle: (_) => FHeaderActionStyle.inherit(
            colors: colors,
            style: baseStyle,
            size: 20,
          ),
        ),
        title: const Text('OneDrive Files'),
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
          final body = _DriveSectionStack(
            sections: _sections,
            activeIndex: _selectedSectionIndex,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: _DriveTopNavBar(
                  selectedIndex: _selectedSectionIndex,
                  onSelected: _handleNavigationSelection,
                  onQuickAction: _handleQuickActionTap,
                ),
              ),
              const SizedBox(height: 16),
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
        _showPlaceholder('File exceeds 250MB. Use chunked upload.');
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
      _showPlaceholder('Added to upload queue: ${file.name}');
      await ref.read(driveHomeControllerProvider.notifier).refresh();
    } catch (err) {
      _showPlaceholder('Upload failed: $err');
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
        'Added to chunked upload queue: ${file.name} '
        '(${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB)',
      );
      await ref.read(driveHomeControllerProvider.notifier).refresh();
    } catch (err) {
      _showPlaceholder('Upload failed: $err');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }
}

class _DriveTopNavBar extends StatelessWidget {
  const _DriveTopNavBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.onQuickAction,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onQuickAction;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    final destinations = const [
      _NavDestination(index: 0, label: 'Files', icon: FIcons.folder),
      _NavDestination(index: 1, label: 'Downloads', icon: FIcons.cloudDownload),
      _NavDestination(index: 2, label: 'Uploads', icon: FIcons.cloudUpload),
      _NavDestination(index: 3, label: 'Settings', icon: FIcons.settings),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: colors.barrier.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: destinations
                    .map(
                      (destination) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _NavButton(
                          destination: destination,
                          selected: selectedIndex == destination.index,
                          onTap: () => onSelected(destination.index),
                          colors: colors,
                          typography: typography,
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FButton(
            onPress: onQuickAction,
            style: FButtonStyle.primary(
              (style) => style.copyWith(
                decoration: FWidgetStateMap.all(
                  BoxDecoration(
                    color: colors.foreground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                contentStyle: (contentStyle) => contentStyle.copyWith(
                  textStyle: FWidgetStateMap.all(
                    typography.sm.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.background,
                    ),
                  ),
                  iconStyle: FWidgetStateMap.all(
                    IconThemeData(
                      color: colors.background,
                      size: 18,
                    ),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  spacing: 8,
                ),
              ),
            ),
            prefix: const Icon(FIcons.plus),
            child: const Text('New'),
          ),
        ],
      ),
    );
  }
}

class _NavDestination {
  const _NavDestination({
    required this.index,
    required this.label,
    required this.icon,
  });

  final int index;
  final String label;
  final IconData icon;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.colors,
    required this.typography,
  });

  final _NavDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final FColors colors;
  final FTypography typography;

  @override
  Widget build(BuildContext context) {
    final selectedStyle = FButtonStyle.primary(
      (style) => style.copyWith(
        decoration: FWidgetStateMap.all(
          BoxDecoration(
            color: colors.foreground,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        contentStyle: (contentStyle) => contentStyle.copyWith(
          textStyle: FWidgetStateMap.all(
            typography.sm.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.background,
            ),
          ),
          iconStyle: FWidgetStateMap.all(
            IconThemeData(color: colors.background, size: 18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          spacing: 8,
        ),
      ),
    );

    final idleStyle = FButtonStyle.outline(
      (style) => style.copyWith(
        decoration: FWidgetStateMap.all(
          BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colors.border.withValues(alpha: 0.6)),
          ),
        ),
        contentStyle: (contentStyle) => contentStyle.copyWith(
          textStyle: FWidgetStateMap.all(
            typography.sm.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.foreground,
            ),
          ),
          iconStyle: FWidgetStateMap.all(
            IconThemeData(color: colors.mutedForeground, size: 18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          spacing: 8,
        ),
      ),
    );

    return FButton(
      onPress: onTap,
      style: selected ? selectedStyle : idleStyle,
      prefix: Icon(destination.icon),
      child: Text(destination.label),
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
