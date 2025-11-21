import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class DriveNavigationRail extends StatefulWidget {
  const DriveNavigationRail({
    super.key,
    this.selectedIndex = 0,
    this.initialExtended = false,
    this.onQuickAction,
    this.onDestinationSelected,
    this.onExtendedChanged,
  });

  final int selectedIndex;
  final bool initialExtended;
  final VoidCallback? onQuickAction;
  final ValueChanged<int>? onDestinationSelected;
  final ValueChanged<bool>? onExtendedChanged;

  @override
  State<DriveNavigationRail> createState() => _DriveNavigationRailState();
}

class _DriveNavigationRailState extends State<DriveNavigationRail> {
  static const _animationDuration = Duration(milliseconds: 320);
  static const List<_DriveRailDestination> _destinations = [
    _DriveRailDestination(label: 'Files', icon: Icons.folder_rounded),
    _DriveRailDestination(
      label: 'Download',
      icon: Icons.cloud_download_rounded,
    ),
    _DriveRailDestination(label: 'Upload', icon: Icons.cloud_upload_rounded),
    _DriveRailDestination(label: 'Settings', icon: Icons.settings_rounded),
  ];

  late bool _isExtended = widget.initialExtended;
  late int _selectedIndex = widget.selectedIndex;

  @override
  void didUpdateWidget(covariant DriveNavigationRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _selectedIndex = widget.selectedIndex;
    }
  }

  void _toggleExtended() {
    setState(() {
      _isExtended = !_isExtended;
    });
    widget.onExtendedChanged?.call(_isExtended);
  }

  void _handleDestinationTap(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      _selectedIndex = index;
    });
    widget.onDestinationSelected?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderRadius = BorderRadius.circular(30);
    final navBackground = _tonalSurface(colorScheme);
    final indicatorColor = colorScheme.primaryContainer.withOpacity(0.95);
    final navShadowColor = colorScheme.shadow.withOpacity(
      theme.brightness == Brightness.light ? 0.12 : 0.4,
    );
    final quickActionBackground = colorScheme.primaryContainer.withOpacity(
      theme.colorSchemeBrightnessBlend(),
    );
    final quickActionForeground = colorScheme.onPrimaryContainer;
    final quickActionShadows = [
      BoxShadow(
        color: colorScheme.shadow.withOpacity(
          theme.brightness == Brightness.light ? 0.18 : 0.5,
        ),
        blurRadius: 26,
        offset: const Offset(0, 14),
      ),
    ];

    final railContainer = AnimatedContainer(
      duration: _animationDuration,
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
          extended: _isExtended,
          minWidth: 72,
          minExtendedWidth: 236,
          groupAlignment: -0.8,
          labelType: _isExtended
              ? NavigationRailLabelType.none
              : NavigationRailLabelType.all,
          selectedIndex: _selectedIndex,
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
          onDestinationSelected: _handleDestinationTap,
          leading: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: _isExtended ? '收起导航' : '展开导航',
                    icon: Icon(
                      _isExtended
                          ? Icons.menu_open_rounded
                          : Icons.menu_rounded,
                    ),
                    onPressed: _toggleExtended,
                  ),
                ),
                const SizedBox(height: 20),
                _DriveRailQuickAction(
                  extended: _isExtended,
                  onPressed: widget.onQuickAction,
                  backgroundColor: quickActionBackground,
                  foregroundColor: quickActionForeground,
                  shadows: quickActionShadows,
                ),
              ],
            ),
          ),
          destinations: _destinations
              .map(
                (destination) => NavigationRailDestination(
                  icon: _buildDestinationIcon(destination, colorScheme, false),
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
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 2),
      child: railContainer
          .animate(key: ValueKey('rail-$_isExtended'))
          .fade(begin: 0.7, end: 1, duration: 280.ms, curve: Curves.easeOutQuad)
          .slideX(
            begin: _isExtended ? -0.05 : 0.05,
            end: 0,
            duration: 360.ms,
            curve: Curves.easeOutQuint,
          )
          .scaleXY(
            begin: _isExtended ? 0.96 : 1.02,
            end: 1,
            duration: 420.ms,
            curve: Curves.easeOutBack,
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
    Widget iconWidget = Icon(destination.icon, color: iconColor);
    if (destination.badgeCount != null || destination.showDot) {
      iconWidget = Stack(
        clipBehavior: Clip.none,
        children: [
          iconWidget,
          Positioned(
            right: -8,
            top: -4,
            child: _DriveRailBadge(
              key: ValueKey(destination.badgeCount ?? destination.showDot),
              label: destination.badgeCount?.toString(),
              color: colorScheme.error,
              isDot: destination.badgeCount == null,
            ),
          ),
        ],
      );
    }
    return iconWidget
        .animate(target: selected ? 1 : 0)
        .scaleXY(
          begin: 0.92,
          end: 1,
          duration: 280.ms,
          curve: Curves.easeOutQuad,
        )
        .fade(begin: 0.8, end: 1, duration: 240.ms, curve: Curves.easeOut)
        .tint(
          color: colorScheme.primary.withOpacity(selected ? 0.18 : 0.0),
          duration: 260.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

Color _tonalSurface(ColorScheme colorScheme) {
  final surface = colorScheme.surface;
  final tint = colorScheme.primary.withOpacity(0.08);
  return Color.alphaBlend(tint, surface);
}

extension on ThemeData {
  double colorSchemeBrightnessBlend() {
    return brightness == Brightness.light ? 0.95 : 0.85;
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
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final List<BoxShadow> shadows;

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
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
                Icon(Icons.add_rounded, color: foregroundColor, size: 22),
                if (extended) ...[
                  const SizedBox(width: 12),
                  Text(
                    'Add',
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
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: card
          .animate(key: ValueKey('quick-extended-$extended'))
          .fade(
            begin: 0.6,
            end: 1,
            duration: 240.ms,
            curve: Curves.easeOutCubic,
          )
          .slideY(
            begin: extended ? 0.12 : -0.12,
            end: 0,
            duration: 360.ms,
            curve: Curves.easeOutQuint,
          )
          .scaleXY(
            begin: extended ? 0.92 : 1.04,
            end: 1,
            duration: 420.ms,
            curve: Curves.easeOutBack,
          ),
    );
  }
}

class _DriveRailBadge extends StatelessWidget {
  const _DriveRailBadge({
    super.key,
    this.label,
    required this.color,
    required this.isDot,
  });

  final String? label;
  final Color color;
  final bool isDot;

  @override
  Widget build(BuildContext context) {
    Widget badge;
    if (isDot) {
      badge = Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    } else {
      badge = Container(
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
    return badge
        .animate()
        .fadeIn(duration: 160.ms, curve: Curves.easeOutQuad)
        .moveY(begin: -4, end: 0, duration: 260.ms, curve: Curves.easeOutCubic)
        .scaleXY(
          begin: 0.8,
          end: 1,
          duration: 260.ms,
          curve: Curves.easeOutBack,
        );
  }
}
