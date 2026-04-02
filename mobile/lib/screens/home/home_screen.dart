// screens/home/home_screen.dart

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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  // SingleTickerProviderStateMixin es necesario para usar TabController (las pestañas)

  late TabController _tabController;

  String _filtroEstado  = 'todas';
  bool   _cargando      = true;
  String _nombreUsuario = '';
  List<Tarea> _tareas   = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _cargarDatos();
    // Cargamos datos reales del backend al iniciar la pantalla
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
        _tareas[index] = actualizada;
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

  Future<void> _mostrarFormularioNuevaTarea() async {
    final tarea = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.fondoTarjetaOscuro,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const NuevaTareaSheet(),
    );

    // Si el usuario guardó la tarea (no canceló), la agregamos a la lista
    if (tarea != null && tarea is Tarea) {
      setState(() => _tareas.insert(0, tarea));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoy = DateFormat('EEEE d MMMM', 'es').format(DateTime.now());
    // DateFormat del paquete intl — formatea fechas
    // 'EEEE' = nombre completo del día (lunes, martes...)
    // 'd'    = número del día
    // 'MMMM' = nombre completo del mes
    // Resultado: "lunes 29 de marzo"

    if (_cargando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.primario)),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          // CustomScrollView = scroll avanzado que permite mezclar distintos tipos de contenido
          slivers: [
            // Un "sliver" es una porción del scroll. Permite crear efectos como
            // el AppBar que se colapsa al hacer scroll (SliverAppBar)

            // ── Header con saludo y progreso ──────────────────────────
            SliverToBoxAdapter(
              // SliverToBoxAdapter convierte un widget normal en un sliver
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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

                    // ── Tarjeta de progreso del día ────────────────────
                    _buildTarjetaProgreso(context),

                    const SizedBox(height: 24),

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
                        );
                      },
                      childCount: _tareasFiltradas.length,
                    ),
                  ),
                ),
          ],
        ),
      ),

      // ── Botón agregar tarea ──────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarFormularioNuevaTarea,
        backgroundColor: AppTheme.primario,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Nueva tarea', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
