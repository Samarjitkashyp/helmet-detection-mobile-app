import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

class AuthState extends ChangeNotifier {
  AuthState(this.api, this._prefs) {
    token = _prefs.getString('token');
    role = _prefs.getString('role');
    onboarded = _prefs.getBool('onboarded') ?? false;
    api.token = token;
    api.onUnauthorized = () => logout();
  }

  final Api api;
  final SharedPreferences _prefs;
  String? token;
  String? role; // 'admin' accounts also see the CCTV alerts tab
  bool onboarded = false;

  bool get isLoggedIn => token != null;
  bool get isAdmin => role == 'admin';

  Future<void> finishOnboarding() async {
    onboarded = true;
    await _prefs.setBool('onboarded', true);
    notifyListeners();
  }

  Future<void> _setToken(String? t, [String? r]) async {
    token = t;
    role = t == null ? null : r;
    api.token = t;
    if (t == null) {
      await _prefs.remove('token');
      await _prefs.remove('role');
    } else {
      await _prefs.setString('token', t);
      if (r != null) await _prefs.setString('role', r);
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final r = await api.login(email.trim().toLowerCase(), password);
    await _setToken(r.token, r.role);
  }

  /// Sessions opened by an older app version have no stored role: ask the server once.
  Future<void> ensureRole() async {
    if (token == null || role != null) return;
    try {
      role = await api.myRole();
      await _prefs.setString('role', role!);
      notifyListeners();
    } on ApiException {
      // offline: the Alerts tab simply appears the next time the app can reach the server
    }
  }

  Future<void> register(String name, String email, String password) async {
    await api.register(name.trim(), email.trim().toLowerCase(), password);
    await login(email, password);
  }

  Future<void> logout() => _setToken(null);
}
