// windows/notificacion_windows.dart
// ─────────────────────────────────────────────────────────────────────────────
// Notificaciones y voz para Windows.
// Usa PowerShell + APIs nativas de Windows (System.Speech, WinForms).
// NO depende de Flutter plugins — funciona desde cualquier isolate/engine.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/foundation.dart';

class NotificacionWindows {
  /// Habla un texto usando SAPI (Text-to-Speech de Windows)
  static void hablar(String texto) {
    final limpio = _limpiar(texto);
    if (limpio.isEmpty) return;
    debugPrint('[NotifWin] Hablando: "$limpio"');

    Process.run('powershell', [
      '-WindowStyle', 'Hidden',
      '-Command',
      'Add-Type -AssemblyName System.Speech; '
      '\$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; '
      '\$s.Rate = 1; '
      '\$s.Speak("$limpio");',
    ]).then((_) {
      debugPrint('[NotifWin] Voz OK');
    }).catchError((e) {
      debugPrint('[NotifWin] Error voz: $e');
    });
  }

  /// Muestra un globo de notificación en la bandeja del sistema
  static void notificar(String titulo, String texto) {
    final tituloLimpio = _limpiar(titulo);
    final textoLimpio  = _limpiar(texto);
    debugPrint('[NotifWin] Notificación: "$tituloLimpio" - "$textoLimpio"');

    Process.run('powershell', [
      '-WindowStyle', 'Hidden',
      '-Command',
      'Add-Type -AssemblyName System.Windows.Forms; '
      '\$n = New-Object System.Windows.Forms.NotifyIcon; '
      '\$n.Icon = [System.Drawing.SystemIcons]::Information; '
      '\$n.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info; '
      '\$n.BalloonTipTitle = "$tituloLimpio"; '
      '\$n.BalloonTipText = "$textoLimpio"; '
      '\$n.Visible = \$true; '
      '\$n.ShowBalloonTip(10000); '
      'Start-Sleep -Seconds 12; '
      '\$n.Dispose();',
    ]).then((_) {
      debugPrint('[NotifWin] Notificación OK');
    }).catchError((e) {
      debugPrint('[NotifWin] Error notificación: $e');
    });
  }

  /// Combo: notificación + voz + sonido del sistema
  static void recordatorio(String titulo, String texto) {
    // 1. Sonido de alerta del sistema (inmediato)
    Process.run('powershell', [
      '-WindowStyle', 'Hidden',
      '-Command',
      '[System.Media.SystemSounds]::Exclamation.Play();',
    ]);

    // 2. Notificación visual en bandeja del sistema
    notificar(titulo, texto);

    // 3. Voz
    hablar(texto);
  }

  static String _limpiar(String texto) {
    return texto
        .replaceAll(RegExp(r'[^\w\sáéíóúñüÁÉÍÓÚÑÜ¿¡.,!?:;\-\n"()]'), '')
        .replaceAll('\n', ' ')
        .replaceAll('"', "'")
        .trim();
  }
}
