// screens/calendario/calendario_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Vista de calendario mensual: muestra los días del mes, resalta los días
// que tienen tareas, y al tocar un día muestra las tareas de ese día.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile/models/tarea.dart';
import 'package:mobile/services/tareas_service.dart';
import 'package:mobile/theme/app_theme.dart';

class CalendarioScreen extends StatefulWidget {
  const CalendarioScreen({super.key});

  @override
  State<CalendarioScreen> createState() => _CalendarioScreenState();
}

class _CalendarioScreenState extends State<CalendarioScreen> {
  DateTime _mesActual  = DateTime.now();
  DateTime? _diaSeleccionado;
  List<Tarea> _todasLasTareas = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarTareas();
  }

  Future<void> _cargarTareas() async {
    try {
      // Cargamos TODAS las tareas para poder resaltar los días en el calendario
      final tareas = await TareasService.obtenerTareas();
      setState(() { _todasLasTareas = tareas; _cargando = false; });
    } catch (e) {
      setState(() => _cargando = false);
    }
  }

  // Tareas que caen en un día específico
  List<Tarea> _tareasDelDia(DateTime dia) {
    return _todasLasTareas.where((t) {
      if (t.fechaLimite == null) return false;
      return t.fechaLimite!.year  == dia.year  &&
             t.fechaLimite!.month == dia.month &&
             t.fechaLimite!.day   == dia.day;
    }).toList();
  }

  // Avanzar/retroceder mes
  void _cambiarMes(int delta) {
    setState(() {
      _mesActual = DateTime(_mesActual.year, _mesActual.month + delta, 1);
      _diaSeleccionado = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _cargando
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primario))
        : SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Columna izquierda: el calendario ──────────────────
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildEncabezadoMes(),
                        const SizedBox(height: 16),
                        _buildDiasDeSemanaCabecera(),
                        const SizedBox(height: 8),
                        Expanded(child: _buildGrillaDias()),
                      ],
                    ),
                  ),
                ),

                // ── Divisor ────────────────────────────────────────────
                const VerticalDivider(width: 1, color: Colors.white10),

                // ── Columna derecha: tareas del día seleccionado ───────
                SizedBox(
                  width: 320,
                  child: _buildPanelTareas(),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildEncabezadoMes() {
    final nombreMes = DateFormat('MMMM yyyy', 'es').format(_mesActual);

    return Row(
      children: [
        Text(
          nombreMes[0].toUpperCase() + nombreMes.substring(1),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Spacer(),
        // Botones de navegación de mes
        IconButton(
          onPressed: () => _cambiarMes(-1),
          icon: const Icon(Icons.chevron_left_rounded, color: Colors.white70),
        ),
        IconButton(
          onPressed: () => _cambiarMes(1),
          icon: const Icon(Icons.chevron_right_rounded, color: Colors.white70),
        ),
        // Botón "Hoy"
        TextButton(
          onPressed: () => setState(() {
            _mesActual = DateTime.now();
            _diaSeleccionado = DateTime.now();
          }),
          child: const Text('Hoy', style: TextStyle(color: AppTheme.primario)),
        ),
      ],
    );
  }

  Widget _buildDiasDeSemanaCabecera() {
    // En español: Lun Mar Mié Jue Vie Sáb Dom
    const dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return Row(
      children: dias.map((d) => Expanded(
        child: Center(
          child: Text(d,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      )).toList(),
    );
  }

  Widget _buildGrillaDias() {
    // Primer día del mes
    final primerDia = DateTime(_mesActual.year, _mesActual.month, 1);
    // En Dart, weekday: 1=Lun ... 7=Dom. Necesitamos offset para la grilla.
    final offsetInicio = primerDia.weekday - 1;
    // Último día del mes
    final ultimoDia = DateTime(_mesActual.year, _mesActual.month + 1, 0).day;
    // Total de celdas = offset + días del mes, redondeado a múltiplos de 7
    final totalCeldas = ((offsetInicio + ultimoDia) / 7).ceil() * 7;

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1.2,
      ),
      itemCount: totalCeldas,
      itemBuilder: (context, index) {
        final numeroDia = index - offsetInicio + 1;

        // Celdas vacías antes del primer día del mes
        if (numeroDia < 1 || numeroDia > ultimoDia) {
          return const SizedBox();
        }

        final fecha = DateTime(_mesActual.year, _mesActual.month, numeroDia);
        final tareasDelDia = _tareasDelDia(fecha);
        final tieneCompletadas = tareasDelDia.any((t) => t.estaCompletada);
        final tienePendientes  = tareasDelDia.any((t) => t.estaPendiente);
        final tieneVencidas    = tareasDelDia.any((t) => t.estaVencida);

        final esHoy = _esHoy(fecha);
        final estaSeleccionado = _diaSeleccionado != null &&
          _diaSeleccionado!.year  == fecha.year &&
          _diaSeleccionado!.month == fecha.month &&
          _diaSeleccionado!.day   == fecha.day;

        return GestureDetector(
          onTap: () => setState(() => _diaSeleccionado = fecha),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: estaSeleccionado
                ? AppTheme.primario
                : esHoy
                  ? AppTheme.primario.withOpacity(0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: esHoy && !estaSeleccionado
                ? Border.all(color: AppTheme.primario, width: 1)
                : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$numeroDia',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: esHoy || estaSeleccionado
                      ? FontWeight.bold
                      : FontWeight.normal,
                    color: estaSeleccionado
                      ? Colors.white
                      : esHoy
                        ? AppTheme.primario
                        : Colors.white70,
                  ),
                ),
                // Indicadores de tareas debajo del número
                if (tareasDelDia.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (tieneVencidas)
                        _buildPunto(AppTheme.peligro),
                      if (tienePendientes)
                        _buildPunto(estaSeleccionado
                          ? Colors.white70
                          : AppTheme.advertencia),
                      if (tieneCompletadas)
                        _buildPunto(AppTheme.acento),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPunto(Color color) {
    return Container(
      width: 5, height: 5,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildPanelTareas() {
    final tareas = _diaSeleccionado != null
      ? _tareasDelDia(_diaSeleccionado!)
      : <Tarea>[];

    final titulo = _diaSeleccionado == null
      ? 'Seleccioná un día'
      : DateFormat('EEEE d \'de\' MMMM', 'es').format(_diaSeleccionado!);

    return Container(
      color: AppTheme.fondoTarjetaOscuro,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _diaSeleccionado == null
              ? 'Agenda'
              : titulo[0].toUpperCase() + titulo.substring(1),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _diaSeleccionado == null
              ? 'Tocá cualquier día del calendario'
              : tareas.isEmpty
                ? 'Sin tareas este día'
                : '${tareas.length} tarea${tareas.length == 1 ? '' : 's'}',
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10),
          const SizedBox(height: 8),

          if (tareas.isEmpty && _diaSeleccionado != null)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: Column(
                  children: [
                    Icon(Icons.event_available_rounded, color: Colors.white12, size: 48),
                    SizedBox(height: 12),
                    Text('Día libre', style: TextStyle(color: Colors.white24)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: tareas.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _buildTareaAgenda(tareas[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTareaAgenda(Tarea tarea) {
    final colorPrioridad = AppTheme.coloresPrioridad[tarea.prioridad] ?? AppTheme.acento;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: colorPrioridad, width: 3)),
      ),
      child: Row(
        children: [
          // Indicador de estado
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tarea.estaCompletada
                ? AppTheme.acento
                : tarea.estaVencida
                  ? AppTheme.peligro
                  : AppTheme.advertencia,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tarea.titulo,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: tarea.estaCompletada ? Colors.white38 : Colors.white,
                    decoration: tarea.estaCompletada
                      ? TextDecoration.lineThrough
                      : null,
                  ),
                ),
                if (tarea.horaLimite != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    // Mostramos solo HH:MM
                    tarea.horaLimite!.substring(0, 5),
                    style: const TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _esHoy(DateTime fecha) {
    final hoy = DateTime.now();
    return fecha.year == hoy.year &&
           fecha.month == hoy.month &&
           fecha.day   == hoy.day;
  }
}
