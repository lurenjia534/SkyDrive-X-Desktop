import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/src/rust/api/auth/auth.dart' as auth_api;
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;
import 'package:skydrivex/main.dart';

class DriveHomePage extends ConsumerStatefulWidget {
  const DriveHomePage({super.key});

  @override
  ConsumerState<DriveHomePage> createState() => _DriveHomePageState();
}

class _DriveHomePageState extends ConsumerState<DriveHomePage> {
  final List<drive_api.DriveItemSummary> _items = [];
  String? _nextLink;
  String? _error;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _selectedRailIndex = 0;
  bool _isRailExtended = false;

  static const double _railBreakpoint = 720;
  static const Duration _railAnimationDuration = Duration(milliseconds: 320);

  static const List<_DriveRailDestination> _railDestinations = [
    _DriveRailDestination(label: 'Inbox', icon: Icons.inbox_rounded),
    _DriveRailDestination(
      label: 'Outbox',
      icon: Icons.outbox_rounded,
      badgeCount: 3,
    ),
    _DriveRailDestination(
      label: 'Favorites',
      icon: Icons.favorite_border_rounded,
      showDot: true,
    ),
    _DriveRailDestination(label: 'Trash', icon: Icons.delete_outline_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final page = await drive_api.listDriveChildren(
        folderPath: null,
        nextLink: null,
      );
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _nextLink = page.nextLink;
      });
    } catch (err) {
      setState(() {
        _error = err.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    final link = _nextLink;
    if (link == null || _isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
    });
    try {
      final page = await drive_api.listDriveChildren(
        folderPath: null,
        nextLink: link,
      );
      setState(() {
        _items.addAll(page.items);
        _nextLink = page.nextLink;
      });
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载更多失败：$err')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _clearCredentials() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _items.clear();
      _nextLink = null;
    });
    try {
      await auth_api.clearPersistedAuthState();
      if (!mounted) return;
      ref.invalidate(authControllerProvider);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthPrototypePage()),
        (_) => false,
      );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('清除凭据失败：$err')));
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleQuickActionTap() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('快速操作暂未实现，敬请期待。')));
  }

  String _buildSubtitle(drive_api.DriveItemSummary item) {
    final pieces = <String>[];
    if (item.isFolder) {
      final count = item.childCount?.toInt();
      if (count != null) {
        pieces.add('$count 项内容');
      }
    } else {
      final size = item.size?.toInt();
      if (size != null) {
        pieces.add(_formatSize(size));
      }
      if (item.mimeType != null) {
        pieces.add(item.mimeType!);
      }
    }
    if (item.lastModified != null) {
      pieces.add('更新于 ${item.lastModified}');
    }
    if (pieces.isEmpty) return '—';
    return pieces.join(' · ');
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return unitIndex == 0
        ? '${size.toStringAsFixed(0)} ${units[unitIndex]}'
        : '${size.toStringAsFixed(1)} ${units[unitIndex]}';
  }

  Widget _buildNavigationRail(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    final borderRadius = BorderRadius.circular(30);
    final navBackground = isLight
        ? const Color(0xFFF2E7FE)
        : colorScheme.surfaceContainerHighest;
    final indicatorColor = isLight
        ? const Color(0xFFD0BCFF)
        : colorScheme.primaryContainer.withOpacity(0.9);
    final navShadowColor = Colors.black.withOpacity(isLight ? 0.08 : 0.35);
    final quickActionBackground = isLight
        ? const Color(0xFFCAB8FF)
        : colorScheme.primaryContainer.withOpacity(0.95);
    final quickActionForeground = isLight
        ? const Color(0xFF2E194F)
        : colorScheme.onPrimaryContainer;
    final quickActionShadows = [
      BoxShadow(
        color: Colors.black.withOpacity(isLight ? 0.15 : 0.45),
        blurRadius: 26,
        offset: const Offset(0, 14),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 2),
      child: AnimatedContainer(
        duration: _railAnimationDuration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: navBackground,
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: navShadowColor,
              blurRadius: 30,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: NavigationRail(
            backgroundColor: Colors.transparent,
            extended: _isRailExtended,
            minWidth: 72,
            minExtendedWidth: 236,
            groupAlignment: -0.8,
            labelType: _isRailExtended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            selectedIndex: _selectedRailIndex,
            useIndicator: true,
            indicatorColor: indicatorColor,
            indicatorShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            unselectedLabelTextStyle: TextStyle(
              color: colorScheme.onSurfaceVariant.withOpacity(0.9),
              fontSize: 12,
              height: 1.1,
            ),
            selectedLabelTextStyle: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              height: 1.1,
            ),
            onDestinationSelected: (index) {
              setState(() {
                _selectedRailIndex = index;
              });
            },
            leading: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: _isRailExtended ? '收起导航' : '展开导航',
                      icon: Icon(
                        _isRailExtended
                            ? Icons.menu_open_rounded
                            : Icons.menu_rounded,
                      ),
                      onPressed: () {
                        setState(() {
                          _isRailExtended = !_isRailExtended;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  _DriveRailQuickAction(
                    extended: _isRailExtended,
                    onPressed: _handleQuickActionTap,
                    backgroundColor: quickActionBackground,
                    foregroundColor: quickActionForeground,
                    shadows: quickActionShadows,
                  ),
                ],
              ),
            ),
            destinations: _railDestinations
                .map(
                  (destination) => NavigationRailDestination(
                    icon: _buildDestinationIcon(
                      destination,
                      colorScheme,
                      false,
                    ),
                    selectedIcon: _buildDestinationIcon(
                      destination,
                      colorScheme,
                      true,
                    ),
                    label: Text(destination.label),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildDestinationIcon(
    _DriveRailDestination destination,
    ColorScheme colorScheme,
    bool selected,
  ) {
    final iconColor = selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    final icon = Icon(destination.icon, color: iconColor);
    if (destination.badgeCount == null && !destination.showDot) {
      return icon;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -8,
          top: -4,
          child: _DriveRailBadge(
            label: destination.badgeCount?.toString(),
            color: colorScheme.error,
            isDot: destination.badgeCount == null,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget driveContent;
    if (_isLoading) {
      driveContent = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      driveContent = _DriveErrorView(message: _error!, onRetry: _loadInitial);
    } else if (_items.isEmpty) {
      driveContent = const _DriveEmptyView();
    } else {
      driveContent = RefreshIndicator(
        onRefresh: _loadInitial,
        child: ListView.separated(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: _items.length + (_nextLink != null ? 1 : 0),
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            if (index >= _items.length) {
              return _DriveLoadMoreTile(
                isLoading: _isLoadingMore,
                onLoadMore: _loadMore,
              );
            }
            final item = _items[index];
            final icon = item.isFolder
                ? Icons.folder_rounded
                : Icons.insert_drive_file_rounded;
            return ListTile(
              leading: Icon(
                icon,
                color: item.isFolder
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              title: Text(item.name),
              subtitle: Text(_buildSubtitle(item)),
              onTap: () {
                if (item.isFolder && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('暂不支持子文件夹浏览，敬请期待。')),
                  );
                }
              },
            );
          },
        ),
      );
    }

    final animatedDriveContent = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: driveContent,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('OneDrive 文件'),
        actions: [
          IconButton(
            tooltip: '注销',
            icon: const Icon(Icons.logout),
            onPressed: _clearCredentials,
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : () => _loadInitial(),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showRail = constraints.maxWidth >= _railBreakpoint;
          if (!showRail) {
            return animatedDriveContent;
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildNavigationRail(theme),
              const SizedBox(width: 32),
              Expanded(child: animatedDriveContent),
            ],
          );
        },
      ),
    );
  }
}

class _DriveEmptyView extends StatelessWidget {
  const _DriveEmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.inbox_rounded, size: 72),
          SizedBox(height: 16),
          Text('空空如也，赶紧去 OneDrive 上传点内容吧。'),
        ],
      ),
    );
  }
}

class _DriveErrorView extends StatelessWidget {
  const _DriveErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriveLoadMoreTile extends StatelessWidget {
  const _DriveLoadMoreTile({required this.isLoading, required this.onLoadMore});

  final bool isLoading;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: OutlinedButton.icon(
        onPressed: isLoading ? null : onLoadMore,
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.expand_more),
        label: Text(isLoading ? '加载中…' : '加载更多'),
      ),
    );
  }
}

class _DriveRailDestination {
  const _DriveRailDestination({
    required this.label,
    required this.icon,
    this.badgeCount,
    this.showDot = false,
  });

  final String label;
  final IconData icon;
  final int? badgeCount;
  final bool showDot;
}

class _DriveRailQuickAction extends StatelessWidget {
  const _DriveRailQuickAction({
    required this.extended,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.shadows,
  });

  final bool extended;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final List<BoxShadow> shadows;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: AnimatedContainer(
        key: ValueKey<bool>(extended),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
        width: extended ? 196 : 64,
        height: 64,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(22),
          boxShadow: shadows,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onPressed,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: extended ? 20 : 0),
              child: Row(
                mainAxisAlignment: extended
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Icon(Icons.edit_rounded, color: foregroundColor, size: 22),
                  if (extended) ...[
                    const SizedBox(width: 12),
                    Text(
                      'Label',
                      style: TextStyle(
                        color: foregroundColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DriveRailBadge extends StatelessWidget {
  const _DriveRailBadge({this.label, required this.color, required this.isDot});

  final String? label;
  final Color color;
  final bool isDot;

  @override
  Widget build(BuildContext context) {
    if (isDot) {
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label ?? '',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
