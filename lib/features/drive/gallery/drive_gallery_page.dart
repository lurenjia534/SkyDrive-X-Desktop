import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:skydrivex/features/drive/providers/drive_gallery_controller.dart';
import 'package:skydrivex/features/drive/providers/drive_item_details_provider.dart';
import 'package:skydrivex/features/drive/services/drive_item_action_service.dart';
import 'package:skydrivex/features/drive/utils/drive_item_formatters.dart';
import 'package:skydrivex/features/drive/widgets/drive_inline_progress_indicator.dart';
import 'package:skydrivex/features/drive/widgets/drive_load_more_tile.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;
import 'package:skydrivex/utils/toast.dart';

class DriveGalleryPage extends ConsumerWidget {
  const DriveGalleryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(driveGalleryControllerProvider);
    return asyncState.when(
      data: (data) => _DriveGalleryView(state: data, isRefreshing: false),
      loading: () {
        final previous = asyncState.value;
        if (previous != null) {
          return _DriveGalleryView(state: previous, isRefreshing: true);
        }
        return const _DriveGalleryLoadingView();
      },
      error: (error, _) {
        final previous = asyncState.value;
        if (previous != null) {
          return _DriveGalleryView(state: previous, isRefreshing: false);
        }
        return _DriveGalleryErrorView(message: error.toString());
      },
    );
  }
}

class _DriveGalleryLoadingView extends StatelessWidget {
  const _DriveGalleryLoadingView();

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FCircularProgress.loader(
            style: (style) => style.copyWith(
              iconStyle: IconThemeData(color: colors.primary, size: 24),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Loading gallery...',
            style: typography.sm.copyWith(color: colors.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _DriveGalleryErrorView extends ConsumerWidget {
  const _DriveGalleryErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: FCard.raw(
          style: (style) => style.copyWith(
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colors.border.withValues(alpha: 0.7)),
              boxShadow: [
                BoxShadow(
                  color: colors.barrier.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FIcons.triangleAlert, size: 30, color: colors.destructive),
                const SizedBox(height: 14),
                Text(
                  'Failed to load gallery',
                  style: typography.lg.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.foreground,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: typography.sm.copyWith(color: colors.mutedForeground),
                ),
                const SizedBox(height: 16),
                FButton.icon(
                  onPress: () => ref
                      .read(driveGalleryControllerProvider.notifier)
                      .refresh(showSkeleton: true),
                  style: FButtonStyle.outline(),
                  child: const Icon(FIcons.refreshCcw),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DriveGalleryView extends ConsumerWidget {
  const _DriveGalleryView({required this.state, required this.isRefreshing});

  final DriveGalleryState state;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(driveGalleryControllerProvider.notifier);
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    final showInlineLoadingBar =
        (isRefreshing || state.isRefreshing) && state.items.isNotEmpty;
    final showLoadingState =
        state.items.isEmpty && (isRefreshing || state.isRefreshing);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Text(
                'Photos',
                style: typography.base.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.foreground,
                ),
              ),
              const SizedBox(width: 8),
              _GalleryCountBadge(count: state.items.length),
              const Spacer(),
              FButton.icon(
                onPress: () => unawaited(controller.refresh()),
                style: FButtonStyle.outline(),
                child: const Icon(FIcons.refreshCcw, size: 16),
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              RefreshIndicator(
                onRefresh: () => controller.refresh(),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (showLoadingState) {
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 120),
                            child: _DriveGalleryLoadingView(),
                          ),
                        ],
                      );
                    }
                    if (state.items.isEmpty) {
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 48),
                            child: _DriveGalleryEmptyView(),
                          ),
                        ],
                      );
                    }

                    final rawCount = (constraints.maxWidth / 220).floor();
                    final crossAxisCount = rawCount.clamp(2, 6).toInt();
                    final hasMore = state.nextLink != null;
                    final itemCount = state.items.length + (hasMore ? 1 : 0);
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      physics: const AlwaysScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.98,
                      ),
                      itemCount: itemCount,
                      itemBuilder: (context, index) {
                        if (index >= state.items.length) {
                          return DriveLoadMoreCard(
                            isLoading: state.isLoadingMore,
                            onLoadMore: () => _handleLoadMore(
                              context: context,
                              controller: controller,
                            ),
                          );
                        }
                        final item = state.items[index];
                        return _GalleryGridTile(
                          item: item,
                          onTap: () =>
                              DriveItemActionService.showPropertiesSheet(
                                context: context,
                                ref: ref,
                                item: item,
                              ),
                        );
                      },
                    );
                  },
                ),
              ),
              if (showInlineLoadingBar)
                const Positioned(
                  top: 0,
                  left: 20,
                  right: 20,
                  child: DriveInlineProgressIndicator(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleLoadMore({
    required BuildContext context,
    required DriveGalleryController controller,
  }) async {
    try {
      await controller.loadMore();
    } catch (err) {
      if (!context.mounted) return;
      showToast(context, 'Failed to load more photos: $err');
    }
  }
}

class _DriveGalleryEmptyView extends StatelessWidget {
  const _DriveGalleryEmptyView();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final typography = theme.typography;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: FCard.raw(
          style: (style) => style.copyWith(
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: colors.border.withValues(alpha: 0.7)),
              boxShadow: [
                BoxShadow(
                  color: colors.barrier.withValues(alpha: 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: colors.secondary.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(
                    FIcons.imageOff,
                    size: 34,
                    color: colors.foreground,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'No photos yet',
                  style: typography.lg.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.foreground,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your gallery will show images stored in OneDrive once they are available.',
                  textAlign: TextAlign.center,
                  style: typography.sm.copyWith(
                    color: colors.mutedForeground,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryCountBadge extends StatelessWidget {
  const _GalleryCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colors.secondary.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: typography.xs.copyWith(
          fontWeight: FontWeight.w700,
          color: colors.foreground,
        ),
      ),
    );
  }
}

class _GalleryGridTile extends StatelessWidget {
  const _GalleryGridTile({required this.item, required this.onTap});

  final drive_api.DriveItemSummary item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final typography = context.theme.typography;
    return FCard.raw(
      style: (style) => style.copyWith(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border.withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(
              color: colors.barrier.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          hoverColor: colors.secondary.withValues(alpha: 0.35),
          splashColor: colors.secondary.withValues(alpha: 0.28),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _GalleryPreview(item: item),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typography.sm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.foreground,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _buildPhotoMeta(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typography.xs.copyWith(color: colors.mutedForeground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _buildPhotoMeta(drive_api.DriveItemSummary target) {
    final pieces = <String>[];
    final size = target.size?.toInt();
    if (size != null && size > 0) {
      pieces.add(formatFileSize(size));
    }
    final modifiedAt = _formatDate(target.lastModified);
    if (modifiedAt != null) {
      pieces.add(modifiedAt);
    }
    if (pieces.isEmpty) {
      final mimeType = target.mimeType;
      if (mimeType != null && mimeType.isNotEmpty) {
        return mimeType;
      }
      return 'Image';
    }
    return pieces.join(' · ');
  }

  String? _formatDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}

class _GalleryPreview extends ConsumerWidget {
  const _GalleryPreview({required this.item});

  final drive_api.DriveItemSummary item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.theme.colors;
    final url = item.thumbnailUrl;
    if (url == null || url.isEmpty) {
      final details = ref.watch(driveItemDetailsProvider(item.id));
      return details.when(
        data: (value) {
          final fallbackUrl = value.downloadUrl;
          if (fallbackUrl == null || fallbackUrl.isEmpty) {
            return _GalleryPreviewFallback(iconColor: colors.mutedForeground);
          }
          return Image.network(
            fallbackUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                _GalleryPreviewFallback(iconColor: colors.mutedForeground),
          );
        },
        loading: () => const _GalleryPreviewLoading(),
        error: (_, _) =>
            _GalleryPreviewFallback(iconColor: colors.mutedForeground),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) =>
          _GalleryPreviewFallback(iconColor: colors.mutedForeground),
    );
  }
}

class _GalleryPreviewLoading extends StatelessWidget {
  const _GalleryPreviewLoading();

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      color: colors.secondary.withValues(alpha: 0.35),
      alignment: Alignment.center,
      child: FCircularProgress.loader(
        style: (style) => style.copyWith(
          iconStyle: IconThemeData(color: colors.primary, size: 16),
        ),
      ),
    );
  }
}

class _GalleryPreviewFallback extends StatelessWidget {
  const _GalleryPreviewFallback({required this.iconColor});

  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      color: colors.secondary.withValues(alpha: 0.35),
      alignment: Alignment.center,
      child: Icon(FIcons.imageOff, size: 30, color: iconColor),
    );
  }
}
