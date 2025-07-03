import 'dart:async';
import 'dart:isolate';
import 'dart:ui';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
class HybridBackgroundService {
  static const String _isolatePortName = 'hybrid_voice_service';
  static const String _notificationChannelId = 'voice_service_channel';
  static const String _notificationChannelName = 'Smart Home Voice Service';
  static const MethodChannel _platformChannel = MethodChannel('com.smarthome.voice/wake_app');

  static FlutterLocalNotificationsPlugin? _notificationsPlugin;

  static Future<void> initializeService() async {
    print('🚀 Inicializando servicio híbrido...');
    final service = FlutterBackgroundService();
    _notificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin!.initialize(initSettings);
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: 'Canal para el servicio de voz en segundo plano',
      importance: Importance.high,
      enableVibration: false,
      enableLights: false,
      showBadge: false,
    );
    await _notificationsPlugin!
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: _notificationChannelId,
        initialNotificationTitle: 'Smart Home Voice Service',
        initialNotificationContent: 'Servicio activo - Agita para activar',
        foregroundServiceNotificationId: 888,
        autoStartOnBoot: true,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
    print('✅ Servicio híbrido configurado correctamente');
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    print('🔄 Servicio híbrido iniciando...');
    DartPluginRegistrant.ensureInitialized();
    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
      service.on('setAsForeground').listen((event) {
        print('📱 Configurando como foreground service');
        service.setAsForegroundService();
      });
      service.on('setAsBackground').listen((event) {
        print('📱 Configurando como background service');
        service.setAsBackgroundService();
      });
    }
    service.on('stopService').listen((event) {
      print('🛑 Deteniendo servicio...');
      service.stopSelf();
    });
    final shakeDetector = ShakeDetector(service);
    await shakeDetector.initialize();
    Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (service is AndroidServiceInstance) {
        try {
          service.setAsForegroundService();
          service.setForegroundNotificationInfo(
            title: "Smart Home Voice Service",
            content: "Activo - ${DateTime.now().toString().substring(11, 19)} - Agita para activar",
          );
          print('💓 Servicio alive - ${DateTime.now()}');
        } catch (e) {
          print('❌ Error manteniendo servicio: $e');
        }
      }
    });
    print('✅ Servicio híbrido completamente inicializado');
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    return true;
  }

  // Método para wake up de la app desde el background service
  static Future<void> wakeUpApp() async {
    try {
      await _platformChannel.invokeMethod('wakeUpApp');
      print('✅ App wake up solicitado');
    } catch (e) {
      print('❌ Error al wake up app: $e');
    }
  }

  static Future<void> startService() async {
    print('🚀 Intentando iniciar servicio híbrido...');
    final service = FlutterBackgroundService();
    await service.startService();
    print('✅ Comando de inicio de servicio híbrido enviado');
  }

  static Future<void> stopService() async {
    print('🛑 Intentando detener servicio híbrido...');
    final service = FlutterBackgroundService();
    service.invoke("stopService");
    print('✅ Comando de detención de servicio híbrido enviado');
  }
}

@pragma('vm:entry-point')
class ShakeDetector {
  final ServiceInstance service;
  late StreamSubscription<AccelerometerEvent> _accelerometerSubscription;
  double _shakeThreshold = 25.0;
  DateTime _lastShakeTime = DateTime.now();
  bool _isActive = true;
  ShakeDetector(this.service);
  Future<void> initialize() async {
    await _initAccelerometer();
    print('✅ ShakeDetector initialized');
  }
  Future<void> _initAccelerometer() async {
    print('📱 Inicializando acelerómetro para shake detection...');
    try {
      bool sensorAvailable = true;
      _accelerometerSubscription = accelerometerEvents.listen(
        (AccelerometerEvent event) {
          if (_isActive) {
            _detectShake(event);
          }
        },
        onError: (error) {
          print('❌ Error en acelerómetro: $error');
          Timer(Duration(seconds: 5), () {
            if (_isActive) {
              _reinitializeAccelerometer();
            }
          });
        },
        cancelOnError: false,
      );
      print('✅ Acelerómetro inicializado correctamente');
      Timer(Duration(seconds: 2), () {
        if (_isActive) {
          print('🧪 Sensor test - Detector activo');
        }
      });
    } catch (e) {
      print('❌ Error inicializando acelerómetro: $e');
      Timer(Duration(seconds: 5), () {
        if (_isActive) {
          _reinitializeAccelerometer();
        }
      });
    }
  }
  void _reinitializeAccelerometer() {
    print('🔄 Reinicializando acelerómetro...');
    try {
      _accelerometerSubscription.cancel();
    } catch (e) {
      print('Error cancelando subscription: $e');
    }
    _initAccelerometer();
  }
  void _detectShake(AccelerometerEvent event) {
    double acceleration = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    if (DateTime.now().second % 30 == 0) {
      print('📊 Aceleración actual: ${acceleration.toStringAsFixed(2)}');
    }
    if (acceleration > _shakeThreshold) {
      DateTime now = DateTime.now();
      if (now.difference(_lastShakeTime).inMilliseconds > 1500) {
        _lastShakeTime = now;
        print('🎯 SHAKE DETECTADO! Aceleración: ${acceleration.toStringAsFixed(2)}');
        _handleShakeDetected();
      }
    }
  }
  void _handleShakeDetected() async {
    print('🚀 Procesando shake detectado...');
    _updateNotification('🎙️ Activando reconocimiento de voz...');
    service.invoke('shakeDetected');
    try {
      await HybridBackgroundService.wakeUpApp();
    } catch (e) {
      print('❌ Error wake up app: $e');
    }
    print('✅ Evento de shake enviado a la app principal');
    Timer(Duration(seconds: 5), () {
      _updateNotification('Servicio activo - Agita para activar');
    });
  }
  void _updateNotification(String content) {
    if (service is AndroidServiceInstance) {
      try {
        (service as AndroidServiceInstance).setForegroundNotificationInfo(
          title: "Smart Home Voice Service",
          content: content,
        );
      } catch (e) {
        print('❌ Error actualizando notificación: $e');
      }
    }
  }
  void dispose() {
    _isActive = false;
    _accelerometerSubscription.cancel();
  }
} 