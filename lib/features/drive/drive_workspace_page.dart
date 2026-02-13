import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/auth/auth_controller.dart';
import 'package:skydrivex/features/drive/downloads/drive_downloads_page.dart';
import 'package:skydrivex/features/drive/gallery/drive_gallery_page.dart';
import 'package:skydrivex/features/drive/providers/drive_home_controller.dart';
import 'package:skydrivex/features/drive/providers/drive_search_query_provider.dart';
import 'package:skydrivex/features/drive/providers/drive_upload_manager.dart';
import 'package:skydrivex/features/drive/settings/drive_settings_page.dart';
import 'package:skydrivex/features/drive/widgets/quick_action_side_sheet.dart';
import 'package:skydrivex/features/drive/uploads/drive_uploads_page.dart';
import 'package:skydrivex/src/rust/api/auth/auth.dart' as auth_api;
import 'package:skydrivex/theme/app_theme_provider.dart';
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
  static const Duration _searchDebounceDuration = Duration(milliseconds: 320);

  int _selectedSectionIndex = 0;
  bool _isClearingCredentials = false;
  bool _isUploading = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  late final List<Widget> _sections;

  @override
  void initState() {
    super.initState();
    _sections = [
      const DriveHomePage(),
      const DriveDownloadsPage(),
      const DriveUploadsPage(),
      const DriveGalleryPage(),
      const DriveSettingsPage(),
    ];
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _handleQuickActionTap() {
    if (!mounted) return;
    showQuickActionSideSheet(
      context,
      onUploadPhoto: _pickAndUploadSmallFile,
      onCreateFolder: () => _showPlaceholder('Create folder is not wired yet.'),
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

  Future<void> _toggleThemeMode() async {
    final brightness = Theme.of(context).brightness;
    final nextMode = brightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    try {
      await ref.read(appThemeProvider.notifier).setManualMode(nextMode);
    } catch (err) {
      if (!mounted) return;
      showToast(context, 'Failed to update theme: $err');
    }
  }

  void _handleSearchChanged(TextEditingValue value) {
    final query = value.text.trim();
    ref.read(driveSearchQueryProvider.notifier).setQuery(query);

    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDuration, () async {
      if (!mounted || _selectedSectionIndex != 0) return;
      if (ref.read(driveSearchQueryProvider) != query) return;
      await ref.read(driveHomeControllerProvider.notifier).applySearchQuery(
        query,
      );
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
    final searchQuery = ref.watch(driveSearchQueryProvider);
    if (_searchController.text != searchQuery) {
      _searchController.value = TextEditingValue(
        text: searchQuery,
        selection: TextSelection.collapsed(offset: searchQuery.length),
      );
    }
    final accountIcon = _isClearingCredentials
        ? SizedBox(
            width: 14,
            height: 14,
            child: FCircularProgress.loader(
              style: (style) => style.copyWith(
                iconStyle: IconThemeData(
                  color: colors.mutedForeground,
                  size: 14,
                ),
              ),
            ),
          )
        : Icon(FIcons.userRound, size: 14, color: colors.mutedForeground);

    return FScaffold(
      childPad: false,
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
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: _DriveWorkspaceHeader(
                  selectedSectionIndex: _selectedSectionIndex,
                  searchEnabled: _selectedSectionIndex == 0,
                  searchController: _searchController,
                  onSearchChanged: _handleSearchChanged,
                  onRefresh: _selectedSectionIndex == 0
                      ? () => ref
                            .read(driveHomeControllerProvider.notifier)
                            .refresh(showSkeleton: true)
                      : null,
                  onQuickAction: _handleQuickActionTap,
                  onOpenSettings: () => _handleNavigationSelection(4),
                  onToggleTheme: () => unawaited(_toggleThemeMode()),
                  isDarkMode: Theme.of(context).brightness == Brightness.dark,
                  onLogout: _isClearingCredentials ? null : _clearCredentials,
                  accountIcon: accountIcon,
                  typography: typography,
                  colors: colors,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                child: _DriveTopNavBar(
                  selectedIndex: _selectedSectionIndex,
                  onSelected: _handleNavigationSelection,
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

class _DriveWorkspaceHeader extends StatelessWidget {
  const _DriveWorkspaceHeader({
    required this.selectedSectionIndex,
    required this.searchEnabled,
    required this.searchController,
    required this.onSearchChanged,
    required this.onRefresh,
    required this.onQuickAction,
    required this.onOpenSettings,
    required this.onToggleTheme,
    required this.isDarkMode,
    required this.onLogout,
    required this.accountIcon,
    required this.typography,
    required this.colors,
  });

  final int selectedSectionIndex;
  final bool searchEnabled;
  final TextEditingController searchController;
  final ValueChanged<TextEditingValue> onSearchChanged;
  final VoidCallback? onRefresh;
  final VoidCallback onQuickAction;
  final VoidCallback onOpenSettings;
  final VoidCallback onToggleTheme;
  final bool isDarkMode;
  final VoidCallback? onLogout;
  final Widget accountIcon;
  final FTypography typography;
  final FColors colors;

  @override
  Widget build(BuildContext context) {
    final iconButtonStyle = FButtonStyle.outline(
      (style) => style.copyWith(
        contentStyle: (contentStyle) => contentStyle.copyWith(
          padding: const EdgeInsets.all(9),
          iconStyle: FWidgetStateMap.all(
            IconThemeData(color: colors.mutedForeground, size: 16),
          ),
        ),
      ),
    );

    final newButtonStyle = FButtonStyle.primary(
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
              fontWeight: FontWeight.w700,
              color: colors.background,
            ),
          ),
          iconStyle: FWidgetStateMap.all(
            IconThemeData(color: colors.background, size: 16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          spacing: 8,
        ),
      ),
    );

    Widget searchField() => FTextField(
      control: FTextFieldControl.managed(
        controller: searchController,
        onChange: onSearchChanged,
      ),
      enabled: searchEnabled,
      hint: 'Search in current folder...',
      textInputAction: TextInputAction.search,
      clearable: (value) => searchEnabled && value.text.isNotEmpty,
      prefixBuilder: (context, style, states) => const Padding(
        padding: EdgeInsets.only(left: 14, right: 10),
        child: Icon(FIcons.search, size: 16),
      ),
    );

    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(FIcons.cloud, size: 18, color: colors.primary),
        const SizedBox(width: 8),
        Text(
          'OneDrive Files',
          style: typography.lg.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.foreground,
          ),
        ),
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FButton.icon(
          onPress: onRefresh,
          style: iconButtonStyle,
          child: const Icon(FIcons.refreshCcw),
        ),
        const SizedBox(width: 8),
        FButton(
          onPress: onQuickAction,
          style: newButtonStyle,
          prefix: const Icon(FIcons.plus),
          child: const Text('New'),
        ),
        const SizedBox(width: 8),
        FButton.icon(
          onPress: onOpenSettings,
          style: selectedSectionIndex == 4
              ? FButtonStyle.primary()
              : iconButtonStyle,
          child: const Icon(FIcons.settings),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: isDarkMode ? 'Switch to light mode' : 'Switch to dark mode',
          child: FButton.icon(
            onPress: onToggleTheme,
            style: iconButtonStyle,
            child: Icon(
              isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
          ),
        ),
        const SizedBox(width: 8),
        FButton.icon(
          onPress: onLogout,
          style: iconButtonStyle,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: colors.secondary.withValues(alpha: 0.75),
              shape: BoxShape.circle,
            ),
            child: Center(child: accountIcon),
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border.withValues(alpha: 0.55)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1080;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 12),
                    actions,
                  ],
                ),
                const SizedBox(height: 10),
                searchField(),
              ],
            );
          }
          return Row(
            children: [
              title,
              const SizedBox(width: 16),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: searchField(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _DriveTopNavBar extends StatelessWidget {
  const _DriveTopNavBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    final destinations = const [
      _NavDestination(index: 0, label: 'Files', icon: FIcons.folder),
      _NavDestination(index: 1, label: 'Downloads', icon: FIcons.cloudDownload),
      _NavDestination(index: 2, label: 'Uploads', icon: FIcons.cloudUpload),
      _NavDestination(
        index: 3,
        label: 'Gallery',
        icon: FIcons.images,
      ),
      _NavDestination(index: 4, label: 'Settings', icon: FIcons.settings),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ...destinations.map(
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
