// main.dart — Punto de entrada de la app Flutter

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/screens/auth/login_screen.dart';
import 'package:mobile/screens/home/home_screen.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/notificaciones_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es', null);
  await NotificacionesService.inicializar();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  final haySession = await StorageService.haySessionActiva();
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

      // ── Localización ────────────────────────────────────────────────────
      // Sin esto, DatePickerDialog no sabe cómo mostrar textos en español
      // GlobalMaterialLocalizations provee: "Aceptar", "Cancelar", nombres de meses, etc.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'ES'),
        Locale('en', 'US'),
      ],

      home: iniciarEnHome ? const HomeScreen() : const LoginScreen(),
    );
  }
}
