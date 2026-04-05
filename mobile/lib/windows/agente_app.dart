// windows/agente_app.dart
// ─────────────────────────────────────────────────────────────────────────────
// Ventana secundaria flotante: el Agente Desktop.
// Corre en el mismo proceso que la app principal (mismo exe, nuevo Flutter engine).
// Fondo transparente, sin bordes, siempre encima — igual que Microsoft Agent.
//
// Recibe mensajes desde la app principal vía:
//   controller.invokeMethod('mostrarMensaje', 'texto')
//
// El usuario puede:
//   - Arrastrar el Agente a cualquier posición de la pantalla
//   - Click izquierdo: mostrar saludo / ocultar globo
//   - Click derecho: menú contextual (Abrir App, Saludar, Cerrar)
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
        // Negro puro = color de LWA_COLORKEY → se vuelve transparente.
        // Colors.transparent (alpha=0) renderiza como blanco (fondo GDI por defecto)
        // en ventanas secundarias, lo que oculta el globo blanco.
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

  // ── Animaciones ────────────────────────────────────────────────────────────
  late AnimationController _flotarCtrl;
  late AnimationController _saludarCtrl;
  late AnimationController _respCtrl;
  late Animation<double>   _flotarAnim;
  late Animation<double>   _saludarAnim;
  late Animation<double>   _respAnim;

  // ── Estado ─────────────────────────────────────────────────────────────────
  String? _mensaje;
  bool    _globoVisible = false;
  bool    _ojosCerrados = false;
  bool    _saludando    = false;
  Timer?  _timerGlobo;
  Timer?  _timerParpadeo;
  Timer?  _timerPoll;

  // Personaje actual
  Personaje _personaje = Personaje.todos[0]; // Carlos por defecto

  // Cola de mensajes pendientes (el methodHandler escribe aquí,
  // el timer periódico lee y actualiza la UI)
  static String? _mensajePendiente;
  static bool    _saludoPendiente = false;
  static String? _personajePendiente;

  @override
  void initState() {
    super.initState();

    // Flotación suave (sube y baja 10px)
    _flotarCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _flotarAnim = Tween<double>(begin: 0, end: -10).animate(
      CurvedAnimation(parent: _flotarCtrl, curve: Curves.easeInOut),
    );

    // IMPORTANTE: forzar rebuild completo en cada frame de animación Y procesar
    // mensajes pendientes aquí mismo.
    //
    // ¿Por qué? En ventanas secundarias de Flutter (desktop_multi_window),
    // setState() llamado desde Timer.periodic o el methodHandler NO garantiza
    // que la ventana se repinte. El único mecanismo confiable es el listener del
    // AnimationController, que corre dentro del frame scheduler.
    // Al procesar los mensajes pendientes AQUÍ, garantizamos que cualquier
    // cambio de estado se refleja inmediatamente en el mismo frame.
    _flotarCtrl.addListener(() {
      if (!mounted) return;

      // ── Procesar mensajes pendientes ────────────────────────────────────
      if (_mensajePendiente != null) {
        final msg = _mensajePendiente!;
        _mensajePendiente = null;
        _mostrarMensajeInterno(msg);
      }
      if (_saludoPendiente) {
        _saludoPendiente = false;
        // Solo agitar el brazo como señal de atención.
        // NO llamar _saludarConMensaje() porque eso sobreescribiría el mensaje
        // de la tarea con el saludo genérico.
        _saludar();
      }
      if (_personajePendiente != null) {
        final id = _personajePendiente!;
        _personajePendiente = null;
        _personaje = Personaje.obtenerPorId(id);
        debugPrint('[AgenteApp] Personaje cambiado a ${_personaje.nombre}');
      }

      setState(() {});
    });

    // Brazo saludando
    _saludarCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 280),
    );
    _saludarAnim = Tween<double>(begin: 0, end: 0.65).animate(
      CurvedAnimation(parent: _saludarCtrl, curve: Curves.easeInOut),
    );

    // Respiración idle (escala del torso)
    _respCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
    _respAnim = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _respCtrl, curve: Curves.easeInOut),
    );

    _programarParpadeo();
    _cargarPersonaje();

    // Registrar handler para mensajes desde la app principal.
    // NOTA: el handler NO puede llamar setState directamente porque Flutter
    // no repinta la ventana secundaria desde el callback del channel.
    // El mensaje se encola en _mensajePendiente y el AnimationListener
    // lo procesa en el próximo frame (mecanismo primario) o el Timer
    // de respaldo lo procesa a los 500ms.
    widget.controller.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'mostrarMensaje':
          _mensajePendiente = call.arguments as String;
          break;
        case 'saludar':
          _saludoPendiente = true;
          break;
        case 'cambiarPersonaje':
          _personajePendiente = call.arguments as String;
          break;
        default:
          debugPrint('[AgenteApp] Método desconocido: ${call.method}');
      }
      return null;
    });

    // Timer de respaldo: si el AnimationListener no procesó el mensaje en 500ms
    // (p. ej. ticker pausado), el poll lo procesa igual.
    _timerPoll = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      if (_mensajePendiente != null) {
        final msg = _mensajePendiente!;
        _mensajePendiente = null;
        mostrarMensaje(msg);
      }
      if (_saludoPendiente) {
        _saludoPendiente = false;
        _saludar();
      }
      if (_personajePendiente != null) {
        final id = _personajePendiente!;
        _personajePendiente = null;
        _personaje = Personaje.obtenerPorId(id);
      }
    });

    // Saludo inicial
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _saludarConMensaje();
    });
  }

  // ── Saludo: animación de brazo + mensaje ────────────────────────────────

  void _saludar() {
    if (_saludando) return;
    _saludando = true;

    _agitarBrazo().then((_) => _agitarBrazo()).then((_) => _agitarBrazo())
        .then((_) => _saludando = false);
  }

  Future<void> _cargarPersonaje() async {
    final id = await StorageService.obtenerPersonaje();
    if (mounted) setState(() => _personaje = Personaje.obtenerPorId(id));
  }

  void _saludarConMensaje() {
    // FIX: si ya hay un mensaje de tarea visible, NO sobreescribir.
    // El saludo genérico tiene menor prioridad que cualquier mensaje de alarma.
    if (_globoVisible) {
      debugPrint('[AgenteApp] _saludarConMensaje ignorado: ya hay mensaje visible: "$_mensaje"');
      return;
    }
    final hora   = DateTime.now().hour;
    final saludo = hora < 12 ? 'Buenos días' :
                   hora < 18 ? 'Buenas tardes' : 'Buenas noches';
    mostrarMensaje('$saludo 👋\n¿En qué le puedo\nasistir hoy?');
  }

  Future<void> _agitarBrazo() async {
    if (!mounted) return;
    await _saludarCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await _saludarCtrl.reverse();
  }

  // Llamado desde el AnimationController listener (siempre dentro de un frame).
  // NO llama setState directamente porque el listener ya lo hará al final.
  void _mostrarMensajeInterno(String texto) {
    if (!mounted) return;

    _timerGlobo?.cancel();
    _mensaje      = texto;
    _globoVisible = true;
    // No llamamos setState aquí — el listener lo hará inmediatamente después.

    _hablar(texto);
    if (!_saludando) _saludar();

    _timerGlobo = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _globoVisible = false);
    });
  }

  void mostrarMensaje(String texto) {
    _timerGlobo?.cancel();
    if (!mounted) {
      _mensajePendiente = texto;
      return;
    }
    setState(() {
      _mensaje      = texto;
      _globoVisible = true;
    });

    _hablar(texto);
    if (!_saludando) _saludar();

    _timerGlobo = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _globoVisible = false);
    });
  }

  /// Usa el sintetizador de voz de Windows (SAPI) via PowerShell
  void _hablar(String texto) {
    final textoLimpio = _limpiarTexto(texto);
    if (textoLimpio.isEmpty) return;

    Process.run('powershell', [
      '-WindowStyle', 'Hidden',
      '-Command',
      'Add-Type -AssemblyName System.Speech; '
      '\$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; '
      '\$s.Rate = 1; '
      '\$s.SelectVoiceByHints([System.Speech.Synthesis.VoiceGender]::Male); '
      '\$s.Speak("$textoLimpio");',
    ]).catchError((e) {
      debugPrint('[AgenteApp] Error voz: $e');
    });
  }

  /// Muestra una notificación de sistema de Windows (globo en bandeja del sistema)
  void _notificacionWindows(String titulo, String texto) {
    final textoLimpio = _limpiarTexto(texto);

    Process.run('powershell', [
      '-WindowStyle', 'Hidden',
      '-Command',
      'Add-Type -AssemblyName System.Windows.Forms; '
      '\$n = New-Object System.Windows.Forms.NotifyIcon; '
      '\$n.Icon = [System.Drawing.SystemIcons]::Information; '
      '\$n.BalloonTipIcon = "Info"; '
      '\$n.BalloonTipTitle = "$titulo"; '
      '\$n.BalloonTipText = "$textoLimpio"; '
      '\$n.Visible = \$true; '
      '\$n.ShowBalloonTip(10000); '
      'Start-Sleep -Seconds 10; '
      '\$n.Dispose();',
    ]).catchError((e) {
      debugPrint('[AgenteApp] Error notificación: $e');
    });
  }

  String _limpiarTexto(String texto) {
    return texto
        .replaceAll(RegExp(r'[^\w\sáéíóúñüÁÉÍÓÚÑÜ¿¡.,!?:;\-\n"()]'), '')
        .replaceAll('\n', ' ')
        .replaceAll('"', "'")
        .trim();
  }

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

  @override
  void dispose() {
    _flotarCtrl.dispose();
    _saludarCtrl.dispose();
    _respCtrl.dispose();
    _timerGlobo?.cancel();
    _timerParpadeo?.cancel();
    _timerPoll?.cancel();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000), // negro = transparente vía LWA_COLORKEY
      body: GestureDetector(
        // Arrastrar = mover toda la ventana transparente
        onPanStart: (_) => win32.iniciarArrastre(),
        // Click izquierdo: alternar globo
        onTap: () {
          if (_globoVisible) {
            setState(() => _globoVisible = false);
          } else {
            _saludarConMensaje();
          }
        },
        // Click derecho: menú contextual
        onSecondaryTapUp: _abrirMenu,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Globo de diálogo ────────────────────────────────────────
            if (_globoVisible) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildGlobo(),
              ),
              // Cola del globo apuntando al personaje
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: CustomPaint(
                    size: const Size(24, 14),
                    painter: _ColaPainter(),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 4),

            // ── Personaje animado ───────────────────────────────────────
            AnimatedBuilder(
              animation: _flotarAnim,
              builder: (ctx, child) => Transform.translate(
                offset: Offset(0, _flotarAnim.value),
                child: child,
              ),
              child: _buildPersonaje(),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ── Personaje moderno ──────────────────────────────────────────────────────

  Widget _buildPersonaje() {
    final p = _personaje;
    return SizedBox(
      width: 140,
      height: 220,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [

          // Sombra difusa bajo el personaje
          Positioned(
            bottom: 0,
            child: Container(
              width: 90, height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 18, spreadRadius: 8,
                  ),
                ],
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

          // Cuerpo (con respiración)
          Positioned(
            bottom: 42,
            child: AnimatedBuilder(
              animation: _respAnim,
              builder: (ctx, child) => Transform.scale(scaleX: _respAnim.value, child: child),
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
                  boxShadow: [
                    BoxShadow(
                      color: p.trajeTop.withValues(alpha: 0.45),
                      blurRadius: 20, spreadRadius: 2, offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(child: Container(
                  width: 10, height: 40,
                  margin: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(color: p.corbata, borderRadius: BorderRadius.circular(5)),
                )),
              ),
            ),
          ),

          // Brazo izquierdo
          Positioned(bottom: 78, left: 16, child: Container(
            width: 18, height: 68,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [p.trajeTop, p.trajeBottom],
                begin: Alignment.topCenter, end: Alignment.bottomCenter),
              borderRadius: BorderRadius.circular(9),
            ),
          )),

          // Brazo derecho (saluda)
          Positioned(
            bottom: 100, right: 16,
            child: AnimatedBuilder(
              animation: _saludarAnim,
              builder: (ctx, child) => Transform.rotate(
                angle: -_saludarAnim.value, alignment: Alignment.topCenter, child: child),
              child: Container(
                width: 18, height: 68,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [p.trajeTop, p.trajeBottom],
                    begin: Alignment.topCenter, end: Alignment.bottomCenter),
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
          ),

          // Mano derecha (visible al saludar)
          Positioned(
            bottom: 160, right: 8,
            child: AnimatedBuilder(
              animation: _saludarAnim,
              builder: (ctx, child) {
                final opacity = (_saludarAnim.value / 0.65).clamp(0.0, 1.0);
                return Opacity(opacity: opacity, child: child);
              },
              child: Container(
                width: 20, height: 20,
                decoration: BoxDecoration(color: p.piel, shape: BoxShape.circle),
              ),
            ),
          ),

          // Cuello
          Positioned(bottom: 140, child: Container(width: 24, height: 20, color: p.piel)),

          // Cabeza
          Positioned(
            top: 0,
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

          // Cabello
          Positioned(
            top: 0,
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
          children: [ _buildOjo(), const SizedBox(width: 16), _buildOjo() ],
        ),
        const SizedBox(height: 7),
        Container(
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
        ),
      ],
    );
  }

  Widget _buildOjo() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: 10,
      height: _ojosCerrados ? 2 : 10,
      decoration: BoxDecoration(
        color: _personaje.ojos,
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }

  Widget _buildGlobo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        // Color oscuro (NO blanco) para que sea visible sobre cualquier fondo.
        // El fondo del Scaffold es negro (LWA_COLORKEY = transparente), así que
        // el globo aparece flotando sobre el escritorio.
        color: const Color(0xFF1E1B4B),
        borderRadius: const BorderRadius.only(
          topLeft:     Radius.circular(18),
          topRight:    Radius.circular(18),
          bottomRight: Radius.circular(18),
          bottomLeft:  Radius.circular(4),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        _mensaje ?? '',
        style: const TextStyle(
          color:      Colors.white,
          fontSize:   14,
          height:     1.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ── Menú contextual ────────────────────────────────────────────────────────

  void _abrirMenu(TapUpDetails details) {
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
            Icon(Icons.open_in_new_rounded, size: 18, color: Color(0xFF7C3AED)),
            SizedBox(width: 10),
            Text('Abrir App', style: TextStyle(color: Colors.white)),
          ]),
          onTap: () => _abrirAppPrincipal(),
        ),
        PopupMenuItem(
          value: 'saludo',
          child: const Row(children: [
            Icon(Icons.waving_hand_rounded, size: 18, color: Colors.amber),
            SizedBox(width: 10),
            Text('Saludar', style: TextStyle(color: Colors.white)),
          ]),
          onTap: () => Future.delayed(const Duration(milliseconds: 200), _saludarConMensaje),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'cerrar',
          child: const Row(children: [
            Icon(Icons.close_rounded, size: 18, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Cerrar Agente', style: TextStyle(color: Colors.redAccent)),
          ]),
          onTap: () => win32.moverVentana(-1000, -1000, 260, 420),
        ),
      ],
    );
  }

  Future<void> _abrirAppPrincipal() async {
    try {
      // Buscar la ventana principal entre todas las ventanas del proceso
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

// ── Cola triangular del globo de diálogo ──────────────────────────────────────

class _ColaPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF1E1B4B);
    final path  = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}
