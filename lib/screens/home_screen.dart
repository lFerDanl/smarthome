import 'package:flutter/material.dart';
import '../navigation_helper.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Aplicación'),
        backgroundColor: const Color.fromRGBO(50, 100, 200, 1.0),
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            const DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.fromRGBO(50, 100, 200, 1.0),
                    Color.fromRGBO(33, 150, 243, 1.0),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.account_circle,
                    size: 64,
                    color: Colors.white,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Menú Principal',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home, color: Color.fromRGBO(50, 100, 200, 1.0)),
              title: const Text(
                'Inicio',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.mic, color: Color.fromRGBO(50, 100, 200, 1.0)),
              title: const Text(
                'Interfaz de Voz',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(context); // Cierra el Drawer
                NavigationHelper.goToInterface(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.grey),
              title: const Text(
                'Configuración',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Configuración - Próximamente'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info, color: Colors.grey),
              title: const Text(
                'Acerca de',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Acerca de - Versión 1.0.0'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color.fromRGBO(245, 245, 245, 1.0),
              Color.fromRGBO(230, 230, 230, 1.0),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.home,
                size: 120,
                color: Color.fromRGBO(50, 100, 200, 0.3),
              ),
              SizedBox(height: 24),
              Text(
                'Inicio',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Color.fromRGBO(50, 100, 200, 0.7),
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Bienvenido a la aplicación',
                style: TextStyle(
                  fontSize: 18,
                  color: Color.fromRGBO(100, 100, 100, 1.0),
                  fontWeight: FontWeight.w300,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Usa el menú lateral para navegar',
                style: TextStyle(
                  fontSize: 14,
                  color: Color.fromRGBO(150, 150, 150, 1.0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 