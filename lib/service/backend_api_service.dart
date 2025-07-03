import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/tuya_device.dart';

// Configurar cliente HTTP inseguro globalmente
void setupUnsafeHttpClient() {
  HttpOverrides.global = MyHttpOverrides();
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

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
      print('🤖 Enviando comando a Gemini: "$userInput"');
      print('🌐 URL del backend: ${BackendConfig.baseUrl}/gemini/chat');
      
      final requestBody = {'prompt': userInput};
      final requestBodyJson = json.encode(requestBody);
      
      print('📤 Body de la petición: $requestBodyJson');
      print('📤 Headers de la petición: {"Content-Type": "application/json", "Accept": "application/json"}');
      
      final response = await http.post(
        Uri.parse('${BackendConfig.baseUrl}/gemini/chat'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: requestBodyJson,
      );
      
      print('📡 Respuesta del servidor: ${response.statusCode}');
      print('📋 Headers de respuesta: ${response.headers}');
      print('📥 Body de respuesta: ${response.body}');
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;
        print('✅ Respuesta de Gemini recibida');
        return result;
      } else if (response.statusCode == 201) {
        // 201 también puede ser una respuesta exitosa
        print('✅ Respuesta exitosa con código 201');
        final result = json.decode(response.body) as Map<String, dynamic>;
        return result;
      } else if (response.statusCode == 307) {
        // Manejar redirección
        final location = response.headers['location'];
        print('🔄 Redirección detectada a: $location');
        
        if (location != null) {
          // Intentar la petición a la URL de redirección
          final redirectResponse = await http.post(
            Uri.parse(location),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: requestBodyJson,
          );
          
          print('📡 Respuesta después de redirección: ${redirectResponse.statusCode}');
          
          if (redirectResponse.statusCode == 200) {
            final result = json.decode(redirectResponse.body) as Map<String, dynamic>;
            print('✅ Respuesta de Gemini recibida después de redirección');
            return result;
          } else {
            print('❌ Error después de redirección: ${redirectResponse.statusCode} - ${redirectResponse.body}');
            throw Exception('Error en Gemini backend después de redirección: ${redirectResponse.statusCode}');
          }
        } else {
          throw Exception('Redirección sin URL de destino');
        }
      } else {
        print('❌ Error HTTP ${response.statusCode}: ${response.body}');
        throw Exception('Error en Gemini backend: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error procesando comando Gemini: $e');
      
      // Manejar errores específicos
      if (e.toString().contains('CERTIFICATE_VERIFY_FAILED')) {
        return {
          'type': 'error',
          'message': 'Error de conexión segura con el servidor. Verifica la configuración del backend.',
        };
      } else if (e.toString().contains('Connection refused')) {
        return {
          'type': 'error',
          'message': 'No se puede conectar al servidor. Verifica que el backend esté ejecutándose.',
        };
      } else if (e.toString().contains('timeout')) {
        return {
          'type': 'error',
          'message': 'Tiempo de espera agotado. El servidor no responde.',
        };
      } else if (e.toString().contains('307')) {
        return {
          'type': 'error',
          'message': 'Error de redirección del servidor. Verifica la configuración del backend.',
        };
      } else {
        return {
          'type': 'error',
          'message': 'Error al procesar el comando. Intenta de nuevo.',
        };
      }
    }
  }
} 