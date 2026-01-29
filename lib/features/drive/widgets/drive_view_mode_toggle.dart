import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/drive/providers/drive_view_mode_provider.dart';

class DriveViewModeToggle extends StatelessWidget {
  const DriveViewModeToggle({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final DriveItemViewMode mode;
  final ValueChanged<DriveItemViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: colors.barrier.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeButton(
            selected: mode == DriveItemViewMode.list,
            icon: Icons.view_list_rounded,
            tooltip: 'List view',
            onTap: () => onChanged(DriveItemViewMode.list),
          ),
          const SizedBox(width: 4),
          _ModeButton(
            selected: mode == DriveItemViewMode.grid,
            icon: Icons.grid_view_rounded,
            tooltip: 'Grid view',
            onTap: () => onChanged(DriveItemViewMode.grid),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.selected,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final foreground = selected ? colors.primary : colors.mutedForeground;
    final background = selected
        ? colors.primary.withValues(alpha: 0.18)
        : Colors.transparent;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 36,
            height: 32,
            child: Icon(icon, size: 18, color: foreground),
          ),
        ),
      ),
    );
  }
}
