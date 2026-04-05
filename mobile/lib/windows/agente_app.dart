// windows/agente_app.dart
// ─────────────────────────────────────────────────────────────────────────────
// Ventana secundaria flotante: el Agente Desktop.
// Animaciones disponibles:
//   • Aparición Mágica    – partículas doradas en espiral + fade-in
//   • El Saludo           – agitar brazo + globo de diálogo
//   • Desaparición        – remolino + fade-out
//   • El Bostezador       – boca abierta + ZZZ (inactividad 5 min)
//   • El Lector Distraído – libro aparece + brazos bajan (inactividad 3 min)
//   • Rasca-Cabezas       – brazo sube a cabeza + globo "?" (errores)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:mobile/models/personaje.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/windows/win32_helper.dart' as win32;

class AgenteApp extends StatelessWidget {
  final WindowController controller;
  const AgenteApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF000000),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C3AED),
          brightness: Brightness.dark,
        ),
      ),
      home: _AgenteVentana(controller: controller),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _AgenteVentana extends StatefulWidget {
  final WindowController controller;
  const _AgenteVentana({required this.controller});

  @override
  State<_AgenteVentana> createState() => _AgenteVentanaState();
}

class _AgenteVentanaState extends State<_AgenteVentana>
    with TickerProviderStateMixin {

  // ── Controladores de animación ─────────────────────────────────────────────
  late AnimationController _flotarCtrl;   // flotación idle
  late AnimationController _saludarCtrl;  // brazo saludo
  late AnimationController _respCtrl;     // respiración torso
  late AnimationController _aparCtrl;     // aparición / desaparición mágica
  late AnimationController _bostezCtrl;   // boca bostezando
  late AnimationController _zzzCtrl;      // letras ZZZ flotando
  late AnimationController _lecCtrl;      // libro (lector distraído)
  late AnimationController _rascaCtrl;    // brazo rascando cabeza

  late Animation<double> _flotarAnim;
  late Animation<double> _saludarAnim;
  late Animation<double> _respAnim;
  late Animation<double> _aparAnim;   // 0→1 aparición, 1→0 desaparición
  late Animation<double> _bostezAnim; // 0 boca cerrada → 1 boca abierta
  late Animation<double> _zzzAnim;    // 0→1 cada ciclo
  late Animation<double> _lecAnim;    // 0→1 libro abierto
  late Animation<double> _rascaAnim;  // 0→1 brazo arriba

  // ── Estado de animaciones especiales ──────────────────────────────────────
  bool _apareciendo    = false;
  bool _desapareciendo = false;
  bool _bostezando     = false;
  bool _leyendo        = false;
  bool _rascando       = false;
  bool _visible        = false; // personaje visible (tras aparición)

  // ── Estado UI ──────────────────────────────────────────────────────────────
  String? _mensaje;
  bool    _globoVisible  = false;
  bool    _globoEsError  = false; // "?" rojo vs. normal
  bool    _ojosCerrados  = false;
  bool    _saludando     = false;

  // ── Timers ─────────────────────────────────────────────────────────────────
  Timer? _timerGlobo;
  Timer? _timerParpadeo;
  Timer? _timerPoll;
  Timer? _timerInactividad;  // detecta idle para lector / bostezador

  // ── Personaje ──────────────────────────────────────────────────────────────
  Personaje _personaje = Personaje.todos[0];

  // ── Cola inter-isolate ─────────────────────────────────────────────────────
  static String? _mensajePendiente;
  static bool    _saludoPendiente    = false;
  static bool    _confusionPendiente = false;
  static String? _personajePendiente;

  // ── Constantes ─────────────────────────────────────────────────────────────
  static const _durApar   = Duration(milliseconds: 900);
  static const _durBostez = Duration(milliseconds: 600);
  static const _durLec    = Duration(milliseconds: 500);
  static const _durRasca  = Duration(milliseconds: 400);
  static const _idleLeer  = Duration(minutes: 3);
  static const _idleZzz   = Duration(minutes: 5);

  // ──────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    // Flotación idle
    _flotarCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _flotarAnim = Tween<double>(begin: 0, end: -10).animate(
      CurvedAnimation(parent: _flotarCtrl, curve: Curves.easeInOut),
    );

    // Procesar mensajes pendientes en cada frame (mecanismo confiable en
    // ventanas secundarias donde setState desde Timer no garantiza repaint).
    _flotarCtrl.addListener(() {
      if (!mounted) return;
      _procesarPendientes();
      setState(() {});
    });

    // Brazo saludando
    _saludarCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    _saludarAnim = Tween<double>(begin: 0, end: 0.65).animate(
      CurvedAnimation(parent: _saludarCtrl, curve: Curves.easeInOut),
    );

    // Respiración
    _respCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))
      ..repeat(reverse: true);
    _respAnim = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _respCtrl, curve: Curves.easeInOut),
    );

    // Aparición / desaparición mágica
    _aparCtrl = AnimationController(vsync: this, duration: _durApar);
    _aparAnim = CurvedAnimation(parent: _aparCtrl, curve: Curves.easeOut);

    // Bostezar
    _bostezCtrl = AnimationController(vsync: this, duration: _durBostez);
    _bostezAnim = CurvedAnimation(parent: _bostezCtrl, curve: Curves.easeInOut);

    // ZZZ (loop)
    _zzzCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _zzzAnim = _zzzCtrl; // valor 0→1 cada ciclo

    // Libro lector
    _lecCtrl = AnimationController(vsync: this, duration: _durLec);
    _lecAnim = CurvedAnimation(parent: _lecCtrl, curve: Curves.easeOut);

    // Rascar cabeza
    _rascaCtrl = AnimationController(vsync: this, duration: _durRasca);
    _rascaAnim = CurvedAnimation(parent: _rascaCtrl, curve: Curves.easeInOut);

    _programarParpadeo();
    _cargarPersonaje();
    _registrarHandler();
    _iniciarPoll();

    // Aparición mágica al lanzar
    Future.delayed(const Duration(milliseconds: 300), _iniciarAparicion);

    // Timer de inactividad
    _resetInactividad();
  }

  // ── Procesar cola inter-isolate ────────────────────────────────────────────

  void _procesarPendientes() {
    if (_mensajePendiente != null) {
      final msg = _mensajePendiente!;
      _mensajePendiente = null;
      _mostrarMensajeInterno(msg);
    }
    if (_saludoPendiente) {
      _saludoPendiente = false;
      _saludar();
    }
    if (_confusionPendiente) {
      _confusionPendiente = false;
      _iniciarRascarCabeza();
    }
    if (_personajePendiente != null) {
      final id = _personajePendiente!;
      _personajePendiente = null;
      _personaje = Personaje.obtenerPorId(id);
    }
  }

  // ── Handler de mensajes desde la app principal ─────────────────────────────

  void _registrarHandler() {
    widget.controller.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'mostrarMensaje':
          _mensajePendiente = call.arguments as String;
          break;
        case 'saludar':
          _saludoPendiente = true;
          break;
        case 'confundido':
          _confusionPendiente = true;
          break;
        case 'cambiarPersonaje':
          _personajePendiente = call.arguments as String;
          break;
        default:
          debugPrint('[AgenteApp] Método desconocido: ${call.method}');
      }
      return null;
    });
  }

  // ── Timer de respaldo (poll) ───────────────────────────────────────────────

  void _iniciarPoll() {
    _timerPoll = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      _procesarPendientes();
    });
  }

  // ── Inactividad ───────────────────────────────────────────────────────────

  void _resetInactividad() {
    _timerInactividad?.cancel();
    // Si estaba en animación idle, salir
    if (_bostezando) _detenerBostezar();
    if (_leyendo)    _detenerLeer();

    // Leer primero, luego bostezar
    _timerInactividad = Timer(_idleLeer, () {
      if (!mounted || _globoVisible) return;
      _iniciarLeer();
      // Después de otros 2 min adicionales: bostezar encima
      _timerInactividad = Timer(_idleZzz - _idleLeer, () {
        if (!mounted) return;
        _detenerLeer();
        _iniciarBostezar();
      });
    });
  }

  // ── 1. APARICIÓN MÁGICA ───────────────────────────────────────────────────

  Future<void> _iniciarAparicion() async {
    if (!mounted) return;
    setState(() { _apareciendo = true; _visible = false; });
    _aparCtrl.reset();
    await _aparCtrl.forward();
    if (!mounted) return;
    setState(() { _apareciendo = false; _visible = true; });
    // Saludo inicial después de aparecer
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) _saludarConMensaje();
  }

  // ── 2. DESAPARICIÓN EN REMOLINO ───────────────────────────────────────────

  Future<void> _iniciarDesaparicion({VoidCallback? onDone}) async {
    if (!mounted) return;
    setState(() { _desapareciendo = true; });
    _aparCtrl.value = 1.0;
    await _aparCtrl.reverse();
    if (!mounted) return;
    setState(() { _desapareciendo = false; _visible = false; });
    onDone?.call();
  }

  // ── 3. SALUDO ─────────────────────────────────────────────────────────────

  void _saludar() {
    if (_saludando) return;
    _saludando = true;
    _agitarBrazo()
        .then((_) => _agitarBrazo())
        .then((_) => _agitarBrazo())
        .then((_) { if (mounted) setState(() => _saludando = false); });
  }

  Future<void> _agitarBrazo() async {
    if (!mounted) return;
    await _saludarCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await _saludarCtrl.reverse();
  }

  void _saludarConMensaje() {
    if (_globoVisible) return;
    final hora = DateTime.now().hour;
    final saludo = hora < 12 ? 'Buenos días' : hora < 18 ? 'Buenas tardes' : 'Buenas noches';
    mostrarMensaje('$saludo 👋\n¿En qué le puedo\nasistir hoy?');
  }

  // ── 4. BOSTEZADOR ─────────────────────────────────────────────────────────

  Future<void> _iniciarBostezar() async {
    if (!mounted || _bostezando) return;
    setState(() => _bostezando = true);
    // Ciclos de bostezo: abrir, cerrar, pausa, repetir
    for (int i = 0; i < 3; i++) {
      if (!mounted || !_bostezando) break;
      await _bostezCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted || !_bostezando) break;
      await _bostezCtrl.reverse();
      await Future.delayed(const Duration(milliseconds: 2000));
    }
    if (mounted) _detenerBostezar();
  }

  void _detenerBostezar() {
    _bostezCtrl.reverse();
    if (mounted) setState(() => _bostezando = false);
  }

  // ── 5. LECTOR DISTRAÍDO ───────────────────────────────────────────────────

  Future<void> _iniciarLeer() async {
    if (!mounted || _leyendo) return;
    setState(() => _leyendo = true);
    _lecCtrl.forward();
  }

  void _detenerLeer() {
    _lecCtrl.reverse().then((_) {
      if (mounted) setState(() => _leyendo = false);
    });
  }

  // ── 6. RASCA-CABEZAS CONFUNDIDO ───────────────────────────────────────────

  Future<void> _iniciarRascarCabeza() async {
    if (!mounted || _rascando) return;
    setState(() { _rascando = true; _globoEsError = true; });
    mostrarMensaje('Hmm... 🤔\n¿Algo salió mal?');
    _rascaCtrl.forward();
    // Movimiento de rascar: ida y vuelta varias veces
    for (int i = 0; i < 4; i++) {
      if (!mounted || !_rascando) break;
      await _rascaCtrl.reverse();
      await Future.delayed(const Duration(milliseconds: 80));
      if (!mounted || !_rascando) break;
      await _rascaCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 80));
    }
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      _rascaCtrl.reverse();
      setState(() { _rascando = false; _globoEsError = false; });
    }
  }

  // ── Mensajes ──────────────────────────────────────────────────────────────

  void _mostrarMensajeInterno(String texto) {
    if (!mounted) return;
    _timerGlobo?.cancel();
    _mensaje      = texto;
    _globoVisible = true;
    _hablar(texto);
    if (!_saludando) _saludar();
    _timerGlobo = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _globoVisible = false);
    });
    _resetInactividad();
  }

  void mostrarMensaje(String texto) {
    _timerGlobo?.cancel();
    if (!mounted) { _mensajePendiente = texto; return; }
    setState(() { _mensaje = texto; _globoVisible = true; });
    _hablar(texto);
    if (!_saludando) _saludar();
    _timerGlobo = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _globoVisible = false);
    });
    _resetInactividad();
  }

  // ── Voz ───────────────────────────────────────────────────────────────────

  void _hablar(String texto) {
    final t = _limpiarTexto(texto);
    if (t.isEmpty) return;
    Process.run('powershell', [
      '-WindowStyle', 'Hidden', '-Command',
      'Add-Type -AssemblyName System.Speech; '
      '\$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; '
      '\$s.Rate = 1; '
      '\$s.SelectVoiceByHints([System.Speech.Synthesis.VoiceGender]::Male); '
      '\$s.Speak("$t");',
    ]).catchError((e) {
      debugPrint('[AgenteApp] Error voz: $e');
      return Process.run('echo', []);
    });
  }

  String _limpiarTexto(String t) => t
      .replaceAll(RegExp(r'[^\w\sáéíóúñüÁÉÍÓÚÑÜ¿¡.,!?:;\-\n"()]'), '')
      .replaceAll('\n', ' ').replaceAll('"', "'").trim();

  // ── Parpadeo ──────────────────────────────────────────────────────────────

  void _programarParpadeo() {
    _timerParpadeo = Timer(Duration(seconds: 3 + Random().nextInt(5)), () {
      if (!mounted) return;
      setState(() => _ojosCerrados = true);
      Future.delayed(const Duration(milliseconds: 140), () {
        if (mounted) setState(() => _ojosCerrados = false);
        _programarParpadeo();
      });
    });
  }

  Future<void> _cargarPersonaje() async {
    final id = await StorageService.obtenerPersonaje();
    if (mounted) setState(() => _personaje = Personaje.obtenerPorId(id));
  }

  @override
  void dispose() {
    _flotarCtrl.dispose();
    _saludarCtrl.dispose();
    _respCtrl.dispose();
    _aparCtrl.dispose();
    _bostezCtrl.dispose();
    _zzzCtrl.dispose();
    _lecCtrl.dispose();
    _rascaCtrl.dispose();
    _timerGlobo?.cancel();
    _timerParpadeo?.cancel();
    _timerPoll?.cancel();
    _timerInactividad?.cancel();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: GestureDetector(
        onPanStart: (_) { win32.iniciarArrastre(); _resetInactividad(); },
        onTap: () {
          _resetInactividad();
          if (_globoVisible) {
            setState(() => _globoVisible = false);
          } else {
            _saludarConMensaje();
          }
        },
        onSecondaryTapUp: _abrirMenu,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [

            // ── Partículas de aparición / desaparición ─────────────────────
            if (_apareciendo || _desapareciendo)
              AnimatedBuilder(
                animation: _aparCtrl,
                builder: (_, __) => CustomPaint(
                  size: const Size(260, 420),
                  painter: _RemolinoPainter(
                    progreso:  _aparAnim.value,
                    invirtiendo: _desapareciendo,
                  ),
                ),
              ),

            // ── Columna principal ──────────────────────────────────────────
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [

                // Globo de diálogo
                if (_globoVisible) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildGlobo(),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 48),
                      child: CustomPaint(
                        size: const Size(24, 14),
                        painter: _ColaPainter(
                          color: _globoEsError
                              ? const Color(0xFF7B0000)
                              : const Color(0xFF1E1B4B),
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 4),

                // ZZZ flotantes (bostezador)
                if (_bostezando)
                  AnimatedBuilder(
                    animation: _zzzAnim,
                    builder: (_, __) => _buildZzz(),
                  ),

                // Personaje con flotación
                AnimatedBuilder(
                  animation: _flotarAnim,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(0, _flotarAnim.value),
                    child: child,
                  ),
                  child: AnimatedOpacity(
                    opacity: _visible || _apareciendo || _desapareciendo ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 100),
                    child: AnimatedBuilder(
                      animation: _aparAnim,
                      builder: (_, child) => Transform.scale(
                        scale: _apareciendo
                            ? _aparAnim.value
                            : _desapareciendo
                                ? _aparAnim.value
                                : 1.0,
                        child: child,
                      ),
                      child: _buildPersonaje(),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // WIDGETS DE ANIMACIONES ESPECIALES
  // ══════════════════════════════════════════════════════════════════════════

  /// Letras ZZZ escalonadas que flotan hacia arriba
  Widget _buildZzz() {
    final t = _zzzAnim.value; // 0→1 en loop
    return SizedBox(
      width: 80, height: 60,
      child: Stack(
        children: List.generate(3, (i) {
          // Cada Z tiene un offset de fase de 1/3 del ciclo
          final fase = ((t + i / 3) % 1.0);
          final opacity = (fase < 0.7 ? fase / 0.3 : (1.0 - fase) / 0.3).clamp(0.0, 1.0);
          final y = -fase * 50.0;
          final x = i * 14.0 + fase * 6.0;
          final size = 12.0 + i * 3.0;
          return Positioned(
            left: 30 + x, top: 40 + y,
            child: Opacity(
              opacity: opacity,
              child: Text(
                'Z',
                style: TextStyle(
                  color: const Color(0xFFFFD700),
                  fontSize: size,
                  fontWeight: FontWeight.bold,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PERSONAJE
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildPersonaje() {
    final p = _personaje;
    return SizedBox(
      width: 140,
      height: 220,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [

          // Sombra
          Positioned(
            bottom: 0,
            child: Container(
              width: 90, height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 18, spreadRadius: 8,
                )],
              ),
            ),
          ),

          // Piernas
          Positioned(bottom: 2, left: 42, child: Container(
            width: 18, height: 44,
            decoration: BoxDecoration(color: p.pantalon, borderRadius: BorderRadius.circular(9)),
          )),
          Positioned(bottom: 2, right: 42, child: Container(
            width: 18, height: 44,
            decoration: BoxDecoration(color: p.pantalon, borderRadius: BorderRadius.circular(9)),
          )),

          // Zapatos
          Positioned(bottom: 0, left: 38, child: Container(
            width: 26, height: 12,
            decoration: BoxDecoration(color: p.zapatos, borderRadius: BorderRadius.circular(6)),
          )),
          Positioned(bottom: 0, right: 38, child: Container(
            width: 26, height: 12,
            decoration: BoxDecoration(color: p.zapatos, borderRadius: BorderRadius.circular(6)),
          )),

          // Cuerpo
          Positioned(
            bottom: 42,
            child: AnimatedBuilder(
              animation: _respAnim,
              builder: (_, child) => Transform.scale(scaleX: _respAnim.value, child: child),
              child: Container(
                width: 72, height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [p.trajeTop, p.trajeBottom],
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10), topRight: Radius.circular(10),
                    bottomLeft: Radius.circular(6), bottomRight: Radius.circular(6),
                  ),
                  boxShadow: [BoxShadow(
                    color: p.trajeTop.withValues(alpha: 0.45),
                    blurRadius: 20, spreadRadius: 2, offset: const Offset(0, 8),
                  )],
                ),
                child: Center(child: Container(
                  width: 10, height: 40,
                  margin: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(color: p.corbata, borderRadius: BorderRadius.circular(5)),
                )),
              ),
            ),
          ),

          // ── Brazo izquierdo ──────────────────────────────────────────────
          // En modo "lector": baja hacia el libro. Normal: cuelga al costado.
          AnimatedBuilder(
            animation: _lecAnim,
            builder: (_, child) {
              // Rotar brazo izq hacia adelante (ángulo positivo = hacia frente)
              final angle = _lecAnim.value * 0.5;
              return Positioned(
                bottom: 78 - _lecAnim.value * 10, left: 16,
                child: Transform.rotate(
                  angle: angle, alignment: Alignment.topCenter,
                  child: child,
                ),
              );
            },
            child: Container(
              width: 18, height: 68,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [p.trajeTop, p.trajeBottom],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter),
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),

          // ── Brazo derecho ────────────────────────────────────────────────
          // Saludo OU rascar cabeza OU lector (hacia libro)
          AnimatedBuilder(
            animation: Listenable.merge([_saludarAnim, _rascaAnim, _lecAnim]),
            builder: (_, child) {
              double angle;
              double bottom;
              if (_rascando) {
                // Brazo sube a la cabeza: rota hacia atrás/arriba
                angle  = -(_rascaAnim.value * 1.2);
                bottom = 100 + _rascaAnim.value * 40;
              } else if (_leyendo) {
                // Hacia el libro (igual que el izquierdo)
                angle  = _lecAnim.value * 0.5;
                bottom = 78 - (_lecAnim.value * 10).round().toDouble();
              } else {
                // Saludo normal
                angle  = -_saludarAnim.value;
                bottom = 100;
              }
              return Positioned(
                bottom: bottom, right: 16,
                child: Transform.rotate(
                  angle: angle, alignment: Alignment.topCenter,
                  child: child,
                ),
              );
            },
            child: Container(
              width: 18, height: 68,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [p.trajeTop, p.trajeBottom],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter),
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),

          // Mano derecha (saludo)
          AnimatedBuilder(
            animation: _saludarAnim,
            builder: (_, child) {
              if (_rascando || _leyendo) return const SizedBox.shrink();
              final opacity = (_saludarAnim.value / 0.65).clamp(0.0, 1.0);
              return Positioned(
                bottom: 160, right: 8,
                child: Opacity(opacity: opacity, child: child),
              );
            },
            child: Container(
              width: 20, height: 20,
              decoration: BoxDecoration(color: p.piel, shape: BoxShape.circle),
            ),
          ),

          // ── Libro (lector distraído) ────────────────────────────────────
          AnimatedBuilder(
            animation: _lecAnim,
            builder: (_, __) {
              if (_lecAnim.value < 0.05) return const SizedBox.shrink();
              return Positioned(
                bottom: 55, left: 40,
                child: Opacity(
                  opacity: _lecAnim.value,
                  child: _buildLibro(p),
                ),
              );
            },
          ),

          // Cuello
          Positioned(bottom: 140, child: Container(width: 24, height: 20, color: p.piel)),

          // ── Cabeza ───────────────────────────────────────────────────────
          Positioned(
            top: 0,
            child: AnimatedBuilder(
              animation: Listenable.merge([_lecAnim, _rascaAnim]),
              builder: (_, child) {
                // En modo lector: inclinar cabeza hacia abajo
                // En rascar: leve inclinación lateral
                double angle = 0;
                if (_leyendo)   angle =  _lecAnim.value * 0.25;
                if (_rascando)  angle = -_rascaAnim.value * 0.12;
                return Transform.rotate(angle: angle, child: child);
              },
              child: Container(
                width: 84, height: 84,
                decoration: BoxDecoration(
                  color: p.piel, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 12, offset: const Offset(0, 5),
                  )],
                ),
                child: _buildCara(),
              ),
            ),
          ),

          // Cabello
          Positioned(
            top: 0,
            child: AnimatedBuilder(
              animation: _rascaAnim,
              builder: (_, child) {
                // Sombrero/cabello se desplaza levemente al rascar
                final offsetX = _rascaAnim.value * 6;
                final offsetY = -_rascaAnim.value * 4;
                return Transform.translate(offset: Offset(offsetX, offsetY), child: child);
              },
              child: ClipOval(
                child: SizedBox(
                  width: 84, height: 84,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      width: 84, height: 40,
                      decoration: BoxDecoration(
                        color: p.pelo,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(42), topRight: Radius.circular(42)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Libro pequeño entre las manos del personaje
  Widget _buildLibro(Personaje p) {
    return Container(
      width: 52, height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFF5C3A1E),
        borderRadius: BorderRadius.circular(3),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 6)],
      ),
      child: Row(
        children: [
          // Lomo del libro
          Container(
            width: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF3E2510),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(3), bottomLeft: Radius.circular(3)),
            ),
          ),
          // Páginas con líneas
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(3),
              color: const Color(0xFFFFF8E1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(4, (_) => Container(
                  height: 1.5,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  color: const Color(0xFFBDBDBD),
                )),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCara() {
    final p = _personaje;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [_buildOjo(), const SizedBox(width: 16), _buildOjo()],
        ),
        const SizedBox(height: 7),
        // Boca: sonrisa normal ↔ círculo bostezando
        AnimatedBuilder(
          animation: _bostezAnim,
          builder: (_, __) {
            final bostez = _bostezAnim.value;
            if (bostez > 0.1) {
              // Boca abierta (óvalo)
              return Container(
                width:  16 + bostez * 8,
                height:  8 + bostez * 14,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A0A00),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.sonrisa, width: 1.5),
                ),
              );
            }
            // Sonrisa normal
            return Container(
              width: 24, height: 11,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: p.sonrisa, width: 2.5),
                  left:   BorderSide(color: p.sonrisa, width: 2.5),
                  right:  BorderSide(color: p.sonrisa, width: 2.5),
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildOjo() {
    // En bostezador: ojos semicerrados
    final alturaOjo = _bostezando
        ? (_bostezAnim.value > 0.3 ? 3.0 : 10.0)
        : (_ojosCerrados ? 2.0 : 10.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: 10, height: alturaOjo,
      decoration: BoxDecoration(
        color: _personaje.ojos,
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GLOBO DE DIÁLOGO
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildGlobo() {
    final bgColor = _globoEsError
        ? const Color(0xFF7B0000)
        : const Color(0xFF1E1B4B);
    final glowColor = _globoEsError
        ? Colors.red.withValues(alpha: 0.5)
        : const Color(0xFF7C3AED).withValues(alpha: 0.45);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.only(
          topLeft:     Radius.circular(18),
          topRight:    Radius.circular(18),
          bottomRight: Radius.circular(18),
          bottomLeft:  Radius.circular(4),
        ),
        boxShadow: [BoxShadow(color: glowColor, blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Text(
        _mensaje ?? '',
        style: const TextStyle(
          color: Colors.white, fontSize: 14, height: 1.5, fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MENÚ CONTEXTUAL
  // ══════════════════════════════════════════════════════════════════════════

  void _abrirMenu(TapUpDetails details) {
    _resetInactividad();
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    showMenu<String>(
      context: context,
      color:   const Color(0xFF1E1B4B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'abrir',
          child: const Row(children: [
            Icon(Icons.open_in_new_rounded,   size: 18, color: Color(0xFF7C3AED)),
            SizedBox(width: 10),
            Text('Abrir App', style: TextStyle(color: Colors.white)),
          ]),
          onTap: _abrirAppPrincipal,
        ),
        PopupMenuItem(
          value: 'saludo',
          child: const Row(children: [
            Icon(Icons.waving_hand_rounded,   size: 18, color: Colors.amber),
            SizedBox(width: 10),
            Text('Saludar', style: TextStyle(color: Colors.white)),
          ]),
          onTap: () => Future.delayed(
            const Duration(milliseconds: 200), _saludarConMensaje),
        ),
        PopupMenuItem(
          value: 'leer',
          child: const Row(children: [
            Icon(Icons.menu_book_rounded,     size: 18, color: Color(0xFF5C3A1E)),
            SizedBox(width: 10),
            Text('Leer libro', style: TextStyle(color: Colors.white)),
          ]),
          onTap: () => Future.delayed(
            const Duration(milliseconds: 200),
            () => _leyendo ? _detenerLeer() : _iniciarLeer()),
        ),
        PopupMenuItem(
          value: 'confundido',
          child: const Row(children: [
            Icon(Icons.help_outline_rounded,  size: 18, color: Colors.orange),
            SizedBox(width: 10),
            Text('Confundido', style: TextStyle(color: Colors.white)),
          ]),
          onTap: () => Future.delayed(
            const Duration(milliseconds: 200), _iniciarRascarCabeza),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'cerrar',
          child: const Row(children: [
            Icon(Icons.close_rounded,         size: 18, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Cerrar Agente', style: TextStyle(color: Colors.redAccent)),
          ]),
          onTap: () => _iniciarDesaparicion(
            onDone: () => win32.moverVentana(-2000, -2000, 260, 420)),
        ),
      ],
    );
  }

  Future<void> _abrirAppPrincipal() async {
    try {
      final todos = await WindowController.getAll();
      for (final c in todos) {
        if (c.arguments != 'agente') {
          await c.invokeMethod('abrirApp', null);
          break;
        }
      }
    } catch (_) {}
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PAINTERS
// ══════════════════════════════════════════════════════════════════════════════

/// Partículas doradas en espiral para la aparición / desaparición mágica
class _RemolinoPainter extends CustomPainter {
  final double progreso;    // 0→1
  final bool   invirtiendo; // true = desaparición (partículas giran hacia dentro)

  const _RemolinoPainter({required this.progreso, required this.invirtiendo});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height * 0.62; // centrado sobre el personaje
    const totalParticulas = 40;
    const radioMax = 90.0;

    for (int i = 0; i < totalParticulas; i++) {
      final fraccion = i / totalParticulas;
      // Ángulo base + rotación progresiva
      final angulo = fraccion * 2 * pi * 3 + progreso * 4 * pi;
      // Radio: crece durante aparición, decrece durante desaparición
      final radio = invirtiendo
          ? radioMax * (1 - progreso) * fraccion
          : radioMax * progreso * fraccion;

      final x = cx + cos(angulo) * radio;
      final y = cy + sin(angulo) * radio * 0.5; // elipse vertical

      // Opacidad basada en el progreso de cada partícula
      final opacity = (invirtiendo ? (1 - progreso) : progreso).clamp(0.0, 1.0);
      final tamano  = (2.0 + fraccion * 4.0) * opacity;

      // Degradado dorado → naranja → blanco
      final t = fraccion;
      final color = Color.lerp(
        const Color(0xFFFFD700),
        t < 0.5 ? const Color(0xFFFFA500) : Colors.white,
        t < 0.5 ? t * 2 : (t - 0.5) * 2,
      )!.withValues(alpha: opacity);

      canvas.drawCircle(
        Offset(x, y),
        tamano,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RemolinoPainter old) =>
      old.progreso != progreso || old.invirtiendo != invirtiendo;
}

/// Cola triangular del globo
class _ColaPainter extends CustomPainter {
  final Color color;
  const _ColaPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ColaPainter old) => old.color != color;
}
