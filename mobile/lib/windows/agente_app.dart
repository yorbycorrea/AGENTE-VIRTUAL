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
import 'package:rive/rive.dart' hide LinearGradient;

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

  // ── Rive personaje ─────────────────────────────────────────────────────────
  // El archivo Rive viene directamente del personaje seleccionado
  String get _riveAsset => _personaje.riveAsset;

  StateMachineController? _riveSMCtrl;
  SMITrigger?             _riveTrigSaludar;
  SMITrigger?             _riveTrigConfundido;
  SMITrigger?             _riveTrigFeliz;
  SMITrigger?             _riveTrigTriste;
  SMINumber?              _riveNumExpresion;

  // ── TTS ────────────────────────────────────────────────────────────────────
  // null = sin verificar, true = edge-tts disponible, false = solo SAPI
  static bool? _edgeTtsDisponible;

  // Proceso de reproducción activo — se mata antes de iniciar uno nuevo
  // para evitar que dos voces suenen al mismo tiempo.
  Process? _procesoVoz;

  // Voces en español — ordenadas de más formal a más natural
  static const _vozesId = [
    'es-ES-AlvaroNeural',
    'es-ES-EloyNeural',
    'es-MX-JorgeNeural',
    'es-AR-TomasNeural',
    'es-US-AlonsoNeural',
  ];
  static const _vozesNombre = [
    'Álvaro — Español España ★',
    'Eloy — Español Formal',
    'Jorge — Español México',
    'Tomás — Español Argentina',
    'Alonso — Español Latino',
  ];
  int _vozIndex = 0;

  String get _vozId     => _vozesId[_vozIndex];
  String get _vozNombre => _vozesNombre[_vozIndex];

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

    // Verificar edge-tts en paralelo con la aparición
    _verificarEdgeTts();

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
      _riveSMCtrl = null; // forzar reinicio de la animación Rive
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

  // ── TTS: verificación de edge-tts ─────────────────────────────────────────

  Future<void> _verificarEdgeTts() async {
    try {
      final r = await Process.run('python', ['-m', 'edge_tts', '--version']);
      _edgeTtsDisponible = r.exitCode == 0;
    } catch (_) {
      _edgeTtsDisponible = false;
    }
    debugPrint('[TTS] edge-tts: '
        '${_edgeTtsDisponible! ? "✓ disponible — voz: $_vozId" : "✗ no encontrado, usando SAPI"}');
  }

  // ── TTS: dispatcher principal ──────────────────────────────────────────────

  void _hablar(String texto) {
    final t = _limpiarTexto(texto);
    if (t.isEmpty) return;

    if (_edgeTtsDisponible == true) {
      _hablarEdgeTts(t);
    } else if (_edgeTtsDisponible == null) {
      // Todavía verificando: esperar y reintentar
      _verificarEdgeTts().then((_) { if (mounted) _hablar(texto); });
    } else {
      // edge-tts no disponible → SAPI como respaldo
      _hablarSAPI(t);
    }
  }

  // ── TTS: detener voz en curso ─────────────────────────────────────────────

  void _detenerVoz() {
    try { _procesoVoz?.kill(); } catch (_) {}
    _procesoVoz = null;
  }

  // ── TTS: Edge TTS (voz neural de alta calidad) ────────────────────────────

  Future<void> _hablarEdgeTts(String texto) async {
    _detenerVoz();
    // Archivo temporal único. Forward-slashes funcionan en Python y PowerShell.
    final ts       = DateTime.now().millisecondsSinceEpoch;
    final tempPath = Directory.systemTemp.path.replaceAll('\\', '/') +
        '/agent_tts_$ts.mp3';
    final voz = _vozId;

    try {
      // Todo en un único proceso PowerShell — guardamos el handle para poder matarlo.
      _procesoVoz = await Process.start('powershell', [
        '-WindowStyle', 'Hidden',
        '-NonInteractive',
        '-Command',
        'python -m edge_tts '
            '--voice $voz '
            '--text "${texto.replaceAll('"', "'")}" '
            '--write-media "$tempPath"; '
        'if (Test-Path "$tempPath") { '
            'Add-Type -AssemblyName PresentationCore; '
            '\$p = New-Object System.Windows.Media.MediaPlayer; '
            '\$p.Open([System.Uri]"$tempPath"); '
            'Start-Sleep -Milliseconds 900; '
            '\$dur = \$p.NaturalDuration.TimeSpan.TotalSeconds; '
            '\$wait = if (\$dur -gt 0) { [Math]::Ceiling(\$dur) + 1 } else { 15 }; '
            '\$p.Play(); '
            'Start-Sleep -Seconds \$wait; '
            '\$p.Close(); '
            'Remove-Item "$tempPath" -ErrorAction SilentlyContinue '
        '}',
      ]);
      await _procesoVoz!.exitCode;
    } catch (e) {
      debugPrint('[TTS] Error edge-tts: $e — cambiando a SAPI');
      _edgeTtsDisponible = false;
      if (mounted) _hablarSAPI(texto);
    } finally {
      _procesoVoz = null;
    }
  }

  // ── TTS: SAPI (Windows nativo, respaldo sin internet) ─────────────────────

  Future<void> _hablarSAPI(String texto) async {
    _detenerVoz();
    try {
      _procesoVoz = await Process.start('powershell', [
        '-WindowStyle', 'Hidden',
        '-Command',
        'Add-Type -AssemblyName System.Speech; '
        '\$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; '
        '\$s.Rate = 1; '
        'try { \$s.SelectVoice("Microsoft Sabina Desktop"); } catch { '
        '  try { \$s.SelectVoice("Microsoft Helena Desktop"); } catch { '
        '    \$s.SelectVoiceByHints([System.Speech.Synthesis.VoiceGender]::Male) } }; '
        '\$s.Speak("$texto");',
      ]);
      await _procesoVoz!.exitCode;
    } catch (e) {
      debugPrint('[TTS] Error SAPI: $e');
    } finally {
      _procesoVoz = null;
    }
  }

  // ── Selector de voz ────────────────────────────────────────────────────────

  void _mostrarSelectorVoz() {
    if (_edgeTtsDisponible != true) {
      // edge-tts no instalado: mostrar instrucciones
      showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: const Color(0xFF1E1B4B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber),
                  SizedBox(width: 8),
                  Text('edge-tts no instalado',
                      style: TextStyle(color: Colors.white, fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 12),
                const Text(
                  'Para usar voces neurales ejecutá:\n\n'
                  '  pip install edge-tts\n\n'
                  'Luego reiniciá el agente.',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Aceptar',
                        style: TextStyle(color: Color(0xFF7C3AED))),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          backgroundColor: const Color(0xFF1E1B4B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.record_voice_over_rounded, color: Color(0xFF7C3AED)),
                  SizedBox(width: 8),
                  Text('Seleccionar voz',
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ]),
                const SizedBox(height: 12),
                ...List.generate(_vozesId.length, (i) {
                  final activa = i == _vozIndex;
                  return InkWell(
                    onTap: () {
                      setState(() => _vozIndex = i);
                      setLocal(() {});
                      Navigator.of(ctx).pop();
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (mounted) _hablar('Listo. Voz activada. A su servicio.');
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: activa
                            ? const Color(0xFF7C3AED).withValues(alpha: 0.25)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: activa ? const Color(0xFF7C3AED) : Colors.white12,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            activa ? Icons.radio_button_checked : Icons.radio_button_off,
                            size: 16,
                            color: activa ? const Color(0xFF7C3AED) : Colors.white38,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _vozesNombre[i],
                              style: TextStyle(
                                color: activa ? Colors.white : Colors.white70,
                                fontWeight: activa ? FontWeight.w600 : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (i == 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('★ TOP',
                                style: TextStyle(color: Colors.amber, fontSize: 9,
                                    fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
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
    if (mounted) setState(() { _personaje = Personaje.obtenerPorId(id); _riveSMCtrl = null; });
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
    try { _procesoVoz?.kill(); } catch (_) {}
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

  // ── Rive: inicializar state machine ────────────────────────────────────────
  void _onRiveInit(Artboard artboard) {
    if (artboard.stateMachines.isEmpty) return;

    for (final sm in artboard.stateMachines) {
      debugPrint('[Rive] StateMachine: "${sm.name}"');
    }
    final smName = artboard.stateMachines.first.name;
    final ctrl   = StateMachineController.fromArtboard(artboard, smName);
    if (ctrl == null) return;

    artboard.addController(ctrl);
    _riveSMCtrl = ctrl;

    for (final input in ctrl.inputs) {
      debugPrint('[Rive] Input: "${input.name}" (${input.runtimeType})');
      final n = input.name.toLowerCase();
      if (input is SMITrigger) {
        if (n.contains('wave') || n.contains('hello') || n.contains('salud') ||
            n.contains('happy') || n.contains('feliz')) {
          _riveTrigSaludar  = input;
        } else if (n.contains('sad') || n.contains('angry') || n.contains('confus')) {
          _riveTrigConfundido = input;
        } else if (n.contains('excit') || n.contains('joy') || n.contains('love')) {
          _riveTrigFeliz = input;
        } else if (n.contains('cry') || n.contains('triste')) {
          _riveTrigTriste = input;
        }
      } else if (input is SMINumber) {
        if (n.contains('express') || n.contains('state') || n.contains('emotion')) {
          _riveNumExpresion = input;
        }
      }
    }
    debugPrint('[Rive] Mapeo → saludo:$_riveTrigSaludar | confundido:$_riveTrigConfundido');
  }

  Widget _buildPersonaje() {
    return SizedBox(
      width: 200,
      height: 240,
      child: RiveAnimation.asset(
        _riveAsset,
        key: ValueKey('${_personaje.id}_rive'),
        artboard: _personaje.riveArtboard,
        fit: BoxFit.contain,
        onInit: _onRiveInit,
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
        // ── Voz ──────────────────────────────────────────────────────────
        PopupMenuItem(
          value: 'voz',
          child: Row(
            children: [
              Icon(
                Icons.record_voice_over_rounded,
                size: 18,
                color: _edgeTtsDisponible == true
                    ? const Color(0xFF00E5FF)
                    : Colors.white38,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Cambiar voz',
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                    Text(
                      _edgeTtsDisponible == true ? _vozNombre : 'SAPI (instalar edge-tts)',
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 16, color: Colors.white38),
            ],
          ),
          onTap: () => Future.delayed(
              const Duration(milliseconds: 200), _mostrarSelectorVoz),
        ),
        // ── Personaje Rive ────────────────────────────────────────────────
        PopupMenuItem(
          value: 'personaje',
          child: Row(children: [
            const Icon(Icons.face_rounded, size: 18, color: Color(0xFF7C3AED)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Cambiar personaje',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                Text(_personaje.nombre,
                    style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            )),
            const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white38),
          ]),
          onTap: () => Future.delayed(
              const Duration(milliseconds: 200), _abrirAppPrincipal),
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

// ══════════════════════════════════════════════════════════════════════════════
// PAINTERS DEL PERSONAJE — Opción 2: formas orgánicas con curvas Bézier
// ══════════════════════════════════════════════════════════════════════════════

/// Pierna con ligero degradado y costura central
class _PiernaPainter extends CustomPainter {
  final Personaje p;
  _PiernaPainter(this.p);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    final path = Path()
      ..moveTo(1, 0)..lineTo(w - 1, 0)
      ..lineTo(w - 2, h)..lineTo(2, h)..close();
    canvas.drawPath(path, Paint()..shader = LinearGradient(
      colors: [p.pantalon, Color.lerp(p.pantalon, Colors.black, 0.22)!],
      begin: Alignment.topLeft, end: Alignment.bottomRight,
    ).createShader(Rect.fromLTWH(0, 0, w, h)));
    canvas.drawLine(Offset(w / 2, 3), Offset(w / 2, h - 4),
        Paint()..color = Colors.black.withValues(alpha: 0.10)
               ..strokeWidth = 1.0..style = PaintingStyle.stroke);
  }
  @override bool shouldRepaint(_PiernaPainter old) => old.p != p;
}

/// Zapato con punta redondeada, suela y reflejo
class _ZapatoPainter extends CustomPainter {
  final Personaje p;
  _ZapatoPainter(this.p);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    final path = Path()
      ..moveTo(4, 0)..lineTo(w - 10, 0)
      ..quadraticBezierTo(w - 1, 0, w - 1, h * 0.5)
      ..quadraticBezierTo(w - 1, h, w - 5, h)
      ..lineTo(3, h)
      ..quadraticBezierTo(0, h, 0, h * 0.5)
      ..quadraticBezierTo(0, 0, 4, 0)..close();
    canvas.drawPath(path, Paint()..color = p.zapatos);
    canvas.drawLine(Offset(2, h - 2), Offset(w - 3, h - 2),
        Paint()..color = Colors.black.withValues(alpha: 0.30)
               ..strokeWidth = 1.5..style = PaintingStyle.stroke);
    canvas.drawLine(Offset(w * 0.2, 3), Offset(w * 0.6, 3),
        Paint()..color = Colors.white.withValues(alpha: 0.20)
               ..strokeWidth = 1.5..strokeCap = StrokeCap.round
               ..style = PaintingStyle.stroke);
  }
  @override bool shouldRepaint(_ZapatoPainter old) => old.p != p;
}

/// Chaqueta/torso con solapas en V, corbata con nudo y costuras de hombro
class _TorsoPainter extends CustomPainter {
  final Personaje p;
  _TorsoPainter(this.p);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    final cx = w / 2;

    // ── Chaqueta principal ────────────────────────────────────────────────
    final suitPath = Path();
    suitPath.moveTo(cx - 16, 0);
    suitPath.cubicTo(cx - 30, 0, cx - 54, 10, cx - 52, 24);
    suitPath.lineTo(cx - 40, h);
    suitPath.lineTo(cx + 40, h);
    suitPath.lineTo(cx + 52, 24);
    suitPath.cubicTo(cx + 54, 10, cx + 30, 0, cx + 16, 0);
    suitPath.lineTo(cx + 8, 68);
    suitPath.lineTo(cx, 48);
    suitPath.lineTo(cx - 8, 68);
    suitPath.close();
    canvas.drawPath(suitPath, Paint()..shader = LinearGradient(
      colors: [p.trajeTop, p.trajeBottom],
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
    ).createShader(Rect.fromLTWH(0, 0, w, h)));

    // ── Camisa visible (triángulo blanco entre solapas) ───────────────────
    canvas.drawPath(
      Path()
        ..moveTo(cx - 16, 0)..lineTo(cx - 8, 68)
        ..lineTo(cx, 48)..lineTo(cx + 8, 68)
        ..lineTo(cx + 16, 0)..close(),
      Paint()..color = Colors.white.withValues(alpha: 0.88),
    );

    // ── Solapas con highlight ─────────────────────────────────────────────
    final lapelColor = Color.lerp(p.trajeTop, Colors.white, 0.13)!;
    canvas.drawPath(
      Path()..moveTo(cx - 16, 0)..lineTo(cx - 8, 68)
            ..lineTo(cx - 28, 54)..lineTo(cx - 32, 10)..close(),
      Paint()..color = lapelColor,
    );
    canvas.drawPath(
      Path()..moveTo(cx + 16, 0)..lineTo(cx + 8, 68)
            ..lineTo(cx + 28, 54)..lineTo(cx + 32, 10)..close(),
      Paint()..color = lapelColor,
    );

    // ── Nudo de corbata ───────────────────────────────────────────────────
    canvas.drawPath(
      Path()
        ..moveTo(cx - 5, 44)
        ..quadraticBezierTo(cx, 40, cx + 5, 44)
        ..quadraticBezierTo(cx + 6, 52, cx, 54)
        ..quadraticBezierTo(cx - 6, 52, cx - 5, 44)..close(),
      Paint()..color = p.corbata,
    );

    // ── Cuerpo de la corbata ──────────────────────────────────────────────
    canvas.drawPath(
      Path()
        ..moveTo(cx - 4, 53)..lineTo(cx - 7, h * 0.72)
        ..lineTo(cx, h * 0.88)..lineTo(cx + 7, h * 0.72)
        ..lineTo(cx + 4, 53)..close(),
      Paint()..color = p.corbata,
    );
    // Brillo diagonal
    canvas.drawLine(Offset(cx - 1, 58), Offset(cx - 3, h * 0.70),
        Paint()..color = Colors.white.withValues(alpha: 0.22)
               ..strokeWidth = 2.0..style = PaintingStyle.stroke);

    // ── Botón ─────────────────────────────────────────────────────────────
    canvas.drawCircle(Offset(cx, h * 0.58), 3.5,
        Paint()..color = p.corbata.withValues(alpha: 0.65));

    // ── Costuras de hombro ────────────────────────────────────────────────
    final seam = Paint()..color = Colors.black.withValues(alpha: 0.13)
        ..strokeWidth = 1.0..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - 52, 24), Offset(cx - 30, 6), seam);
    canvas.drawLine(Offset(cx + 52, 24), Offset(cx + 30, 6), seam);

    // ── Sombra lateral ────────────────────────────────────────────────────
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..shader = LinearGradient(
      colors: [Colors.black.withValues(alpha: 0.07), Colors.transparent,
               Colors.black.withValues(alpha: 0.07)],
      stops: const [0.0, 0.5, 1.0],
    ).createShader(Rect.fromLTWH(0, 0, w, h)));
  }
  @override bool shouldRepaint(_TorsoPainter old) => old.p != p;
}

/// Brazo cónico con puño de camisa visible en la muñeca
class _BrazoPainter extends CustomPainter {
  final Personaje p;
  _BrazoPainter(this.p);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    final path = Path()
      ..moveTo(2, 0)..lineTo(w - 2, 0)
      ..quadraticBezierTo(w, 2, w - 2, h * 0.5)
      ..lineTo(w - 4, h)..lineTo(4, h)
      ..lineTo(2, h * 0.5)
      ..quadraticBezierTo(0, 2, 2, 0)..close();
    canvas.drawPath(path, Paint()..shader = LinearGradient(
      colors: [p.trajeTop, Color.lerp(p.trajeTop, Colors.black, 0.28)!],
      begin: Alignment.topLeft, end: Alignment.bottomRight,
    ).createShader(Rect.fromLTWH(0, 0, w, h)));
    // Puño de camisa
    canvas.drawRect(Rect.fromLTWH(3, h - 11, w - 6, 9),
        Paint()..color = Colors.white.withValues(alpha: 0.62));
    canvas.drawRect(Rect.fromLTWH(3, h - 11, w - 6, 9),
        Paint()..color = Colors.black.withValues(alpha: 0.08)
               ..style = PaintingStyle.stroke..strokeWidth = 0.8);
  }
  @override bool shouldRepaint(_BrazoPainter old) => old.p != p;
}

/// Mano con palma + 3 dedos + pulgar
class _ManoPainter extends CustomPainter {
  final Color color;
  _ManoPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    final paint = Paint()..color = color;
    canvas.drawOval(Rect.fromCenter(center: Offset(w / 2, h * 0.62),
        width: w * 0.78, height: h * 0.62), paint);
    for (int i = 0; i < 3; i++) {
      canvas.drawOval(Rect.fromCenter(
          center: Offset(w * 0.22 + i * w * 0.28, h * 0.30),
          width: w * 0.24, height: h * 0.38), paint);
    }
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.06, h * 0.55),
        width: w * 0.22, height: h * 0.30), paint);
  }
  @override bool shouldRepaint(_ManoPainter old) => old.color != color;
}

/// Cabeza completa: orejas, pelo, cejas, ojos con destellos, nariz, boca animada
class _CabezaPainter extends CustomPainter {
  final Personaje personaje;
  final bool   ojosCerrados;
  final double bostezApertura;
  final bool   bostezando;
  final double rascaValue;

  const _CabezaPainter({
    required this.personaje,
    required this.ojosCerrados,
    required this.bostezApertura,
    required this.bostezando,
    required this.rascaValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2; // 70
    const cy = 50.0;
    const rx = 40.0;
    const ry = 46.0;
    final p = personaje;

    // ── Orejas ──────────────────────────────────────────────────────────────
    final earPaint      = Paint()..color = p.piel;
    final innerEarPaint = Paint()..color = Color.lerp(p.piel, Colors.redAccent, 0.18)!;
    canvas.drawOval(Rect.fromCenter(
        center: Offset(cx - rx + 3, cy + 6), width: 15, height: 22), earPaint);
    canvas.drawOval(Rect.fromCenter(
        center: Offset(cx - rx + 4, cy + 6), width:  8, height: 14), innerEarPaint);
    canvas.drawOval(Rect.fromCenter(
        center: Offset(cx + rx - 3, cy + 6), width: 15, height: 22), earPaint);
    canvas.drawOval(Rect.fromCenter(
        center: Offset(cx + rx - 4, cy + 6), width:  8, height: 14), innerEarPaint);

    // ── Base de la cabeza ────────────────────────────────────────────────────
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
      Paint()..color = p.piel,
    );
    // Reflejo sutil
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 7, cy - 10), width: rx * 1.2, height: ry * 0.9),
      Paint()..color = Colors.white.withValues(alpha: 0.07),
    );

    // ── Cabello (clipeado al óvalo, se desplaza al rascar) ────────────────────
    canvas.save();
    canvas.clipPath(Path()..addOval(
        Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2)));
    canvas.translate(rascaValue * 5, -rascaValue * 3);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - ry * 0.32), width: rx * 2.1, height: ry * 1.4),
      Paint()..color = p.pelo,
    );
    canvas.restore();

    // ── Cejas ────────────────────────────────────────────────────────────────
    final browPaint = Paint()
      ..color = Color.lerp(p.pelo, Colors.black, 0.35)!
      ..strokeWidth = 2.8..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(Path()
        ..moveTo(cx - 24, cy + 4)
        ..quadraticBezierTo(cx - 15, cy - 1, cx - 6, cy + 4), browPaint);
    canvas.drawPath(Path()
        ..moveTo(cx + 6, cy + 4)
        ..quadraticBezierTo(cx + 15, cy - 1, cx + 24, cy + 4), browPaint);

    // ── Ojos ────────────────────────────────────────────────────────────────
    final eyeH = bostezando
        ? (bostezApertura > 0.3 ? 3.0 : 10.0)
        : (ojosCerrados ? 2.0 : 10.0);
    const eyeY = cy + 16.0;

    if (eyeH > 4) {
      canvas.drawOval(Rect.fromCenter(center: Offset(cx - 15, eyeY),
          width: 16, height: eyeH + 4), Paint()..color = Colors.white);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx + 15, eyeY),
          width: 16, height: eyeH + 4), Paint()..color = Colors.white);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx - 15, eyeY + 1),
          width: 9, height: eyeH), Paint()..color = p.ojos);
      canvas.drawOval(Rect.fromCenter(center: Offset(cx + 15, eyeY + 1),
          width: 9, height: eyeH), Paint()..color = p.ojos);
      // Destellos
      final glint = Paint()..color = Colors.white.withValues(alpha: 0.92);
      canvas.drawCircle(Offset(cx - 12, eyeY - 2), 2.2, glint);
      canvas.drawCircle(Offset(cx + 18, eyeY - 2), 2.2, glint);
    } else {
      // Ojos cerrados: curva suave
      final closed = Paint()..color = p.ojos..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
      canvas.drawPath(Path()
          ..moveTo(cx - 21, eyeY)
          ..quadraticBezierTo(cx - 15, eyeY + 3, cx - 9, eyeY), closed);
      canvas.drawPath(Path()
          ..moveTo(cx + 9, eyeY)
          ..quadraticBezierTo(cx + 15, eyeY + 3, cx + 21, eyeY), closed);
    }

    // ── Nariz ────────────────────────────────────────────────────────────────
    canvas.drawPath(Path()
        ..moveTo(cx - 3, cy + 26)
        ..quadraticBezierTo(cx, cy + 31, cx + 3, cy + 26),
      Paint()..color = Color.lerp(p.piel, Colors.brown, 0.30)!
             ..strokeWidth = 1.6..strokeCap = StrokeCap.round
             ..style = PaintingStyle.stroke,
    );

    // ── Boca ─────────────────────────────────────────────────────────────────
    if (bostezApertura > 0.1) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy + 38),
            width: 12 + bostezApertura * 10, height: 6 + bostezApertura * 16),
        Paint()..color = const Color(0xFF1A0A00),
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy + 38),
            width: 12 + bostezApertura * 10, height: 6 + bostezApertura * 16),
        Paint()..color = p.sonrisa..strokeWidth = 1.5..style = PaintingStyle.stroke,
      );
    } else {
      canvas.drawPath(
        Path()..moveTo(cx - 12, cy + 34)
              ..quadraticBezierTo(cx, cy + 44, cx + 12, cy + 34),
        Paint()..color = p.sonrisa..strokeWidth = 2.6
               ..strokeCap = StrokeCap.round..style = PaintingStyle.stroke,
      );
      // Rubor en mejillas
      canvas.drawOval(Rect.fromCenter(center: Offset(cx - 24, cy + 30),
          width: 16, height: 8), Paint()..color = Colors.pink.withValues(alpha: 0.14));
      canvas.drawOval(Rect.fromCenter(center: Offset(cx + 24, cy + 30),
          width: 16, height: 8), Paint()..color = Colors.pink.withValues(alpha: 0.14));
    }
  }

  @override
  bool shouldRepaint(_CabezaPainter old) =>
      old.personaje != personaje ||
      old.ojosCerrados != ojosCerrados ||
      old.bostezApertura != bostezApertura ||
      old.bostezando != bostezando ||
      old.rascaValue != rascaValue;
}
