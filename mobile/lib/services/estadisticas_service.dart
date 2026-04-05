// services/estadisticas_service.dart

import 'package:mobile/services/api_service.dart';

class EstadisticasService {

  static Future<Map<String, dynamic>> obtenerEstadisticasHoy() async {
    final response = await ApiService.cliente.get('/api/estadisticas/hoy');
    return Map<String, dynamic>.from(response.data);
  }

  static Future<List<dynamic>> obtenerHistorial({int dias = 7}) async {
    final response = await ApiService.cliente.get(
      '/api/estadisticas/historial',
      queryParameters: {'dias': dias},
    );
    return response.data['historial'] as List;
  }

  static Future<Map<String, dynamic>> obtenerRacha() async {
    final response = await ApiService.cliente.get('/api/estadisticas/racha');
    return Map<String, dynamic>.from(response.data);
  }
}
