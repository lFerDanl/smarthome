import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:math';
import 'dart:convert';

void main() {
  runApp(VoiceApp());
}

class VoiceApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Home Voice Control',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.blueAccent,
      ),
      home: VoiceHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}



class GeminiService {
  static const String apiKey = 'TU-API-KEY'; // Reemplaza con tu API key
  static const String baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent'; 

  static Future<Map<String, dynamic>> processCommand(String userInput) async {
    String prompt = '''
Eres un asistente de smart home que debe analizar comandos de voz y responder en formato JSON.

Analiza este comando: "$userInput"

DISPOSITIVOS DISPONIBLES:
1. foco_sala (light): Foco inteligente de la sala
   - Acciones: turn_on, turn_off, set_brightness, set_color, set_temperature
   - Parámetros: brightness (0-100), color (red, green, blue, white, etc), temperature (2700-6500K)

2. termostato_principal (thermostat): Termostato principal
   - Acciones: turn_on, turn_off, set_temperature, set_mode, set_fan_speed
   - Parámetros: temperature (16-30°C), mode (auto, cool, heat), fan_speed (low, medium, high)

3. persiana_dormitorio (blind): Persiana del dormitorio
   - Acciones: turn_on (abrir), turn_off (cerrar), set_position
   - Parámetros: position (0-100, donde 0=cerrada, 100=abierta)

CASOS DE RESPUESTA:
1. Si el mensaje no tiene sentido o no está relacionado con smart home:
   {"type": "error", "message": "Comando no comprendido. Por favor, di un comando relacionado con el control del hogar."}

2. Si hay intención de smart home pero la función no existe:
   {"type": "error", "message": "Esa función no está disponible en esta aplicación."}

3. Si el comando es válido:
   {"type": "success", "message": "MENSAJE", "command": {"device_id": "ID_DISPOSITIVO", "action": "ACCION", "parameters": {"key": "value"}}}

INSTRUCCIONES ESPECIALES
- Para el MENSAJE coloca la intención del usuario en forma de ejecutado por ejemplo, prende la luz : mensaje -> se ha prendido la luz.

Responde SOLO con el JSON, sin texto adicional.
''';

    try {
      final response = await http.post(
        Uri.parse('$baseUrl?key=$apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text': prompt
                }
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.1,
            'topK': 1,
            'topP': 1,
            'maxOutputTokens': 2048,
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String responseText = data['candidates'][0]['content']['parts'][0]['text'];
        
        // Limpiar la respuesta para extraer solo el JSON
        responseText = responseText.trim();
        if (responseText.startsWith('```json')) {
          responseText = responseText.substring(7);
        }
        if (responseText.endsWith('```')) {
          responseText = responseText.substring(0, responseText.length - 3);
        }
        
        return jsonDecode(responseText);
      } else {
        throw Exception('Error en la API: ${response.statusCode}');
      }
    } catch (e) {
      print('Error procesando comando: $e');
      return {
        'type': 'error',
        'message': 'Error al procesar el comando. Intenta de nuevo.',
      };
    }
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
  bool _isProcessing = false;
  String _recognizedText = 'Di un comando...';
  String _completeText = '';
  String _lastResponse = '';
  
  // Para detectar movimiento
  late StreamSubscription<AccelerometerEvent> _accelerometerSubscription;
  double _shakeThreshold = 15.0;
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
      if (now.difference(_lastShakeTime).inMilliseconds > 1000) {
        _lastShakeTime = now;
        if (_speechEnabled && !_isListening && !_isProcessing) {
          _activateVoiceWithMessage();
        }
      }
    }
  }

  void _activateVoiceWithMessage() async {
    await _speak("¿Qué deseas realizar?");
    await Future.delayed(Duration(milliseconds: 500));
    _startListening();
  }

  void _startListening() {
    if (!_isListening && _speechEnabled && !_isProcessing) {
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
        listenFor: Duration(minutes: 10),
        pauseFor: Duration(seconds: 5),
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
      
      if (result.finalResult) {
        if (_completeText.isNotEmpty && !_completeText.endsWith(' ')) {
          _completeText += ' ';
        }
        _completeText += currentWords;
        
        Future.delayed(Duration(milliseconds: 100), () {
          if (_isListening) {
            _listenContinuously();
          }
        });
      }
      
      _startSilenceTimer();
    }
  }

  void _startSilenceTimer() {
    _cancelSilenceTimer();
    _silenceTimer = Timer(Duration(seconds: 3), () {
      if (_isListening && _hasSpokenSomething) {
        _finishListening();
      }
    });
  }

  void _cancelSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
  }

  void _finishListening() async {
    _cancelSilenceTimer();
    
    if (_isListening) {
      setState(() {
        _isListening = false;
        _isProcessing = true;
        if (_completeText.isNotEmpty) {
          _recognizedText = _completeText;
        } else if (_recognizedText.isEmpty || _recognizedText == 'Escuchando...') {
          _recognizedText = 'No se detectó voz';
          _isProcessing = false;
          return;
        }
      });
      
      _speech.stop();
      
      // Procesar comando con Gemini
      if (_completeText.isNotEmpty) {
        await _processWithGemini(_completeText);
      }
    }
  }

  Future<void> _processWithGemini(String userInput) async {
    setState(() {
      _recognizedText = 'Procesando comando...';
    });

    try {
      Map<String, dynamic> result = await GeminiService.processCommand(userInput);
      
      setState(() {
        _isProcessing = false;
        _lastResponse = result['message'];
        _recognizedText = '"$userInput"';
      });

      // Ejecutar comando si es exitoso
      if (result['type'] == 'success' && result.containsKey('command')) {
        // Aquí más adelante se implementará la lógica para controlar dispositivos reales
        print('Comando a ejecutar: ${result['command']}');
      }

      // Reproducir respuesta con TTS
      await _speak(result['message']);
      
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _lastResponse = 'Error al procesar el comando';
        _recognizedText = '"$userInput"';
      });
      
      await _speak('Error al procesar el comando. Intenta de nuevo.');
    }
  }

  void _handleListeningEnd() {
    if (_isListening) {
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
      _finishListening();
    } else if (!_isProcessing) {
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
        title: Text('Smart Home Control'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              SizedBox(height: 30),
              // Icono principal
              Icon(
                Icons.home_outlined,
                size: 60,
                color: Colors.blueAccent,
              ),
              SizedBox(height: 30),
              
              // Texto reconocido
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: _isListening ? Colors.red : (_isProcessing ? Colors.orange : Colors.blueAccent),
                    width: 2,
                  ),
                ),
                child: Text(
                  _recognizedText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.white70,
                    height: 1.3,
                  ),
                ),
              ),
              
              // Respuesta de Gemini
              if (_lastResponse.isNotEmpty) ...[
                SizedBox(height: 15),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _lastResponse,
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              SizedBox(height: 20),
              
              // Indicador de estado
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _speechEnabled 
                    ? (_isListening ? Colors.red.withOpacity(0.2) : 
                       (_isProcessing ? Colors.orange.withOpacity(0.2) : Colors.green.withOpacity(0.2)))
                    : Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Text(
                  _speechEnabled 
                    ? (_isListening ? '🎙️ Escuchando... (3s de silencio para finalizar)' : 
                       (_isProcessing ? '🤖 Procesando con Gemini...' : '📱 Agita el teléfono o toca el micrófono'))
                    : '❌ Reconocimiento no disponible',
                  style: TextStyle(
                    color: _speechEnabled 
                      ? (_isListening ? Colors.red : 
                         (_isProcessing ? Colors.orange : Colors.green))
                      : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              
              SizedBox(height: 40),
              
              // Botón de micrófono
              GestureDetector(
                onTap: _speechEnabled ? _listen : null,
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 200),
                  child: CircleAvatar(
                    backgroundColor: _speechEnabled 
                      ? (_isListening ? Colors.red : 
                         (_isProcessing ? Colors.orange : Colors.blueAccent))
                      : Colors.grey,
                    radius: 40,
                    child: Icon(
                      _isListening ? Icons.mic : (_isProcessing ? Icons.sync : Icons.mic_none),
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              
              SizedBox(height: 20),
              
              // Botones adicionales
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (_lastResponse.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: () => _speak(_lastResponse),
                      icon: Icon(Icons.volume_up),
                      label: Text('Repetir'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                  if (!_speechEnabled)
                    ElevatedButton(
                      onPressed: _initSpeech,
                      child: Text('Reiniciar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                      ),
                    ),
                ],
              ),
              
              SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}