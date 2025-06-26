import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/tuya_devices_screen.dart' show TuyaDevice;

class TuyaConfig {
  static String get baseUrl => 'https://openapi.tuyaus.com';
  static String get clientId => dotenv.env['TUYA_CLIENT_ID'] ?? '';
  static String get clientSecret => dotenv.env['TUYA_CLIENT_SECRET'] ?? '';
  static String get userId => dotenv.env['TUYA_USER_ID'] ?? '';
}

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