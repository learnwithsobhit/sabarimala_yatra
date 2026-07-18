import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Branded landing screen shown briefly on launch, then routes onward
/// (go_router redirect decides login vs home based on auth).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 2400), _continue);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _continue() {
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF7A1F12),
      body: GestureDetector(
        onTap: _continue,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/branding/ayyappa_splash_hero.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, __, ___) => const ColoredBox(
                color: Color(0xFF7A1F12),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC3D0F08)],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Swamy Sharanam',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        shadows: const [
                          Shadow(blurRadius: 14, color: Colors.black54),
                        ],
                      ),
                    ).animate().fadeIn(duration: 700.ms).slideY(
                          begin: .25,
                          end: 0,
                          curve: Curves.easeOut,
                        ),
                    const SizedBox(height: 10),
                    Text(
                      'Swamiye Sharanam Ayyappa',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white.withValues(alpha: .92),
                        letterSpacing: .3,
                        shadows: const [
                          Shadow(blurRadius: 10, color: Colors.black54),
                        ],
                      ),
                    ).animate().fadeIn(delay: 350.ms, duration: 700.ms),
                    const SizedBox(height: 28),
                    const SizedBox(
                      height: 26,
                      width: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    ).animate().fadeIn(delay: 700.ms),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
