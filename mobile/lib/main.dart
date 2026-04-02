// main.dart — Punto de entrada de la app Flutter

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/screens/auth/login_screen.dart';
import 'package:mobile/screens/home/home_screen.dart';
import 'package:mobile/services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es', null);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Verificamos si hay una sesión activa ANTES de mostrar la app
  final haySession = await StorageService.haySessionActiva();
  // Si el usuario ya inició sesión antes, lo mandamos directo al Home
  // Si no, lo mandamos al Login

  runApp(AgendaApp(iniciarEnHome: haySession));
}

class AgendaApp extends StatelessWidget {
  final bool iniciarEnHome;
  const AgendaApp({super.key, required this.iniciarEnHome});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agenda App',
      debugShowCheckedModeBanner: false,
      theme:     AppTheme.temaClaro,
      darkTheme: AppTheme.temaOscuro,
      themeMode: ThemeMode.dark,
      home: iniciarEnHome ? const HomeScreen() : const LoginScreen(),
      // Si hay token guardado → HomeScreen directamente
      // Si no → LoginScreen
    );
  }
}
