// services/agente_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Lanza y controla la ventana flotante del Agente Desktop (Windows only).
//
// Flujo:
//   1. HomeScreen llama AgenteService.iniciar() al arrancar en Windows
//   2. WindowController.create() crea una nueva ventana Flutter en el mismo proceso
//   3. Esa ventana detecta arguments=='agente' en main.dart y corre AgenteApp
//   4. Para mostrar mensajes: AgenteService.mostrarMensaje('texto')
//      → controller.invokeMethod('mostrarMensaje', 'texto')
//      → el Agente muestra el globo de diálogo
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';

class AgenteService {
  static WindowController? _controller;
  static bool _iniciado = false;

  /// Lanza la ventana flotante del Agente
  static Future<void> iniciar() async {
    if (!Platform.isWindows) return;
    if (_iniciado) return;
    _iniciado = true;

    try {
      _controller = await WindowController.create(
        const WindowConfiguration(
          arguments:      'agente',
          hiddenAtLaunch: true,
        ),
      );
    } catch (e, stack) {
      debugPrint('[AgenteService] ERROR creando ventana del agente: $e\n$stack');
      _iniciado = false;
      _controller = null;
    }
  }

  /// Envía un mensaje al Agente para que lo muestre en el globo de diálogo
  static Future<void> mostrarMensaje(String mensaje) async {
    if (_controller == null) return;
    try {
      await _controller!.invokeMethod('mostrarMensaje', mensaje);
    } catch (e) {
      debugPrint('[AgenteService] ERROR mostrarMensaje: $e');
    }
  }

  /// Activa la animación de saludo del Agente
  static Future<void> saludar() async {
    if (_controller == null) return;
    try {
      await _controller!.invokeMethod('saludar', null);
    } catch (e) {
      debugPrint('[AgenteService] ERROR saludar: $e');
    }
  }

  /// Cambia el personaje del Agente
  static Future<void> cambiarPersonaje(String personajeId) async {
    if (_controller == null) return;
    try {
      await _controller!.invokeMethod('cambiarPersonaje', personajeId);
    } catch (e) {
      debugPrint('[AgenteService] ERROR cambiarPersonaje: $e');
    }
  }

  static bool get estaActivo => _controller != null && _iniciado;
}
