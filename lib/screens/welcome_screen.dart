import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth_state.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    (
      Icons.health_and_safety_rounded,
      'Helmet safety, checked by AI',
      'Record a short video and Helmet Check finds every person who is not wearing a helmet.',
    ),
    (
      Icons.videocam_rounded,
      'Record it the right way',
      'Use good light, hold the phone steady, and keep people clearly in the frame. Closer and brighter means more accurate.',
    ),
    (
      Icons.fact_check_rounded,
      'Clear results with proof',
      'See who is safe and who is not, with a photo and the exact time for each person.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _pages.length - 1) {
      context.read<AuthState>().finishOnboarding();
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = _page == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: last ? null : () => context.read<AuthState>().finishOnboarding(),
                child: Text(last ? '' : 'Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final (icon, title, body) = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                          child: Icon(icon, size: 76, color: scheme.primary),
                        ),
                        const SizedBox(height: 40),
                        Text(title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 14),
                        Text(body,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.all(4),
                    width: i == _page ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? scheme.primary : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: FilledButton(onPressed: _next, child: Text(last ? 'Get started' : 'Next')),
            ),
          ],
        ),
      ),
    );
  }
}
