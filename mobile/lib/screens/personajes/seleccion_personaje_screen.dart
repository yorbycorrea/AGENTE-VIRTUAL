// screens/personajes/seleccion_personaje_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Pantalla para elegir el personaje del Agente Desktop.
// Muestra una grilla con todos los personajes disponibles.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:mobile/models/personaje.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/agente_service.dart';
import 'package:mobile/theme/app_theme.dart';
import 'dart:io';

class SeleccionPersonajeScreen extends StatefulWidget {
  const SeleccionPersonajeScreen({super.key});

  @override
  State<SeleccionPersonajeScreen> createState() => _SeleccionPersonajeScreenState();
}

class _SeleccionPersonajeScreenState extends State<SeleccionPersonajeScreen> {
  String _seleccionado = 'carlos';

  @override
  void initState() {
    super.initState();
    _cargarSeleccion();
  }

  Future<void> _cargarSeleccion() async {
    final id = await StorageService.obtenerPersonaje();
    setState(() => _seleccionado = id);
  }

  Future<void> _seleccionar(Personaje p) async {
    setState(() => _seleccionado = p.id);
    await StorageService.guardarPersonaje(p.id);

    // Notificar al agente que cambie de personaje
    if (Platform.isWindows) {
      AgenteService.cambiarPersonaje(p.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Elige tu asistente',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('Tu mayordomo personal te acompañará en el escritorio',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 24),

              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.65,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: Personaje.todos.length,
                  itemBuilder: (ctx, i) {
                    final p = Personaje.todos[i];
                    final activo = _seleccionado == p.id;
                    return _buildPersonajeCard(p, activo);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPersonajeCard(Personaje p, bool activo) {
    return GestureDetector(
      onTap: () => _seleccionar(p),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: activo
              ? p.trajeTop.withOpacity(0.15)
              : AppTheme.fondoTarjetaOscuro,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: activo ? p.trajeTop : Colors.white12,
            width: activo ? 2.5 : 1,
          ),
          boxShadow: activo
              ? [BoxShadow(color: p.trajeTop.withOpacity(0.3), blurRadius: 20)]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Preview del personaje
            SizedBox(
              width: 100,
              height: 150,
              child: _buildMiniPersonaje(p),
            ),
            const SizedBox(height: 12),
            Text(
              p.nombre,
              style: TextStyle(
                color: activo ? p.trajeTop : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              p.descripcion,
              style: TextStyle(
                color: activo ? p.trajeTop.withOpacity(0.7) : Colors.white38,
                fontSize: 11,
              ),
            ),
            if (activo) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: p.trajeTop,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Seleccionado',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Mini preview del personaje (versión simplificada)
  Widget _buildMiniPersonaje(Personaje p) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        // Piernas
        Positioned(
          bottom: 2, left: 28,
          child: Container(
            width: 12, height: 30,
            decoration: BoxDecoration(
              color: p.pantalon, borderRadius: BorderRadius.circular(6)),
          ),
        ),
        Positioned(
          bottom: 2, right: 28,
          child: Container(
            width: 12, height: 30,
            decoration: BoxDecoration(
              color: p.pantalon, borderRadius: BorderRadius.circular(6)),
          ),
        ),
        // Zapatos
        Positioned(
          bottom: 0, left: 24,
          child: Container(
            width: 18, height: 8,
            decoration: BoxDecoration(
              color: p.zapatos, borderRadius: BorderRadius.circular(4)),
          ),
        ),
        Positioned(
          bottom: 0, right: 24,
          child: Container(
            width: 18, height: 8,
            decoration: BoxDecoration(
              color: p.zapatos, borderRadius: BorderRadius.circular(4)),
          ),
        ),
        // Cuerpo
        Positioned(
          bottom: 28,
          child: Container(
            width: 50, height: 65,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [p.trajeTop, p.trajeBottom],
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8), topRight: Radius.circular(8),
                bottomLeft: Radius.circular(4), bottomRight: Radius.circular(4),
              ),
            ),
            child: Center(
              child: Container(
                width: 7, height: 28,
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: p.corbata, borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
        ),
        // Brazos
        Positioned(
          bottom: 50, left: 10,
          child: Container(
            width: 12, height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [p.trajeTop, p.trajeBottom],
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(6)),
          ),
        ),
        Positioned(
          bottom: 50, right: 10,
          child: Container(
            width: 12, height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [p.trajeTop, p.trajeBottom],
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(6)),
          ),
        ),
        // Cabeza
        Positioned(
          top: 0,
          child: Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: p.piel, shape: BoxShape.circle),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 7, height: 7,
                      decoration: BoxDecoration(color: p.ojos, borderRadius: BorderRadius.circular(4))),
                    const SizedBox(width: 10),
                    Container(width: 7, height: 7,
                      decoration: BoxDecoration(color: p.ojos, borderRadius: BorderRadius.circular(4))),
                  ],
                ),
                const SizedBox(height: 5),
                Container(
                  width: 16, height: 7,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: p.sonrisa, width: 2),
                      left: BorderSide(color: p.sonrisa, width: 2),
                      right: BorderSide(color: p.sonrisa, width: 2),
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Pelo
        Positioned(
          top: 0,
          child: ClipOval(
            child: SizedBox(
              width: 56, height: 56,
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: 56, height: 26,
                  decoration: BoxDecoration(
                    color: p.pelo,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28), topRight: Radius.circular(28)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
