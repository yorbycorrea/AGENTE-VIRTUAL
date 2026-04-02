// screens/home/home_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile/models/tarea.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/screens/home/widgets/tarea_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  // SingleTickerProviderStateMixin es necesario para usar TabController (las pestañas)

  late TabController _tabController;
  // "late" = le prometemos a Dart que esto se inicializará antes de usarse
  // Se usa cuando no podemos inicializar en la declaración (necesitamos context primero)

  String _filtroEstado = 'todas';

  // ── Datos de prueba (se reemplazan con datos reales en Sprint 7) ─────────
  final List<Tarea> _tareas = [
    Tarea(
      id: 1, usuarioId: 1,
      titulo: 'Llamar al médico',
      descripcion: 'Turno de control anual',
      prioridad: 'alta',
      fechaLimite: DateTime.now(),
      creadaEn: DateTime.now(),
    ),
    Tarea(
      id: 2, usuarioId: 1,
      titulo: 'Comprar víveres',
      prioridad: 'media',
      fechaLimite: DateTime.now(),
      creadaEn: DateTime.now(),
    ),
    Tarea(
      id: 3, usuarioId: 1,
      titulo: 'Revisar emails del trabajo',
      prioridad: 'baja',
      fechaLimite: DateTime.now().add(const Duration(days: 1)),
      creadaEn: DateTime.now(),
      diasPospuesta: 2,
    ),
    Tarea(
      id: 4, usuarioId: 1,
      titulo: 'Pagar facturas',
      descripcion: 'Luz, internet y seguro',
      prioridad: 'alta',
      estado: 'completada',
      fechaLimite: DateTime.now(),
      creadaEn: DateTime.now(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // initState se ejecuta UNA SOLA VEZ cuando el widget se crea
    // Es el equivalente a useEffect(() => {}, []) en React
    // Acá inicializamos cosas que dependen del ciclo de vida del widget
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

  void _completarTarea(int id) {
    setState(() {
      final tarea = _tareas.firstWhere((t) => t.id == id);
      tarea.estado = tarea.estaCompletada ? 'pendiente' : 'completada';
      // Toggle: si estaba completada, la reabre; si estaba pendiente, la completa
    });
  }

  void _posponerTarea(int id) {
    setState(() {
      final tarea = _tareas.firstWhere((t) => t.id == id);
      tarea.fechaLimite = tarea.fechaLimite?.add(const Duration(days: 1))
                          ?? DateTime.now().add(const Duration(days: 1));
      tarea.diasPospuesta++;
      tarea.estado = 'pospuesta';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Tarea pospuesta al mañana'),
        backgroundColor: AppTheme.advertencia,
        behavior: SnackBarBehavior.floating,
        // floating = la snackbar flota sobre el contenido en lugar de estar pegada abajo
      ),
    );
  }

  void _eliminarTarea(int id) {
    setState(() => _tareas.removeWhere((t) => t.id == id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Tarea eliminada'),
        backgroundColor: AppTheme.peligro,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _mostrarFormularioNuevaTarea() {
    final tituloController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // isScrollControlled: true = el bottom sheet puede ocupar más del 50% de la pantalla
      // Necesario para que el teclado no tape el contenido
      backgroundColor: AppTheme.fondoTarjetaOscuro,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          // viewInsets.bottom = altura del teclado
          // Sumamos ese valor al padding para que el contenido suba con el teclado
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // MainAxisSize.min = la columna ocupa solo el espacio necesario
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nueva tarea', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: tituloController,
              autofocus: true,
              // autofocus: true = el teclado aparece automáticamente
              decoration: const InputDecoration(
                hintText: '¿Qué necesitás hacer?',
                prefixIcon: Icon(Icons.add_task_rounded),
              ),
              onSubmitted: (value) {
                if (value.trim().isEmpty) return;
                setState(() {
                  _tareas.insert(0, Tarea(
                    id: DateTime.now().millisecondsSinceEpoch,
                    // ID temporal usando timestamp — se reemplaza con el ID real del backend en Sprint 7
                    usuarioId: 1,
                    titulo: value.trim(),
                    creadaEn: DateTime.now(),
                  ));
                });
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                if (tituloController.text.trim().isEmpty) return;
                setState(() {
                  _tareas.insert(0, Tarea(
                    id: DateTime.now().millisecondsSinceEpoch,
                    usuarioId: 1,
                    titulo: tituloController.text.trim(),
                    creadaEn: DateTime.now(),
                  ));
                });
                Navigator.pop(ctx);
              },
              child: const Text('Agregar tarea'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hoy = DateFormat('EEEE d MMMM', 'es').format(DateTime.now());
    // DateFormat del paquete intl — formatea fechas
    // 'EEEE' = nombre completo del día (lunes, martes...)
    // 'd'    = número del día
    // 'MMMM' = nombre completo del mes
    // Resultado: "lunes 29 de marzo"

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
                              '¡Hola! 👋',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            Text(
                              hoy.substring(0, 1).toUpperCase() + hoy.substring(1),
                              // Capitaliza la primera letra
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                        // ── Avatar ────────────────────────────────────
                        CircleAvatar(
                          backgroundColor: AppTheme.primario,
                          child: const Text('U', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          // En Sprint 7 mostramos la inicial del nombre real del usuario
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
