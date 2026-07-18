import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';

import '../../core/theme.dart';
import '../../core/widgets/status_banner.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _hint;
  String? _localError;
  bool _otpSent = false;
  bool _submitting = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _onPrimaryPressed() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _localError = null;
    });

    try {
      final auth = ref.read(authProvider);
      if (!_otpSent) {
        final hint = await auth.requestOtp(_phone.text.trim());
        if (!mounted) return;
        if (auth.lastError != null) {
          setState(
            () => _localError =
                'Could not send OTP. Check the phone is on the roster.',
          );
          return;
        }
        setState(() {
          _otpSent = true;
          _hint = hint;
        });
        if (hint != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(hint)),
          );
        }
      } else {
        final ok = await auth.verifyOtp(_phone.text.trim(), _code.text.trim());
        if (!mounted) return;
        if (!ok) {
          setState(
            () => _localError = 'Incorrect or expired OTP. Try again.',
          );
          return;
        }
        context.go('/home');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _localError = 'Something went wrong. Check network and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.sharanam;
    final error = _localError ?? ref.watch(authProvider).lastError;
    final scaffoldBg = theme.scaffoldBackgroundColor;
    final pinTheme = PinTheme(
      width: 48,
      height: 56,
      textStyle: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
    );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scaffoldBg,
              scaffoldBg,
              theme.colorScheme.primary.withValues(alpha: .22),
              c.gold.withValues(alpha: .18),
            ],
            stops: const [0, .45, .8, 1],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  Icon(Icons.temple_hindu_outlined, size: 52, color: c.gold)
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .scale(begin: const Offset(.9, .9)),
                  const SizedBox(height: 14),
                  Text(
                    'Swamy Sharanam',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sabarimala yatra companion\nSwamiye Sharanam Ayyappa',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .75),
                    ),
                  ),
                  const SizedBox(height: 36),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.border),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(alpha: .12),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _otpSent ? 'Enter the OTP' : 'Sign in',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          enabled: !_submitting && !_otpSent,
                          decoration: const InputDecoration(
                            labelText: 'Phone number',
                            prefixIcon: Icon(Icons.phone_outlined),
                            helperText: 'Use your rostered mobile number',
                          ),
                        ),
                        if (_otpSent) ...[
                          const SizedBox(height: 18),
                          Pinput(
                            controller: _code,
                            length: 6,
                            enabled: !_submitting,
                            defaultPinTheme: pinTheme,
                            focusedPinTheme: pinTheme.copyWith(
                              decoration: pinTheme.decoration!.copyWith(
                                border: Border.all(
                                  color: theme.colorScheme.primary,
                                  width: 1.6,
                                ),
                              ),
                            ),
                            onCompleted: (_) => _onPrimaryPressed(),
                          ),
                        ],
                        if (_hint != null) ...[
                          const SizedBox(height: 12),
                          StatusBanner(
                            kind: StatusBannerKind.info,
                            message: _hint!,
                          ),
                        ],
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          StatusBanner(
                            kind: StatusBannerKind.danger,
                            message: error,
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _submitting ? null : _onPrimaryPressed,
                          child: _submitting
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(_otpSent ? 'Enter yatra' : 'Send OTP'),
                        ),
                        if (_otpSent) ...[
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: _submitting
                                ? null
                                : () => setState(() {
                                      _otpSent = false;
                                      _hint = null;
                                      _localError = null;
                                      _code.clear();
                                    }),
                            child: const Text('Use a different phone'),
                          ),
                        ],
                      ],
                    ),
                  ).animate().fadeIn(delay: 100.ms).slideY(begin: .04, end: 0),
                  const SizedBox(height: 20),
                  Text(
                    'Roster-only login. Ask the leader if your phone is not registered.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
