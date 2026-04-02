// main.dart — Punto de entrada de la app Flutter

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/screens/auth/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Asegura que Flutter esté inicializado antes de llamar código nativo
  // Necesario cuando usás await antes de runApp()

  await initializeDateFormatting('es', null);
  // Inicializa los datos de localización para español
  // Sin esto, DateFormat('EEEE', 'es') no funcionaría en español

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(const AgendaApp());
}

class AgendaApp extends StatelessWidget {
  const AgendaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agenda App',
      debugShowCheckedModeBanner: false,
      theme:      AppTheme.temaClaro,
      darkTheme:  AppTheme.temaOscuro,
      themeMode:  ThemeMode.dark,
      // ThemeMode.dark → tema oscuro siempre por ahora
      // En Sprint 9 cambiamos a ThemeMode.system para respetar la preferencia del dispositivo
      home: const LoginScreen(),
    );
  }
}
