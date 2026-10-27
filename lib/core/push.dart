import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api.dart';
import 'auth_state.dart';

/// CCTV alert notifications (Firebase Cloud Messaging). Only admin accounts get them: the server rejects other roles.
/// While the app is closed or in the background Android shows the notification by itself; this class shows it
/// while the app is open and keeps the phone's token registered on the server.
class PushService {
  PushService(this._api, this._auth);

  final Api _api;
  final AuthState _auth;
  final _local = FlutterLocalNotificationsPlugin();
  String? _registeredToken;

  static const _channel = AndroidNotificationChannel(
    'cctv_alerts',
    'CCTV alerts',
    description: 'A rider without a helmet was seen on a camera',
    importance: Importance.high,
  );

  Future<void> start() async {
    try {
      await _local.initialize(
          settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.instance.onTokenRefresh.listen((t) => _register(t));
      _auth.onBeforeLogout = _unregister;
      _auth.addListener(_sync);
      await _sync();
    } catch (e) {
      debugPrint('push: setup failed: ${e.runtimeType}');   // the app must work without push
    }
  }

  Future<void> _sync() async {
    if (!_auth.isLoggedIn || !_auth.isAdmin) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _register(token);
    } catch (e) {
      debugPrint('push: token failed: ${e.runtimeType}');
    }
  }

  Future<void> _register(String token) async {
    if (!_auth.isLoggedIn || !_auth.isAdmin || token == _registeredToken) return;
    try {
      await _api.registerDevice(token);
      _registeredToken = token;
    } on ApiException {
      // offline or not an admin: tried again the next time the app opens or signs in
    }
  }

  Future<void> _unregister() async {
    final token = _registeredToken;
    if (token == null) return;
    _registeredToken = null;
    try {
      await _api.unregisterDevice(token);
    } on ApiException {
      // the server drops dead tokens by itself
    }
  }

  void _showForeground(RemoteMessage m) {
    final n = m.notification;
    if (n == null) return;
    _local.show(
      id: m.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(_channel.id, _channel.name,
            channelDescription: _channel.description, importance: Importance.high, priority: Priority.high),
      ),
    );
  }
}
