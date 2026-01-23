import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/drive/models/drive_breadcrumb.dart';
import 'package:skydrivex/features/drive/providers/drive_move_provider.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;

/// 侧边抽屉式的“移动到”选择器，使用独立的浏览状态，不影响主界面。
class DriveMoveSheet extends ConsumerWidget {
  const DriveMoveSheet({super.key, required this.item, required this.onMove});

  final drive_api.DriveItemSummary item;
  final Future<void> Function(String? targetFolderId) onMove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driveMoveBrowserProvider);
    final controller = ref.read(driveMoveBrowserProvider.notifier);
    final breadcrumbs = state.breadcrumbs;
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    final folders = state.items.where((entry) => entry.isFolder).toList();
    final sheetRadius = const BorderRadius.horizontal(
      left: Radius.circular(24),
    );
    final listRadius = BorderRadius.circular(16);
    final listDecoration = BoxDecoration(
      color: colors.background,
      borderRadius: listRadius,
      border: Border.all(
        color: colors.border.withValues(alpha: 0.6),
      ),
    );

    Widget listBody;
    if (state.isLoading) {
      listBody = _MoveStatusPanel(
        decoration: listDecoration,
        borderRadius: listRadius,
        child: Center(
          child: FCircularProgress.loader(
            style: (style) => style.copyWith(
              iconStyle: IconThemeData(
                color: colors.primary,
                size: 20,
              ),
            ),
          ),
        ),
      );
    } else if (state.error != null) {
      listBody = _MoveStatusPanel(
        decoration: listDecoration,
        borderRadius: listRadius,
        child: _MoveErrorView(
          message: state.error!,
          onRetry: controller.refreshCurrent,
        ),
      );
    } else if (folders.isEmpty) {
      listBody = _MoveStatusPanel(
        decoration: listDecoration,
        borderRadius: listRadius,
        child: Center(
          child: Text(
            '暂无可用文件夹',
            style: typography.sm.copyWith(
              color: colors.mutedForeground,
            ),
          ),
        ),
      );
    } else {
      listBody = FItemGroup.builder(
        count: folders.length,
        divider: FItemDivider.full,
        style: (style) => style.copyWith(
          decoration: listDecoration,
          spacing: 0,
          dividerColor: FWidgetStateMap.all(
            colors.border.withValues(alpha: 0.6),
          ),
          itemStyle: (itemStyle) => itemStyle.copyWith(
            margin: EdgeInsets.zero,
            decoration: FWidgetStateMap({
              WidgetState.hovered | WidgetState.pressed: BoxDecoration(
                color: colors.secondary.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              WidgetState.any: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(12),
              ),
            }),
            contentStyle: (contentStyle) => contentStyle.copyWith(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
              titleTextStyle: FWidgetStateMap.all(
                typography.sm.copyWith(
                  color: colors.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitleTextStyle: FWidgetStateMap.all(
                typography.xs.copyWith(
                  color: colors.mutedForeground,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
        itemBuilder: (context, index) {
          final entry = folders[index];
          final isSelf = entry.id == item.id;
          final iconBackground = isSelf
              ? colors.disable(colors.secondary)
              : colors.secondary.withValues(alpha: 0.7);
          final iconColor =
              isSelf ? colors.mutedForeground : colors.foreground;
          return FItem(
            enabled: !isSelf,
            onPress: isSelf ? null : () => controller.enterFolder(entry),
            prefix: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                FIcons.folder,
                size: 18,
                color: iconColor,
              ),
            ),
            title: Text(entry.name),
            subtitle: entry.childCount != null
                ? Text('${entry.childCount} 项')
                : null,
            suffix: isSelf
                ? null
                : Icon(
                    FIcons.chevronRight,
                    size: 16,
                    color: colors.mutedForeground,
                  ),
          );
        },
      );
    }

    return SafeArea(
      child: SizedBox(
        height: double.infinity,
        child: FCard.raw(
          style: (style) => style.copyWith(
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: sheetRadius,
              border: Border.all(
                color: colors.border.withValues(alpha: 0.7),
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.barrier.withValues(alpha: 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
          ),
          child: ClipRRect(
            borderRadius: sheetRadius,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      FButton.icon(
                        onPress:
                            breadcrumbs.isEmpty ? null : controller.goBack,
                        style: FButtonStyle.ghost(),
                        child: const Icon(FIcons.arrowLeft, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '移动 “${item.name}”',
                          style: typography.lg.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.foreground,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      FButton.icon(
                        onPress: () => Navigator.of(context).maybePop(),
                        style: FButtonStyle.ghost(),
                        child: const Icon(FIcons.x, size: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    breadcrumbs.isEmpty
                        ? '当前位置：根目录'
                        : _breadcrumbText(breadcrumbs),
                    style: typography.sm.copyWith(
                      color: colors.mutedForeground,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: listBody),
                  const SizedBox(height: 12),
                  const FDivider(),
                  const SizedBox(height: 12),
                  FButton(
                    onPress: () {
                      final target = breadcrumbs.isEmpty
                          ? null
                          : breadcrumbs.last.id;
                      onMove(target);
                    },
                    style: FButtonStyle.primary(),
                    child: const Text('移动到当前目录'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _breadcrumbText(List<DriveBreadcrumbSegment> segments) {
  return segments.map((s) => s.name).join(' / ');
}

class _MoveStatusPanel extends StatelessWidget {
  const _MoveStatusPanel({
    required this.decoration,
    required this.borderRadius,
    required this.child,
  });

  final BoxDecoration decoration;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: DecoratedBox(
        decoration: decoration,
        child: child,
      ),
    );
  }
}

class _MoveErrorView extends StatelessWidget {
  const _MoveErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FIcons.circleAlert,
              size: 20,
              color: colors.error,
            ),
            const SizedBox(height: 8),
            Text(
              '加载失败：$message',
              textAlign: TextAlign.center,
              style: typography.sm.copyWith(
                color: colors.mutedForeground,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            FButton(
              onPress: onRetry,
              style: FButtonStyle.outline(),
              prefix: const Icon(FIcons.refreshCcw, size: 16),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
