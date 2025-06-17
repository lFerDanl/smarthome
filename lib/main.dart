import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:async';
import 'dart:math';

void main() {
  runApp(VoiceApp());
}

class VoiceApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control por Voz',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.blueAccent,
      ),
      home: VoiceHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class VoiceHome extends StatefulWidget {
  @override
  _VoiceHomeState createState() => _VoiceHomeState();
}

class _VoiceHomeState extends State<VoiceHome> {
  late stt.SpeechToText _speech;
  late FlutterTts _flutterTts;
  bool _isListening = false;
  bool _speechEnabled = false;
  String _recognizedText = 'Di un comando...';
  String _completeText = ''; // Para acumular todo el texto reconocido
  
  // Para detectar movimiento
  late StreamSubscription<AccelerometerEvent> _accelerometerSubscription;
  double _shakeThreshold = 15.0; // Umbral para detectar movimiento brusco
  DateTime _lastShakeTime = DateTime.now();
  
  // Timer para manejar el silencio
  Timer? _silenceTimer;
  bool _hasSpokenSomething = false;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _flutterTts = FlutterTts();
    _initSpeech();
    _initTts();
    _initAccelerometer();
  }

  void _initSpeech() async {
    _speechEnabled = await _speech.initialize(
      onStatus: (status) {
        print('Estado: $status');
        if (status == 'done' || status == 'notListening') {
          _handleListeningEnd();
        }
      },
      onError: (error) {
        print('Error: $error');
        _handleListeningEnd();
      },
    );
    setState(() {});
  }

  void _initTts() async {
    await _flutterTts.setLanguage("es-ES");
    await _flutterTts.setSpeechRate(0.8);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  void _initAccelerometer() {
    _accelerometerSubscription = accelerometerEvents.listen(
      (AccelerometerEvent event) {
        _detectShake(event);
      },
    );
  }

  void _detectShake(AccelerometerEvent event) {
    double acceleration = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    
    if (acceleration > _shakeThreshold) {
      DateTime now = DateTime.now();
      if (now.difference(_lastShakeTime).inMilliseconds > 1000) { // Evitar activaciones múltiples
        _lastShakeTime = now;
        if (_speechEnabled && !_isListening) {
          _activateVoiceWithMessage();
        }
      }
    }
  }

  void _activateVoiceWithMessage() async {
    // Primero reproducir el mensaje
    await _speak("¿Qué deseas realizar?");
    
    // Esperar un momento después del mensaje para iniciar la captura
    await Future.delayed(Duration(milliseconds: 500));
    
    // Ahora iniciar la escucha
    _startListening();
  }

  void _startListening() {
    if (!_isListening && _speechEnabled) {
      setState(() {
        _isListening = true;
        _completeText = '';
        _recognizedText = 'Escuchando...';
        _hasSpokenSomething = false;
      });
      
      _cancelSilenceTimer();
      _listenContinuously();
    }
  }

  void _listenContinuously() async {
    if (!_isListening) return;
    
    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          _handleSpeechResult(result);
        },
        listenFor: Duration(minutes: 10), // Tiempo máximo
        pauseFor: Duration(seconds: 5), // Pausa de 5 segundos
        partialResults: true,
        localeId: "es_ES",
        cancelOnError: false,
        listenMode: stt.ListenMode.confirmation,
      );
    } catch (e) {
      print('Error al escuchar: $e');
      _handleListeningEnd();
    }
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
    if (!_isListening) return;
    
    String currentWords = result.recognizedWords;
    
    if (currentWords.isNotEmpty) {
      _hasSpokenSomething = true;
      _cancelSilenceTimer();
      
      setState(() {
        _recognizedText = currentWords;
      });
      
      // Si es resultado final, agregarlo al texto completo
      if (result.finalResult) {
        if (_completeText.isNotEmpty && !_completeText.endsWith(' ')) {
          _completeText += ' ';
        }
        _completeText += currentWords;
        
        // Reiniciar la escucha para continuar
        Future.delayed(Duration(milliseconds: 100), () {
          if (_isListening) {
            _listenContinuously();
          }
        });
      }
      
      // Iniciar timer de silencio
      _startSilenceTimer();
    }
  }

  void _startSilenceTimer() {
    _cancelSilenceTimer();
    _silenceTimer = Timer(Duration(seconds: 5), () {
      if (_isListening && _hasSpokenSomething) {
        _finishListening();
      }
    });
  }

  void _cancelSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
  }

  void _finishListening() {
    _cancelSilenceTimer();
    
    if (_isListening) {
      setState(() {
        _isListening = false;
        if (_completeText.isNotEmpty) {
          _recognizedText = _completeText;
        } else if (_recognizedText.isEmpty || _recognizedText == 'Escuchando...') {
          _recognizedText = 'No se detectó voz';
        }
      });
      
      _speech.stop();
      
      // Reproducir el texto completo si hay contenido
      if (_completeText.isNotEmpty) {
        _speak(_completeText);
      }
    }
  }

  void _handleListeningEnd() {
    if (_isListening) {
      // Si se terminó la sesión actual pero aún estamos en modo escucha,
      // intentar continuar
      if (_hasSpokenSomething) {
        Future.delayed(Duration(milliseconds: 200), () {
          if (_isListening) {
            _listenContinuously();
          }
        });
      } else {
        _finishListening();
      }
    }
  }

  void _listen() async {
    if (_isListening) {
      // Si ya está escuchando, detener
      _finishListening();
    } else {
      // Iniciar escucha directamente (sin mensaje de voz)
      _startListening();
    }
  }

  Future<void> _speak(String text) async {
    if (text.isNotEmpty) {
      await _flutterTts.speak(text);
    }
  }

  @override
  void dispose() {
    _cancelSilenceTimer();
    _accelerometerSubscription.cancel();
    _flutterTts.stop();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Control por Voz'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 60,
                color: Colors.amber,
              ),
              SizedBox(height: 30),
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: _isListening ? Colors.red : Colors.blueAccent,
                    width: 2,
                  ),
                ),
                child: Text(
                  _recognizedText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    color: Colors.white70,
                    height: 1.3,
                  ),
                ),
              ),
              SizedBox(height: 20),
              // Indicador de estado
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _speechEnabled 
                    ? (_isListening ? Colors.red.withOpacity(0.2) : Colors.green.withOpacity(0.2))
                    : Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _speechEnabled 
                    ? (_isListening ? '🎙️ Escuchando... (5s de silencio para finalizar)' : '📱 Agita el teléfono o toca el micrófono')
                    : '❌ Reconocimiento no disponible',
                  style: TextStyle(
                    color: _speechEnabled 
                      ? (_isListening ? Colors.red : Colors.green)
                      : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: 50),
              GestureDetector(
                onTap: _speechEnabled ? _listen : null,
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 200),
                  child: CircleAvatar(
                    backgroundColor: _speechEnabled 
                      ? (_isListening ? Colors.red : Colors.blueAccent)
                      : Colors.grey,
                    radius: 40,
                    child: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20),
              // Botón para reproducir texto
              if (_recognizedText != 'Di un comando...' && 
                  _recognizedText != 'Escuchando...' && 
                  _recognizedText.isNotEmpty &&
                  _recognizedText != 'No se detectó voz')
                ElevatedButton.icon(
                  onPressed: () => _speak(_recognizedText),
                  icon: Icon(Icons.volume_up),
                  label: Text('Repetir'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                ),
              if (!_speechEnabled) ...[
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _initSpeech,
                  child: Text('Reintentar Inicialización'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}