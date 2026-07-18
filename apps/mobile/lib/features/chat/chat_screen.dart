import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../providers/auth_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _messages = <_Msg>[];
  bool _busy = false;

  final _chips = const [
    'Lost at Pamba?',
    'Return train number',
    'When is mala removal?',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask(String q) async {
    if (q.trim().isEmpty) return;
    setState(() {
      _messages.add(_Msg(q, true));
      _busy = true;
    });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.post('/chat/ask', body: {'question': q});
      final map = Map<String, dynamic>.from(res as Map);
      final answer = map['answer']?.toString() ?? '';
      final grounded = map['grounded'] == true;
      final citations = ((map['citations'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _messages.add(_Msg(
          answer,
          false,
          grounded: grounded,
          citations: citations,
        ));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _messages.add(_Msg(
            'Could not reach the guide. Try again when online, or ask a leader.',
            false,
            grounded: false,
          )));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sharanam;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Yatra guide')),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: _chips
                  .map(
                    (chip) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(chip),
                        onPressed: _busy ? null : () => _ask(chip),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? const EmptyState(
                    icon: Icons.chat_bubble_outline,
                    message: 'Ask about the yatra',
                    detail:
                        'Try a chip above — answers come from the trip document.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      return Align(
                        alignment: m.mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.85,
                          ),
                          decoration: BoxDecoration(
                            color: m.mine
                                ? c.passCard
                                : theme.colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(14),
                            border: m.mine
                                ? null
                                : Border.all(color: c.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.text,
                                style: TextStyle(
                                  color: m.mine ? c.onPassCard : null,
                                  fontSize: 16,
                                ),
                              ),
                              if (!m.mine) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      m.grounded
                                          ? Icons.verified_outlined
                                          : Icons.info_outline,
                                      size: 16,
                                      color: m.grounded
                                          ? c.success
                                          : theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      m.grounded
                                          ? 'Grounded in trip docs'
                                          : 'Not found in trip docs',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        color: m.grounded
                                            ? c.success
                                            : theme.colorScheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                if (m.citations.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  ...m.citations.map((cit) {
                                    final section =
                                        cit['source_section']?.toString();
                                    final title =
                                        cit['source_title']?.toString() ?? '';
                                    return Text(
                                      '• ${section == null || section.isEmpty ? title : '$section ($title)'}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: .6),
                                      ),
                                    );
                                  }),
                                ],
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_busy)
            const LinearProgressIndicator(minHeight: 2),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Ask about the yatra…',
                      ),
                      onSubmitted: _busy
                          ? null
                          : (v) {
                              _controller.clear();
                              _ask(v);
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _busy
                        ? null
                        : () {
                            final q = _controller.text;
                            _controller.clear();
                            _ask(q);
                          },
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Msg {
  _Msg(
    this.text,
    this.mine, {
    this.grounded = true,
    this.citations = const [],
  });
  final String text;
  final bool mine;
  final bool grounded;
  final List<Map<String, dynamic>> citations;
}
