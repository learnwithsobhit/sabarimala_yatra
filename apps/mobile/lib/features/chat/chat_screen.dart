import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../core/voice_service.dart';
import '../../core/widgets/widgets.dart';
import '../../providers/auth_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  static const _cacheKey = 'yatra_guide_messages_v1';
  static const _langKey = 'yatra_guide_voice_lang_v1';
  static const _speakKey = 'yatra_guide_voice_speak_v1';
  final _controller = TextEditingController();
  final _messages = <_Msg>[];
  bool _busy = false;

  final _voice = VoiceService();
  bool _voiceReady = false;
  bool _listening = false;
  bool _speakAnswers = true;
  List<VoiceLang> _inputLangs = const [];
  VoiceLang _lang = VoiceLang.english;

  final _chips = const [
    'Lost at Pamba?',
    'Lost at Sannidhanam?',
    'Outbound train 16315',
    'Return train number',
    'When is mala removal?',
    'Today’s schedule',
    'Packing checklist',
    'Guruvayur Seeveli',
    'Nilakkal to Pampa',
    'Emergency contacts',
  ];

  static const _offlineFaqs = <String, ({String answer, String section})>{
    'Lost at Pamba?': (
      answer:
          'Going up: wait near the start of the steps at Pamba Ganapathy, just before Virtual Q / Aadhaar check. Returning: wait near the Indian Oil petrol bunk. Network is often BSNL-only.',
      section: 'What to do if you are lost',
    ),
    'Lost at Sannidhanam?': (
      answer:
          'Wait in front of the Holy 18 Steps if you are below the main temple, or near the Melshanthi room if you are on top. Tell a volunteer; do not wander alone.',
      section: 'What to do if you are lost',
    ),
    'Outbound train 16315': (
      answer:
          'Outbound train is 16315 KOCHUVELI EXP, depart ~16:35 on 15 Aug; arrive Thrissur ~02:50 on 16 Aug.',
      section: '15th August',
    ),
    'Return train number': (
      answer:
          'Return train is 16316 KCVL MYS EXP from Cherthala (~19:40 on 19 Aug) arriving Bengaluru SBC (~08:25 on 20 Aug).',
      section: '19th August',
    ),
    'When is mala removal?': (
      answer:
          'Mala should be removed at the same place it was worn after returning. Plan includes mala removal on 20 Aug after reaching Bengaluru (Ravindra’s House), unless you wore it at a temple near home.',
      section: '20th August',
    ),
    'Today’s schedule': (
      answer:
          'Open the Plan tab for today’s stops. Key days: 15 Aug assemble & train; 16 Thrissur/Guruvayur; 17 Pampa climb; 18 abhishekam & descend; 19 Chengannur circuit & return train; 20 Bengaluru mala removal.',
      section: 'Itinerary overview',
    ),
    'Packing checklist': (
      answer:
          'Carry ID, black clothes, shawl, torch, medicines, water bottle, and irumudi items as listed in the packing checklist in More → Packing. Do not store Aadhaar photos in the app.',
      section: 'Packing',
    ),
    'Guruvayur Seeveli': (
      answer:
          'Guruvayur Seeveli is on the Thrissur/Guruvayur day (16 Aug). Stay with your bus group; rendezvous at the temple gate if separated.',
      section: '16th August',
    ),
    'Nilakkal to Pampa': (
      answer:
          'From Nilakkal, buses/trek continue toward Pampa before the climb. Keep your count Present marks before each departure. Network may drop — download the trip pack on Wi‑Fi first.',
      section: '17th August',
    ),
    'Emergency contacts': (
      answer:
          'Use Home SOS / If lost for rendezvous points. Call your bus volunteer or leader from the roster. Prefer the PDF lost-person points over wandering.',
      section: 'Safety',
    ),
  };

  @override
  void initState() {
    super.initState();
    _loadCachedMessages();
    _initVoice();
  }

  Future<void> _initVoice() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      await _voice.init();
    } catch (_) {
      // Voice engines are best-effort; still mark ready so the mic can appear
      // when the browser claims speech support.
    }
    if (!mounted) return;
    final inputLangs = _voice.availableInputLangs();
    final savedCode = prefs?.getString(_langKey);
    final saved = VoiceLang.values.where((l) => l.code == savedCode);
    setState(() {
      _voiceReady = true;
      _inputLangs = inputLangs;
      _speakAnswers = prefs?.getBool(_speakKey) ?? true;
      if (saved.isNotEmpty && inputLangs.contains(saved.first)) {
        _lang = saved.first;
      } else if (inputLangs.isNotEmpty) {
        _lang = inputLangs.first;
      }
    });
  }

  Future<void> _loadCachedMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_cacheKey);
    if (encoded == null || !mounted) return;
    try {
      final raw = jsonDecode(encoded) as List<dynamic>;
      setState(() {
        if (_messages.isNotEmpty) return;
        _messages
          ..clear()
          ..addAll(
            raw.map(
              (item) => _Msg.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            ),
          );
      });
    } catch (_) {
      await prefs.remove(_cacheKey);
    }
  }

  Future<void> _saveCachedMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final recent = _messages.length <= 40
        ? _messages
        : _messages.sublist(_messages.length - 40);
    await prefs.setString(
      _cacheKey,
      jsonEncode(recent.map((message) => message.toJson()).toList()),
    );
  }

  @override
  void dispose() {
    _voice.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _voice.stopListening();
      if (mounted) setState(() => _listening = false);
      return;
    }
    await _voice.stopSpeaking();
    setState(() => _listening = true);
    final started = await _voice.listen(
      lang: _lang,
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() => _controller.text = text);
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
        if (isFinal && text.trim().isNotEmpty) {
          final q = text;
          _controller.clear();
          _ask(q);
        }
      },
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!started && mounted) {
      setState(() => _listening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Voice input is not available in this browser. Allow the microphone, or type your question.',
          ),
        ),
      );
    }
  }

  Future<void> _setLang(VoiceLang lang) async {
    setState(() => _lang = lang);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langKey, lang.code);
  }

  Future<void> _toggleSpeak() async {
    final next = !_speakAnswers;
    setState(() => _speakAnswers = next);
    if (!next) await _voice.stopSpeaking();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_speakKey, next);
  }

  Future<void> _ask(String q) async {
    if (q.trim().isEmpty) return;
    await _voice.stopSpeaking();
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
      await _saveCachedMessages();
      _maybeSpeak(answer);
    } catch (_) {
      final offline = _offlineFaqs[q.trim()];
      if (!mounted) return;
      if (offline != null) {
        setState(() => _messages.add(_Msg(
              offline.answer,
              false,
              grounded: true,
              citations: [
                {
                  'source_title': 'Shabarimala2026_Aug15-20.pdf',
                  'source_section': offline.section,
                },
              ],
            )));
        await _saveCachedMessages();
        _maybeSpeak(offline.answer);
      } else {
        setState(() => _messages.add(_Msg(
              'Could not reach the guide. Try a chip above offline, or ask a leader when online.',
              false,
              grounded: false,
            )));
        await _saveCachedMessages();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _maybeSpeak(String text) {
    if (_speakAnswers && _voiceReady) _voice.speak(text, _lang);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sharanam;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yatra guide'),
        actions: [
          if (_voiceReady && _voice.ttsSupported)
            IconButton(
              tooltip: _speakAnswers
                  ? 'Read answers aloud: on'
                  : 'Read answers aloud: off',
              onPressed: _toggleSpeak,
              icon: Icon(
                _speakAnswers ? Icons.volume_up : Icons.volume_off,
              ),
            ),
          if (_voiceReady && _inputLangs.length > 1)
            PopupMenuButton<VoiceLang>(
              tooltip: 'Voice language',
              initialValue: _lang,
              onSelected: _setLang,
              icon: const Icon(Icons.language),
              itemBuilder: (context) => _inputLangs
                  .map(
                    (lang) => PopupMenuItem<VoiceLang>(
                      value: lang,
                      child: Row(
                        children: [
                          if (lang == _lang)
                            const Icon(Icons.check, size: 18)
                          else
                            const SizedBox(width: 18),
                          const SizedBox(width: 8),
                          Text(lang.label),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
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
                ? EmptyState(
                    icon: Icons.chat_bubble_outline,
                    message: 'Ask about the yatra',
                    detail: _voiceReady && _voice.sttSupported
                        ? 'Try a chip above, type, or tap the mic to ask by voice — answers come from the trip document.'
                        : 'Try a chip above — answers come from the trip document.',
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
                                    Expanded(
                                      child: Text(
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
                                    ),
                                    if (_voiceReady && _voice.ttsSupported)
                                      InkWell(
                                        onTap: () =>
                                            _voice.speak(m.text, _lang),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        child: Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: Icon(
                                            Icons.volume_up_outlined,
                                            size: 18,
                                            semanticLabel: 'Read answer aloud',
                                            color: theme.colorScheme.primary,
                                          ),
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
                  if (_voiceReady && _voice.sttSupported) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: _listening ? 'Stop listening' : 'Ask by voice',
                      onPressed: _busy ? null : _toggleListening,
                      icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                      // The theme's ColorScheme doesn't define
                      // secondaryContainer, so filledTonal would fall back to
                      // charcoal-on-charcoal; set explicit colors instead.
                      style: IconButton.styleFrom(
                        backgroundColor: _listening
                            ? theme.colorScheme.error
                            : theme.colorScheme.primaryContainer,
                        foregroundColor: _listening
                            ? theme.colorScheme.onError
                            : theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
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

  factory _Msg.fromJson(Map<String, dynamic> json) => _Msg(
        json['text']?.toString() ?? '',
        json['mine'] == true,
        grounded: json['grounded'] == true,
        citations: ((json['citations'] as List?) ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'mine': mine,
        'grounded': grounded,
        'citations': citations,
      };
}
