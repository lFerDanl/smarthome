import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'navigation_helper.dart';
import 'package:provider/provider.dart';
import 'provider/smart_home_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await dotenv.load(fileName: ".env");
    print('✅ Variables de entorno cargadas correctamente');
    print('GEMINI_API_KEY: ${dotenv.env['GEMINI_API_KEY'] != null ? 'CONFIGURADO' : 'NO CONFIGURADO'}');
    print('TUYA_CLIENT_ID: ${dotenv.env['TUYA_CLIENT_ID'] ?? 'NO CONFIGURADO'}');
    print('TUYA_CLIENT_SECRET: ${dotenv.env['TUYA_CLIENT_SECRET'] != null ? 'CONFIGURADO' : 'NO CONFIGURADO'}');
    print('TUYA_USER_ID: ${dotenv.env['TUYA_USER_ID'] ?? 'NO CONFIGURADO'}');
    print('BACKEND_BASE_URL: ${dotenv.env['BACKEND_BASE_URL'] ?? 'http://localhost:3000'}');
  } catch (e) {
    print('❌ Error cargando variables de entorno: $e');
  }
  
  runApp(
    ChangeNotifierProvider(
      create: (_) => SmartHomeProvider(),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Home Voice Control',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.blueAccent,
      ),
      initialRoute: '/home',
      routes: NavigationHelper.getRoutes(),
      debugShowCheckedModeBanner: false,
    );
  }
}