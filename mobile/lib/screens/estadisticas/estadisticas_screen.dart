// screens/estadisticas/estadisticas_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile/services/estadisticas_service.dart';
import 'package:mobile/theme/app_theme.dart';

class EstadisticasScreen extends StatefulWidget {
  const EstadisticasScreen({super.key});

  @override
  State<EstadisticasScreen> createState() => _EstadisticasScreenState();
}

class _EstadisticasScreenState extends State<EstadisticasScreen> {
  Map<String, dynamic>? _statsHoy;
  Map<String, dynamic>? _racha;
  List<dynamic> _historial = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    try {
      final results = await Future.wait([
        EstadisticasService.obtenerEstadisticasHoy(),
        EstadisticasService.obtenerRacha(),
        EstadisticasService.obtenerHistorial(dias: 7),
      ]);
      // Future.wait ejecuta las 3 llamadas EN PARALELO
      // En lugar de esperar una, luego otra, luego otra (3x el tiempo)
      // las 3 corren al mismo tiempo y esperamos a que todas terminen

      setState(() {
        _statsHoy  = results[0] as Map<String, dynamic>;
        _racha     = results[1] as Map<String, dynamic>;
        _historial = results[2] as List;
        _cargando  = false;
      });
    } catch (e) {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi progreso'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () { setState(() => _cargando = true); _cargarDatos(); },
          ),
        ],
      ),
      body: _cargando
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primario))
        : RefreshIndicator(
            onRefresh: _cargarDatos,
            color: AppTheme.primario,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── Tarjeta principal del día ──────────────────────────
                  _buildTarjetaDia(),
                  const SizedBox(height: 16),

                  // ── Racha ──────────────────────────────────────────────
                  _buildTarjetaRacha(),
                  const SizedBox(height: 24),

                  // ── Desglose de tareas ─────────────────────────────────
                  Text('Desglose de hoy', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  _buildDesglose(),
                  const SizedBox(height: 24),

                  // ── Historial últimos 7 días ───────────────────────────
                  Text('Últimos 7 días', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  _buildHistorial(),

                ],
              ),
            ),
          ),
    );
  }

  Widget _buildTarjetaDia() {
    if (_statsHoy == null) return const SizedBox();

    final porcentaje = (_statsHoy!['porcentaje'] as num).toDouble();
    final mensaje    = _statsHoy!['mensaje'] as Map<String, dynamic>? ?? {};
    final emoji      = mensaje['emoji'] ?? '✨';
    final texto      = mensaje['texto'] ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primario, AppTheme.primarioOscuro],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('EEEE d MMMM', 'es').format(DateTime.now()),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_statsHoy!['completadas']} de ${_statsHoy!['total']} tareas',
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                '${porcentaje.toInt()}%',
                style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Barra de progreso
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: porcentaje / 100,
              minHeight: 10,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          // Mensaje motivacional
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(texto,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTarjetaRacha() {
    if (_racha == null) return const SizedBox();
    final racha = _racha!['racha'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.fondoTarjetaOscuro,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: racha > 0 ? AppTheme.advertencia.withOpacity(0.5) : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.advertencia.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              racha > 0 ? '🔥' : '💤',
              style: const TextStyle(fontSize: 28),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$racha ${racha == 1 ? 'día' : 'días'} de racha',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  _racha!['mensaje_racha'] ?? '',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesglose() {
    if (_statsHoy == null) return const SizedBox();

    final items = [
      {'label': 'Completadas', 'valor': _statsHoy!['completadas'], 'color': AppTheme.acento,      'icono': Icons.check_circle_rounded},
      {'label': 'Pendientes',  'valor': _statsHoy!['pendientes'],  'color': AppTheme.primario,    'icono': Icons.radio_button_unchecked},
      {'label': 'Pospuestas',  'valor': _statsHoy!['pospuestas'],  'color': AppTheme.advertencia, 'icono': Icons.event_repeat_rounded},
      {'label': 'Vencidas',    'valor': _statsHoy!['vencidas'],    'color': AppTheme.peligro,     'icono': Icons.warning_amber_rounded},
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      // shrinkWrap: true = el GridView ocupa solo el espacio que necesita
      // Sin esto, dentro de un SingleChildScrollView causa errores
      physics: const NeverScrollableScrollPhysics(),
      // NeverScrollableScrollPhysics = desactiva el scroll propio del grid
      // El scroll lo maneja el SingleChildScrollView padre
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: items.map((item) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.fondoTarjetaOscuro,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: (item['color'] as Color).withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(item['icono'] as IconData, color: item['color'] as Color, size: 22),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item['valor'] ?? 0}',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: item['color'] as Color),
                  ),
                  Text(item['label'] as String,
                    style: const TextStyle(fontSize: 12, color: Colors.white54)),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHistorial() {
    if (_historial.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.fondoTarjetaOscuro,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text('Sin historial todavía', style: TextStyle(color: Colors.white38)),
        ),
      );
    }

    // Encontramos el máximo para escalar las barras
    final maxCompletadas = _historial
        .map((d) => (d['completadas'] as num).toInt())
        .fold(0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.fondoTarjetaOscuro,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: _historial.map((dia) {
          final completadas = (dia['completadas'] as num).toInt();
          final fecha = DateTime.parse(dia['fecha']);
          final esHoy = dia['fecha'] == DateTime.now().toIso8601String().split('T')[0];
          final porcentajeBarra = maxCompletadas > 0 ? completadas / maxCompletadas : 0.0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                // Día
                SizedBox(
                  width: 48,
                  child: Text(
                    esHoy ? 'Hoy' : DateFormat('EEE', 'es').format(fecha),
                    style: TextStyle(
                      fontSize: 12,
                      color: esHoy ? AppTheme.primario : Colors.white54,
                      fontWeight: esHoy ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                // Barra de progreso
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: porcentajeBarra.toDouble(),
                      minHeight: 10,
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        esHoy ? AppTheme.primario : AppTheme.acento,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Número
                SizedBox(
                  width: 24,
                  child: Text(
                    '$completadas',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: esHoy ? AppTheme.primario : Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
