// screens/home/home_screen.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile/models/tarea.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/screens/home/widgets/tarea_card.dart';
import 'package:mobile/services/tareas_service.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/screens/auth/login_screen.dart';
import 'package:mobile/screens/home/widgets/nueva_tarea_sheet.dart';
import 'package:mobile/screens/estadisticas/estadisticas_screen.dart';
import 'package:mobile/screens/home/widgets/mayordomo_widget.dart';
import 'package:mobile/screens/calendario/calendario_screen.dart';
import 'package:mobile/screens/personajes/seleccion_personaje_screen.dart';
import 'package:mobile/services/agente_service.dart';
import 'package:mobile/windows/notificacion_windows.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  // SingleTickerProviderStateMixin es necesario para usar TabController (las pestañas)

  late TabController _tabController;

  int    _paginaActual  = 0;
  // 0 = Tareas, 1 = Estadísticas

  // GlobalKey: referencia directa al State del Mayordomo.
  // currentState?.mostrarMensaje(...) funciona sin importar cuántas veces
  // Flutter haya reconstruido el widget — la key siempre apunta al mismo State.
  final _mayordomoKey = GlobalKey<MayordomoWidgetState>();
  final Map<int, Timer> _timersRecordatorio = {};
  // Un Timer por tarea — se dispara a la hora del recordatorio
  String _filtroEstado  = 'todas';
  bool   _cargando      = true;
  String _nombreUsuario = '';
  List<Tarea> _tareas   = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this); // tabs de filtro de tareas
    _cargarDatos();
    // En Windows: lanzar el Agente flotante (ventana transparente separada)
    if (Platform.isWindows) {
      AgenteService.iniciar();
    }
  }

  Future<void> _cargarDatos() async {
    // Cargamos el nombre del usuario guardado en el dispositivo
    final usuario = await StorageService.obtenerUsuario();
    setState(() => _nombreUsuario = usuario?['nombre'] ?? 'Usuario');

    try {
      final tareas = await TareasService.obtenerTareas();
      setState(() { _tareas = tareas; _cargando = false; });
    } catch (e) {
      setState(() => _cargando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al cargar tareas. ¿El servidor está corriendo?'),
          backgroundColor: AppTheme.peligro, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _cerrarSesion() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final t in _timersRecordatorio.values) t.cancel();
    super.dispose();
  }

  List<Tarea> get _tareasFiltradas {
    // Getter que filtra las tareas según la pestaña activa
    switch (_filtroEstado) {
      case 'pendientes':
        return _tareas.where((t) => t.estaPendiente).toList();
      case 'completadas':
        return _tareas.where((t) => t.estaCompletada).toList();
      default:
        return _tareas;
    }
  }

  int get _completadasHoy => _tareas.where((t) => t.estaCompletada).length;
  int get _totalHoy       => _tareas.length;
  double get _progreso    => _totalHoy == 0 ? 0 : _completadasHoy / _totalHoy;

  Future<void> _completarTarea(int id) async {
    final tarea = _tareas.firstWhere((t) => t.id == id);
    final nuevoEstado = tarea.estaCompletada ? 'pendiente' : 'completada';
    try {
      final actualizada = await TareasService.cambiarEstado(id, nuevoEstado);
      setState(() {
        final index = _tareas.indexWhere((t) => t.id == id);
        // Nueva lista para que didUpdateWidget detecte el cambio de estado
        _tareas = List.from(_tareas)..[index] = actualizada;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al actualizar la tarea'),
        backgroundColor: AppTheme.peligro, behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _posponerTarea(int id) async {
    try {
      final actualizada = await TareasService.cambiarEstado(id, 'pospuesta');
      setState(() {
        final index = _tareas.indexWhere((t) => t.id == id);
        _tareas[index] = actualizada;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tarea pospuesta al mañana'),
        backgroundColor: AppTheme.advertencia, behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al posponer la tarea'),
        backgroundColor: AppTheme.peligro, behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _eliminarTarea(int id) async {
    try {
      await TareasService.eliminarTarea(id);
      setState(() => _tareas.removeWhere((t) => t.id == id));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tarea eliminada'),
        backgroundColor: AppTheme.peligro, behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al eliminar la tarea'),
        backgroundColor: AppTheme.peligro, behavior: SnackBarBehavior.floating),
      );
    }
  }

  // ── Programa el Mayordomo para recordar una tarea en su hora ────────────
  void _programarRecordatorioMayordomo(Tarea tarea) {
    if (!Platform.isWindows) return;

    if (tarea.fechaLimite == null || tarea.horaLimite == null) return;

    final partes = tarea.horaLimite!.split(':');
    final hora   = int.parse(partes[0]);
    final minuto = int.parse(partes[1]);

    final horaExacta = DateTime(
      tarea.fechaLimite!.year,
      tarea.fechaLimite!.month,
      tarea.fechaLimite!.day,
      hora,
      minuto,
    );

    final ahora = DateTime.now();

    // Cancelamos timers anteriores para esta tarea
    _timersRecordatorio[tarea.id]?.cancel();
    _timersRecordatorio[tarea.id * 1000]?.cancel();

    // Timer 1: Aviso 15 minutos antes (si aún no pasó)
    final horaAviso15 = horaExacta.subtract(const Duration(minutes: 15));
    if (horaAviso15.isAfter(ahora)) {
      final demora = horaAviso15.difference(ahora);
      _timersRecordatorio[tarea.id] = Timer(demora, () async {
        NotificacionWindows.recordatorio(
          'Recordatorio',
          'En 15 minutos tiene pendiente: ${tarea.titulo}',
        );
        await AgenteService.mostrarMensaje(
          'Señor/a, en 15 minutos tiene\npendiente: "${tarea.titulo}"',
        );
      });
    }

    // Timer 2: Aviso en el momento exacto (si aún no pasó)
    if (horaExacta.isAfter(ahora)) {
      final demora = horaExacta.difference(ahora);
      _timersRecordatorio[tarea.id * 1000] = Timer(demora, () async {
        NotificacionWindows.recordatorio('Es hora!', tarea.titulo);
        // NO llamamos AgenteService.saludar() para no sobreescribir el mensaje.
        await AgenteService.mostrarMensaje('¡Es hora!\n"${tarea.titulo}"');
      });
    }
  }

  // ── Abre NuevaTareaSheet adaptado a la plataforma ────────────────────────
  // En móvil: BottomSheet (desliza desde abajo, patrón nativo)
  // En escritorio: Dialog centrado (los BottomSheets no funcionan en Windows)
  Future<dynamic> _abrirFormulario({Tarea? tareaInicial}) {
    final sheet = NuevaTareaSheet(tareaInicial: tareaInicial);

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // Dialog de escritorio: ancho fijo, centrado, con scroll
      return showDialog<dynamic>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: AppTheme.fondoTarjetaOscuro,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: SizedBox(
            width: 480,
            // Altura máxima: 85% de la pantalla para que no tape todo
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: sheet,
            ),
          ),
        ),
      );
    }

    // Móvil: el BottomSheet original
    return showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.fondoTarjetaOscuro,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => sheet,
    );
  }

  Future<void> _mostrarFormularioNuevaTarea() async {
    final tarea = await _abrirFormulario();

    if (tarea != null && tarea is Tarea) {
      // Nueva lista (no mutación) para que didUpdateWidget en MayordomoWidget
      // detecte el cambio al comparar widget.tareas vs oldWidget.tareas
      setState(() => _tareas = [tarea, ..._tareas]);

      // addPostFrameCallback = ejecutar DESPUÉS de que el frame actual termine.
      // Si llamamos mostrarMensaje mientras HomeScreen está reconstruyendo,
      // Flutter puede descartar el setState interno del Mayordomo.
      // Con postFrameCallback esperamos a que todo esté pintado antes de actuar.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (tarea.horaLimite != null) {
          final partes  = tarea.horaLimite!.split(':');
          final horaStr = '${partes[0]}:${partes[1]}';
          if (Platform.isWindows) {
            final msg = 'Entendido. Le recordaré "${tarea.titulo}" a las $horaStr.';
            AgenteService.mostrarMensaje(msg);
            NotificacionWindows.hablar(msg);
          } else {
            _mayordomoKey.currentState?.mostrarMensaje(
              'Entendido. Le recordaré "${tarea.titulo}" a las $horaStr.',
            );
          }
          _programarRecordatorioMayordomo(tarea);
        } else {
          if (Platform.isWindows) {
            final msg = 'Tarea registrada. A por ella!';
            AgenteService.mostrarMensaje(msg);
            NotificacionWindows.hablar(msg);
          } else {
            _mayordomoKey.currentState?.mostrarMensaje(
              'Tarea registrada. ¡A por ella, señor/a!',
            );
          }
        }
      });
    }
  }

  Future<void> _editarTarea(Tarea tareaActual) async {
    final tareaEditada = await _abrirFormulario(tareaInicial: tareaActual);
    if (tareaEditada != null && tareaEditada is Tarea) {
      setState(() {
        final index = _tareas.indexWhere((t) => t.id == tareaEditada.id);
        if (index != -1) _tareas[index] = tareaEditada;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.primario)),
      );
    }

    // LayoutBuilder nos da el ancho disponible en tiempo real.
    // En móvil será ~360-430px, en escritorio Windows 800-1920px.
    return LayoutBuilder(
      builder: (context, constraints) {
        final esEscritorio = constraints.maxWidth >= 720;
        // 720px es el punto de quiebre — debajo es móvil, arriba es escritorio

        return esEscritorio
          ? _buildLayoutEscritorio()
          : _buildLayoutMovil();
      },
    );
  }

  // ── Layout móvil (el original) ────────────────────────────────────────────
  Widget _buildLayoutMovil() {
    return Scaffold(
      body: IndexedStack(
        index: _paginaActual,
        children: [
          _buildTareasView(),
          const EstadisticasScreen(),
        ],
      ),
      floatingActionButton: _paginaActual == 0
        ? FloatingActionButton.extended(
            onPressed: _mostrarFormularioNuevaTarea,
            backgroundColor: AppTheme.primario,
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: const Text('Nueva tarea', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          )
        : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _paginaActual,
        onTap: (index) => setState(() => _paginaActual = index),
        backgroundColor: AppTheme.fondoTarjetaOscuro,
        selectedItemColor: AppTheme.primario,
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.checklist_rounded),  label: 'Tareas'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded),   label: 'Progreso'),
        ],
      ),
    );
  }

  // ── Layout escritorio (dos columnas) ─────────────────────────────────────
  // El Agente Desktop ahora flota FUERA de esta ventana (ventana transparente
  // separada, lanzada por AgenteService.iniciar()). No hay overlay dentro.
  Widget _buildLayoutEscritorio() {
    return Scaffold(
      body: Row(
        children: [
          _buildBarraLateral(),
          const VerticalDivider(width: 1, color: Colors.white10),
          Expanded(
            child: IndexedStack(
              index: _paginaActual,
              children: [
                _buildTareasView(esEscritorio: true),
                const EstadisticasScreen(),
                const CalendarioScreen(),
                const SeleccionPersonajeScreen(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _paginaActual == 0
        ? FloatingActionButton.extended(
            onPressed: _mostrarFormularioNuevaTarea,
            backgroundColor: AppTheme.primario,
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: const Text('Nueva tarea', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          )
        : null,
    );
  }

  // ── Barra lateral del layout de escritorio ────────────────────────────────
  Widget _buildBarraLateral() {
    final hoy = DateFormat('EEEE d\nMMMM', 'es').format(DateTime.now());
    // '\n' = salto de línea para mostrar día y mes en dos líneas

    return Container(
      width: 220,
      color: AppTheme.fondoTarjetaOscuro,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Avatar y nombre ──────────────────────────────────────────
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.primario,
                radius: 20,
                child: Text(
                  _nombreUsuario.isNotEmpty ? _nombreUsuario[0].toUpperCase() : 'U',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _nombreUsuario,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              hoy[0].toUpperCase() + hoy.substring(1),
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),

          const SizedBox(height: 24),

          // ── Progreso rápido ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primario.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primario.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_completadasHoy / $_totalHoy tareas',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _progreso,
                    minHeight: 6,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primario),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(_progreso * 100).toInt()}% completado',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Ítems de navegación ──────────────────────────────────────
          _buildNavItem(icono: Icons.checklist_rounded,      label: 'Tareas',      indice: 0),
          const SizedBox(height: 4),
          _buildNavItem(icono: Icons.calendar_month_rounded, label: 'Calendario',  indice: 2),
          const SizedBox(height: 4),
          _buildNavItem(icono: Icons.bar_chart_rounded,      label: 'Progreso',    indice: 1),
          const SizedBox(height: 4),
          _buildNavItem(icono: Icons.person_rounded,         label: 'Asistente',   indice: 3),

          const Spacer(),

          const SizedBox(height: 16),

          // ── Cerrar sesión ────────────────────────────────────────────
          GestureDetector(
            onTap: _cerrarSesion,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.peligro.withOpacity(0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.logout_rounded, color: AppTheme.peligro, size: 18),
                  SizedBox(width: 8),
                  Text('Cerrar sesión', style: TextStyle(color: AppTheme.peligro, fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({required IconData icono, required String label, required int indice}) {
    final activo = _paginaActual == indice;
    return GestureDetector(
      onTap: () => setState(() => _paginaActual = indice),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: activo ? AppTheme.primario.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icono, color: activo ? AppTheme.primario : Colors.white38, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: activo ? AppTheme.primario : Colors.white54,
                fontWeight: activo ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // esEscritorio se pasa desde el layout padre (build → LayoutBuilder),
  // NO lo detectamos aquí dentro para evitar leer el ancho incorrecto
  // (la columna derecha tiene menos ancho que la pantalla completa).
  Widget _buildTareasView({bool esEscritorio = false}) {
    final hoy = DateFormat('EEEE d MMMM', 'es').format(DateTime.now());

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── Header (saludo + progreso) — solo en móvil ─────
                  if (!esEscritorio) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '¡Hola, $_nombreUsuario! 👋',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            Text(
                              hoy.substring(0, 1).toUpperCase() + hoy.substring(1),
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: _cerrarSesion,
                          child: CircleAvatar(
                            backgroundColor: AppTheme.primario,
                            child: Text(
                              _nombreUsuario.isNotEmpty ? _nombreUsuario[0].toUpperCase() : 'U',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildTarjetaProgreso(context),
                    const SizedBox(height: 24),
                  ],

                  // ── Título de sección en escritorio ────────────────
                  if (esEscritorio) ...[
                    Text('Mis tareas', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 16),
                  ],

                  // ── Tabs de filtro ─────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.fondoTarjetaOscuro,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      onTap: (index) {
                        setState(() {
                          _filtroEstado = ['todas', 'pendientes', 'completadas'][index];
                        });
                      },
                      indicator: BoxDecoration(
                        color: AppTheme.primario,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white38,
                      tabs: const [
                        Tab(text: 'Todas'),
                        Tab(text: 'Pendientes'),
                        Tab(text: 'Completadas'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // ── Lista de tareas ────────────────────────────────────────
          _tareasFiltradas.isEmpty
            ? SliverFillRemaining(child: _buildEstadoVacio())
            : SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final tarea = _tareasFiltradas[index];
                      return TareaCard(
                        tarea: tarea,
                        onCompletar: () => _completarTarea(tarea.id),
                        onPosponer:  () => _posponerTarea(tarea.id),
                        onEliminar:  () => _eliminarTarea(tarea.id),
                        onEditar:    () => _editarTarea(tarea),
                      );
                    },
                    childCount: _tareasFiltradas.length,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildTarjetaProgreso(BuildContext context) {
    final mensaje = _progreso == 1.0
      ? '¡Completaste todo! Excelente trabajo 🎉'
      : _progreso >= 0.7
        ? '¡Vas muy bien! Seguí así 💪'
        : _progreso >= 0.3
          ? 'Buen progreso, continuá 🚀'
          : 'Empecemos el día con energía ✨';
    // Lógica de felicitación/motivación según el progreso

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primario, AppTheme.primarioOscuro],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_completadasHoy de $_totalHoy tareas',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
              ),
              Text(
                '${(_progreso * 100).toInt()}%',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _progreso,
              minHeight: 8,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          Text(mensaje, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildEstadoVacio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.task_alt_rounded, size: 64, color: Colors.white12),
          const SizedBox(height: 16),
          Text(
            _filtroEstado == 'completadas'
              ? 'No completaste tareas todavía'
              : '¡Sin tareas pendientes!',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white38),
          ),
          const SizedBox(height: 8),
          Text(
            _filtroEstado == 'completadas'
              ? 'Completá tareas para verlas acá'
              : 'Tocá el botón para agregar una',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
