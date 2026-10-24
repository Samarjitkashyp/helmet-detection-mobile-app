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

  Future<void> deleteVideo(int id) => _guard(() async {
        await _dio.delete('/videos/$id');
      });
}
