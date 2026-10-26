import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../core/api.dart';
import '../core/models.dart';
import 'history_screen.dart' show formatDate;

/// CCTV alerts: the newest first, with the photo the worker took. Checks for new ones every 20 seconds while open.
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  static const _pageSize = 30;

  final List<CctvEvent> _events = [];
  CctvStatus? _status;
  String? _error;
  bool _loading = true;
  bool _hasMore = true;
  bool _loadingMore = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final api = context.read<Api>();
    try {
      final results = await Future.wait([api.cctvEvents(limit: _pageSize), api.cctvStatus()]);
      if (!mounted) return;
      final events = results[0] as List<CctvEvent>;
      setState(() {
        _events
          ..clear()
          ..addAll(events);
        _status = results[1] as CctvStatus;
        _hasMore = events.length == _pageSize;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.statusCode == 403 ? 'CCTV alerts are only for admin accounts.' : e.message;
          _loading = false;
        });
      }
    }
  }

  /// Quietly fetches only what is newer than the top item.
  Future<void> _poll() async {
    if (!mounted || _loading || _events.isEmpty && _error != null) return;
    final api = context.read<Api>();
    try {
      final newer = await api.cctvEvents(sinceId: _events.isEmpty ? 0 : _events.first.id);
      final status = await api.cctvStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        if (newer.isNotEmpty) _events.insertAll(0, newer);
      });
      if (newer.isNotEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('${newer.length} new alert${newer.length == 1 ? '' : 's'}'),
            backgroundColor: AppColors.danger,
          ));
      }
    } on ApiException {
      // a failed check is not worth interrupting the screen for; the next one tries again
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _events.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final older = await context.read<Api>().cctvEvents(beforeId: _events.last.id, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _events.addAll(older);
        _hasMore = older.length == _pageSize;
      });
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _open(CctvEvent e) async {
    final removed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => EventViewer(event: e)));
    if (removed == true && mounted) setState(() => _events.removeWhere((x) => x.id == e.id));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                setState(() => _loading = true);
                _refresh();
              },
              style: FilledButton.styleFrom(minimumSize: const Size(140, 48)),
              child: const Text('Retry'),
            ),
          ]),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _events.length + 2,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (i == 0) return _StatusCard(status: _status);
          if (_events.isEmpty) {
            return const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: Text('No alerts yet. They appear here as soon as a camera sees someone without a helmet.', textAlign: TextAlign.center)),
            );
          }
          final index = i - 1;
          if (index == _events.length) {
            if (!_hasMore) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: OutlinedButton(
                onPressed: _loadingMore ? null : _loadMore,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                child: Text(_loadingMore ? 'Loading…' : 'Older alerts'),
              ),
            );
          }
          return _EventTile(event: _events[index], onTap: () => _open(_events[index]));
        },
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});
  final CctvStatus? status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = status;
    final Color color;
    final String title;
    final String detail;
    if (s == null || s.secondsSinceHeartbeat == null) {
      color = AppColors.warning;
      title = 'No camera monitor connected yet';
      detail = 'Start the CCTV worker on the PC next to the camera.';
    } else if (s.workerOnline) {
      color = AppColors.success;
      title = 'Monitoring is running';
      detail = '${s.cameraCount} camera${s.cameraCount == 1 ? '' : 's'} · last signal ${_ago(s.secondsSinceHeartbeat!)} ago';
    } else {
      color = AppColors.danger;
      title = 'Monitoring is OFFLINE';
      detail = 'Last signal ${_ago(s.secondsSinceHeartbeat!)} ago. Is the PC with the worker on?';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.videocam_rounded, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
              const SizedBox(height: 2),
              Text(detail, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
            ]),
          ),
        ]),
      ),
    );
  }

  static String _ago(int seconds) {
    if (seconds < 90) return '${seconds}s';
    if (seconds < 7200) return '${(seconds / 60).round()} min';
    return '${(seconds / 3600).round()} h';
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.onTap});
  final CctvEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final api = context.read<Api>();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 96,
                height: 60,
                child: event.photoUrl == null
                    ? ColoredBox(color: scheme.surfaceContainerHighest)
                    : Image.network(
                        api.absoluteUrl(event.photoUrl!),
                        headers: api.authHeaders,
                        fit: BoxFit.cover,
                        cacheWidth: 240,
                        errorBuilder: (_, _, _) => ColoredBox(color: scheme.surfaceContainerHighest, child: const Icon(Icons.broken_image_outlined)),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(event.cameraName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  [if (event.createdAt != null) formatDate(event.createdAt!), '${(event.confidence * 100).round()}%'].join(' · '),
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
                ),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
              child: const Text('No helmet', style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Full-size photo with pinch zoom, and a button to mark the alert as a mistake.
class EventViewer extends StatefulWidget {
  const EventViewer({super.key, required this.event});
  final CctvEvent event;

  @override
  State<EventViewer> createState() => _EventViewerState();
}

class _EventViewerState extends State<EventViewer> {
  bool _busy = false;

  Future<void> _markMistake() async {
    setState(() => _busy = true);
    try {
      await context.read<Api>().toggleCctvFalsePositive(widget.event.id);
      if (mounted) Navigator.of(context).pop(true); // the list drops it
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();
    final e = widget.event;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(e.cameraName),
      ),
      body: Column(children: [
        Expanded(
          child: e.photoUrl == null
              ? const Center(child: Text('No photo', style: TextStyle(color: Colors.white70)))
              : InteractiveViewer(
                  maxScale: 6,
                  child: Center(
                    child: Image.network(
                      api.absoluteUrl(e.photoUrl!),
                      headers: api.authHeaders,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()),
                      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                    ),
                  ),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: Text(
                  [if (e.createdAt != null) formatDate(e.createdAt!), '${(e.confidence * 100).round()}% sure'].join(' · '),
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _markMistake,
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Not a violation'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46), foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
