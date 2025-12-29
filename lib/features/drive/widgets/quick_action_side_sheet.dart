import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// 右侧弹出的快捷操作 Side Sheet，支持注入自定义回调。
Future<void> showQuickActionSideSheet(
  BuildContext context, {
  VoidCallback? onUploadPhoto,
  VoidCallback? onCreateFolder,
  VoidCallback? onUploadDoc,
  VoidCallback? onUploadLarge,
}) {
  final screenWidth = MediaQuery.of(context).size.width;
  final widthFactor = screenWidth >= 1280
      ? 0.3
      : screenWidth >= 960
          ? 0.38
          : 0.6;

  return showFSheet(
    context: context,
    side: FLayout.rtl,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: '关闭快捷操作',
    draggable: false,
    mainAxisMaxRatio: widthFactor,
    builder: (sheetContext) => _QuickActionSideSheet(
      onUploadPhoto: onUploadPhoto,
      onCreateFolder: onCreateFolder,
      onUploadDoc: onUploadDoc,
      onUploadLarge: onUploadLarge,
      onClose: () => Navigator.of(sheetContext).maybePop(),
    ),
  );
}

class _QuickActionSideSheet extends StatelessWidget {
  const _QuickActionSideSheet({
    required this.onUploadPhoto,
    required this.onCreateFolder,
    required this.onUploadDoc,
    required this.onUploadLarge,
    required this.onClose,
  });

  final VoidCallback? onUploadPhoto;
  final VoidCallback? onCreateFolder;
  final VoidCallback? onUploadDoc;
  final VoidCallback? onUploadLarge;
  final VoidCallback onClose;

  void _handleAction(BuildContext context, VoidCallback? action) {
    Navigator.of(context).maybePop();
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;

    return SafeArea(
      child: SizedBox(
        height: double.infinity,
        child: FCard.raw(
          style: (style) => style.copyWith(
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(24),
              ),
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
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 40,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Quick Actions',
                                style: typography.lg.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colors.foreground,
                                ),
                              ),
                              const Spacer(),
                              FButton.icon(
                                onPress: onClose,
                                style: FButtonStyle.ghost(),
                                child: const Icon(FIcons.x, size: 16),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '快速上传照片或新建项目，稍后可在前端接入实际逻辑。',
                            style: typography.sm.copyWith(
                              color: colors.mutedForeground,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 18),
                          FItemGroup(
                            divider: FItemDivider.full,
                            style: (style) => style.copyWith(
                              decoration: BoxDecoration(
                                color: colors.background,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: colors.border.withValues(alpha: 0.6),
                                ),
                              ),
                              dividerColor: FWidgetStateMap.all(
                                colors.border.withValues(alpha: 0.6),
                              ),
                              itemStyle: (itemStyle) => itemStyle.copyWith(
                                margin: EdgeInsets.zero,
                                decoration: FWidgetStateMap({
                                  WidgetState.hovered | WidgetState.pressed:
                                      BoxDecoration(
                                    color: colors.secondary.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  WidgetState.any: BoxDecoration(
                                    color: colors.background,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                }),
                                contentStyle: (contentStyle) =>
                                    contentStyle.copyWith(
                                  padding: const EdgeInsetsDirectional.fromSTEB(
                                    12,
                                    10,
                                    12,
                                    10,
                                  ),
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
                            children: [
                              _QuickActionItem(
                                icon: Icons.image_outlined,
                                label: '上传照片/小文件',
                                description: '选择本地图片并上传到当前目录',
                                onPress: () =>
                                    _handleAction(context, onUploadPhoto),
                              ),
                              _QuickActionItem(
                                icon: Icons.create_new_folder_outlined,
                                label: '新建文件夹',
                                description: '在当前视图下创建一个子文件夹',
                                onPress: () =>
                                    _handleAction(context, onCreateFolder),
                              ),
                              _QuickActionItem(
                                icon: Icons.insert_drive_file_outlined,
                                label: '上传文档',
                                description: '适合小体积的文档即时上传',
                                onPress: () => _handleAction(context, onUploadDoc),
                              ),
                              _QuickActionItem(
                                icon: Icons.cloud_upload_rounded,
                                label: '上传大文件（分片）',
                                description: '适合超过 250MB 的内容，使用分片上传',
                                onPress: () =>
                                    _handleAction(context, onUploadLarge),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '后续可将这些入口与实际上传/创建逻辑绑定。',
                            style: typography.xs.copyWith(
                              color: colors.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionItem extends StatelessWidget with FItemMixin {
  const _QuickActionItem({
    required this.icon,
    required this.label,
    required this.description,
    required this.onPress,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FItem(
      onPress: onPress,
      prefix: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: colors.secondary.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 18, color: colors.foreground),
      ),
      title: Text(label),
      subtitle: Text(description),
      suffix: Icon(
        Icons.chevron_right_rounded,
        size: 18,
        color: colors.mutedForeground,
      ),
    );
  }
}
