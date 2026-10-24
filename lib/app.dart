import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'core/auth_state.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/record_screen.dart';
import 'screens/results_screen.dart';
import 'screens/upload_screen.dart';
import 'screens/welcome_screen.dart';

class HelmetApp extends StatefulWidget {
  const HelmetApp({super.key});

  @override
  State<HelmetApp> createState() => _HelmetAppState();
}

class _HelmetAppState extends State<HelmetApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthState>();
    _router = GoRouter(
      initialLocation: '/',
      refreshListenable: auth,
      redirect: (context, state) {
        final loc = state.matchedLocation;
        if (!auth.onboarded) return loc == '/welcome' ? null : '/welcome';
        if (!auth.isLoggedIn) return loc == '/login' ? null : '/login';
        if (loc == '/login' || loc == '/welcome') return '/';
        return null;
      },
      routes: [
        GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(path: '/', builder: (_, _) => const HomeShell()),
        GoRoute(path: '/record', builder: (_, _) => const RecordScreen()),
        GoRoute(
          path: '/upload',
          builder: (_, state) => UploadScreen(path: state.extra as String),
        ),
        GoRoute(
          path: '/results/:id',
          builder: (_, state) => ResultsScreen(videoId: int.parse(state.pathParameters['id']!)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Helmet Check',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}
