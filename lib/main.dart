import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/api.dart';
import 'core/auth_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final api = Api(prefs);
  final auth = AuthState(api, prefs);
  runApp(MultiProvider(
    providers: [
      Provider<Api>.value(value: api),
      ChangeNotifierProvider<AuthState>.value(value: auth),
    ],
    child: const HelmetApp(),
  ));
}
