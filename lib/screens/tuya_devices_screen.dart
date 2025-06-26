import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'device_control_screen.dart';
import '../provider/smart_home_provider.dart';

// Configuración de Tuya API
class TuyaConfig {
  static String get baseUrl => 'https://openapi.tuyaus.com';
  static String get clientId => dotenv.env['TUYA_CLIENT_ID'] ?? '';
  static String get clientSecret => dotenv.env['TUYA_CLIENT_SECRET'] ?? '';
  static String get userId => dotenv.env['TUYA_USER_ID'] ?? '';
}

// Modelo de dispositivo mejorado
class TuyaDevice {
  final String id;
  final String name;
  final String category;
  final bool online;
  final Map<String, dynamic> status;

  TuyaDevice({
    required this.id,
    required this.name,
    required this.category,
    required this.online,
    required this.status,
  });

  // Propiedades para control avanzado
  bool get isOn {
    for (String key in status.keys) {
      if (key.startsWith('switch') && status[key] == true) {
        return true;
      }
    }
    return false;
  }

  int? get brightness {
    return status['bright_value'] as int? ?? status['bright_value_v2'] as int?;
  }

  String? get colorMode {
    return status['work_mode'] as String?;
  }

  String? get colorValue {
    return status['colour_data'] as String? ?? status['colour_data_v2'] as String?;
  }

  int? get colorTemp {
    return status['temp_value'] as int? ?? status['temp_value_v2'] as int?;
  }

  bool get supportsColor {
    return status.containsKey('colour_data') || 
           status.containsKey('colour_data_v2') ||
           status.containsKey('work_mode');
  }

  bool get supportsBrightness {
    return status.containsKey('bright_value') || 
           status.containsKey('bright_value_v2');
  }

  bool get supportsColorTemp {
    return status.containsKey('temp_value') || 
           status.containsKey('temp_value_v2');
  }

  factory TuyaDevice.fromJson(Map<String, dynamic> json) {
    try {
      Map<String, dynamic> statusMap = {};
      
      if (json['status'] != null) {
        if (json['status'] is List) {
          final statusList = json['status'] as List;
          for (var item in statusList) {
            if (item is Map<String, dynamic> && 
                item.containsKey('code') && 
                item.containsKey('value')) {
              statusMap[item['code'].toString()] = item['value'];
            }
          }
        } else if (json['status'] is Map) {
          statusMap = Map<String, dynamic>.from(json['status'] as Map);
        }
      }

      return TuyaDevice(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Dispositivo sin nombre',
        category: json['category']?.toString() ?? 'unknown',
        online: json['online'] == true || json['online'] == 'true',
        status: statusMap,
      );
    } catch (e) {
      print('Error parsing device JSON: $e');
      print('JSON data: $json');
      rethrow;
    }
  }
}

// Servicio API de Tuya (sin cambios en la lógica base)
class TuyaApiService {
  static const String _tokenKey = 'tuya_access_token';
  String? _accessToken;

  String _generateSignature(String method, String url, String body, String timestamp, String nonce) {
    final String stringToSign = method.toUpperCase() + '\n' +
        _sha256(body) + '\n' +
        '' + '\n' +
        url;
    
    final String signStr = TuyaConfig.clientId + (_accessToken ?? '') + timestamp + nonce + stringToSign;
    final List<int> signBytes = utf8.encode(signStr);
    final List<int> secretBytes = utf8.encode(TuyaConfig.clientSecret);
    
    final Hmac hmacSha256 = Hmac(sha256, secretBytes);
    final Digest digest = hmacSha256.convert(signBytes);
    
    return digest.toString().toUpperCase();
  }

  String _sha256(String input) {
    final List<int> bytes = utf8.encode(input);
    final Digest digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> clearToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    _accessToken = null;
  }

  Future<bool> getAccessToken([bool forceRefresh = false]) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      
      if (!forceRefresh) {
        _accessToken = prefs.getString(_tokenKey);
        if (_accessToken != null) {
          return true;
        }
      } else {
        await clearToken();
      }

      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String nonce = Random().nextInt(999999).toString();
      final String url = '/v1.0/token?grant_type=1';
      
      final String stringToSign = 'GET\n' +
          _sha256('') + '\n' +
          '' + '\n' +
          url;
      
      final String signStr = TuyaConfig.clientId + timestamp + nonce + stringToSign;
      final List<int> signBytes = utf8.encode(signStr);
      final List<int> secretBytes = utf8.encode(TuyaConfig.clientSecret);
      
      final Hmac hmacSha256 = Hmac(sha256, secretBytes);
      final Digest digest = hmacSha256.convert(signBytes);
      final String sign = digest.toString().toUpperCase();

      final Map<String, String> headers = {
        'client_id': TuyaConfig.clientId,
        'sign': sign,
        'sign_method': 'HMAC-SHA256',
        't': timestamp,
        'nonce': nonce,
        'Content-Type': 'application/json',
      };

      final response = await http.get(
        Uri.parse('${TuyaConfig.baseUrl}$url'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['success'] == true && data['result'] != null) {
          _accessToken = data['result']['access_token']?.toString();
          if (_accessToken != null) {
            await prefs.setString(_tokenKey, _accessToken!);
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      print('Error getting access token: $e');
      return false;
    }
  }

  Future<List<TuyaDevice>> getDevices() async {
    if (_accessToken == null && !await getAccessToken()) {
      throw Exception('Failed to get access token');
    }

    try {
      return await _makeDevicesRequest();
    } catch (e) {
      if (e.toString().contains('token invalid')) {
        if (await getAccessToken(true)) {
          return await _makeDevicesRequest();
        }
      }
      rethrow;
    }
  }

  Future<List<TuyaDevice>> _makeDevicesRequest() async {
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String nonce = Random().nextInt(999999).toString();
    final String url = '/v1.0/users/${TuyaConfig.userId}/devices';
    
    final String sign = _generateSignature('GET', url, '', timestamp, nonce);

    final Map<String, String> headers = {
      'client_id': TuyaConfig.clientId,
      'access_token': _accessToken!,
      'sign': sign,
      'sign_method': 'HMAC-SHA256',
      't': timestamp,
      'nonce': nonce,
      'Content-Type': 'application/json',
    };

    final response = await http.get(
      Uri.parse('${TuyaConfig.baseUrl}$url'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      
      if (data['success'] == true) {
        dynamic result = data['result'];
        List<dynamic> deviceList = [];
        
        if (result != null) {
          if (result is Map<String, dynamic> && result.containsKey('list')) {
            deviceList = (result['list'] as List? ?? []);
          } else if (result is List) {
            deviceList = result;
          }
        }

        List<TuyaDevice> devices = [];
        for (var deviceData in deviceList) {
          if (deviceData is Map<String, dynamic>) {
            try {
              final device = TuyaDevice.fromJson(deviceData);
              devices.add(device);
            } catch (e) {
              print('Error processing device: $e');
              continue;
            }
          }
        }
        
        return devices;
      } else {
        throw Exception('API returned success=false: ${data['msg'] ?? 'Unknown error'}');
      }
    } else {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  // Método mejorado para enviar múltiples comandos
  Future<bool> controlDevice(String deviceId, List<Map<String, dynamic>> commands) async {
    if (_accessToken == null && !await getAccessToken()) {
      throw Exception('Failed to get access token');
    }

    try {
      return await _makeControlRequest(deviceId, commands);
    } catch (e) {
      if (e.toString().contains('token invalid')) {
        if (await getAccessToken(true)) {
          return await _makeControlRequest(deviceId, commands);
        }
      }
      return false;
    }
  }

  Future<bool> _makeControlRequest(String deviceId, List<Map<String, dynamic>> commands) async {
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String nonce = Random().nextInt(999999).toString();
    final String url = '/v1.0/devices/$deviceId/commands';
    final String body = json.encode({'commands': commands});
    
    final String sign = _generateSignature('POST', url, body, timestamp, nonce);

    final Map<String, String> headers = {
      'client_id': TuyaConfig.clientId,
      'access_token': _accessToken!,
      'sign': sign,
      'sign_method': 'HMAC-SHA256',
      't': timestamp,
      'nonce': nonce,
      'Content-Type': 'application/json',
    };

    print('Control request: $body');

    final response = await http.post(
      Uri.parse('${TuyaConfig.baseUrl}$url'),
      headers: headers,
      body: body,
    );

    print('Control response: ${response.statusCode} - ${response.body}');

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      return data['success'] == true;
    }
    return false;
  }
}

// Pantalla principal
class TuyaDevicesScreen extends StatelessWidget {
  const TuyaDevicesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const _TuyaDevicesScreenBody();
  }
}

class _TuyaDevicesScreenBody extends StatefulWidget {
  const _TuyaDevicesScreenBody({Key? key}) : super(key: key);

  @override
  State<_TuyaDevicesScreenBody> createState() => _TuyaDevicesScreenBodyState();
}

class _TuyaDevicesScreenBodyState extends State<_TuyaDevicesScreenBody> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SmartHomeProvider>(context, listen: false).loadDevices();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispositivos Tuya'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              Provider.of<SmartHomeProvider>(context, listen: false).loadDevices();
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear_token') {
                Provider.of<SmartHomeProvider>(context, listen: false).clearTokenAndReload();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear_token',
                child: Text('Limpiar Token'),
              ),
            ],
          ),
        ],
      ),
      body: Consumer<SmartHomeProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Cargando dispositivos...'),
                ],
              ),
            );
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${provider.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => provider.loadDevices(),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }

          if (provider.devices.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.devices, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No se encontraron dispositivos'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => provider.loadDevices(),
                    child: const Text('Buscar dispositivos'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.loadDevices(),
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.2,
              ),
              itemCount: provider.devices.length,
              itemBuilder: (context, index) {
                final device = provider.devices[index];
                return DeviceCard(device: device);
              },
            ),
          );
        },
      ),
    );
  }
}

// Widget mejorado para tarjeta de dispositivo
class DeviceCard extends StatelessWidget {
  final TuyaDevice device;

  const DeviceCard({Key? key, required this.device}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (device.supportsColor || device.supportsBrightness || device.supportsColorTemp) {
            // Abrir pantalla de control avanzado
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DeviceControlScreen(device: device),
              ),
            );
          } else {
            // Control básico de encendido/apagado
            Provider.of<SmartHomeProvider>(context, listen: false).toggleDevice(device);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: device.isOn
                  ? [Colors.blue.shade400, Colors.blue.shade600]
                  : [Colors.grey.shade300, Colors.grey.shade400],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(
                    _getDeviceIcon(device.category),
                    color: device.isOn ? Colors.white : Colors.grey.shade600,
                    size: 32,
                  ),
                  Row(
                    children: [
                      if (device.supportsColor)
                        Icon(
                          Icons.palette,
                          color: device.isOn ? Colors.white70 : Colors.grey.shade500,
                          size: 16,
                        ),
                      const SizedBox(width: 4),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: device.online ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Text(
                device.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: device.isOn ? Colors.white : Colors.grey.shade700,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                device.isOn ? 'Encendido' : 'Apagado',
                style: TextStyle(
                  fontSize: 12,
                  color: device.isOn ? Colors.white70 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getDeviceIcon(String category) {
    switch (category.toLowerCase()) {
      case 'switch':
      case 'light':
      case 'dj':
        return Icons.lightbulb;
      case 'fan':
        return Icons.toys;
      case 'socket':
      case 'cz':
        return Icons.power;
      case 'camera':
        return Icons.camera_alt;
      case 'sensor':
        return Icons.sensors;
      default:
        return Icons.device_unknown;
    }
  }
}