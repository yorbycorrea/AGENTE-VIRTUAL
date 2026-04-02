// jobs/recordatorios.job.js
// ─────────────────────────────────────────────────────────────────────────────
// RESPONSABILIDAD: revisar cada minuto si hay recordatorios que deban dispararse.
// Cuando encuentra uno, lo marca como enviado en la base de datos.
// (La notificación visual ya fue programada por Flutter directamente en el dispositivo)
// Este job mantiene el historial y maneja los recordatorios repetitivos.
// ─────────────────────────────────────────────────────────────────────────────

const cron = require('node-cron');
const { pool } = require('../db/connection');

const iniciarJobRecordatorios = () => {

  // '* * * * *' = sintaxis cron = cada minuto
  // Los 5 campos son: minuto hora día-del-mes mes día-de-la-semana
  // '*' = cualquier valor
  // Ejemplos:
  //   '0 9 * * *'     = todos los días a las 9:00
  //   '0 9 * * 1'     = todos los lunes a las 9:00
  //   '*/5 * * * *'   = cada 5 minutos
  cron.schedule('* * * * *', async () => {
    try {
      // Buscamos recordatorios cuya fecha ya pasó y no fueron enviados
      const [recordatorios] = await pool.query(`
        SELECT r.*, t.titulo, t.usuario_id, t.estado
        FROM recordatorios r
        JOIN tareas t ON r.tarea_id = t.id
        WHERE r.fecha_hora <= NOW()
          AND r.enviado = FALSE
          AND r.activo = TRUE
          AND t.estado != 'completada'
        LIMIT 50
        -- LIMIT 50: procesar máximo 50 a la vez para no sobrecargar
      `);

      if (recordatorios.length === 0) return;
      // No hay nada que hacer — salimos sin ruido

      console.log(`[Cron] ${recordatorios.length} recordatorio(s) para procesar`);

      for (const recordatorio of recordatorios) {
        // Marcar como enviado
        await pool.query(
          'UPDATE recordatorios SET enviado = TRUE WHERE id = ?',
          [recordatorio.id]
        );

        // Registrar en el historial de la tarea
        await pool.query(
          `INSERT INTO historial_tareas (tarea_id, usuario_id, accion, notas)
           VALUES (?, ?, 'recordatorio_enviado', ?)`,
          [
            recordatorio.tarea_id,
            recordatorio.usuario_id,
            `Recordatorio enviado: ${recordatorio.mensaje || recordatorio.titulo}`
          ]
        );

        // Si es repetitivo y la tarea sigue pendiente, programar el siguiente
        if (recordatorio.tipo === 'repetir' && recordatorio.intervalo_minutos) {
          const proximaFecha = new Date(recordatorio.fecha_hora);
          proximaFecha.setMinutes(proximaFecha.getMinutes() + recordatorio.intervalo_minutos);

          await pool.query(
            `INSERT INTO recordatorios
              (tarea_id, usuario_id, tipo, fecha_hora, intervalo_minutos, mensaje, activo)
             VALUES (?, ?, 'repetir', ?, ?, ?, TRUE)`,
            [
              recordatorio.tarea_id,
              recordatorio.usuario_id,
              proximaFecha,
              recordatorio.intervalo_minutos,
              recordatorio.mensaje
            ]
          );
        }
      }

    } catch (error) {
      console.error('[Cron] Error en job de recordatorios:', error.message);
      // No usamos process.exit() acá — un error en el cron no debe tirar el servidor
    }
  });

  console.log('✓ Job de recordatorios iniciado (revisa cada minuto)');
};

module.exports = iniciarJobRecordatorios;
