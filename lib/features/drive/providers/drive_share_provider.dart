import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skydrivex/src/rust/api/drive.dart' as drive_api;
import 'package:skydrivex/src/rust/api/drive/share.dart' as share_api;
import 'package:skydrivex/src/rust/api/drive/models.dart' as drive_models;

/// 当前正在分享的目标项（由对话框注入）。
final shareTargetItemProvider = Provider<drive_api.DriveItemSummary>(
  (ref) => throw UnimplementedError('shareTargetItemProvider not overridden'),
);

/// 缓存分享能力（可重复利用，避免每次弹窗都请求）。
final shareCapabilitiesProvider =
    FutureProvider.autoDispose<drive_models.ShareCapabilities>((ref) {
      return share_api.getShareCapabilities();
    });

/// 创建分享链接。
final createShareLinkProvider = FutureProvider.autoDispose
    .family<drive_models.ShareLinkResult, ShareLinkRequest>((ref, req) async {
      return share_api.createShareLink(
        itemId: req.itemId,
        linkType: req.linkType,
        scope: req.scope,
        password: req.password,
        expirationDateTime: req.expirationIso,
        retainInheritedPermissions: req.retainInheritedPermissions,
        recipients: req.recipients,
      );
    });

class ShareLinkRequest {
  const ShareLinkRequest({
    required this.itemId,
    required this.linkType,
    required this.scope,
    this.password,
    this.expirationIso,
    this.retainInheritedPermissions,
    this.recipients,
  });

  final String itemId;
  final drive_models.LinkType linkType;
  final drive_models.LinkScope scope;
  final String? password;
  final String? expirationIso;
  final bool? retainInheritedPermissions;
  final List<String>? recipients;
}
