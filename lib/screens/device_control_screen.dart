import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../provider/smart_home_provider.dart';
import 'tuya_devices_screen.dart' show TuyaDevice;

class DeviceControlScreen extends StatefulWidget {
  final TuyaDevice device;

  const DeviceControlScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<DeviceControlScreen> createState() => _DeviceControlScreenState();
}

class _DeviceControlScreenState extends State<DeviceControlScreen> {
  late double _brightness;
  late double _colorTemperature;
  Color _selectedColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _brightness = (widget.device.brightness ?? 100).toDouble();
    _colorTemperature = (widget.device.colorTemp ?? 250).toDouble();
    if (widget.device.colorValue != null) {
      _selectedColor = _parseColorFromTuya(widget.device.colorValue!);
    }
  }

  Color _parseColorFromTuya(String colorData) {
    try {
      if (colorData.length >= 12) {
        final int hue = int.parse(colorData.substring(0, 4), radix: 16);
        final int saturation = int.parse(colorData.substring(4, 8), radix: 16);
        final int value = int.parse(colorData.substring(8, 12), radix: 16);
        return HSVColor.fromAHSV(
          1.0,
          hue.toDouble(),
          saturation / 1000.0,
          value / 1000.0,
        ).toColor();
      }
    } catch (e) {
      print('Error parsing color: $e');
    }
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: Consumer<SmartHomeProvider>(
        builder: (context, provider, child) {
          // Obtener el dispositivo actualizado por ID
          final device = provider.devices.firstWhere(
            (d) => d.id == widget.device.id,
            orElse: () => widget.device,
          );
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Estado', style: Theme.of(context).textTheme.titleMedium),
                            Text(
                              device.isOn ? 'Encendido' : 'Apagado',
                              style: TextStyle(
                                color: device.isOn ? Colors.green : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: device.isOn,
                          onChanged: (value) {
                            provider.toggleDevice(device);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (device.supportsBrightness) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Brillo', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Slider(
                            value: _brightness,
                            min: 10,
                            max: 1000,
                            divisions: 100,
                            label: '${(_brightness / 10).round()}%',
                            onChanged: (value) {
                              setState(() {
                                _brightness = value;
                              });
                            },
                            onChangeEnd: (value) {
                              provider.setBrightness(device, value.round());
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (device.supportsColor) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Color', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Colors.red,
                              Colors.green,
                              Colors.blue,
                              Colors.yellow,
                              Colors.purple,
                              Colors.orange,
                              Colors.pink,
                              Colors.cyan,
                              Colors.lime,
                              Colors.indigo,
                            ].map((color) => GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedColor = color;
                                });
                                provider.setColor(device, color);
                              },
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _selectedColor == color ? Colors.black : Colors.grey.shade300,
                                    width: _selectedColor == color ? 3 : 1,
                                  ),
                                ),
                                child: _selectedColor == color ? const Icon(Icons.check, color: Colors.white) : null,
                              ),
                            )).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (device.supportsColorTemp) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Temperatura de Color', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('Cálido'),
                              Expanded(
                                child: Slider(
                                  value: _colorTemperature,
                                  min: 0,
                                  max: 1000,
                                  divisions: 100,
                                  label: '${_colorTemperature.round()}K',
                                  onChanged: (value) {
                                    setState(() {
                                      _colorTemperature = value;
                                    });
                                  },
                                  onChangeEnd: (value) {
                                    provider.setColorTemperature(device, value.round());
                                  },
                                ),
                              ),
                              const Text('Frío'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Accesos Rápidos', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (device.supportsBrightness) ...[
                              _QuickActionButton(
                                label: 'Brillo 100%',
                                icon: Icons.brightness_high,
                                onPressed: () => provider.setBrightness(device, 1000),
                              ),
                              _QuickActionButton(
                                label: 'Brillo 50%',
                                icon: Icons.brightness_medium,
                                onPressed: () => provider.setBrightness(device, 500),
                              ),
                              _QuickActionButton(
                                label: 'Brillo 10%',
                                icon: Icons.brightness_low,
                                onPressed: () => provider.setBrightness(device, 100),
                              ),
                            ],
                            if (device.supportsColorTemp) ...[
                              _QuickActionButton(
                                label: 'Luz Cálida',
                                icon: Icons.wb_incandescent,
                                onPressed: () => provider.setColorTemperature(device, 0),
                              ),
                              _QuickActionButton(
                                label: 'Luz Fría',
                                icon: Icons.wb_sunny,
                                onPressed: () => provider.setColorTemperature(device, 1000),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Información del Dispositivo', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        _InfoRow('ID:', device.id),
                        _InfoRow('Categoría:', device.category),
                        _InfoRow('Estado:', device.online ? 'En línea' : 'Desconectado'),
                        if (device.brightness != null)
                          _InfoRow('Brillo actual:', '${(device.brightness! / 10).round()}%'),
                        if (device.colorTemp != null)
                          _InfoRow('Temp. color:', '${device.colorTemp}K'),
                        if (device.colorMode != null)
                          _InfoRow('Modo:', device.colorMode!),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
} 