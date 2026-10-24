import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../core/api.dart';
import '../core/auth_state.dart';
import '../core/models.dart';
import 'history_screen.dart';
import 'server_dialog.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final api = context.read<Api>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_index == 0 ? 'Helmet Check' : 'History'),
        actions: [
          IconButton(
            tooltip: 'Server address',
            icon: const Icon(Icons.dns_outlined),
            onPressed: () => showServerDialog(context, api),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthState>().logout(),
          ),
        ],
      ),
      body: SafeArea(child: _index == 0 ? const _HomeTab() : const HistoryScreen()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield), label: 'Check'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  List<VideoItem>? _videos;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await context.read<Api>().listVideos();
      if (mounted) setState(() => _videos = v);
    } on ApiException {
      if (mounted) setState(() => _videos ??= []); // stats are optional; the buttons still work
    }
  }

  Future<void> _record() async {
    final path = await context.push<String>('/record');
    if (path != null && mounted) await context.push('/upload', extra: path);
    if (mounted) _load();
  }

  Future<void> _pickGallery() async {
    try {
      final file = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 2));
      if (file != null && mounted) {
        await context.push('/upload', extra: file.path);
        if (mounted) _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open gallery: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final videos = _videos ?? const <VideoItem>[];
    final done = videos.where((v) => v.isDone).toList();
    final violations = done.fold<int>(0, (s, v) => s + (v.violations ?? 0));
    final recent = videos.take(3).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, Color.lerp(scheme.primary, Colors.black, 0.35)!],
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Your safety checks', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 12),
              Row(children: [
                _HeroStat(value: _videos == null ? '–' : '${done.length}', label: 'Videos checked'),
                const SizedBox(width: 12),
                _HeroStat(value: _videos == null ? '–' : '$violations', label: 'Without helmet', warn: violations > 0),
              ]),
            ]),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _record,
            icon: const Icon(Icons.videocam_rounded),
            label: const Text('Record video'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Upload from gallery'),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text('Up to 2 minutes · HD recording', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Recent', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final v in recent)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: VideoTile(
                  video: v,
                  onTap: () async {
                    await context.push('/results/${v.id}');
                    if (mounted) _load();
                  },
                ),
              ),
          ],
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.tips_and_updates_outlined, color: AppColors.warning, size: 20),
                  const SizedBox(width: 8),
                  Text('For the best accuracy', style: Theme.of(context).textTheme.titleSmall),
                ]),
                const SizedBox(height: 8),
                const Text('• Record in daylight or good light\n'
                    '• Keep people fully in the frame, not too far\n'
                    '• Hold the phone steady\n'
                    '• Tap the screen to focus on people'),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label, this.warn = false});
  final String value;
  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: TextStyle(
                  color: warn ? const Color(0xFFFFB4AB) : Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        ]),
      ),
    );
  }
}
