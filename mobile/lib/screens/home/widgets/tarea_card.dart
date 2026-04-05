// screens/home/widgets/tarea_card.dart
// Widget reutilizable que muestra una tarea como tarjeta

import 'package:flutter/material.dart';
import 'package:mobile/models/tarea.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:intl/intl.dart';

class TareaCard extends StatelessWidget {
  // StatelessWidget porque la card solo muestra datos, no tiene estado propio
  // El estado (la lista de tareas) vive en HomeScreen

  final Tarea tarea;
  final VoidCallback onCompletar;
  final VoidCallback onPosponer;
  final VoidCallback onEliminar;
  final VoidCallback onEditar;

  const TareaCard({
    super.key,
    required this.tarea,
    required this.onCompletar,
    required this.onPosponer,
    required this.onEliminar,
    required this.onEditar,
  });

  @override
  Widget build(BuildContext context) {
    final colorPrioridad = AppTheme.coloresPrioridad[tarea.prioridad] ?? AppTheme.acento;

    return Dismissible(
      // Dismissible permite deslizar la tarjeta para realizar acciones
      // Gesture muy común en apps de tareas (como en iOS Mail, Todoist, etc.)
      key: Key('tarea_${tarea.id}'),
      // Key única por item — Flutter la necesita para identificar widgets en listas

      background: _buildFondoCompletar(),
      secondaryBackground: _buildFondoEliminar(),
      // background = fondo al deslizar a la derecha
      // secondaryBackground = fondo al deslizar a la izquierda

      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onCompletar();
          return false;
          // false = no eliminar el widget del árbol (solo completar)
        } else {
          return await _confirmarEliminacion(context);
          // Muestra diálogo de confirmación antes de eliminar
        }
      },

      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(color: colorPrioridad, width: 4),
            // Barra de color a la izquierda indica la prioridad visualmente
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // ── Checkbox ───────────────────────────────────────────────
              GestureDetector(
                onTap: onCompletar,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tarea.estaCompletada ? AppTheme.acento : Colors.transparent,
                    border: Border.all(
                      color: tarea.estaCompletada ? AppTheme.acento : Colors.white38,
                      width: 2,
                    ),
                  ),
                  child: tarea.estaCompletada
                    ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                    : null,
                ),
              ),

              const SizedBox(width: 12),

              // ── Contenido ───────────────────────────────────────────────
              Expanded(
                // Expanded hace que este widget ocupe todo el espacio horizontal restante
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tarea.titulo,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: tarea.estaCompletada ? Colors.white38 : Colors.white,
                        decoration: tarea.estaCompletada ? TextDecoration.lineThrough : null,
                        // Tachado cuando está completada — feedback visual claro
                      ),
                    ),
                    if (tarea.descripcion != null && tarea.descripcion!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        tarea.descripcion!,
                        style: const TextStyle(fontSize: 12, color: Colors.white54),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Si el texto es muy largo, muestra "..."
                      ),
                    ],
                    if (tarea.fechaLimite != null) ...[
                      // "..." (spread operator) = inserta múltiples widgets en la lista
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 12,
                            color: tarea.estaVencida ? AppTheme.peligro : Colors.white38,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatearFecha(tarea.fechaLimite!),
                            style: TextStyle(
                              fontSize: 11,
                              color: tarea.estaVencida ? AppTheme.peligro : Colors.white38,
                              fontWeight: tarea.estaVencida ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          if (tarea.diasPospuesta > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.advertencia.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Pospuesta ${tarea.diasPospuesta}x',
                                style: const TextStyle(fontSize: 10, color: AppTheme.advertencia),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // ── Menú de opciones ────────────────────────────────────────
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white38, size: 20),
                onSelected: (value) {
                  if (value == 'editar')   onEditar();
                  if (value == 'posponer') onPosponer();
                  if (value == 'eliminar') onEliminar();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'editar', child: Row(children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Editar'),
                  ])),
                  const PopupMenuItem(value: 'posponer', child: Row(children: [
                    Icon(Icons.event_repeat_rounded, size: 18), SizedBox(width: 8), Text('Posponer al mañana'),
                  ])),
                  const PopupMenuItem(value: 'eliminar', child: Row(children: [
                    Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.peligro),
                    SizedBox(width: 8),
                    Text('Eliminar', style: TextStyle(color: AppTheme.peligro)),
                  ])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatearFecha(DateTime fecha) {
    final hoy    = DateTime.now();
    final manana = DateTime.now().add(const Duration(days: 1));

    if (fecha.year == hoy.year && fecha.month == hoy.month && fecha.day == hoy.day) {
      return 'Hoy';
    }
    if (fecha.year == manana.year && fecha.month == manana.month && fecha.day == manana.day) {
      return 'Mañana';
    }
    return DateFormat('d MMM', 'es').format(fecha);
    // DateFormat del paquete intl — formatea la fecha en español
    // Ejemplo: "29 mar"
  }

  Widget _buildFondoCompletar() {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 20),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.acento,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(children: [
        Icon(Icons.check_rounded, color: Colors.white),
        SizedBox(width: 8),
        Text('Completar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildFondoEliminar() {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.peligro,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(children: [
        Spacer(),
        Text('Eliminar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        SizedBox(width: 8),
        Icon(Icons.delete_outline_rounded, color: Colors.white),
      ]),
    );
  }

  Future<bool> _confirmarEliminacion(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar tarea'),
        content: Text('¿Eliminar "${tarea.titulo}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: AppTheme.peligro)),
          ),
        ],
      ),
    ) ?? false;
  }
}
