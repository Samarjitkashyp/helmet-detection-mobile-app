import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/api.dart';
import 'core/auth_state.dart';
import 'core/push.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('firebase: ${e.runtimeType}');   // push is optional: the app works without it
  }
  final prefs = await SharedPreferences.getInstance();
  final api = Api(prefs);
  final auth = AuthState(api, prefs);
  unawaited(PushService(api, auth).start());
  runApp(MultiProvider(
    providers: [
      Provider<Api>.value(value: api),
      ChangeNotifierProvider<AuthState>.value(value: auth),
    ],
    child: const HelmetApp(),
  ));
}
