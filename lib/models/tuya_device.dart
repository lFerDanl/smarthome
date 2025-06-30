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