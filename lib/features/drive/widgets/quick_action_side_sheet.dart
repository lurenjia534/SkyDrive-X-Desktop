import 'dart:async';

import 'package:flutter/material.dart';

/// 右侧弹出的快捷操作 Side Sheet，支持注入自定义回调。
Future<void> showQuickActionSideSheet(
  BuildContext context, {
  VoidCallback? onUploadPhoto,
  VoidCallback? onCreateFolder,
  VoidCallback? onUploadDoc,
  VoidCallback? onUploadLarge,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;
  const maxWidth = 420.0;

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
                                onUploadPhoto?.call();
                              },
                            ),
                            const SizedBox(height: 12),
                            _QuickActionButton(
                              icon: Icons.create_new_folder_outlined,
                              label: '新建文件夹',
                              description: '在当前视图下创建一个子文件夹',
                              onPressed: () {
                                Navigator.of(context).maybePop();
                                onCreateFolder?.call();
                              },
                            ),
                            const SizedBox(height: 12),
                            _QuickActionButton(
                              icon: Icons.insert_drive_file_outlined,
                              label: '上传文档',
                              description: '适合小体积的文档即时上传',
                              onPressed: () {
                                Navigator.of(context).maybePop();
                                onUploadDoc?.call();
                              },
                            ),
                            const SizedBox(height: 12),
                            _QuickActionButton(
                              icon: Icons.cloud_upload_rounded,
                              label: '上传大文件（分片）',
                              description: '适合超过 250MB 的内容，使用分片上传',
                              onPressed: () {
                                Navigator.of(context).maybePop();
                                onUploadLarge?.call();
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
