import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Languages the Ask Guide voice feature targets. Actual availability is
/// resolved per-platform at runtime (see [VoiceService]).
enum VoiceLang {
  english('en', 'English', 'en-IN', 'en_IN'),
  hindi('hi', 'हिंदी', 'hi-IN', 'hi_IN'),
  kannada('kn', 'ಕನ್ನಡ', 'kn-IN', 'kn_IN');

  const VoiceLang(this.code, this.label, this.ttsLanguage, this.sttLocaleId);

  /// ISO-639 language prefix (e.g. `en`).
  final String code;

  /// Human-readable label for the picker.
  final String label;

  /// Preferred BCP-47 tag passed to text-to-speech.
  final String ttsLanguage;

  /// Preferred locale id passed to speech-to-text.
  final String sttLocaleId;
}

/// Cross-platform wrapper around [SpeechToText] (mic input) and [FlutterTts]
/// (spoken answers). Keeps all platform branching in one place so widgets can
/// stay thin. Works on Android, iOS and (best-effort) web; when a platform or
/// browser lacks speech support, [sttSupported] is false and callers should
/// hide the mic.
class VoiceService {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _initialized = false;
  bool _sttAvailable = false;
  bool _speaking = false;

  List<String> _sttLocaleIds = const [];
  List<String> _ttsLanguages = const [];

  void Function()? _onListenDone;

  bool get initialized => _initialized;

  /// Whether speech-to-text (the mic) can be used on this device/browser.
  bool get sttSupported => _sttAvailable;

  /// Whether text-to-speech reported at least one usable language.
  bool get ttsSupported => _ttsLanguages.isNotEmpty;

  bool get isListening => _speech.isListening;

  bool get isSpeaking => _speaking;

  /// Initializes both engines and probes available locales. Safe to call more
  /// than once; only the first call does work. Never throws.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _sttAvailable = await _speech.initialize(
        onError: (e) => _onListenDone?.call(),
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _onListenDone?.call();
          }
        },
      );
    } catch (_) {
      _sttAvailable = false;
    }

    if (_sttAvailable) {
      try {
        final locales = await _speech.locales();
        _sttLocaleIds = locales.map((l) => l.localeId).toList();
      } catch (_) {
        _sttLocaleIds = const [];
      }
    }

    // Browsers (notably Chrome) populate speechSynthesis voices
    // asynchronously, so the first query often returns empty. Retry briefly
    // before concluding TTS is unavailable.
    for (var attempt = 0; attempt < 6 && _ttsLanguages.isEmpty; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      try {
        final langs = await _tts.getLanguages;
        if (langs is List) {
          _ttsLanguages = langs.map((e) => e.toString()).toList();
        }
      } catch (_) {
        break;
      }
    }

    try {
      _tts.setCompletionHandler(() => _speaking = false);
      _tts.setCancelHandler(() => _speaking = false);
      _tts.setErrorHandler((_) => _speaking = false);
    } catch (_) {
      // Handlers are best-effort; failures shouldn't block init.
    }
  }

  /// Input languages the current platform can transcribe.
  List<VoiceLang> availableInputLangs() {
    if (!_sttAvailable) return const [];
    if (_sttLocaleIds.isEmpty) {
      // Some platforms (notably web) don't enumerate locales; assume the
      // browser/OS default handles at least English.
      return const [VoiceLang.english];
    }
    return VoiceLang.values
        .where((lang) => _matchLocaleId(lang) != null)
        .toList();
  }

  /// Output languages the current platform can speak.
  List<VoiceLang> availableOutputLangs() {
    if (_ttsLanguages.isEmpty) return const [VoiceLang.english];
    return VoiceLang.values
        .where((lang) => _matchTtsLanguage(lang) != null)
        .toList();
  }

  String? _matchLocaleId(VoiceLang lang) {
    for (final id in _sttLocaleIds) {
      if (_normalize(id).startsWith(lang.code)) return id;
    }
    return null;
  }

  String? _matchTtsLanguage(VoiceLang lang) {
    for (final code in _ttsLanguages) {
      if (_normalize(code).startsWith(lang.code)) return code;
    }
    return null;
  }

  String _normalize(String tag) => tag.toLowerCase().replaceAll('_', '-');

  /// Starts listening. [onResult] streams partial and final transcripts;
  /// [onDone] fires when the engine stops (silence, timeout, or error).
  Future<void> listen({
    required VoiceLang lang,
    required void Function(String text, bool isFinal) onResult,
    void Function()? onDone,
    void Function(double level)? onLevel,
  }) async {
    if (!_sttAvailable) return;
    _onListenDone = onDone;
    await _speech.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      onSoundLevelChange: onLevel,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        localeId: _matchLocaleId(lang) ?? lang.sttLocaleId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> stopListening() async {
    if (_speech.isListening) await _speech.stop();
  }

  Future<void> cancel() async {
    if (_speech.isListening) await _speech.cancel();
  }

  /// Speaks [text] in [lang]. Silently no-ops if the language is unavailable.
  Future<void> speak(String text, VoiceLang lang) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final language = _matchTtsLanguage(lang);
    if (language == null) return;
    await stopSpeaking();
    try {
      await _tts.setLanguage(language);
      _speaking = true;
      await _tts.speak(trimmed);
    } catch (_) {
      _speaking = false;
    }
  }

  Future<void> stopSpeaking() async {
    if (!_speaking) return;
    try {
      await _tts.stop();
    } catch (_) {
      // ignore
    }
    _speaking = false;
  }

  Future<void> dispose() async {
    _onListenDone = null;
    await cancel();
    await stopSpeaking();
  }
}
