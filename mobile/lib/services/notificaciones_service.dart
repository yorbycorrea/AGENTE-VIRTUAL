// services/notificaciones_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// RESPONSABILIDAD: programar y cancelar notificaciones locales del dispositivo.
// Una notificación local NO necesita internet — el dispositivo la dispara solo
// a la hora programada, aunque la app esté cerrada.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

class NotificacionesService {
  // Instancia única del plugin (singleton)
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _inicializado = false;

  // ── Inicializar (llamar una sola vez al arrancar la app) ─────────────────
  static Future<void> inicializar() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    // flutter_local_notifications no soporta Windows — salimos sin hacer nada
    if (_inicializado) return;

    tz.initializeTimeZones();
    // Carga los datos de todas las zonas horarias del mundo
    // Necesario para programar notificaciones a horas correctas

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    // @mipmap/ic_launcher = el ícono de la app como ícono de la notificación

    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificacionTocada,
      // Callback que se ejecuta cuando el usuario TOCA la notificación
    );

    _inicializado = true;
  }

  // ── Pedir permisos al usuario ─────────────────────────────────────────────
  static Future<bool> pedirPermisos() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    final status = await Permission.notification.request();
    // .request() muestra el diálogo del sistema "¿Permitir notificaciones?"
    // Solo se muestra una vez — si el usuario deniega, hay que ir a Configuración

    return status.isGranted;
    // true = el usuario aceptó
    // false = el usuario rechazó
  }

  // ── Programar un recordatorio ─────────────────────────────────────────────
  static Future<void> programarRecordatorio({
    required int id,
    required String titulo,
    required String cuerpo,
    required DateTime fechaHora,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (!_inicializado) await inicializar();

    // Convertimos la fecha a timezone-aware (necesario para notificaciones exactas)
    final fechaZona = tz.TZDateTime.from(fechaHora, tz.local);
    // tz.local = zona horaria del dispositivo
    // Así si el usuario viaja, la notificación se ajusta

    if (fechaZona.isBefore(tz.TZDateTime.now(tz.local))) {
      // No programamos notificaciones en el pasado
      return;
    }

    const detallesAndroid = AndroidNotificationDetails(
      'recordatorios_canal',      // ID del canal (único por tipo de notificación)
      'Recordatorios de tareas',  // Nombre visible en Configuración del sistema
      channelDescription: 'Notificaciones de recordatorios de tus tareas',
      importance: Importance.high,
      // high = aparece en pantalla aunque el teléfono esté en uso (heads-up notification)
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
    );

    await _plugin.zonedSchedule(
      id,
      titulo,
      cuerpo,
      fechaZona,
      const NotificationDetails(android: detallesAndroid),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      // absoluteTime = la notificación se dispara en la fecha/hora exacta indicada
      // La alternativa es wallClockTime que se usa para recordatorios relativos al reloj
      // Para nuestro caso (hora exacta del recordatorio) siempre usamos absoluteTime
    );
  }

  // ── Programar recordatorios repetitivos ──────────────────────────────────
  static Future<void> programarRecordatorioRepetitivo({
    required int tareaId,
    required String titulo,
    required DateTime fechaInicio,
    required int intervaloMinutos,
    // Cada cuántos minutos repetir
    int cantidadRepeticiones = 5,
    // Cuántas veces repetir como máximo (para no ser molesto)
  }) async {
    for (int i = 0; i < cantidadRepeticiones; i++) {
      final fechaNotificacion = fechaInicio.add(Duration(minutes: intervaloMinutos * i));

      if (fechaNotificacion.isAfter(DateTime.now())) {
        await programarRecordatorio(
          id: tareaId * 100 + i,
          // ID único por repetición: tareaId=5, i=2 → id=502
          titulo: titulo,
          cuerpo: i == 0
            ? 'Es hora de: $titulo'
            : 'Recordatorio #${i + 1}: $titulo',
          fechaHora: fechaNotificacion,
        );
      }
    }
  }

  // ── Cancelar notificaciones de una tarea ─────────────────────────────────
  static Future<void> cancelarRecordatorio(int tareaId) async {
    // Cancela la notificación exacta
    await _plugin.cancel(tareaId);

    // Cancela también las repetitivas (hasta 5)
    for (int i = 0; i < 5; i++) {
      await _plugin.cancel(tareaId * 100 + i);
    }
  }

  // ── Mostrar notificación inmediata (para pruebas) ─────────────────────────
  static Future<void> mostrarNotificacionInmediata({
    required String titulo,
    required String cuerpo,
  }) async {
    if (!_inicializado) await inicializar();

    const detallesAndroid = AndroidNotificationDetails(
      'recordatorios_canal',
      'Recordatorios de tareas',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _plugin.show(
      0,
      titulo,
      cuerpo,
      const NotificationDetails(android: detallesAndroid),
    );
  }

  // ── Callback cuando el usuario toca la notificación ──────────────────────
  static void _onNotificacionTocada(NotificationResponse response) {
    // Acá podríamos navegar a la tarea específica
    // Lo implementamos en una versión futura
  }
}
