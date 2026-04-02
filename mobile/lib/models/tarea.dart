// models/tarea.dart
// ─────────────────────────────────────────────────────────────────────────────
// Define la estructura de una Tarea en Dart.
// Es el equivalente a la tabla "tareas" de MySQL, pero en código.
// Cada objeto Tarea representa una fila de esa tabla.
// ─────────────────────────────────────────────────────────────────────────────

class Tarea {
  final int id;
  final int usuarioId;
  String titulo;
  String? descripcion;    // El "?" significa que puede ser null
  String prioridad;       // 'alta', 'media', 'baja'
  String estado;          // 'pendiente', 'completada', 'cancelada', 'pospuesta'
  DateTime? fechaLimite;
  String? horaLimite;
  bool posponerAutomatico;
  int diasPospuesta;
  DateTime? completadaEn;
  DateTime creadaEn;
  String? categoriaNombre;
  String? categoriaColor;
  String? categoriaIcono;

  Tarea({
    required this.id,
    required this.usuarioId,
    required this.titulo,
    this.descripcion,
    this.prioridad = 'media',
    // "= 'media'" define el valor por defecto si no se pasa el parámetro
    this.estado = 'pendiente',
    this.fechaLimite,
    this.horaLimite,
    this.posponerAutomatico = false,
    this.diasPospuesta = 0,
    this.completadaEn,
    required this.creadaEn,
    this.categoriaNombre,
    this.categoriaColor,
    this.categoriaIcono,
  });

  // ── fromJson: convierte el JSON del backend a un objeto Tarea ────────────
  // Cuando Flutter recibe la respuesta del servidor, llega como Map (diccionario)
  // Este método lo convierte a un objeto Tarea que Dart puede usar fácilmente
  factory Tarea.fromJson(Map<String, dynamic> json) {
    // "factory" = constructor especial que puede devolver una instancia existente
    // o crear una nueva. Se usa comúnmente para parsear JSON.
    // Map<String, dynamic> = las claves son String, los valores pueden ser cualquier tipo
    return Tarea(
      id:                 json['id'],
      usuarioId:          json['usuario_id'],
      titulo:             json['titulo'],
      descripcion:        json['descripcion'],
      prioridad:          json['prioridad'] ?? 'media',
      // ?? = operador "null-coalescing" — si es null, usa el valor de la derecha
      // Igual que || en JS para valores null/undefined
      estado:             json['estado'] ?? 'pendiente',
      fechaLimite:        json['fecha_limite'] != null
                            ? DateTime.parse(json['fecha_limite'])
                            : null,
      // Operador ternario: condición ? valor_si_true : valor_si_false
      // Igual que en JS
      horaLimite:         json['hora_limite'],
      posponerAutomatico: json['posponer_automatico'] == 1 || json['posponer_automatico'] == true,
      // MySQL devuelve BOOLEAN como 0/1, Dart necesita true/false
      diasPospuesta:      json['dias_pospuesta'] ?? 0,
      completadaEn:       json['completada_en'] != null
                            ? DateTime.parse(json['completada_en'])
                            : null,
      creadaEn:           DateTime.parse(json['creada_en']),
      categoriaNombre:    json['categoria_nombre'],
      categoriaColor:     json['categoria_color'],
      categoriaIcono:     json['categoria_icono'],
    );
  }

  // ── toJson: convierte el objeto a Map para enviarlo al backend ───────────
  Map<String, dynamic> toJson() {
    return {
      'titulo':               titulo,
      'descripcion':          descripcion,
      'prioridad':            prioridad,
      'estado':               estado,
      'fecha_limite':         fechaLimite?.toIso8601String().split('T')[0],
      // ?. = acceso seguro a null: si fechaLimite es null, devuelve null en lugar de crash
      'hora_limite':          horaLimite,
      'posponer_automatico':  posponerAutomatico,
    };
  }

  // ── Getters de conveniencia ───────────────────────────────────────────────
  bool get estaCompletada => estado == 'completada';
  bool get estaPendiente  => estado == 'pendiente';
  bool get estaVencida {
    if (fechaLimite == null) return false;
    final hoy = DateTime.now();
    return fechaLimite!.isBefore(DateTime(hoy.year, hoy.month, hoy.day))
        && !estaCompletada;
    // ! después de ? = "sé que no es null aquí" (forzamos el tipo)
  }
}
