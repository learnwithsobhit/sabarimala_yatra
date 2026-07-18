import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/widgets.dart';
import '../../providers/auth_provider.dart';

class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  int _rating = 5;
  final _lessons = TextEditingController();
  String? _error;
  String? _saved;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _lessons.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/feedback');
      if (res is Map && res.isNotEmpty) {
        _rating = (res['rating'] as num?)?.toInt() ?? 5;
        _lessons.text = res['lessons']?.toString() ?? '';
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _saved = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/feedback', body: {
        'rating': _rating,
        'lessons': _lessons.text.trim(),
      });
      setState(() => _saved = 'Thank you — lessons saved for next year.');
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feedback')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                const ScreenHeader(
                  title: 'Lessons for next year',
                  subtitle: 'Share what worked and what to improve',
                ),
                if (_error != null) ...[
                  StatusBanner(kind: StatusBannerKind.danger, message: _error!),
                  const SizedBox(height: 12),
                ],
                if (_saved != null) ...[
                  StatusBanner(
                    kind: StatusBannerKind.success,
                    message: _saved!,
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  'How was this yatra?',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Slider(
                  value: _rating.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '$_rating',
                  onChanged: (v) => setState(() => _rating = v.round()),
                ),
                TextField(
                  controller: _lessons,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Lessons / notes',
                    hintText: 'More water stops at Nilakkal…',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _save,
                  child: const Text('Save feedback'),
                ),
              ],
            ),
    );
  }
}
