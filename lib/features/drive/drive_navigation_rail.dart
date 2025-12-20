import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:forui/forui.dart';

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
  static const List<_DriveRailDestination> _primaryDestinations = [
    _DriveRailDestination(index: 0, label: 'Files', icon: FIcons.folder),
    _DriveRailDestination(
      index: 1,
      label: 'Download',
      icon: FIcons.cloudDownload,
    ),
    _DriveRailDestination(index: 2, label: 'Upload', icon: FIcons.cloudUpload),
  ];
  static const _settingsDestination = _DriveRailDestination(
    index: 3,
    label: 'Settings',
    icon: FIcons.settings,
  );

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
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    final borderRadius = BorderRadius.circular(24);
    final navShadowColor = colors.barrier.withValues(alpha: 0.1);
    final width = _isExtended ? 212.0 : 68.0;
    final horizontalPadding = _isExtended ? 16.0 : 10.0;

    final railContainer = AnimatedContainer(
      duration: _animationDuration,
      curve: Curves.easeOutCubic,
      width: width,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: borderRadius,
        border: Border.all(color: colors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: navShadowColor,
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            16,
            horizontalPadding,
            18,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DriveRailToggle(
                extended: _isExtended,
                onPressed: _toggleExtended,
                colors: colors,
                typography: typography,
              ),
              const SizedBox(height: 14),
              _DriveRailQuickAction(
                extended: _isExtended,
                onPressed: widget.onQuickAction,
                colors: colors,
                typography: typography,
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _primaryDestinations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final destination = _primaryDestinations[index];
                    return _DriveRailItem(
                      destination: destination,
                      extended: _isExtended,
                      selected: _selectedIndex == destination.index,
                      onTap: () => _handleDestinationTap(destination.index),
                      colors: colors,
                      typography: typography,
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              _DriveRailItem(
                destination: _settingsDestination,
                extended: _isExtended,
                selected: _selectedIndex == _settingsDestination.index,
                onTap: () => _handleDestinationTap(_settingsDestination.index),
                colors: colors,
                typography: typography,
              ),
            ],
          ),
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
}

class _DriveRailDestination {
  const _DriveRailDestination({
    required this.index,
    required this.label,
    required this.icon,
    // ignore: unused_element_parameter
    this.badgeCount,
    // ignore: unused_element_parameter
    this.showDot = false,
  });

  final int index;
  final String label;
  final IconData icon;
  final int? badgeCount;
  final bool showDot;
}

class _DriveRailQuickAction extends StatelessWidget {
  const _DriveRailQuickAction({
    required this.extended,
    required this.onPressed,
    required this.colors,
    required this.typography,
  });

  final bool extended;
  final VoidCallback? onPressed;
  final FColors colors;
  final FTypography typography;

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      key: ValueKey<bool>(extended),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
      width: extended ? 176 : 48,
      height: 50,
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: colors.barrier.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: extended ? 20 : 0),
            child: Row(
              mainAxisAlignment: extended
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  FIcons.plus,
                  color: colors.primaryForeground,
                  size: 22,
                ),
                if (extended) ...[
                  const SizedBox(width: 12),
                  Text(
                    'Add',
                    style: typography.base.copyWith(
                      color: colors.primaryForeground,
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
      child: (extended
              ? card
              : Tooltip(
                  message: 'Add',
                  child: card,
                ))
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

class _DriveRailToggle extends StatelessWidget {
  const _DriveRailToggle({
    required this.extended,
    required this.onPressed,
    required this.colors,
    required this.typography,
  });

  final bool extended;
  final VoidCallback onPressed;
  final FColors colors;
  final FTypography typography;

  @override
  Widget build(BuildContext context) {
    final label = extended ? '收起导航' : '展开导航';
    return Row(
      children: [
        Tooltip(
          message: label,
          child: Material(
            color: colors.background,
            shape: CircleBorder(
              side: BorderSide(
                color: colors.border.withValues(alpha: 0.7),
              ),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox(
                width: 38,
                height: 38,
                child: Icon(
                  extended ? FIcons.panelLeftClose : FIcons.panelLeftOpen,
                  color: colors.foreground,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
        if (extended) ...[
          const SizedBox(width: 10),
          Text(
            '收起导航',
            style: typography.sm.copyWith(
              color: colors.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _DriveRailItem extends StatelessWidget {
  const _DriveRailItem({
    required this.destination,
    required this.extended,
    required this.selected,
    required this.onTap,
    required this.colors,
    required this.typography,
  });

  final _DriveRailDestination destination;
  final bool extended;
  final bool selected;
  final VoidCallback onTap;
  final FColors colors;
  final FTypography typography;

  @override
  Widget build(BuildContext context) {
    final isCompact = !extended;
    final itemSize = isCompact ? 40.0 : 44.0;
    final railRadius = BorderRadius.circular(16);
    final iconColor =
        selected ? colors.primaryForeground : colors.mutedForeground;
    final textStyle = selected
        ? typography.sm.copyWith(
            color: colors.primaryForeground,
            fontWeight: FontWeight.w600,
          )
        : typography.sm.copyWith(
            color: colors.mutedForeground,
            fontWeight: FontWeight.w500,
          );

    final item = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: isCompact ? null : railRadius,
        customBorder:
            isCompact ? const CircleBorder() : RoundedRectangleBorder(borderRadius: railRadius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          height: itemSize,
          width: extended ? double.infinity : itemSize,
          padding: EdgeInsets.symmetric(
            horizontal: extended ? 12 : 0,
            vertical: extended ? 8 : 0,
          ),
          decoration: isCompact
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? colors.primary : colors.background,
                  border: selected
                      ? null
                      : Border.all(
                          color: colors.border.withValues(alpha: 0.8),
                        ),
                )
              : BoxDecoration(
                  color: selected
                      ? colors.primary
                      : colors.secondary.withValues(alpha: 0.0),
                  borderRadius: railRadius,
                ),
          child: Row(
            mainAxisAlignment:
                extended ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Icon(destination.icon, color: iconColor, size: 20),
              if (extended) ...[
                const SizedBox(width: 12),
                Expanded(child: Text(destination.label, style: textStyle)),
              ],
            ],
          ),
        ),
      ),
    );

    if (extended) return item;
    return Tooltip(message: destination.label, child: item);
  }
}
