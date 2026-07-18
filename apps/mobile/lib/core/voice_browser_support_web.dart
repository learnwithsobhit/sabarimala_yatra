import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('window')
external JSObject get _window;

/// Direct browser feature detect for the Web Speech API.
///
/// Prefer this over relying solely on SpeechToText.initialize, which can
/// return false on some HTTPS origins even when Chrome exposes the API.
bool browserClaimsSpeechSupport() {
  try {
    return _window.has('webkitSpeechRecognition') ||
        _window.has('SpeechRecognition');
  } catch (_) {
    return false;
  }
}
