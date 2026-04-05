// models/personaje.dart
// ─────────────────────────────────────────────────────────────────────────────
// Define los personajes disponibles para el Agente Desktop.
// Cada personaje tiene colores distintos para pelo, piel, traje, etc.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

class Personaje {
  final String id;
  final String nombre;
  final String descripcion;
  final Color piel;
  final Color pelo;
  final Color trajeTop;
  final Color trajeBottom;
  final Color corbata;
  final Color zapatos;
  final Color ojos;
  final Color sonrisa;
  final Color pantalon;

  const Personaje({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.piel,
    required this.pelo,
    required this.trajeTop,
    required this.trajeBottom,
    required this.corbata,
    required this.zapatos,
    required this.ojos,
    required this.sonrisa,
    required this.pantalon,
  });

  static const List<Personaje> todos = [
    // ── Carlos — El original ──────────────────────────────────────────────
    Personaje(
      id: 'carlos',
      nombre: 'Carlos',
      descripcion: 'Ejecutivo elegante',
      piel: Color(0xFFFFD09B),
      pelo: Color(0xFF2C1A0E),
      trajeTop: Color(0xFF7C3AED),
      trajeBottom: Color(0xFF4F46E5),
      corbata: Color(0xFF312E81),
      zapatos: Color(0xFF111111),
      ojos: Color(0xFF1E1B4B),
      sonrisa: Color(0xFFAA5533),
      pantalon: Color(0xFF1E1B4B),
    ),

    // ── Sofia — Profesional moderna ───────────────────────────────────────
    Personaje(
      id: 'sofia',
      nombre: 'Sofía',
      descripcion: 'Profesional moderna',
      piel: Color(0xFFF5D0B0),
      pelo: Color(0xFF8B4513),
      trajeTop: Color(0xFFEC4899),
      trajeBottom: Color(0xFFBE185D),
      corbata: Color(0xFF9D174D),
      zapatos: Color(0xFF1F1F1F),
      ojos: Color(0xFF1E3A5F),
      sonrisa: Color(0xFFCC6655),
      pantalon: Color(0xFF1E1B4B),
    ),

    // ── Max — Deportivo tech ──────────────────────────────────────────────
    Personaje(
      id: 'max',
      nombre: 'Max',
      descripcion: 'Tech deportivo',
      piel: Color(0xFFE8B88A),
      pelo: Color(0xFF1A1A1A),
      trajeTop: Color(0xFF10B981),
      trajeBottom: Color(0xFF059669),
      corbata: Color(0xFF047857),
      zapatos: Color(0xFF1C1917),
      ojos: Color(0xFF1E3A2F),
      sonrisa: Color(0xFF996644),
      pantalon: Color(0xFF27272A),
    ),

    // ── Luna — Creativa artística ─────────────────────────────────────────
    Personaje(
      id: 'luna',
      nombre: 'Luna',
      descripcion: 'Artista creativa',
      piel: Color(0xFFFFE0BD),
      pelo: Color(0xFFFF6B35),
      trajeTop: Color(0xFFF59E0B),
      trajeBottom: Color(0xFFD97706),
      corbata: Color(0xFFB45309),
      zapatos: Color(0xFF292524),
      ojos: Color(0xFF7C2D12),
      sonrisa: Color(0xFFBB6644),
      pantalon: Color(0xFF44403C),
    ),

    // ── Diego — Nocturno oscuro ───────────────────────────────────────────
    Personaje(
      id: 'diego',
      nombre: 'Diego',
      descripcion: 'Nocturno misterioso',
      piel: Color(0xFFD4A574),
      pelo: Color(0xFF0A0A0A),
      trajeTop: Color(0xFF374151),
      trajeBottom: Color(0xFF1F2937),
      corbata: Color(0xFFDC2626),
      zapatos: Color(0xFF0A0A0A),
      ojos: Color(0xFF1C1917),
      sonrisa: Color(0xFF8B6644),
      pantalon: Color(0xFF111827),
    ),

    // ── Valentina — Elegante clásica ──────────────────────────────────────
    Personaje(
      id: 'valentina',
      nombre: 'Valentina',
      descripcion: 'Elegante clásica',
      piel: Color(0xFFFDE8D0),
      pelo: Color(0xFF5C3317),
      trajeTop: Color(0xFF6366F1),
      trajeBottom: Color(0xFF4338CA),
      corbata: Color(0xFF3730A3),
      zapatos: Color(0xFF18181B),
      ojos: Color(0xFF312E81),
      sonrisa: Color(0xFFBB7766),
      pantalon: Color(0xFF1E1B4B),
    ),
  ];

  static Personaje obtenerPorId(String id) {
    return todos.firstWhere(
      (p) => p.id == id,
      orElse: () => todos[0], // Carlos por defecto
    );
  }
}
