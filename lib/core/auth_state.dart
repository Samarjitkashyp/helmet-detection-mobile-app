import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

class AuthState extends ChangeNotifier {
  AuthState(this.api, this._prefs) {
    token = _prefs.getString('token');
    onboarded = _prefs.getBool('onboarded') ?? false;
    api.token = token;
    api.onUnauthorized = () => logout();
  }

  final Api api;
  final SharedPreferences _prefs;
  String? token;
  bool onboarded = false;

  bool get isLoggedIn => token != null;

  Future<void> finishOnboarding() async {
    onboarded = true;
    await _prefs.setBool('onboarded', true);
    notifyListeners();
  }

  Future<void> _setToken(String? t) async {
    token = t;
    api.token = t;
    if (t == null) {
      await _prefs.remove('token');
    } else {
      await _prefs.setString('token', t);
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final t = await api.login(email.trim().toLowerCase(), password);
    await _setToken(t);
  }

  Future<void> register(String name, String email, String password) async {
    await api.register(name.trim(), email.trim().toLowerCase(), password);
    await login(email, password);
  }

  Future<void> logout() => _setToken(null);
}
