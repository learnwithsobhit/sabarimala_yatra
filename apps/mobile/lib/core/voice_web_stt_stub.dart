/// Non-web stub for the browser speech recognizer.
class WebSpeechStt {
  bool get isListening => false;

  bool start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
    void Function()? onDone,
    void Function(String error)? onError,
  }) =>
      false;

  void stop() {}

  void abort() {}
}
