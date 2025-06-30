import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/tuya_device.dart';

class BackendConfig {
  // Cambia esta URL por la de tu backend
  static String get baseUrl => dotenv.env['BACKEND_BASE_URL'] ?? 'http://localhost:3000';
}

class BackendApiService {
  Future<List<TuyaDevice>> getDevices() async {
    try {
      final response = await http.get(
        Uri.parse('${BackendConfig.baseUrl}/tuya/devices'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        List<TuyaDevice> devices = [];
        
        for (var deviceData in data) {
          try {
            final device = TuyaDevice.fromJson(deviceData);
            devices.add(device);
          } catch (e) {
            print('Error processing device: $e');
            continue;
          }
        }
        
        return devices;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('Error getting devices: $e');
      throw Exception('Failed to get devices: $e');
    }
  }

  Future<bool> controlDevice(String deviceId, List<Map<String, dynamic>> commands) async {
    try {
      final requestBody = {
        'commands': commands,
      };

      print('Control request: ${json.encode(requestBody)}');

      final response = await http.post(
        Uri.parse('${BackendConfig.baseUrl}/tuya/devices/$deviceId/control'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );

      print('Control response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> data = json.decode(response.body);
        return data['success'] == true;
      }
      
      return false;
    } catch (e) {
      print('Error controlling device: $e');
      return false;
    }
  }

  Future<void> clearToken() async {
    try {
      await http.delete(
        Uri.parse('${BackendConfig.baseUrl}/tuya/token'),
        headers: {
          'Content-Type': 'application/json',
        },
      );
    } catch (e) {
      print('Error clearing token: $e');
    }
  }

  // GEMINI
  Future<Map<String, dynamic>> processGeminiCommand(String userInput) async {
    try {
      final response = await http.post(
        Uri.parse('${BackendConfig.baseUrl}/gemini/chat'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({'prompt': userInput}),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Error en Gemini backend: ${response.statusCode}');
      }
    } catch (e) {
      print('Error procesando comando Gemini: $e');
      return {
        'type': 'error',
        'message': 'Error al procesar el comando. Intenta de nuevo.',
      };
    }
  }
} 