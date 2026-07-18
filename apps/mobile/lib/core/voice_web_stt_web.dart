import 'dart:js_interop';

import 'package:web/web.dart' as web;

// Same workaround as speech_to_text: Chrome exposes webkitSpeechRecognition,
// and constructing SpeechRecognition() directly can fail in release builds.
@JS('webkitSpeechRecognition')
extension type _WebkitSpeechRecognition._(web.SpeechRecognition _)
    implements web.SpeechRecognition {
  external factory _WebkitSpeechRecognition();
}

/// Minimal Web Speech API wrapper used when the speech_to_text plugin fails to
/// initialize on a given origin (observed on Firebase Hosting).
class WebSpeechStt {
  web.SpeechRecognition? _rec;
  bool _listening = false;

  bool get isListening => _listening;

  bool start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
    void Function()? onDone,
    void Function(String error)? onError,
  }) {
    try {
      final rec = _WebkitSpeechRecognition();
      _rec = rec;
      rec.lang = localeId.replaceAll('_', '-');
      rec.interimResults = true;
      rec.continuous = false;
      rec.maxAlternatives = 1;

      rec.onresult = (web.SpeechRecognitionEvent event) {
        final results = event.results;
        final buf = StringBuffer();
        var isFinal = false;
        for (var i = 0; i < results.length; i++) {
          final result = results.item(i);
          if (result.length > 0) {
            buf.write(result.item(0).transcript);
          }
          if (result.isFinal) isFinal = true;
        }
        onResult(buf.toString(), isFinal);
      }.toJS;

      rec.onerror = (web.SpeechRecognitionErrorEvent event) {
        _listening = false;
        onError?.call(event.error);
        onDone?.call();
      }.toJS;

      rec.onend = (web.Event _) {
        _listening = false;
        onDone?.call();
      }.toJS;

      rec.start();
      _listening = true;
      return true;
    } catch (_) {
      _listening = false;
      _rec = null;
      return false;
    }
  }

  void stop() {
    try {
      _rec?.stop();
    } catch (_) {
      // ignore
    }
    _listening = false;
  }

  void abort() {
    try {
      _rec?.abort();
    } catch (_) {
      // ignore
    }
    _listening = false;
    _rec = null;
  }
}
