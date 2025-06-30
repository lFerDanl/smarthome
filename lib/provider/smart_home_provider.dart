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
      final success = await _apiService.controlDevice(device.id, commands);
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
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> setBrightness(TuyaDevice device, int brightness) async {
    try {
      final List<Map<String, dynamic>> commands = [];
      if (device.status.containsKey('bright_value')) {
        commands.add({
          'code': 'bright_value',
          'value': brightness,
        });
      } else if (device.status.containsKey('bright_value_v2')) {
        commands.add({
          'code': 'bright_value_v2',
          'value': brightness,
        });
      }
      if (commands.isNotEmpty) {
        final success = await _apiService.controlDevice(device.id, commands);
        if (success) {
          await loadDevices();
        }
      }
    } catch (e) {
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
      if (device.status.containsKey('colour_data_v2')) {
        commands.add({
          'code': 'colour_data_v2',
          'value': {
            'h': hue,
            's': saturation,
            'v': value,
          },
        });
      } else if (device.status.containsKey('colour_data')) {
        final String colorData = hue.toRadixString(16).padLeft(4, '0') +
                                 saturation.toRadixString(16).padLeft(4, '0') +
                                 value.toRadixString(16).padLeft(4, '0');
        commands.add({
          'code': 'colour_data',
          'value': colorData,
        });
      }
      if (commands.isNotEmpty) {
        final success = await _apiService.controlDevice(device.id, commands);
        if (success) {
          await loadDevices();
        }
      }
    } catch (e) {
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
      if (device.status.containsKey('temp_value')) {
        commands.add({
          'code': 'temp_value',
          'value': temperature,
        });
      } else if (device.status.containsKey('temp_value_v2')) {
        commands.add({
          'code': 'temp_value_v2',
          'value': temperature,
        });
      }
      if (commands.isNotEmpty) {
        final success = await _apiService.controlDevice(device.id, commands);
        if (success) {
          await loadDevices();
        }
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }
} 