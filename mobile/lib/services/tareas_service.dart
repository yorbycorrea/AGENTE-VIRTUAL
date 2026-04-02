// services/tareas_service.dart

import 'package:dio/dio.dart';
import 'package:mobile/models/tarea.dart';
import 'package:mobile/services/api_service.dart';

class TareasService {

  // ── Obtener todas las tareas ───────────────────────────────────────────────
  static Future<List<Tarea>> obtenerTareas({String? estado}) async {
    final response = await ApiService.cliente.get(
      '/api/tareas',
      queryParameters: estado != null ? {'estado': estado} : null,
      // queryParameters = parámetros de URL: GET /api/tareas?estado=pendiente
    );

    final List datos = response.data['tareas'];
    return datos.map((json) => Tarea.fromJson(json)).toList();
    // .map() transforma cada elemento de la lista
    // Tarea.fromJson(json) convierte cada Map a un objeto Tarea
    // .toList() convierte el resultado a List<Tarea>
  }

  // ── Tareas de hoy ─────────────────────────────────────────────────────────
  static Future<List<Tarea>> obtenerTareasHoy() async {
    final response = await ApiService.cliente.get('/api/tareas/hoy');
    final List datos = response.data['tareas'];
    return datos.map((json) => Tarea.fromJson(json)).toList();
  }

  // ── Crear tarea ───────────────────────────────────────────────────────────
  static Future<Tarea> crearTarea({
    required String titulo,
    String? descripcion,
    String prioridad = 'media',
    int? categoriaId,
    DateTime? fechaLimite,
    String? horaLimite,
    bool posponerAutomatico = false,
  }) async {
    final response = await ApiService.cliente.post(
      '/api/tareas',
      data: {
        'titulo':               titulo,
        'descripcion':          descripcion,
        'prioridad':            prioridad,
        'categoria_id':         categoriaId,
        'fecha_limite':         fechaLimite?.toIso8601String().split('T')[0],
        'hora_limite':          horaLimite,
        'posponer_automatico':  posponerAutomatico,
      },
    );
    return Tarea.fromJson(response.data['tarea']);
  }

  // ── Cambiar estado (completar, posponer, cancelar) ────────────────────────
  static Future<Tarea> cambiarEstado(int id, String estado) async {
    final response = await ApiService.cliente.patch(
      '/api/tareas/$id/estado',
      data: {'estado': estado},
    );
    return Tarea.fromJson(response.data['tarea']);
  }

  // ── Eliminar tarea ────────────────────────────────────────────────────────
  static Future<void> eliminarTarea(int id) async {
    await ApiService.cliente.delete('/api/tareas/$id');
  }

  // ── Editar tarea ──────────────────────────────────────────────────────────
  static Future<Tarea> editarTarea(int id, Map<String, dynamic> datos) async {
    final response = await ApiService.cliente.put('/api/tareas/$id', data: datos);
    return Tarea.fromJson(response.data['tarea']);
  }
}
