import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/limits.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key, required this.path});
  final String path;

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  double _progress = 0;
  bool _uploading = false;
  String? _error;

  late final int _bytes = _fileBytes();

  String get _name => widget.path.split(RegExp(r'[\\/]')).last;

  int _fileBytes() {
    try {
      return File(widget.path).lengthSync();
    } catch (_) {
      return 0;
    }
  }

  String get _size => _bytes == 0 ? '' : '${(_bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  bool get _tooBig => _bytes > maxUploadMb * 1024 * 1024;

  Future<void> _upload() async {
    final api = context.read<Api>();
    setState(() {
      _uploading = true;
      _error = null;
      _progress = 0;
    });
    try {
      final video = await api.uploadVideo(widget.path, _name, (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (mounted) context.pushReplacement('/results/${video.id}');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analyze video')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.movie, size: 36),
                  title: Text(_name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_size),
                ),
              ),
              const SizedBox(height: 24),
              if (_uploading) ...[
                LinearProgressIndicator(value: _progress == 0 ? null : _progress, minHeight: 8),
                const SizedBox(height: 8),
                Text('Uploading... ${(_progress * 100).toStringAsFixed(0)}%', textAlign: TextAlign.center),
              ] else
                FilledButton.icon(
                  onPressed: _tooBig ? null : _upload,
                  icon: const Icon(Icons.cloud_upload),
                  label: Text(_error == null ? 'Analyze' : 'Try again'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                ),
              if (_tooBig) ...[
                const SizedBox(height: 16),
                Text(
                  'This video is $_size. The limit is $maxUploadMb MB. '
                  'Record it in the app (it uses a smaller size automatically) or pick a shorter video.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
