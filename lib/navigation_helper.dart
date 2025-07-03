import 'package:flutter/material.dart';
import 'screens/service_control_screen.dart';
// import 'screens/home_screen.dart';
// import 'screens/interface_screen.dart';

class NavigationHelper {
  static Map<String, WidgetBuilder> getRoutes() {
    return {
      '/service_control': (context) => const ServiceControlScreen(),
      // '/home': (context) => const HomeScreen(),
      // '/interface': (context) => const InterfaceScreen(),
    };
  }

  // static void goToServiceControl(BuildContext context) {
  //   Navigator.pushNamed(context, '/service_control');
  // }

  // Métodos de navegación eliminados
} 