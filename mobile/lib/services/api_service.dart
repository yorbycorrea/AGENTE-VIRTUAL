// services/api_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Configura Dio como cliente HTTP central de la app.
// Todos los servicios (auth, tareas) usan esta instancia.
//
// Qué hace este archivo:
//   1. Define la URL base del backend
//   2. Agrega el token JWT automáticamente a cada petición (interceptor)
//   3. Maneja errores de red de forma centralizada
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:mobile/services/storage_service.dart';

class ApiService {
  // Detectamos la plataforma para usar la URL correcta:
  // - Android emulador: 10.0.2.2 es la IP especial que apunta al localhost de la PC
  // - Windows/otros:    localhost apunta directamente a la propia máquina
  static String get _baseUrl =>
    Platform.isAndroid ? 'http://10.0.2.2:3000' : 'http://localhost:3000';
  // En producción (app publicada) esto sería tu dominio real: 'https://tuapp.com'

  static Dio? _instancia;
  // Singleton: una sola instancia de Dio para toda la app
  // El "?" indica que puede ser null (antes de inicializarse)

  static Dio get cliente {
    _instancia ??= _crearCliente();
    // ??= significa: "si _instancia es null, asignale el resultado de _crearCliente()"
    // Es equivalente a: if (_instancia == null) _instancia = _crearCliente();
    return _instancia!;
    // El "!" le dice a Dart: "garantizo que no es null en este punto"
  }

  static Dio _crearCliente() {
    final dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      // Si el servidor no responde en 10 segundos, lanza error
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // ── Interceptor ───────────────────────────────────────────────────────
    // Un interceptor se ejecuta automáticamente en CADA petición/respuesta
    // Es como un middleware de Express, pero en el cliente Flutter
    dio.interceptors.add(InterceptorsWrapper(

      onRequest: (options, handler) async {
        // Se ejecuta ANTES de enviar cada petición
        // Acá adjuntamos el token JWT automáticamente

        final token = await StorageService.obtenerToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
          // Así Flutter nunca olvida mandar el token — es automático
          // Sin esto, habría que agregarlo manualmente en cada llamada
        }
        handler.next(options);
        // next() = continuar con la petición
      },

      onResponse: (response, handler) {
        // Se ejecuta cuando el servidor responde exitosamente (2xx)
        handler.next(response);
      },

      onError: (DioException error, handler) async {
        // Se ejecuta cuando hay un error (4xx, 5xx, sin conexión, timeout)

        if (error.response?.statusCode == 401) {
          // 401 = token expirado o inválido
          // Cerramos la sesión automáticamente
          await StorageService.cerrarSesion();
          // En Sprint 7 agregaremos navegación automática al Login
        }

        handler.next(error);
        // Propagamos el error para que el servicio que hizo la llamada lo maneje
      },
    ));

    return dio;
  }
}
