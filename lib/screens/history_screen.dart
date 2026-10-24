import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../core/api.dart';
import '../core/models.dart';

String formatDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.day} ${months[d.month - 1]} · $h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

/// One row for a video: status icon, name, date and the verdict badge.
class VideoTile extends StatelessWidget {
  const VideoTile({super.key, required this.video, required this.onTap, this.onDelete});
  final VideoItem video;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final v = video;
    final Color color;
    final IconData icon;
    final String badge;
    if (v.isProcessing) {
      color = AppColors.warning;
      icon = Icons.hourglass_top_rounded;
      badge = 'Analyzing';
    } else if (v.isFailed) {
      color = scheme.error;
      icon = Icons.error_outline;
      badge = 'Failed';
    } else if ((v.violations ?? 0) > 0) {
      color = AppColors.danger;
      icon = Icons.warning_amber_rounded;
      badge = '${v.violations} without helmet';
    } else {
      color = AppColors.success;
      icon = Icons.verified_outlined;
      badge = 'All safe';
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
              child: v.isProcessing
                  ? Padding(padding: const EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2.5, color: color))
                  : Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v.filename, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (v.uploadedAt != null) formatDate(v.uploadedAt!.toLocal()),
                    if (v.durationSeconds != null) '${v.durationSeconds!.round()}s',
                  ].join(' · '),
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
                ),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
              child: Text(badge, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline),
                onPressed: v.isProcessing ? null : onDelete,
              ),
          ]),
        ),
      ),
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<VideoItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await context.read<Api>().listVideos();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _delete(VideoItem v) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this video?'),
        content: Text('"${v.filename}" and its results will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await context.read<Api>().deleteVideo(v.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items == null && _error == null) return const Center(child: CircularProgressIndicator());
    if (_items == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, style: FilledButton.styleFrom(minimumSize: const Size(140, 48)), child: const Text('Retry')),
          ]),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: _items!.isEmpty
          ? ListView(children: [
              const SizedBox(height: 120),
              Icon(Icons.video_library_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              const Center(child: Text('No videos yet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
              const SizedBox(height: 4),
              const Center(child: Text('Record or upload one from the Check tab.')),
            ])
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: _items!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final v = _items![i];
                return VideoTile(
                  video: v,
                  onDelete: () => _delete(v),
                  onTap: () async {
                    await context.push('/results/${v.id}');
                    if (mounted) _load();
                  },
                );
              },
            ),
    );
  }
}
