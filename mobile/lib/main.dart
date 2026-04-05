// main.dart — Punto de entrada de la app Flutter
//
// desktop_multi_window crea ventanas secundarias DENTRO del mismo proceso.
// Cada ventana tiene su propio Flutter engine que llama a main().
// WindowController.fromCurrentEngine() nos dice cuál ventana somos:
//   - arguments vacío → Ventana principal (AgendaApp)
//   - arguments == 'agente' → Ventana flotante del Agente

import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/screens/auth/login_screen.dart';
import 'package:mobile/screens/home/home_screen.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/notificaciones_service.dart';
import 'package:mobile/windows/agente_app.dart';
import 'package:mobile/windows/win32_helper.dart' as win32;
import 'package:window_manager/window_manager.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    // Detectar cuál ventana somos (main o agente)
    WindowController? controller;
    try {
      controller = await WindowController.fromCurrentEngine();
      debugPrint('[MAIN] windowId=${controller.windowId}, args="${controller.arguments}"');
    } catch (e) {
      debugPrint('[MAIN] No se pudo obtener WindowController: $e');
    }

    if (controller != null && controller.arguments == 'agente') {
      // ── Ventana del Agente flotante ────────────────────────────────────
      // NO usamos window_manager aquí (su plugin no se registra en engines secundarios).
      // Usamos Win32 API directamente via dart:ffi.
      // Primero lanzar la app Flutter, LUEGO configurar la ventana Win32
      // (el engine necesita estar corriendo para que no crashee al modificar estilos)
      runApp(AgenteApp(controller: controller));

      // Esperar a que Flutter haya renderizado al menos un frame
      await Future.delayed(const Duration(milliseconds: 1000));

      debugPrint('[AGENTE] Configurando ventana con Win32 API...');
      try {
        win32.hacerVentanaFlotante();

        final (screenW, screenH) = win32.obtenerTamanoPantalla();
        win32.moverVentana(screenW - 300, screenH - 460, 260, 420);

        debugPrint('[AGENTE] Ventana configurada OK');
      } catch (e) {
        debugPrint('[AGENTE] ERROR configurando: $e');
      }
      return;
    }

    // ── Ventana principal ────────────────────────────────────────────────
    await windowManager.ensureInitialized();

    if (controller != null) {
      await controller.setWindowMethodHandler((call) async {
        if (call.method == 'abrirApp') {
          await windowManager.restore();
          await windowManager.focus();
        }
        return null;
      });
    }

    const WindowOptions mainOpts = WindowOptions(
      size:        Size(1280, 800),
      minimumSize: Size(900, 600),
      center:      true,
      title:       'Agenda App',
    );
    await windowManager.waitUntilReadyToShow(mainOpts);
    await windowManager.show();
    await windowManager.focus();
  }

  // ── Inicialización común ───────────────────────────────────────────────
  await initializeDateFormatting('es', null);
  await NotificacionesService.inicializar();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:          Colors.transparent,
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
