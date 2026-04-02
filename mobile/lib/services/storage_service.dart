// services/storage_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Guarda datos simples en el dispositivo usando shared_preferences.
// shared_preferences = almacenamiento clave-valor persistente (como localStorage en el browser)
// El token JWT vive acá — sobrevive si cerrás y reabrís la app.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  // Claves constantes — evita typos al escribir el nombre de la clave
  static const String _keyToken    = 'auth_token';
  static const String _keyNombre   = 'user_nombre';
  static const String _keyEmail    = 'user_email';
  static const String _keyUsuarioId = 'user_id';

  // ── Guardar datos de sesión ───────────────────────────────────────────────
  static Future<void> guardarSesion({
    required String token,
    required String nombre,
    required String email,
    required int usuarioId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // SharedPreferences.getInstance() devuelve la instancia del almacenamiento
    // Es async porque necesita acceder al disco

    await prefs.setString(_keyToken,     token);
    await prefs.setString(_keyNombre,    nombre);
    await prefs.setString(_keyEmail,     email);
    await prefs.setInt(_keyUsuarioId,    usuarioId);
  }

  // ── Leer el token ─────────────────────────────────────────────────────────
  static Future<String?> obtenerToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
    // Devuelve null si no hay token guardado (usuario no logueado)
  }

  // ── Leer datos del usuario ────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> obtenerUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyToken);
    if (token == null) return null;

    return {
      'id':     prefs.getInt(_keyUsuarioId),
      'nombre': prefs.getString(_keyNombre),
      'email':  prefs.getString(_keyEmail),
      'token':  token,
    };
  }

  // ── Borrar sesión (logout) ────────────────────────────────────────────────
  static Future<void> cerrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyNombre);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyUsuarioId);
    // remove() borra una clave específica
    // También existe prefs.clear() pero borraría TODOS los datos guardados
  }

  // ── Verificar si hay sesión activa ────────────────────────────────────────
  static Future<bool> haySessionActiva() async {
    final token = await obtenerToken();
    return token != null && token.isNotEmpty;
  }
}
