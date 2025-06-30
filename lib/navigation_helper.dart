import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/interface_screen.dart';

class NavigationHelper {
  static Map<String, WidgetBuilder> getRoutes() {
    return {
      '/home': (context) => const HomeScreen(),
      '/interface': (context) => const InterfaceScreen(),
    };
  }

  static void goToHome(BuildContext context) {
    Navigator.pushNamed(context, '/home');
  }

  static void goToInterface(BuildContext context) {
    Navigator.pushNamed(context, '/interface');
  }

  // Método genérico para navegar por nombre de pantalla
  static void navigateToScreen(BuildContext context, String screenName) {
    final routeName = '/' + screenName.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    Navigator.pushNamed(context, routeName);
  }

  // Método para regresar al inicio desde cualquier pantalla
  static void goBackToHome(BuildContext context) {
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/home',
      (Route<dynamic> route) => false,
    );
  }
} 