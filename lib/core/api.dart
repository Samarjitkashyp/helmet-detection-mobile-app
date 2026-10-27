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

/// Where an interrupted chunked upload stands, kept by the screen so "Try again" can continue it.
class UploadSession {
  String? id;
  int chunkSize = 2 * 1024 * 1024;
  int offset = 0;

  void reset() {
    id = null;
    offset = 0;
  }
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

  /// Signs in and returns the access token together with the account's role (`admin` or `user`).
  Future<({String token, String role})> login(String email, String password) => _guard(() async {
        final r = await _dio.post('/auth/login', data: {'email': email, 'password': password});
        return (token: r.data['access_token'] as String, role: (r.data['role'] as String?) ?? 'user');
      });

  /// The signed-in account's role, for sessions that were opened before the app remembered it.
  Future<String> myRole() => _guard(() async {
        final r = await _dio.get('/auth/me');
        return (r.data['role'] as String?) ?? 'user';
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
  ///
  /// Pass the same [session] again after a failure and the upload continues where it stopped instead of
  /// starting over; [onStatus] reports retries so the screen can say the connection is slow.
  Future<VideoItem> uploadVideoChunked(
    String path,
    String filename,
    void Function(double) onProgress, {
    UploadSession? session,
    void Function(String?)? onStatus,
  }) =>
      _guard(() async {
        final s = session ?? UploadSession();
        final file = File(path);
        final total = await file.length();

        if (s.id != null) {
          // continue an interrupted upload, but never past what the server has really received
          try {
            final st = await _dio.get('/videos/uploads/${s.id}');
            s.offset = min(s.offset, (st.data['received'] as num).toInt());
          } on DioException catch (e) {
            if (e.response?.statusCode != 404) rethrow;
            s.reset(); // the server forgot it (e.g. it was idle too long): start again
          }
        }
        if (s.id == null) {
          final init = await _dio.post('/videos/uploads', data: {'filename': filename, 'size': total});
          s.id = init.data['upload_id'] as String;
          s.chunkSize = init.data['chunk_size'] as int;
          s.offset = 0;
        }

        final reader = await file.open();
        try {
          while (s.offset < total) {
            final len = min(s.chunkSize, total - s.offset);
            await reader.setPosition(s.offset);
            final bytes = await reader.read(len);
            await _putChunk(s.id!, s.offset, bytes, onStatus);
            s.offset += len;
            onStatus?.call(null);
            onProgress(s.offset / total);
          }
        } finally {
          await reader.close();
        }
        final done = await _dio.post('/videos/uploads/${s.id}/complete');
        s.reset();
        return VideoItem.fromJson(done.data as Map<String, dynamic>);
      });

  /// Sends one piece, retrying network drops and server/proxy errors (5xx, including Cloudflare 52x).
  Future<void> _putChunk(String uploadId, int offset, Uint8List bytes, void Function(String?)? onStatus) async {
    const maxAttempts = 6;
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
        onStatus?.call('Weak connection, retrying ($attempt/${maxAttempts - 1})…');
        await Future<void>.delayed(Duration(seconds: min(8, 1 << (attempt - 1)))); // 1, 2, 4, 8, 8 s
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

  // ---- CCTV alerts (admin accounts only) ----

  /// Newest first. [sinceId] returns only newer events (for polling), [beforeId] pages back in time.
  Future<List<CctvEvent>> cctvEvents({int sinceId = 0, int beforeId = 0, int limit = 30}) => _guard(() async {
        final r = await _dio.get('/cctv/events', queryParameters: {
          if (sinceId > 0) 'since_id': sinceId,
          if (beforeId > 0) 'before_id': beforeId,
          'limit': limit,
        });
        return (r.data as List).map((e) => CctvEvent.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<CctvStatus> cctvStatus() => _guard(() async {
        final r = await _dio.get('/cctv/status');
        return CctvStatus.fromJson(r.data as Map<String, dynamic>);
      });

  /// Phone push token (Firebase). Admin accounts only; the server keeps one row per token.
  Future<void> registerDevice(String token) => _guard(() async {
        await _dio.post('/cctv/devices', data: {'token': token});
      });

  Future<void> unregisterDevice(String token) => _guard(() async {
        await _dio.delete('/cctv/devices', data: {'token': token});
      });

  /// Marks an alert as a mistake (or undoes that); returns the new state.
  Future<bool> toggleCctvFalsePositive(int id) => _guard(() async {
        final r = await _dio.post('/cctv/events/$id/false-positive');
        return r.data['is_false_positive'] as bool;
      });
}
