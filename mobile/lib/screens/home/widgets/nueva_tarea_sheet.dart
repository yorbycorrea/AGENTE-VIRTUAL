// screens/home/widgets/nueva_tarea_sheet.dart
// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet para crear O editar una tarea.
// Si recibe `tareaInicial`, entra en modo edición: pre-carga los campos
// y llama PUT en lugar de POST al guardar.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile/models/tarea.dart';
import 'package:mobile/services/tareas_service.dart';
import 'package:mobile/services/notificaciones_service.dart';
import 'package:mobile/theme/app_theme.dart';

class NuevaTareaSheet extends StatefulWidget {
  final Tarea? tareaInicial;
  // null = modo creación, una Tarea = modo edición

  const NuevaTareaSheet({super.key, this.tareaInicial});

  @override
  State<NuevaTareaSheet> createState() => _NuevaTareaSheetState();
}

class _NuevaTareaSheetState extends State<NuevaTareaSheet> {
  final _tituloController      = TextEditingController();
  final _descripcionController = TextEditingController();

  String    _prioridad              = 'media';
  DateTime? _fechaLimite;
  TimeOfDay? _horaLimite;
  bool      _tieneRecordatorio      = false;
  int       _minutosAntesRecordatorio = 30;
  bool      _guardando              = false;

  bool get _esEdicion => widget.tareaInicial != null;
  // Getter de conveniencia — true si estamos editando, false si estamos creando

  @override
  void initState() {
    super.initState();
    // Si viene una tarea, pre-cargamos todos los campos con sus valores actuales
    if (_esEdicion) {
      final t = widget.tareaInicial!;
      _tituloController.text      = t.titulo;
      _descripcionController.text = t.descripcion ?? '';
      _prioridad                  = t.prioridad;
      _fechaLimite                = t.fechaLimite;

      // horaLimite viene como String "HH:MM:SS" desde el backend
      // Necesitamos convertirlo a TimeOfDay para el picker
      if (t.horaLimite != null) {
        final partes = t.horaLimite!.split(':');
        _horaLimite = TimeOfDay(
          hour:   int.parse(partes[0]),
          minute: int.parse(partes[1]),
        );
      }
    }
  }

  // Opciones de recordatorio
  final List<Map<String, dynamic>> _opcionesRecordatorio = [
    {'label': 'En el momento',  'minutos': 0},
    {'label': '5 min antes',    'minutos': 5},
    {'label': '15 min antes',   'minutos': 15},
    {'label': '30 min antes',   'minutos': 30},
    {'label': '1 hora antes',   'minutos': 60},
    {'label': '2 horas antes',  'minutos': 120},
    {'label': '1 día antes',    'minutos': 1440},
  ];

  @override
  void dispose() {
    _tituloController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  // ── Abrir selector de fecha ───────────────────────────────────────────────
  Future<void> _seleccionarFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaLimite ?? DateTime.now(),
      firstDate: DateTime.now(),
      // No permite seleccionar fechas pasadas
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('es', 'ES'),
      builder: (context, child) => Theme(
        // Aplicamos el tema oscuro al picker
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppTheme.primario),
        ),
        child: child!,
      ),
    );

    if (fecha != null) {
      setState(() {
        _fechaLimite = fecha;
        // Si hay fecha, activamos el recordatorio automáticamente
        if (!_tieneRecordatorio) _tieneRecordatorio = true;
      });
    }
  }

  // ── Abrir selector de hora ────────────────────────────────────────────────
  Future<void> _seleccionarHora() async {
    final hora = await showTimePicker(
      context: context,
      initialTime: _horaLimite ?? TimeOfDay.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppTheme.primario),
        ),
        child: child!,
      ),
    );

    if (hora != null) {
      setState(() => _horaLimite = hora);
    }
  }

  // ── Guardar tarea (crea o edita según el modo) ───────────────────────────
  Future<void> _guardarTarea() async {
    if (_tituloController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El título es obligatorio'),
        backgroundColor: AppTheme.peligro, behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() => _guardando = true);

    try {
      // Convertimos TimeOfDay → String "HH:MM:00" para el backend
      String? horaString;
      if (_horaLimite != null) {
        horaString =
          '${_horaLimite!.hour.toString().padLeft(2, '0')}:'
          '${_horaLimite!.minute.toString().padLeft(2, '0')}:00';
      }

      final datos = {
        'titulo':       _tituloController.text.trim(),
        'descripcion':  _descripcionController.text.trim().isEmpty
                          ? null
                          : _descripcionController.text.trim(),
        'prioridad':    _prioridad,
        'fecha_limite': _fechaLimite?.toIso8601String().split('T')[0],
        'hora_limite':  horaString,
        'posponer_automatico': false,
      };

      Tarea tarea;

      if (_esEdicion) {
        // ── Modo edición: llamamos PUT /api/tareas/:id ────────────────
        tarea = await TareasService.editarTarea(widget.tareaInicial!.id, datos);
      } else {
        // ── Modo creación: llamamos POST /api/tareas ───────────────────
        tarea = await TareasService.crearTarea(
          titulo:             datos['titulo'] as String,
          descripcion:        datos['descripcion'] as String?,
          prioridad:          datos['prioridad'] as String,
          fechaLimite:        _fechaLimite,
          horaLimite:         horaString,
          posponerAutomatico: false,
        );

        // Las notificaciones solo se programan al crear (no al editar,
        // para no duplicar alarmas existentes)
        if (_tieneRecordatorio && _fechaLimite != null && _horaLimite != null) {
          await _programarNotificacion(tarea);
        }
      }

      if (mounted) Navigator.pop(context, tarea);
      // Devolvemos la tarea actualizada al Home para que actualice la lista

    } catch (e) {
      setState(() => _guardando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'),
          backgroundColor: AppTheme.peligro, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _programarNotificacion(Tarea tarea) async {
    // Combinamos fecha y hora en un solo DateTime
    final fechaCompleta = DateTime(
      _fechaLimite!.year,
      _fechaLimite!.month,
      _fechaLimite!.day,
      _horaLimite!.hour,
      _horaLimite!.minute,
    );

    // Restamos los minutos de anticipación
    final fechaNotificacion = fechaCompleta.subtract(
      Duration(minutes: _minutosAntesRecordatorio),
    );

    // Pedimos permiso si no lo tenemos
    final tienePermiso = await NotificacionesService.pedirPermisos();
    if (!tienePermiso) return;

    await NotificacionesService.programarRecordatorio(
      id:       tarea.id,
      titulo:   '⏰ ${tarea.titulo}',
      cuerpo:   _minutosAntesRecordatorio == 0
                  ? 'Es hora de esta tarea'
                  : 'En $_minutosAntesRecordatorio min: ${tarea.titulo}',
      fechaHora: fechaNotificacion,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      // SingleChildScrollView permite hacer scroll si el contenido no entra en pantalla
      // Necesario cuando el teclado aparece y empuja el formulario hacia arriba
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Handle visual del bottom sheet ──────────────────────────
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Text(
            _esEdicion ? 'Editar tarea' : 'Nueva tarea',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),

          // ── Título ──────────────────────────────────────────────────
          TextField(
            controller: _tituloController,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: '¿Qué necesitás hacer?',
              prefixIcon: Icon(Icons.add_task_rounded),
            ),
          ),
          const SizedBox(height: 12),

          // ── Descripción ──────────────────────────────────────────────
          TextField(
            controller: _descripcionController,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Descripción (opcional)',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 16),

          // ── Prioridad ────────────────────────────────────────────────
          Text('Prioridad', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Row(
            children: ['baja', 'media', 'alta'].map((p) {
              final color = AppTheme.coloresPrioridad[p]!;
              final seleccionado = _prioridad == p;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _prioridad = p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: seleccionado ? color.withOpacity(0.2) : AppTheme.fondoTarjetaOscuro,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: seleccionado ? color : Colors.white12,
                        width: seleccionado ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      p[0].toUpperCase() + p.substring(1),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: seleccionado ? color : Colors.white54,
                        fontWeight: seleccionado ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // ── Fecha y hora ─────────────────────────────────────────────
          Row(
            children: [
              // Selector de fecha
              Expanded(
                child: GestureDetector(
                  onTap: _seleccionarFecha,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.fondoTarjetaOscuro,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _fechaLimite != null ? AppTheme.primario : Colors.white12,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_rounded,
                          size: 18,
                          color: _fechaLimite != null ? AppTheme.primario : Colors.white38),
                        const SizedBox(width: 8),
                        Text(
                          _fechaLimite != null
                            ? DateFormat('d MMM', 'es').format(_fechaLimite!)
                            : 'Fecha',
                          style: TextStyle(
                            color: _fechaLimite != null ? Colors.white : Colors.white38,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Selector de hora
              Expanded(
                child: GestureDetector(
                  onTap: _seleccionarHora,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.fondoTarjetaOscuro,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _horaLimite != null ? AppTheme.primario : Colors.white12,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.access_time_rounded,
                          size: 18,
                          color: _horaLimite != null ? AppTheme.primario : Colors.white38),
                        const SizedBox(width: 8),
                        Text(
                          _horaLimite != null
                            ? _horaLimite!.format(context)
                            : 'Hora',
                          style: TextStyle(
                            color: _horaLimite != null ? Colors.white : Colors.white38,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Recordatorio ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.fondoTarjetaOscuro,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _tieneRecordatorio ? AppTheme.primario : Colors.white12,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.notifications_outlined,
                          color: _tieneRecordatorio ? AppTheme.primario : Colors.white38,
                          size: 20),
                        const SizedBox(width: 8),
                        Text('Recordatorio',
                          style: TextStyle(
                            color: _tieneRecordatorio ? Colors.white : Colors.white54,
                            fontWeight: FontWeight.w500,
                          )),
                      ],
                    ),
                    Switch(
                      value: _tieneRecordatorio,
                      onChanged: (val) => setState(() => _tieneRecordatorio = val),
                      activeColor: AppTheme.primario,
                    ),
                  ],
                ),

                // Opciones de tiempo solo si el recordatorio está activado
                if (_tieneRecordatorio) ...[
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _opcionesRecordatorio.map((opcion) {
                      final seleccionado = _minutosAntesRecordatorio == opcion['minutos'];
                      return GestureDetector(
                        onTap: () => setState(() => _minutosAntesRecordatorio = opcion['minutos']),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: seleccionado
                              ? AppTheme.primario.withOpacity(0.2)
                              : Colors.white10,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: seleccionado ? AppTheme.primario : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            opcion['label'],
                            style: TextStyle(
                              fontSize: 12,
                              color: seleccionado ? AppTheme.primario : Colors.white54,
                              fontWeight: seleccionado ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  if (_fechaLimite == null || _horaLimite == null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: const [
                        Icon(Icons.info_outline, size: 14, color: Colors.white38),
                        SizedBox(width: 6),
                        Text('Seleccioná fecha y hora para activar la alarma',
                          style: TextStyle(fontSize: 11, color: Colors.white38)),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Botón guardar ────────────────────────────────────────────
          ElevatedButton(
            onPressed: _guardando ? null : _guardarTarea,
            child: _guardando
              ? const SizedBox(height: 20, width: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(_esEdicion ? 'Guardar cambios' : 'Guardar tarea'),
          ),
        ],
      ),
    );
  }
}
