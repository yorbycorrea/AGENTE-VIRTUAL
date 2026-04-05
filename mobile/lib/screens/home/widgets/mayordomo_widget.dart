// screens/home/widgets/mayordomo_widget.dart
// ─────────────────────────────────────────────────────────────────────────────
// El Mayordomo — asistente virtual exclusivo de la versión de escritorio.
// Reemplaza las notificaciones del sistema (que no funcionan en Windows)
// con un personaje animado que aparece con globos de diálogo.
//
// Comportamiento:
//   - Al abrir la app:     saludo inicial
//   - Cada 5 minutos:      revisa si hay tareas venciendo pronto
//   - Al completar todo:   felicitación
//   - Click en él:         siguiente mensaje de la cola
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mobile/models/tarea.dart';
import 'package:mobile/theme/app_theme.dart';

// Con GlobalKey, HomeScreen puede llamar directamente a métodos del State:
//   _mayordomoKey.currentState?.mostrarMensaje('Hola')
// GlobalKey mantiene la referencia al State sin importar cuántas veces
// Flutter reconstruya el widget — es la forma más confiable de comunicación
// entre un padre y un hijo específico en Flutter.

class MayordomoWidget extends StatefulWidget {
  final List<Tarea> tareas;

  const MayordomoWidget({super.key, required this.tareas});

  @override
  MayordomoWidgetState createState() => MayordomoWidgetState();
  // El State es público (sin _) para que GlobalKey pueda acceder a sus métodos
}

class MayordomoWidgetState extends State<MayordomoWidget>
    with TickerProviderStateMixin {

  // ── Animaciones ────────────────────────────────────────────────────────────
  late AnimationController _reboteController;
  late Animation<double>   _reboteAnim;
  // Animación de rebote idle — el Mayordomo flota suavemente


  // ── Estado ─────────────────────────────────────────────────────────────────
  String? _mensajeActual;
  bool    _globoVisible = false;
  Timer?  _timerRevision;
  Timer?  _timerOcultarGlobo;
  bool    _ojosCerrados = false;
  Timer?  _timerParpadeo;

  // Frases del Mayordomo organizadas por situación
  static const _saludos = [
    '¡Bienvenido de vuelta, señor/a! Tengo su agenda lista.',
    'Buenos días. ¿En qué puedo asistirle hoy?',
    'Un placer verle. Sus tareas le esperan.',
  ];

  static const _motivacion = [
    '¡Excelente trabajo! Siga así.',
    'Cada tarea completada es un paso adelante.',
    'El progreso de hoy construye el éxito de mañana.',
    '¡Magnifico! Digno de admiración.',
  ];

  static const _recordatorios = [
    'Permítame recordarle que tiene tareas pendientes.',
    'Hay asuntos que requieren su atención, señor/a.',
    'Si me permite, aún quedan tareas por resolver.',
  ];

  static const _felicitaciones = [
    '¡Extraordinario! Ha completado todas sus tareas. Me honra servirle.',
    '¡Todo listo! Puede descansar con la conciencia tranquila.',
    'Impresionante jornada. ¡Mis más sinceras felicitaciones!',
  ];

  @override
  void initState() {
    super.initState();

    // ── Animación de rebote idle ──────────────────────────────────────────
    _reboteController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    // repeat(reverse: true) = va de 0→1→0→1→... indefinidamente

    _reboteAnim = Tween<double>(begin: 0, end: -8).animate(
      CurvedAnimation(parent: _reboteController, curve: Curves.easeInOut),
    );
    // Mueve el personaje 8px hacia arriba y de vuelta — efecto flotación

    // ── Parpadeo ocasional ────────────────────────────────────────────────
    _programarParpadeo();

    // ── Saludo inicial (con pequeño delay para que la app cargue primero) ─
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) mostrarMensaje(_saludoAleatorio());
    });

    // ── Timer de revisión cada 5 minutos ──────────────────────────────────
    _timerRevision = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) _revisarTareas();
    });
  }

  @override
  void didUpdateWidget(MayordomoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // didUpdateWidget se llama DESPUÉS de que Flutter reconstruyó el widget
    // con las nuevas props — es el momento seguro para llamar setState.

    final total   = widget.tareas.length;
    final anterior = oldWidget.tareas.length;

    // ── Nueva tarea agregada ───────────────────────────────────────────
    if (total > anterior) {
      final nueva = widget.tareas.first;
      // .first porque HomeScreen inserta al principio: _tareas.insert(0, tarea)

      if (nueva.horaLimite != null) {
        final partes  = nueva.horaLimite!.split(':');
        final horaStr = '${partes[0]}:${partes[1]}';
        mostrarMensaje('Entendido. Le recordaré\n"${nueva.titulo}"\na las $horaStr.');
      } else {
        mostrarMensaje('Tarea registrada.\n¡A por ella, señor/a!');
      }
      return;
    }

    // ── Todas las tareas completadas ───────────────────────────────────
    final antesCompletadas = oldWidget.tareas.where((t) => t.estaCompletada).length;
    final ahoraCompletadas = widget.tareas.where((t) => t.estaCompletada).length;

    if (total > 0 && ahoraCompletadas == total && antesCompletadas < total) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) mostrarMensaje(_felicitacionAleatoria());
      });
    }
  }

  @override
  void dispose() {
    _reboteController.dispose();
    _timerRevision?.cancel();
    _timerOcultarGlobo?.cancel();
    _timerParpadeo?.cancel();
    super.dispose();
  }

  // ── Lógica de mensajes ────────────────────────────────────────────────────

  void _revisarTareas() {
    final pendientes = widget.tareas.where((t) => t.estaPendiente).length;
    final total      = widget.tareas.length;

    if (total == 0) return;

    if (pendientes == 0) {
      mostrarMensaje(_felicitacionAleatoria());
    } else if (pendientes > 0) {
      mostrarMensaje(_recordatorioAleatorio());
    }
  }

  void mostrarMensaje(String mensaje) {
    // Si ya hay un globo visible, lo cancelamos primero
    _timerOcultarGlobo?.cancel();

    setState(() {
      _mensajeActual = mensaje;
      _globoVisible  = true;
    });

    // Auto-ocultar después de 6 segundos
    _timerOcultarGlobo = Timer(const Duration(seconds: 6), _ocultarGlobo);
  }

  void _ocultarGlobo() {
    if (mounted) setState(() => _globoVisible = false);
  }

  void _alTocarPersonaje() {
    if (_globoVisible) {
      _ocultarGlobo();
    } else {
      // Mostrar un mensaje motivacional aleatorio
      mostrarMensaje(_motivacionAleatoria());
    }
  }

  void _programarParpadeo() {
    // Cada 4-8 segundos (aleatorio) el Mayordomo parpadea
    final segundos = 4 + Random().nextInt(5);
    _timerParpadeo = Timer(Duration(seconds: segundos), () {
      if (!mounted) return;
      setState(() => _ojosCerrados = true);
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _ojosCerrados = false);
        _programarParpadeo(); // programa el siguiente parpadeo
      });
    });
  }

  // ── Selectores aleatorios ─────────────────────────────────────────────────
  String _saludoAleatorio()       => _saludos[Random().nextInt(_saludos.length)];
  String _motivacionAleatoria()   => _motivacion[Random().nextInt(_motivacion.length)];
  String _recordatorioAleatorio() => _recordatorios[Random().nextInt(_recordatorios.length)];
  String _felicitacionAleatoria() => _felicitaciones[Random().nextInt(_felicitaciones.length)];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      // Ancho fijo para que el globo no cambie el tamaño del Positioned padre
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Globo de diálogo ─────────────────────────────────────────
          // Condicional directo: más simple y confiable que AnimatedOpacity.
          // Al estar en Positioned(bottom:80), el widget crece hacia arriba
          // cuando el globo aparece — exactamente lo que queremos.
          if (_globoVisible) ...[
            _buildGloboDialogo(),
            const SizedBox(height: 10),
          ],

          // ── Personaje (con animación de rebote) ──────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedBuilder(
                animation: _reboteAnim,
                builder: (context, child) => Transform.translate(
                  offset: Offset(0, _reboteAnim.value),
                  child: child,
                ),
                child: GestureDetector(
                  onTap: _alTocarPersonaje,
                  child: _buildPersonaje(),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Mayordomo',
                style: TextStyle(color: Colors.white54, fontSize: 11,
                    fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPersonaje() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [

        // ── Cuerpo: más grande (80px) para parecerse al mago ───────────
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF1A1040), AppTheme.primario],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primario.withOpacity(0.5),
                blurRadius: 16,
                spreadRadius: 3,
              ),
            ],
          ),
          child: _buildCara(),
        ),

        // ── Sombrero de mago ───────────────────────────────────────────
        const Positioned(
          top: -18,
          child: Text('🧙', style: TextStyle(fontSize: 28)),
        ),
      ],
    );
  }

  Widget _buildCara() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 10), // espacio para el sombrero
        // ── Ojos ──────────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildOjo(),
            const SizedBox(width: 10),
            _buildOjo(),
          ],
        ),
        const SizedBox(height: 5),
        // ── Sonrisa ────────────────────────────────────────────────────
        Container(
          width: 16,
          height: 6,
          decoration: BoxDecoration(
            border: Border(
              bottom: const BorderSide(color: Colors.white70, width: 2),
              left:   const BorderSide(color: Colors.white70, width: 2),
              right:  const BorderSide(color: Colors.white70, width: 2),
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft:  Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOjo() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      width: 8,
      height: _ojosCerrados ? 2 : 8,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildGloboDialogo() {
    return Container(
      width: 190,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        // Fondo blanco cremoso como en la imagen del mago
        color: const Color(0xFFFFFDE8),
        borderRadius: const BorderRadius.only(
          topLeft:     Radius.circular(16),
          topRight:    Radius.circular(16),
          bottomRight: Radius.circular(16),
          bottomLeft:  Radius.circular(4),
        ),
        border: Border.all(color: const Color(0xFFCCBB44), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 10,
            offset: const Offset(2, 4),
          ),
        ],
      ),
      child: Text(
        _mensajeActual ?? '...',
        style: const TextStyle(
          color: Color(0xFF1A1A1A),
          // Texto oscuro sobre fondo claro — igual que en el Mayordomo original
          fontSize: 13,
          height: 1.45,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
