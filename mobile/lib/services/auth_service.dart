// services/auth_service.dart

import 'package:dio/dio.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/services/storage_service.dart';

class AuthService {

  // ── Login ─────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await ApiService.cliente.post(
        '/api/auth/login',
        data: {'email': email, 'password': password},
        // data = body de la petición (lo que antes llamábamos req.body en Express)
      );

      // Guardamos la sesión en el dispositivo
      await StorageService.guardarSesion(
        token:     response.data['token'],
        nombre:    response.data['usuario']['nombre'],
        email:     response.data['usuario']['email'],
        usuarioId: response.data['usuario']['id'],
      );

      return {'exito': true, 'usuario': response.data['usuario']};

    } on DioException catch (e) {
      // DioException es el tipo de error que lanza Dio
      // "on DioException" = solo captura errores de ese tipo
      return {
        'exito': false,
        'error': e.response?.data['error'] ?? 'Error de conexión con el servidor',
        // Si el servidor respondió con un error, usamos su mensaje
        // Si no hay respuesta (sin internet), mostramos mensaje genérico
      };
    }
  }

  // ── Registro ──────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> registro({
    required String nombre,
    required String email,
    required String password,
  }) async {
    try {
      final response = await ApiService.cliente.post(
        '/api/auth/registro',
        data: {'nombre': nombre, 'email': email, 'password': password},
      );

      await StorageService.guardarSesion(
        token:     response.data['token'],
        nombre:    response.data['usuario']['nombre'],
        email:     response.data['usuario']['email'],
        usuarioId: response.data['usuario']['id'],
      );

      return {'exito': true, 'usuario': response.data['usuario']};

    } on DioException catch (e) {
      return {
        'exito': false,
        'error': e.response?.data['error'] ?? 'Error al crear la cuenta',
      };
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────
  static Future<void> logout() async {
    await StorageService.cerrarSesion();
    // El token se borra del dispositivo
    // El servidor no necesita saber (los JWT son stateless — expiran solos)
  }
}
