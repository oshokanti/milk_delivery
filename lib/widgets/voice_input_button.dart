import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceInputButton extends StatefulWidget {
  final Function(String) onResult;
  final String? hint;
  final Color? buttonColor;

  const VoiceInputButton({
    super.key,
    required this.onResult,
    this.hint,
    this.buttonColor,
  });

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _text = '';

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    await _speech.initialize(
      onStatus: (status) {
        print('Speech status: $status');
        if (status == 'notListening' && _isListening) {
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        print('Speech error: $error');
        setState(() => _isListening = false);
      },
    );
  }

  void _startListening() async {
    if (!_speech.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition not available'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isListening = true);

    try {
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _text = result.recognizedWords;
          });
          if (result.finalResult) {
            widget.onResult(_text);
            setState(() => _isListening = false);
          }
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 2),
        partialResults: true,
        onSoundLevelChange: (level) {
          // Optional: visual feedback for sound level
        },
      );
    } catch (e) {
      print('Error: $e');
      setState(() => _isListening = false);
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _isListening ? Icons.mic : Icons.mic_none,
        color: _isListening ? Colors.red : (widget.buttonColor ?? Colors.blue),
      ),
      onPressed: _isListening ? _stopListening : _startListening,
      tooltip: _isListening ? 'Stop listening' : 'Speak quantity',
    );
  }
}