// theme/app_theme.dart
// ─────────────────────────────────────────────────────────────────────────────
// Define los colores, tipografía y estilos globales de toda la app.
// Al cambiar algo acá, cambia en TODA la app automáticamente.
// Esto es la ventaja de centralizar el diseño en un solo lugar.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
// "import" en Dart = "require" en Node.js
// 'package:' = viene de una librería instalada en pubspec.yaml
// Rutas locales usan: import '../models/tarea.dart';

class AppTheme {
  // "class" en Dart es obligatorio — no hay funciones sueltas fuera de clases
  // Esta clase agrupa todo lo relacionado al tema. No necesita instanciarse.

  // ── Colores principales ──────────────────────────────────────────────────
  static const Color primario      = Color(0xFF6C63FF); // violeta moderno
  static const Color primarioOscuro = Color(0xFF4B44CC);
  static const Color acento        = Color(0xFF43C59E); // verde menta
  static const Color peligro       = Color(0xFFFF4757); // rojo para urgente
  static const Color advertencia   = Color(0xFFFFB347); // naranja para media
  // "static const" = como una constante de clase en JS
  // "static" = pertenece a la clase, no a instancias: AppTheme.primario
  // "const"  = valor fijo en tiempo de compilación, no cambia nunca

  // ── Colores de fondo ─────────────────────────────────────────────────────
  static const Color fondoOscuro       = Color(0xFF0F0F1A);
  static const Color fondoTarjetaOscuro = Color(0xFF1A1A2E);
  static const Color fondoClaro        = Color(0xFFF5F5FF);
  static const Color fondoTarjetaClaro = Color(0xFFFFFFFF);

  // ── Colores de prioridad ─────────────────────────────────────────────────
  // Mapa que asocia cada prioridad con su color
  static const Map<String, Color> coloresPrioridad = {
    'alta':  Color(0xFFFF4757),
    'media': Color(0xFFFFB347),
    'baja':  Color(0xFF43C59E),
  };
  // Map<String, Color> = como un objeto JS { alta: '#FF4757', ... }
  // pero con tipos explícitos

  // ── Tema oscuro ──────────────────────────────────────────────────────────
  static ThemeData get temaOscuro {
    // "get" define un getter — se accede como propiedad: AppTheme.temaOscuro
    // sin paréntesis, aunque internamente es una función
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      // Brightness.dark le dice a Flutter que es tema oscuro
      // Afecta colores por defecto de texto, íconos, etc.

      colorScheme: ColorScheme.dark(
        primary:   primario,
        secondary: acento,
        surface:   fondoTarjetaOscuro,
        error:     peligro,
      ),

      scaffoldBackgroundColor: fondoOscuro,
      // Scaffold es el "esqueleto" de cada pantalla
      // scaffoldBackgroundColor = color de fondo de todas las pantallas

      textTheme: GoogleFonts.poppinsTextTheme(
        // Poppins es una fuente moderna y limpia — ideal para apps
        ThemeData.dark().textTheme,
      ).copyWith(
        // copyWith = copia el tema y sobreescribe solo los valores que especificás
        headlineLarge: GoogleFonts.poppins(
          fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white,
        ),
        headlineMedium: GoogleFonts.poppins(
          fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white,
        ),
        titleLarge: GoogleFonts.poppins(
          fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white,
        ),
        bodyLarge: GoogleFonts.poppins(
          fontSize: 16, color: Colors.white70,
        ),
        bodyMedium: GoogleFonts.poppins(
          fontSize: 14, color: Colors.white60,
        ),
      ),

      cardTheme: CardThemeData(
        color: fondoTarjetaOscuro,
        elevation: 0,
        // elevation = sombra. 0 = sin sombra (diseño plano moderno)
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          // Bordes redondeados — característica del diseño moderno
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        // Estilo de todos los campos de texto de la app
        filled: true,
        fillColor: fondoTarjetaOscuro,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
          // BorderSide.none = sin borde visible por defecto
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primario, width: 2),
          // Cuando el usuario toca el campo, el borde se vuelve violeta
        ),
        labelStyle: TextStyle(color: Colors.white54),
        hintStyle: TextStyle(color: Colors.white30),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primario,
          foregroundColor: Colors.white,
          // foregroundColor = color del texto e íconos del botón
          minimumSize: Size(double.infinity, 52),
          // double.infinity = ocupa todo el ancho disponible
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 16, fontWeight: FontWeight.w600,
          ),
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: fondoOscuro,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white,
        ),
      ),
    );
  }

  // ── Tema claro ───────────────────────────────────────────────────────────
  static ThemeData get temaClaro {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary:   primario,
        secondary: acento,
        surface:   fondoTarjetaClaro,
        error:     peligro,
      ),
      scaffoldBackgroundColor: fondoClaro,
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.light().textTheme),
      cardTheme: CardThemeData(
        color: fondoTarjetaClaro,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primario,
          foregroundColor: Colors.white,
          minimumSize: Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
