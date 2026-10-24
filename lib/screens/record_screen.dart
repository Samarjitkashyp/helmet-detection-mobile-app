import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_theme.dart';
import '../core/limits.dart';

/// In-app camera: 1080p / 30 fps, tap-to-focus, pinch zoom, torch, 2-minute limit.
/// Pops with the recorded file path.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> with WidgetsBindingObserver {
  static const maxSeconds = 120;
  static const _lowLightLuma = 70; // mean brightness (0-255) under which we suggest the torch

  CameraController? _controller;
  String? _error;
  bool _recording = false;
  bool _torch = false;
  bool _lowLight = false;
  int _seconds = 0;
  Timer? _timer;
  double _zoom = 1, _baseZoom = 1, _minZoom = 1, _maxZoom = 1;
  DateTime _lastLuma = DateTime.fromMillisecondsSinceEpoch(0);
  String _quality = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive && !_recording) {
      final c = _controller;
      _controller = null;
      c?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _controller == null && !_recording) {
      _init();
    }
  }

  Future<CameraController> _open(CameraDescription cam, ResolutionPreset preset) async {
    final c = CameraController(
      cam,
      preset,
      enableAudio: false, // no sound needed: smaller files and no microphone permission
      fps: 30,
      videoBitrate: recordVideoBitrate,
    );
    await c.initialize();
    return c;
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('none', 'No camera found on this device');
      final cam = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      CameraController c;
      try {
        c = await _open(cam, ResolutionPreset.veryHigh); // 1080p
        _quality = '1080p';
      } on CameraException {
        c = await _open(cam, ResolutionPreset.high); // 720p fallback
        _quality = '720p';
      }
      _minZoom = await c.getMinZoomLevel();
      _maxZoom = await c.getMaxZoomLevel();
      _zoom = _minZoom;
      await c.setFocusMode(FocusMode.auto);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _error = null;
      });
      _watchLight(c);
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'CameraAccessDenied'
            ? 'Camera permission is off. Allow it in phone Settings > Apps > Helmet Check.'
            : 'Could not start the camera (${e.description ?? e.code}).');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start the camera: $e');
    }
  }

  /// Samples the live preview about once a second (only before recording) to warn about low light.
  void _watchLight(CameraController c) {
    c.startImageStream((image) {
      final now = DateTime.now();
      if (now.difference(_lastLuma).inMilliseconds < 1000) return;
      _lastLuma = now;
      final y = image.planes.first.bytes;
      var sum = 0, n = 0;
      for (var i = 0; i < y.length; i += 97) {
        sum += y[i];
        n++;
      }
      final dark = n > 0 && sum / n < _lowLightLuma;
      if (mounted && dark != _lowLight) setState(() => _lowLight = dark);
    }).catchError((_) {}); // some devices cannot stream; the hint is optional
  }

  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      setState(() => _torch = !_torch);
    } catch (_) {}
  }

  Future<void> _start() async {
    final c = _controller;
    if (c == null || _recording) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      await c.startVideoRecording();
      setState(() {
        _recording = true;
        _seconds = 0;
        _lowLight = false;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        setState(() => _seconds++);
        if (_seconds >= maxSeconds) _stop();
      });
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start recording: ${e.description}')));
      }
    }
  }

  Future<void> _stop() async {
    final c = _controller;
    if (c == null || !_recording) return;
    _timer?.cancel();
    try {
      final file = await c.stopVideoRecording();
      if (_torch) await c.setFlashMode(FlashMode.off);
      setState(() => _recording = false);
      if (_seconds < 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Too short. Record at least a few seconds.')));
        }
        _watchLight(c);
        return;
      }
      if (mounted) context.pop(file.path);
    } on CameraException catch (e) {
      setState(() => _recording = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Recording failed: ${e.description}')));
      }
    }
  }

  Future<void> _focusAt(TapUpDetails d, BoxConstraints box) async {
    final c = _controller;
    if (c == null) return;
    final p = Offset(d.localPosition.dx / box.maxWidth, d.localPosition.dy / box.maxHeight);
    try {
      await c.setFocusPoint(p);
      await c.setExposurePoint(p);
    } catch (_) {}
  }

  String get _clock {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: _error != null
          ? _errorView()
          : c == null || !c.value.isInitialized
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : _cameraView(c),
    );
  }

  Widget _errorView() => SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.no_photography, color: Colors.white70, size: 56),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 20),
              FilledButton(onPressed: _init, child: const Text('Try again')),
              TextButton(onPressed: () => context.pop(), child: const Text('Close')),
            ]),
          ),
        ),
      );

  Widget _cameraView(CameraController c) {
    return Stack(fit: StackFit.expand, children: [
      Center(
        child: LayoutBuilder(builder: (context, box) {
          return GestureDetector(
            onTapUp: (d) => _focusAt(d, box),
            onScaleStart: (_) => _baseZoom = _zoom,
            onScaleUpdate: (d) {
              final z = (_baseZoom * d.scale).clamp(_minZoom, _maxZoom);
              if ((z - _zoom).abs() > 0.02) {
                _zoom = z;
                c.setZoomLevel(z);
                setState(() {});
              }
            },
            child: CameraPreview(c),
          );
        }),
      ),
      SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(children: [
              IconButton(
                onPressed: _recording ? null : () => context.pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
              const Spacer(),
              _Pill(text: _quality),
              if (_zoom > _minZoom + 0.05) _Pill(text: '${_zoom.toStringAsFixed(1)}x'),
              IconButton(
                tooltip: 'Torch',
                onPressed: _toggleTorch,
                icon: Icon(_torch ? Icons.flash_on : Icons.flash_off, color: _torch ? Colors.amber : Colors.white),
              ),
            ]),
          ),
          if (_recording)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _Pill(
                text: '$_clock / 02:00',
                leading: const Icon(Icons.fiber_manual_record, color: AppColors.danger, size: 14),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 24, right: 24),
              child: Column(children: [
                const _Pill(text: 'Hold steady · keep people fully in frame · tap to focus'),
                if (_lowLight) ...[
                  const SizedBox(height: 8),
                  _Pill(
                    text: 'Too dark. Turn on the torch or move to better light.',
                    color: AppColors.warning.withValues(alpha: 0.92),
                    leading: const Icon(Icons.wb_twilight, color: Colors.white, size: 16),
                  ),
                ],
              ]),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: GestureDetector(
              onTap: _recording ? _stop : _start,
              child: Container(
                width: 78,
                height: 78,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(_recording ? 10 : 40),
                  ),
                  margin: EdgeInsets.all(_recording ? 14 : 0),
                ),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.leading, this.color});
  final String text;
  final Widget? leading;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color ?? Colors.black54, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (leading != null) ...[leading!, const SizedBox(width: 6)],
        Flexible(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12.5))),
      ]),
    );
  }
}
