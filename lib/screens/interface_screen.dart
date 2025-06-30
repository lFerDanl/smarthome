import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import '../provider/smart_home_provider.dart';
import '../models/tuya_device.dart';
import '../service/backend_api_service.dart';

class InterfaceScreen extends StatefulWidget {
  const InterfaceScreen({super.key});

  @override
  _InterfaceScreenState createState() => _InterfaceScreenState();
}

class _InterfaceScreenState extends State<InterfaceScreen> {
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

  final BackendApiService _apiService = BackendApiService();

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _flutterTts = FlutterTts();
    _initializeServices();

    // Cargar dispositivos si la lista está vacía
    final provider = Provider.of<SmartHomeProvider>(context, listen: false);
    if (provider.devices.isEmpty) {
      provider.loadDevices();
    }
  }

  Future<void> _initializeServices() async {
    try {
      // Inicializar servicios en paralelo
      await Future.wait([
        _initSpeech(),
        _initTts(),
      ]);
      
      // Inicializar acelerómetro después de que los servicios principales estén listos
      _initAccelerometer();
    } catch (e) {
      print('Error inicializando servicios: $e');
      setState(() {
        _speechEnabled = false;
      });
    }
  }

  Future<void> _initSpeech() async {
    try {
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
    } catch (e) {
      print('Error inicializando speech: $e');
      _speechEnabled = false;
      setState(() {});
    }
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage("es-ES");
      await _flutterTts.setSpeechRate(0.8);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
    } catch (e) {
      print('Error inicializando TTS: $e');
    }
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
      Map<String, dynamic> result = await _apiService.processGeminiCommand(userInput);
      setState(() {
        _isProcessing = false;
        _lastResponse = result['message'] as String;
        _recognizedText = '"$userInput"';
      });

      // Manejo de errores de Gemini
      if (result['type'] == 'error') {
        await _speak(result['message'] ?? 'Error al procesar el comando.');
        return;
      }

      // Ejecutar comando si es exitoso
      if (result['type'] == 'success' && result.containsKey('command')) {
        final command = result['command'] as Map<String, dynamic>;
        final String typeDevice = (command['type_device'] ?? '').toString().toLowerCase();
        final String deviceName = (command['device_name'] ?? '').toString().toLowerCase();
        final String action = (command['action'] ?? '').toString().toLowerCase();
        final Map<String, dynamic> parameters = command['parameters'] is Map<String, dynamic> ? command['parameters'] as Map<String, dynamic> : <String, dynamic>{};

        // Buscar dispositivos coincidentes
        final provider = Provider.of<SmartHomeProvider>(context, listen: false);
        final List<TuyaDevice> devices = provider.devices.where((d) =>
          isLightCategory(d.category) &&
          d.name.toLowerCase() == deviceName
        ).toList();

        if (devices.isEmpty) {
          await _speak('No se encontró ningún dispositivo "$deviceName" de tipo "$typeDevice".');
          setState(() {
            _lastResponse = 'No se encontró ningún dispositivo "$deviceName" de tipo "$typeDevice".';
          });
          return;
        }

        // Ejecutar acción para cada dispositivo
        for (final device in devices) {
          if (action == 'turn_on') {
            if (!device.isOn) await provider.toggleDevice(device);
          } else if (action == 'turn_off') {
            if (device.isOn) await provider.toggleDevice(device);
          } else if (action == 'set_brightness') {
            final int? brightness = int.tryParse(parameters['brightness']?.toString() ?? '');
            if (brightness != null) await provider.setBrightness(device, brightness);
          } else if (action == 'set_color') {
            final String? colorName = parameters['color']?.toString();
            if (colorName != null) {
              final color = _colorFromName(colorName);
              if (color != null) await provider.setColor(device, color);
            }
          } else if (action == 'set_color_temperature') {
            final int? temp = int.tryParse(parameters['color_temperature']?.toString() ?? '');
            if (temp != null) await provider.setColorTemperature(device, temp);
          }
        }
      }

      // Reproducir respuesta con TTS
      await _speak(result['message'] as String);

    } catch (e) {
      setState(() {
        _isProcessing = false;
        _lastResponse = 'Error al procesar el comando';
        _recognizedText = '"$userInput"';
      });
      await _speak('Error al procesar el comando. Intenta de nuevo.');
    }
  }

  // Utilidad para convertir nombre de color a Color
  Color? _colorFromName(String name) {
    switch (name.toLowerCase()) {
      case 'red': return Colors.red;
      case 'green': return Colors.green;
      case 'blue': return Colors.blue;
      case 'yellow': return Colors.yellow;
      case 'purple': return Colors.purple;
      case 'orange': return Colors.orange;
      case 'pink': return Colors.pink;
      case 'cyan': return Colors.cyan;
      case 'lime': return Colors.lime;
      case 'indigo': return Colors.indigo;
      case 'white': return Colors.white;
      default: return null;
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

  // Métodos de debug para controlar el foco del dormitorio
  Future<void> _debugTurnOnDormitorio() async {
    try {
      final provider = Provider.of<SmartHomeProvider>(context, listen: false);
      
      // Buscar el dispositivo "dormitorio"
      final List<TuyaDevice> dormitorioDevices = provider.devices.where((d) =>
        d.name.toLowerCase() == 'dormitorio' && isLightCategory(d.category)
      ).toList();

      if (dormitorioDevices.isEmpty) {
        await _speak('No se encontró el foco del dormitorio');
        setState(() {
          _lastResponse = 'Error: No se encontró el foco del dormitorio';
        });
        return;
      }

      // Encender el primer dispositivo encontrado
      final device = dormitorioDevices.first;
      if (!device.isOn) {
        await provider.toggleDevice(device);
        await _speak('Foco del dormitorio encendido');
        setState(() {
          _lastResponse = '✅ Foco del dormitorio encendido';
        });
      } else {
        await _speak('El foco del dormitorio ya está encendido');
        setState(() {
          _lastResponse = 'ℹ️ El foco del dormitorio ya está encendido';
        });
      }
    } catch (e) {
      await _speak('Error al encender el foco del dormitorio');
      setState(() {
        _lastResponse = '❌ Error al encender el foco del dormitorio: $e';
      });
    }
  }

  Future<void> _debugTurnOffDormitorio() async {
    try {
      final provider = Provider.of<SmartHomeProvider>(context, listen: false);
      
      // Buscar el dispositivo "dormitorio"
      final List<TuyaDevice> dormitorioDevices = provider.devices.where((d) =>
        d.name.toLowerCase() == 'dormitorio' && isLightCategory(d.category)
      ).toList();

      if (dormitorioDevices.isEmpty) {
        await _speak('No se encontró el foco del dormitorio');
        setState(() {
          _lastResponse = 'Error: No se encontró el foco del dormitorio';
        });
        return;
      }

      // Apagar el primer dispositivo encontrado
      final device = dormitorioDevices.first;
      if (device.isOn) {
        await provider.toggleDevice(device);
        await _speak('Foco del dormitorio apagado');
        setState(() {
          _lastResponse = '✅ Foco del dormitorio apagado';
        });
      } else {
        await _speak('El foco del dormitorio ya está apagado');
        setState(() {
          _lastResponse = 'ℹ️ El foco del dormitorio ya está apagado';
        });
      }
    } catch (e) {
      await _speak('Error al apagar el foco del dormitorio');
      setState(() {
        _lastResponse = '❌ Error al apagar el foco del dormitorio: $e';
      });
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
        title: Text('Interfaz de Voz'),
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
              
              // Botones de Debug para el foco del dormitorio
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange, width: 1),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.bug_report, color: Colors.orange, size: 20),
                        SizedBox(width: 10),
                        Text(
                          'Debug - Foco Dormitorio',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _debugTurnOnDormitorio(),
                          icon: Icon(Icons.lightbulb, color: Colors.white),
                          label: Text('Encender'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _debugTurnOffDormitorio(),
                          icon: Icon(Icons.lightbulb_outline, color: Colors.white),
                          label: Text('Apagar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
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
                      onPressed: _initializeServices,
                      child: Text('Reiniciar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool isLightCategory(String category) {
    final c = category.toLowerCase();
    return c == 'light' || c == 'dj' || c == 'dj_light';
  }
}