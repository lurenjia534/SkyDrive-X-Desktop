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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = _DriveErrorView(message: _error!, onRetry: _loadInitial);
    } else if (_items.isEmpty) {
      body = const _DriveEmptyView();
    } else {
      body = RefreshIndicator(
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
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: body,
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
