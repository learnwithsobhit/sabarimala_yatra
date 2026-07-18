import 'package:flutter_test/flutter_test.dart';
import 'package:swamy_sharanam/core/voice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoiceService', () {
    test('degrades gracefully when speech plugins are unavailable', () async {
      final voice = VoiceService();
      await voice.init();

      // No platform channels are registered in the test harness, so the
      // recognizer initialization fails and the mic must be reported as
      // unsupported rather than throwing.
      expect(voice.initialized, isTrue);
      expect(voice.sttSupported, isFalse);
      expect(voice.availableInputLangs(), isEmpty);
      expect(voice.isListening, isFalse);
      expect(voice.isSpeaking, isFalse);

      // Speaking/listening are safe no-ops when unsupported.
      final started =
          await voice.listen(lang: VoiceLang.english, onResult: (_, __) {});
      expect(started, isFalse);
      await voice.speak('hello', VoiceLang.english);
      await voice.dispose();
    });

    test('exposes the three target languages with distinct codes', () {
      final codes = VoiceLang.values.map((l) => l.code).toSet();
      expect(codes, containsAll(<String>{'en', 'hi', 'kn'}));
      expect(codes.length, VoiceLang.values.length);
    });
  });
}
