import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_theme.dart';
import '../core/api.dart';
import '../core/models.dart';
import 'history_screen.dart' show formatDate;

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.videoId});
  final int videoId;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  Timer? _timer;
  VideoResults? _results;
  VideoItem? _video; // latest status while processing
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final api = context.read<Api>();
    try {
      final status = await api.videoStatus(widget.videoId);
      if (!mounted) return;
      if (status.isProcessing) {
        setState(() {
          _video = status;
          _error = null;
        });
        _timer = Timer(const Duration(seconds: 3), _check);
        return;
      }
      if (status.isFailed) {
        setState(() {
          _video = status;
          _error = null;
        });
        return;
      }
      final results = await api.videoResults(widget.videoId);
      if (mounted) {
        setState(() {
          _results = results;
          _video = results.video;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      _timer = Timer(const Duration(seconds: 5), _check); // keep trying after a network hiccup
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        actions: [
          IconButton(
            tooltip: 'Share report',
            icon: _sharing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share),
            onPressed: _results == null || _sharing ? null : _share,
          ),
        ],
      ),
      body: SafeArea(child: _body(context)),
    );
  }

  bool _sharing = false;

  /// Shares a short text summary plus up to 6 photos (violations first), e.g. to WhatsApp or email.
  Future<void> _share() async {
    final r = _results!;
    final api = context.read<Api>();
    setState(() => _sharing = true);
    try {
      final dir = await getTemporaryDirectory();
      final ordered = [...r.detections.where((d) => d.isViolation), ...r.detections.where((d) => !d.isViolation)];
      final files = <XFile>[];
      for (final d in ordered.where((d) => d.imageUrl != null).take(6)) {
        final bytes = await api.downloadBytes(d.imageUrl!);
        final f = File('${dir.path}/helmet_${r.video.id}_${d.id}.jpg');
        await f.writeAsBytes(bytes, flush: true);
        files.add(XFile(f.path, mimeType: 'image/jpeg'));
      }
      final when = r.video.uploadedAt == null ? '' : '\nDate: ${formatDate(r.video.uploadedAt!.toLocal())}';
      final verdict = r.peopleChecked == 0
          ? 'No people were detected.'
          : r.violations == 0
              ? 'Everyone was wearing a helmet.'
              : '${r.violations} of ${r.peopleChecked} people were NOT wearing a helmet.';
      await SharePlus.instance.share(ShareParams(
        subject: 'Helmet Check report',
        text: 'Helmet Check report\nVideo: ${r.video.filename}$when\nPeople checked: ${r.peopleChecked}\n$verdict',
        files: files,
      ));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not share: $e')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Widget _body(BuildContext context) {
    if (_results != null) return _ResultsView(results: _results!);
    final scheme = Theme.of(context).colorScheme;
    if (_video?.isFailed == true) {
      return _CenterMessage(
        icon: Icons.error_outline,
        color: scheme.error,
        title: 'Processing failed',
        body: _video?.error ?? 'Unknown error',
      );
    }
    return _CenterMessage(
      icon: Icons.hourglass_top_rounded,
      color: scheme.primary,
      title: 'Analyzing video…',
      body: 'This can take a few minutes. You can leave this screen and open it later from History.',
      busy: true,
      note: _error,
    );
  }
}

class _CenterMessage extends StatelessWidget {
  const _CenterMessage({required this.icon, required this.color, required this.title, required this.body, this.busy = false, this.note});
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final bool busy;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(alignment: Alignment.center, children: [
            if (busy) SizedBox(width: 92, height: 92, child: CircularProgressIndicator(strokeWidth: 3, color: color)),
            Icon(icon, size: busy ? 40 : 64, color: color),
          ]),
          const SizedBox(height: 22),
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (note != null) ...[
            const SizedBox(height: 14),
            Text(note!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ]),
      ),
    );
  }
}

String _mmss(double seconds) {
  final s = seconds.round();
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

enum _Filter { all, violations, safe }

class _ResultsView extends StatefulWidget {
  const _ResultsView({required this.results});
  final VideoResults results;

  @override
  State<_ResultsView> createState() => _ResultsViewState();
}

class _ResultsViewState extends State<_ResultsView> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final r = widget.results;
    final scheme = Theme.of(context).colorScheme;
    final shown = r.detections.where((d) => switch (_filter) {
          _Filter.all => true,
          _Filter.violations => d.isViolation,
          _Filter.safe => !d.isViolation,
        }).toList();
    final safe = r.peopleChecked - r.violations;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _Verdict(results: r),
        for (final w in r.warnings) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(child: Text(w)),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _MiniStat(label: 'People checked', value: '${r.peopleChecked}', color: scheme.primary)),
          const SizedBox(width: 10),
          Expanded(child: _MiniStat(label: 'With helmet', value: '$safe', color: AppColors.success)),
          const SizedBox(width: 10),
          Expanded(child: _MiniStat(label: 'No helmet', value: '${r.violations}', color: AppColors.danger)),
        ]),
        if (r.detections.isNotEmpty) ...[
          const SizedBox(height: 18),
          Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('All'), selected: _filter == _Filter.all, onSelected: (_) => setState(() => _filter = _Filter.all)),
            ChoiceChip(
                label: Text('No helmet (${r.violations})'),
                selected: _filter == _Filter.violations,
                onSelected: (_) => setState(() => _filter = _Filter.violations)),
            ChoiceChip(
                label: Text('Helmet ($safe)'),
                selected: _filter == _Filter.safe,
                onSelected: (_) => setState(() => _filter = _Filter.safe)),
          ]),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Nothing in this filter.')))
          else
            _Grid(items: shown),
        ],
      ],
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.results});
  final VideoResults results;

  @override
  Widget build(BuildContext context) {
    final r = results;
    final Color color;
    final IconData icon;
    final String title;
    final String sub;
    if (r.peopleChecked == 0) {
      color = Colors.blueGrey;
      icon = Icons.person_search_outlined;
      title = 'No people detected';
      sub = 'Try again with people clearly in view and better light.';
    } else if (r.violations > 0) {
      color = AppColors.danger;
      icon = Icons.warning_amber_rounded;
      title = r.violations == 1 ? '1 person without a helmet' : '${r.violations} people without a helmet';
      sub = 'Tap a photo below to see the proof and the exact time.';
    } else {
      color = AppColors.success;
      icon = Icons.verified_rounded;
      title = 'Everyone is wearing a helmet';
      sub = '${r.peopleChecked} ${r.peopleChecked == 1 ? 'person' : 'people'} checked.';
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.3)!],
        ),
      ),
      child: Row(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 32),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.items});
  final List<Detection> items;

  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.1,
      ),
      itemBuilder: (context, i) {
        final d = items[i];
        final url = d.imageUrl == null ? null : api.absoluteUrl(d.imageUrl!);
        final color = d.isViolation ? AppColors.danger : AppColors.success;
        return GestureDetector(
          onTap: url == null
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => _Viewer(items: items, start: i, api: api),
                  )),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(fit: StackFit.expand, children: [
              Hero(
                tag: 'det-${d.id}',
                child: url != null
                    ? Image.network(
                        url,
                        headers: api.authHeaders,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12, child: Center(child: Icon(Icons.broken_image))),
                        loadingBuilder: (_, child, p) => p == null
                            ? child
                            : const ColoredBox(color: Colors.black12, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                      )
                    : const ColoredBox(color: Colors.black12, child: Center(child: Icon(Icons.image_not_supported))),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
                    ),
                  ),
                  child: Row(children: [
                    Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${d.isViolation ? 'No helmet' : 'Helmet'} · ${(d.confidence * 100).round()}%',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(_mmss(d.timestampSeconds), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _Viewer extends StatefulWidget {
  const _Viewer({required this.items, required this.start, required this.api});
  final List<Detection> items;
  final int start;
  final Api api;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late final PageController _controller = PageController(initialPage: widget.start);
  late int _index = widget.start;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.items[_index];
    final color = d.isViolation ? AppColors.danger : AppColors.success;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.items.length}', style: const TextStyle(color: Colors.white)),
      ),
      body: Column(children: [
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              final it = widget.items[i];
              return InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Hero(
                    tag: 'det-${it.id}',
                    child: Image.network(widget.api.absoluteUrl(it.imageUrl!), headers: widget.api.authHeaders, fit: BoxFit.contain),
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF111111),
            child: Row(children: [
              Icon(d.isViolation ? Icons.warning_amber_rounded : Icons.verified_outlined, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  d.isViolation ? 'No helmet' : 'Wearing a helmet',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Text('${(d.confidence * 100).round()}% sure · at ${_mmss(d.timestampSeconds)}', style: const TextStyle(color: Colors.white70)),
            ]),
          ),
        ),
      ]),
    );
  }
}
