import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/present_sync.dart';
import 'core/push_bootstrap.dart';
import 'providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: _Bootstrap()));
}

class _Bootstrap extends ConsumerStatefulWidget {
  const _Bootstrap();

  @override
  ConsumerState<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends ConsumerState<_Bootstrap>
    with WidgetsBindingObserver {
  final _present = PresentSync();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final api = ref.read(apiClientProvider);
      PushBootstrap(api).start();
      _flushPresentQueue();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _flushPresentQueue();
    }
  }

  Future<void> _flushPresentQueue() async {
    try {
      await _present.flush(ref.read(apiClientProvider));
    } catch (_) {
      // Keep queued; next resume/refresh will retry with backoff.
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SwamySharanamApp();
  }
}
