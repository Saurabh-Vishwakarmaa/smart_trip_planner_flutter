import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

typedef SpeechTextCallback = void Function(String text, bool isFinal);

class SpeechService with ChangeNotifier {
  final stt.SpeechToText _s2t = stt.SpeechToText();
  bool _available = false;
  bool _listening = false;
  String _initialText = '';

  bool get isAvailable => _available;
  bool get isListening => _listening;

  Future<void> init() async {
    _available = await _s2t.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          _listening = false;
          notifyListeners();
        }
      },
      onError: (e) {
        _listening = false;
        notifyListeners();
      },
    );
    notifyListeners();
  }

  Future<void> start({
    required String currentText,
    required SpeechTextCallback onText,
    String? localeId,
  }) async {
    if (!_available) await init();
    if (!_available) return;
    _initialText = currentText;
    _listening = true;
    notifyListeners();

    await _s2t.listen(
      localeId: localeId, // e.g. 'en_US' if you want to force
      listenMode: stt.ListenMode.dictation,
      onResult: (result) {
        final spoken = result.recognizedWords;
        final merged = (_initialText.trim().isEmpty)
            ? spoken
            : '${_initialText.trim()} ${spoken.trim()}'.trim();
        onText(merged, result.finalResult);
      },
      partialResults: true,
    );
  }

  Future<void> stop() async {
    if (_listening) {
      await _s2t.stop();
      _listening = false;
      notifyListeners();
    }
  }

  Future<void> cancel() async {
    if (_listening) {
      await _s2t.cancel();
      _listening = false;
      notifyListeners();
    }
  }

  Future<void> toggle({
    required String currentText,
    required SpeechTextCallback onText,
    String? localeId,
  }) async {
    if (_listening) {
      await stop();
    } else {
      await start(currentText: currentText, onText: onText, localeId: localeId);
    }
  }
}