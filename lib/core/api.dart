import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Talks to the FastAPI backend. The server address is editable in the app because a real phone
/// needs the PC's LAN IP, while the Android emulator uses 10.0.2.2.
class Api {
  Api(this._prefs) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
    ));
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final t = token;
      if (t != null) options.headers['Authorization'] = 'Bearer $t';
      handler.next(options);
    }));
  }

  /// The live server. Override for local development with
  /// `flutter run --dart-define=API_URL=http://10.0.2.2:8000` (emulator) or the "Server address" dialog.
  static const defaultBaseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://helmet-detection.aiaxom.co.in');

  final SharedPreferences _prefs;
  late final Dio _dio;
  String? token;
  void Function()? onUnauthorized;

  String get baseUrl => _prefs.getString('base_url') ?? defaultBaseUrl;

  Future<void> setBaseUrl(String url) async {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    await _prefs.setString('base_url', u);
    _dio.options.baseUrl = u;
  }

  Future<void> resetBaseUrl() async {
    await _prefs.remove('base_url');
    _dio.options.baseUrl = defaultBaseUrl;
  }

  Map<String, String> get authHeaders => {if (token != null) 'Authorization': 'Bearer $token'};

  String absoluteUrl(String path) => '$baseUrl$path';

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 && token != null) onUnauthorized?.call();
      throw ApiException(_message(e), statusCode: code);
    }
  }

  String _message(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] != null) {
      final d = data['detail'];
      if (d is String) return d;
      if (d is List && d.isNotEmpty && d.first is Map) {
        final m = (d.first as Map)['msg']?.toString() ?? 'Invalid input';
        return m.replaceFirst('Value error, ', '');
      }
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
        return 'Cannot reach the server at $baseUrl. Check the server address and that the backend is running.';
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'The server took too long to respond.';
      default:
        final code = e.response?.statusCode;
        if (code == 413) return 'The video is too large. The limit is 95 MB.';
        if (code != null && code >= 500) return 'The server had a problem ($code). Please try again in a minute.';
        return 'Something went wrong (${code ?? 'no response'}).';
    }
  }

  Future<String> login(String email, String password) => _guard(() async {
        final r = await _dio.post('/auth/login', data: {'email': email, 'password': password});
        return r.data['access_token'] as String;
      });

  Future<void> register(String name, String email, String password) => _guard(() async {
        await _dio.post('/auth/register', data: {'name': name, 'email': email, 'password': password});
      });

  Future<VideoItem> uploadVideo(String path, String filename, void Function(double) onProgress) => _guard(() async {
        final form = FormData.fromMap({'file': await MultipartFile.fromFile(path, filename: filename)});
        final r = await _dio.post(
          '/videos',
          data: form,
          options: Options(sendTimeout: null),
          onSendProgress: (sent, total) {
            if (total > 0) onProgress(sent / total);
          },
        );
        return VideoItem.fromJson(r.data as Map<String, dynamic>);
      });

  /// Uploads a video in small pieces. A single long request gets cut off by Cloudflare (error 524) on slow
  /// mobile connections, while small pieces finish quickly and each one can be retried on its own.
  Future<VideoItem> uploadVideoChunked(String path, String filename, void Function(double) onProgress) =>
      _guard(() async {
        final file = File(path);
        final total = await file.length();
        final init = await _dio.post('/videos/uploads', data: {'filename': filename, 'size': total});
        final uploadId = init.data['upload_id'] as String;
        final chunkSize = init.data['chunk_size'] as int;

        final reader = await file.open();
        try {
          var offset = 0;
          while (offset < total) {
            final len = min(chunkSize, total - offset);
            await reader.setPosition(offset);
            final bytes = await reader.read(len);
            await _putChunk(uploadId, offset, bytes);
            offset += len;
            onProgress(offset / total);
          }
        } finally {
          await reader.close();
        }
        final done = await _dio.post('/videos/uploads/$uploadId/complete');
        return VideoItem.fromJson(done.data as Map<String, dynamic>);
      });

  /// Sends one piece, retrying network drops and server/proxy errors (5xx, including Cloudflare 52x).
  Future<void> _putChunk(String uploadId, int offset, Uint8List bytes) async {
    const maxAttempts = 5;
    for (var attempt = 1;; attempt++) {
      try {
        await _dio.put(
          '/videos/uploads/$uploadId',
          queryParameters: {'offset': offset},
          data: bytes,
          options: Options(
            contentType: 'application/octet-stream',
            sendTimeout: const Duration(seconds: 45), // a stalled piece is retried sooner
            receiveTimeout: const Duration(seconds: 60),
          ),
        );
        return;
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        final retryable = code == null || code >= 500 || code == 408 || code == 429;
        if (!retryable || attempt >= maxAttempts) rethrow;
        await Future<void>.delayed(Duration(seconds: 1 << (attempt - 1))); // 1, 2, 4, 8 s
      }
    }
  }

  Future<List<VideoItem>> listVideos() => _guard(() async {
        final r = await _dio.get('/videos');
        return (r.data as List).map((e) => VideoItem.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<VideoItem> videoStatus(int id) => _guard(() async {
        final r = await _dio.get('/videos/$id/status');
        return VideoItem.fromJson(r.data as Map<String, dynamic>);
      });

  Future<VideoResults> videoResults(int id) => _guard(() async {
        final r = await _dio.get('/videos/$id/results');
        return VideoResults.fromJson(r.data as Map<String, dynamic>);
      });

  /// Downloads a protected file (e.g. a detection photo) given its server path like `/videos/1/detections/2/image`.
  Future<List<int>> downloadBytes(String path) => _guard(() async {
        final r = await _dio.get<List<int>>(path, options: Options(responseType: ResponseType.bytes));
        return r.data!;
      });

  /// Version, size and input size of the on-device detection model offered by the server.
  Future<Map<String, dynamic>> liveModelInfo() => _guard(() async {
        final r = await _dio.get('/app/live-model/info');
        return Map<String, dynamic>.from(r.data as Map);
      });

  Future<void> downloadFile(String path, String savePath, void Function(double) onProgress) => _guard(() async {
        await _dio.download(
          path,
          savePath,
          onReceiveProgress: (got, total) {
            if (total > 0) onProgress(got / total);
          },
          options: Options(receiveTimeout: const Duration(minutes: 3)),
        );
      });

  Future<void> deleteVideo(int id) => _guard(() async {
        await _dio.delete('/videos/$id');
      });
}
