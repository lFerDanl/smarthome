import 'package:flutter/material.dart';
import '../service/hybrid_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../service/backend_api_service.dart';
import 'package:provider/provider.dart';
import '../provider/smart_home_provider.dart';
import '../models/tuya_device.dart';
import 'dart:async';

class ServiceControlScreen extends StatefulWidget {
  const ServiceControlScreen({Key? key}) : super(key: key);

  @override
  State<ServiceControlScreen> createState() => _ServiceControlScreenState();
}

class _ServiceControlScreenState extends State<ServiceControlScreen> with WidgetsBindingObserver {
  bool _serviceRunning = false;
  String _status = 'Servicio detenido';
  String _permStatus = '';
  bool _speechTestResult = false;
  String _speechTestStatus = '';
  bool _batteryOptimizationDisabled = false;
  
  // Speech recognition en UI
  late stt.SpeechToText _speech;
  late FlutterTts _flutterTts;
  bool _speechEnabled = false;
  bool _isListening = false;
  String _lastRecognizedText = '';
  
  final FlutterBackgroundService _backgroundService = FlutterBackgroundService();
  final BackendApiService _apiService = BackendApiService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestAllPermissions();
    _listenToBackgroundEvents();
    _checkBatteryOptimization();

    // Cargar dispositivos si la lista está vacía
    final provider = Provider.of<SmartHomeProvider>(context, listen: false);
    if (provider.devices.isEmpty) {
      provider.loadDevices();
    }
  }

  void _listenToBackgroundEvents() {
    // Escuchar eventos del background service
    _backgroundService.on('shakeDetected').listen((event) {
      print('📱 Shake detectado desde background service');
      print('📱 Estado actual: isListening=$_isListening, speechEnabled=$_speechEnabled');
      if (!_isListening && _speechEnabled) {
        print('✅ Condiciones cumplidas, activando voz...');
        _activateVoiceRecognition();
      } else {
        print('❌ Condiciones NO cumplidas: isListening=$_isListening, speechEnabled=$_speechEnabled');
      }
    });
  }

  Future<void> _requestAllPermissions() async {
    print('🔐 Solicitando permisos básicos...');
    
    // Solo solicitar permisos que se pueden manejar automáticamente
    List<Permission> permissions = [
      Permission.microphone,
      Permission.notification,
    ];
    
    Map<Permission, PermissionStatus> statuses = await permissions.request();
    bool allGranted = statuses.values.every((status) => status.isGranted);
    
    print('📋 Estado de permisos: $statuses');
    
    setState(() {
      if (allGranted) {
        _permStatus = 'Permisos básicos concedidos';
      } else {
        _permStatus = 'Faltan permisos básicos: ${statuses.entries.where((e) => !e.value.isGranted).map((e) => e.key.toString()).join(', ')}';
      }
    });
    
    // Inicializar servicios DESPUÉS de solicitar permisos
    if (allGranted) {
      print('✅ Permisos básicos concedidos, inicializando servicios...');
      await _initializeServices();
    } else {
      print('❌ Faltan permisos básicos, no se pueden inicializar servicios');
      _showPermissionDialog();
    }
  }

  Future<void> _checkBatteryOptimization() async {
    if (Platform.isAndroid) {
      try {
        final status = await Permission.ignoreBatteryOptimizations.status;
        setState(() {
          _batteryOptimizationDisabled = status.isGranted;
        });
        print('🔋 Estado de optimización de batería: $status');
      } catch (e) {
        print('❌ Error verificando optimización de batería: $e');
      }
    }
  }

  Future<void> _requestBatteryOptimization() async {
    if (Platform.isAndroid) {
      try {
        final status = await Permission.ignoreBatteryOptimizations.request();
        setState(() {
          _batteryOptimizationDisabled = status.isGranted;
        });
        
        if (status.isGranted) {
          _showMessage('✅ Optimización de batería deshabilitada correctamente');
        } else {
          _showMessage('❌ No se pudo deshabilitar la optimización de batería');
        }
      } catch (e) {
        print('❌ Error solicitando optimización de batería: $e');
        _showMessage('❌ Error al solicitar permisos de batería');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _initializeServices() async {
    print('🔧 Inicializando servicios...');
    await _initTts();
    await _initSpeech();
    print('✅ Servicios inicializados');
  }

  Future<void> _initSpeech() async {
    print('🎤 Inicializando speech recognition en UI...');
    try {
      _speech = stt.SpeechToText();
      print('🎤 Objeto SpeechToText creado');
      
      // Verificar permisos antes de inicializar
      final micPermission = await Permission.microphone.status;
      print('🎤 Permiso de micrófono: $micPermission');
      
      if (micPermission != PermissionStatus.granted) {
        print('❌ Permiso de micrófono no concedido');
        _speechEnabled = false;
        return;
      }
      
      _speechEnabled = await _speech.initialize(
        onStatus: (status) => print('🎤 Speech status: $status'),
        onError: (error) => print('🎤 Speech error: $error'),
      );
      print('🎤 Speech initialization result: $_speechEnabled');
      
      if (_speechEnabled) {
        print('✅ Speech recognition inicializado correctamente');
      } else {
        print('❌ Speech recognition falló al inicializar');
      }
    } catch (e) {
      print('❌ Error inicializando speech: $e');
      _speechEnabled = false;
    }
  }

  Future<void> _initTts() async {
    print('🔊 Inicializando TTS en UI...');
    try {
      _flutterTts = FlutterTts();
      await _flutterTts.setLanguage("es-ES");
      await _flutterTts.setSpeechRate(0.8);
      await _flutterTts.setVolume(1.0);
      print('✅ TTS inicializado correctamente');
    } catch (e) {
      print('❌ Error inicializando TTS: $e');
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permisos requeridos'),
        content: const Text('La app necesita permisos de micrófono y notificaciones para funcionar correctamente.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('Abrir ajustes'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  void _showBatteryOptimizationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Optimización de batería'),
        content: const Text('Para que el servicio funcione correctamente en segundo plano, es recomendable deshabilitar la optimización de batería para esta app.\n\nEsto permitirá que el detector de movimiento funcione cuando la app esté en segundo plano.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Ahora no'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _requestBatteryOptimization();
            },
            child: const Text('Configurar'),
          ),
        ],
      ),
    );
  }

  Future<void> _testSpeechRecognition() async {
    print('🧪 Probando speech recognition en UI...');
    setState(() {
      _speechTestStatus = 'Probando...';
    });
    
    try {
      final speech = stt.SpeechToText();
      final result = await speech.initialize(
        onStatus: (status) => print('🧪 Test status: $status'),
        onError: (error) => print('🧪 Test error: $error'),
      );
      
      print('🧪 Speech test result: $result');
      setState(() {
        _speechTestResult = result;
        _speechTestStatus = result ? '✅ Funciona en UI' : '❌ No funciona en UI';
      });
    } catch (e) {
      print('🧪 Speech test error: $e');
      setState(() {
        _speechTestResult = false;
        _speechTestStatus = '❌ Error: $e';
      });
    }
  }

  void _activateVoiceRecognition() async {
    if (!_speechEnabled) {
      print('❌ Speech no está habilitado');
      return;
    }
    if (_isListening) {
      print('⚠️ Ya está escuchando, ignorando activación');
      return;
    }
    print('🎙️ Activando reconocimiento de voz desde app principal');
    // Wake up la pantalla si está apagada
    // (Opcional: implementar _wakeUpScreen si lo necesitas)
    // await _wakeUpScreen();
    await _flutterTts.speak("¿Qué deseas realizar?");
    await Future.delayed(Duration(milliseconds: 1500));
    setState(() {
      _isListening = true;
      _lastRecognizedText = 'Escuchando...';
    });
    Timer? timeoutTimer = Timer(Duration(seconds: 12), () {
      if (_isListening) {
        print('⏰ Timeout del reconocimiento de voz');
        _stopListening();
        _handleVoiceTimeout();
      }
    });
    try {
      await _speech.listen(
        onResult: (result) {
          print('🎤 Resultado recibido: [36m${result.recognizedWords}[0m (final: ${result.finalResult})');
          if (result.finalResult) {
            timeoutTimer?.cancel();
            _processVoiceCommand(result.recognizedWords);
          } else {
            setState(() {
              _lastRecognizedText = result.recognizedWords.isEmpty ? 'Escuchando...' : result.recognizedWords;
            });
          }
        },
        listenFor: Duration(seconds: 10),
        pauseFor: Duration(seconds: 3),
        partialResults: true,
        localeId: "es_ES",
        cancelOnError: true,
        onSoundLevelChange: (level) {
          print('🔊 Nivel de sonido: $level');
        },
      );
    } catch (e) {
      print('❌ Error en speech recognition: $e');
      timeoutTimer?.cancel();
      _stopListening();
      _handleVoiceError(e.toString());
    }
  }

  void _stopListening() {
    if (_isListening) {
      _speech.stop();
      setState(() {
        _isListening = false;
      });
    }
  }

  void _handleVoiceTimeout() async {
    print('⏰ Timeout en reconocimiento de voz');
    await _flutterTts.speak("No se detectó ningún comando de voz. Intenta de nuevo.");
    setState(() {
      _lastRecognizedText = 'No se detectó voz - Timeout';
    });
  }

  void _handleVoiceError(String error) async {
    print('❌ Error en reconocimiento de voz: $error');
    await _flutterTts.speak("Error al detectar tu voz. Por favor, intenta de nuevo.");
    setState(() {
      _lastRecognizedText = 'Error al detectar voz: $error';
    });
  }

  void _processVoiceCommand(String command) async {
    print('🤖 Procesando comando: $command');
    _stopListening();
    setState(() {
      _lastRecognizedText = 'Procesando: $command';
    });
    if (command.trim().isEmpty) {
      await _flutterTts.speak("No se detectó ningún comando. Intenta de nuevo.");
      setState(() {
        _lastRecognizedText = 'Comando vacío';
      });
      return;
    }
    try {
      await _flutterTts.speak("Procesando tu comando...");
      Map<String, dynamic> result = await _apiService.processGeminiCommand(command);
      if (result['type'] == 'error') {
        String errorMessage = result['message'] ?? 'Error al procesar el comando.';
        await _flutterTts.speak(errorMessage);
        setState(() {
          _lastRecognizedText = 'Error: $errorMessage';
        });
        return;
      }
      String responseMessage = result['message'] as String;
      await _flutterTts.speak(responseMessage);
      setState(() {
        _lastRecognizedText = 'Respuesta: $responseMessage';
      });
      if (result['type'] == 'success' && result.containsKey('command')) {
        await _executeDeviceCommand(result['command'] as Map<String, dynamic>);
      }
    } catch (e) {
      print('❌ Error procesando comando: $e');
      String errorMessage = 'Error al procesar el comando. Intenta de nuevo.';
      if (e.toString().contains('timeout')) {
        errorMessage = 'El servidor no responde. Verifica tu conexión.';
      } else if (e.toString().contains('connection')) {
        errorMessage = 'No se puede conectar al servidor. Verifica la configuración.';
      }
      await _flutterTts.speak(errorMessage);
      setState(() {
        _lastRecognizedText = 'Error: $errorMessage';
      });
    }
  }

  Future<void> _executeDeviceCommand(Map<String, dynamic> commandData) async {
    try {
      final String typeDevice = (commandData['type_device'] ?? '').toString().toLowerCase();
      final String deviceName = (commandData['device_name'] ?? '').toString().toLowerCase();
      final String action = (commandData['action'] ?? '').toString().toLowerCase();
      final Map<String, dynamic> parameters = commandData['parameters'] is Map<String, dynamic> 
          ? commandData['parameters'] as Map<String, dynamic> 
          : <String, dynamic>{};
      final provider = Provider.of<SmartHomeProvider>(context, listen: false);
      if (provider.devices.isEmpty) {
        print('🔄 Lista de dispositivos vacía, cargando dispositivos...');
        await provider.loadDevices();
      }
      final List<TuyaDevice> devices = provider.devices.where((d) =>
        isLightCategory(d.category) && d.name.toLowerCase() == deviceName
      ).toList();
      print('🔍 Buscando dispositivo: $deviceName (tipo: $typeDevice)');
      print('📱 Dispositivos disponibles: ${provider.devices.map((d) => '${d.name} (${d.category})').toList()}');
      print('✅ Dispositivos encontrados: ${devices.length}');
      if (devices.isEmpty) {
        String message = 'No se encontró ningún dispositivo "$deviceName" de tipo "$typeDevice".';
        await _flutterTts.speak(message);
        setState(() {
          _lastRecognizedText = message;
        });
        return;
      }
      for (final device in devices) {
        await _executeDeviceAction(device, action, parameters, provider);
      }
    } catch (e) {
      print('❌ Error ejecutando comando de dispositivo: $e');
      await _flutterTts.speak('Error al controlar el dispositivo.');
    }
  }

  Future<void> _executeDeviceAction(TuyaDevice device, String action, Map<String, dynamic> parameters, SmartHomeProvider provider) async {
    try {
      switch (action) {
        case 'turn_on':
          if (!device.isOn) {
            print('🔆 Encendiendo dispositivo: ${device.name}');
            await provider.toggleDevice(device);
          } else {
            print('ℹ️ Dispositivo ${device.name} ya está encendido');
          }
          break;
        case 'turn_off':
          if (device.isOn) {
            print('🔇 Apagando dispositivo: ${device.name}');
            await provider.toggleDevice(device);
          } else {
            print('ℹ️ Dispositivo ${device.name} ya está apagado');
          }
          break;
        case 'set_brightness':
          final int? brightness = int.tryParse(parameters['brightness']?.toString() ?? '');
          if (brightness != null && brightness >= 0 && brightness <= 100) {
            print('💡 Ajustando brillo a $brightness% en ${device.name}');
            await provider.setBrightness(device, brightness);
          }
          break;
        case 'set_color':
          final String? colorName = parameters['color']?.toString();
          if (colorName != null) {
            final color = _colorFromName(colorName);
            if (color != null) {
              print('🎨 Cambiando color a $colorName en ${device.name}');
              await provider.setColor(device, color);
            }
          }
          break;
        case 'set_color_temperature':
          final int? temp = int.tryParse(parameters['color_temperature']?.toString() ?? '');
          if (temp != null && temp >= 2700 && temp <= 6500) {
            print('🌡️ Ajustando temperatura de color a $temp K en ${device.name}');
            await provider.setColorTemperature(device, temp);
          }
          break;
        default:
          print('⚠️ Acción no reconocida: $action');
      }
    } catch (e) {
      print('❌ Error ejecutando acción $action en dispositivo ${device.name}: $e');
    }
  }

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

  bool isLightCategory(String category) {
    final c = category.toLowerCase();
    return c == 'light' || c == 'dj' || c == 'dj_light';
  }

  Future<void> _startService() async {
    print('Intentando iniciar servicio híbrido...');
    await HybridBackgroundService.startService();
    setState(() {
      _serviceRunning = true;
      _status = 'Servicio híbrido activo - Agita para activar voz';
    });
  }

  Future<void> _stopService() async {
    print('Intentando detener servicio híbrido...');
    await HybridBackgroundService.stopService();
    setState(() {
      _serviceRunning = false;
      _status = 'Servicio detenido';
    });
  }

  Future<void> _reinitializeServices() async {
    print('🔄 Reinicializando servicios...');
    await _initializeServices();
    setState(() {
      _permStatus = 'Servicios reinicializados';
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      print('📱 App resumed - checando eventos pendientes');
      // Aquí puedes verificar si hay comandos de voz pendientes
      _checkBatteryOptimization(); // Verificar estado de batería cuando la app se reanuda
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _speech.stop();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Control de Servicio de Voz'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _serviceRunning ? Icons.mic : Icons.mic_off,
                  size: 80,
                  color: _serviceRunning ? Colors.green : Colors.red,
                ),
                const SizedBox(height: 20),
                Text(
                  _status,
                  style: const TextStyle(fontSize: 18),
                ),
                if (_permStatus.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(_permStatus, style: const TextStyle(fontSize: 14, color: Colors.orange)),
                ],
                if (Platform.isAndroid) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _batteryOptimizationDisabled ? Icons.battery_saver : Icons.battery_alert,
                        color: _batteryOptimizationDisabled ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _batteryOptimizationDisabled 
                          ? 'Optimización de batería deshabilitada'
                          : 'Optimización de batería habilitada',
                        style: TextStyle(
                          fontSize: 12,
                          color: _batteryOptimizationDisabled ? Colors.green : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
                if (_speechTestStatus.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(_speechTestStatus, style: TextStyle(fontSize: 14, color: _speechTestResult ? Colors.green : Colors.red)),
                ],
                if (_lastRecognizedText.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _isListening ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _lastRecognizedText,
                      style: TextStyle(
                        fontSize: 14,
                        color: _isListening ? Colors.red : Colors.blue,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 40),
                if (Platform.isAndroid && !_batteryOptimizationDisabled) ...[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.battery_saver),
                    label: const Text('Configurar Batería'),
                    onPressed: _showBatteryOptimizationDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      minimumSize: const Size(200, 50),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reinicializar Servicios'),
                  onPressed: _reinitializeServices,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    minimumSize: const Size(200, 50),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar Servicio'),
                  onPressed: _serviceRunning ? null : _startService,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    minimumSize: const Size(200, 50),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.stop),
                  label: const Text('Detener Servicio'),
                  onPressed: _serviceRunning ? _stopService : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    minimumSize: const Size(200, 50),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}