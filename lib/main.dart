import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'navigation_helper.dart';
import 'service/hybrid_background_service.dart';
import 'service/backend_api_service.dart';
import 'package:provider/provider.dart';
import 'provider/smart_home_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configurar cliente HTTP para manejar certificados SSL inseguros
  setupUnsafeHttpClient();
  
  await dotenv.load(fileName: ".env");
  
  print('🚀 Inicializando servicio híbrido...');
  try {
    await HybridBackgroundService.initializeService();
    print('✅ Servicio híbrido inicializado correctamente');
  } catch (e) {
    print('❌ Error inicializando servicio híbrido: $e');
  }
  
  runApp(
    ChangeNotifierProvider(
      create: (_) => SmartHomeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Home Voice Control',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.blueAccent,
      ),
      initialRoute: '/service_control',
      routes: NavigationHelper.getRoutes(),
      debugShowCheckedModeBanner: false,
    );
  }
}