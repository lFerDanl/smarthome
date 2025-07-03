import 'package:flutter/material.dart';
import '../models/tuya_device.dart';
import '../service/backend_api_service.dart';

class SmartHomeProvider extends ChangeNotifier {
  final BackendApiService _apiService = BackendApiService();
  List<TuyaDevice> _devices = [];
  bool _isLoading = false;
  String? _error;

  List<TuyaDevice> get devices => _devices;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> clearTokenAndReload() async {
    await _apiService.clearToken();
    await loadDevices();
  }

  Future<void> loadDevices() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _devices = await _apiService.getDevices();
      _error = null;
    } catch (e) {
      _error = e.toString();
      _devices = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleDevice(TuyaDevice device) async {
    try {
      String switchCode = 'switch_1';
      bool currentState = false;
      for (String key in device.status.keys) {
        if (key.startsWith('switch')) {
          switchCode = key;
          currentState = device.status[key] == true;
          break;
        }
      }
      final List<Map<String, dynamic>> commands = [{
        'code': switchCode,
        'value': !currentState,
      }];
      print('⚡ [toggleDevice] Enviando comando: $commands a deviceId: ${device.id} (actual: $currentState)');
      final success = await _apiService.controlDevice(device.id, commands);
      print('⚡ [toggleDevice] Resultado controlDevice: $success');
      if (success) {
        final index = _devices.indexWhere((d) => d.id == device.id);
        if (index != -1) {
          _devices[index].status[switchCode] = !currentState;
          notifyListeners();
        }
      } else {
        _error = 'No se pudo controlar el dispositivo';
        notifyListeners();
      }
    } catch (e) {
      print('❌ [toggleDevice] Error: $e');
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> setBrightness(TuyaDevice device, int brightness) async {
    try {
      final List<Map<String, dynamic>> commands = [];
      String? code;
      if (device.status.containsKey('bright_value')) {
        code = 'bright_value';
        commands.add({
          'code': code,
          'value': brightness,
        });
      } else if (device.status.containsKey('bright_value_v2')) {
        code = 'bright_value_v2';
        commands.add({
          'code': code,
          'value': brightness,
        });
      }
      if (commands.isNotEmpty) {
        print('💡 [setBrightness] Enviando comando: $commands a deviceId: ${device.id}');
        final success = await _apiService.controlDevice(device.id, commands);
        print('💡 [setBrightness] Resultado controlDevice: $success');
        if (success && code != null) {
          final index = _devices.indexWhere((d) => d.id == device.id);
          if (index != -1) {
            _devices[index].status[code] = brightness;
            notifyListeners();
          }
        }
      }
    } catch (e) {
      print('❌ [setBrightness] Error: $e');
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> setColor(TuyaDevice device, Color color) async {
    try {
      final List<Map<String, dynamic>> commands = [];
      final HSVColor hsvColor = HSVColor.fromColor(color);
      final int hue = (hsvColor.hue).round();
      final int saturation = (hsvColor.saturation * 1000).round();
      final int value = (hsvColor.value * 1000).round();
      commands.add({
        'code': 'work_mode',
        'value': 'colour',
      });
      String? code;
      if (device.status.containsKey('colour_data_v2')) {
        code = 'colour_data_v2';
        commands.add({
          'code': code,
          'value': {
            'h': hue,
            's': saturation,
            'v': value,
          },
        });
      } else if (device.status.containsKey('colour_data')) {
        code = 'colour_data';
        final String colorData = hue.toRadixString(16).padLeft(4, '0') +
                                 saturation.toRadixString(16).padLeft(4, '0') +
                                 value.toRadixString(16).padLeft(4, '0');
        commands.add({
          'code': code,
          'value': colorData,
        });
      }
      if (commands.isNotEmpty) {
        print('🎨 [setColor] Enviando comando: $commands a deviceId: ${device.id}');
        final success = await _apiService.controlDevice(device.id, commands);
        print('🎨 [setColor] Resultado controlDevice: $success');
        if (success && code != null) {
          final index = _devices.indexWhere((d) => d.id == device.id);
          if (index != -1) {
            if (code == 'colour_data_v2') {
              _devices[index].status[code] = {'h': hue, 's': saturation, 'v': value};
            } else if (code == 'colour_data') {
              _devices[index].status[code] = hue.toRadixString(16).padLeft(4, '0') +
                                             saturation.toRadixString(16).padLeft(4, '0') +
                                             value.toRadixString(16).padLeft(4, '0');
            }
            notifyListeners();
          }
        }
      }
    } catch (e) {
      print('❌ [setColor] Error: $e');
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> setColorTemperature(TuyaDevice device, int temperature) async {
    try {
      final List<Map<String, dynamic>> commands = [];
      commands.add({
        'code': 'work_mode',
        'value': 'white',
      });
      String? code;
      if (device.status.containsKey('temp_value')) {
        code = 'temp_value';
        commands.add({
          'code': code,
          'value': temperature,
        });
      } else if (device.status.containsKey('temp_value_v2')) {
        code = 'temp_value_v2';
        commands.add({
          'code': code,
          'value': temperature,
        });
      }
      if (commands.isNotEmpty) {
        print('🌡️ [setColorTemperature] Enviando comando: $commands a deviceId: ${device.id}');
        final success = await _apiService.controlDevice(device.id, commands);
        print('🌡️ [setColorTemperature] Resultado controlDevice: $success');
        if (success && code != null) {
          final index = _devices.indexWhere((d) => d.id == device.id);
          if (index != -1) {
            _devices[index].status[code] = temperature;
            notifyListeners();
          }
        }
      }
    } catch (e) {
      print('❌ [setColorTemperature] Error: $e');
      _error = e.toString();
      notifyListeners();
    }
  }
} 