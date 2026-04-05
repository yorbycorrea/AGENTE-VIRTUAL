// routes/estadisticas.js
// ─────────────────────────────────────────────────────────────────────────────
// RUTAS:
//   GET /api/estadisticas/hoy      → resumen del día actual
//   GET /api/estadisticas/historial → tareas completadas por día (últimos 7 días)
//   GET /api/estadisticas/racha    → cuántos días consecutivos con al menos 1 tarea completada
// ─────────────────────────────────────────────────────────────────────────────

const express        = require('express');
const { pool }       = require('../db/connection');
const verificarToken = require('../middleware/auth');

const router = express.Router();
router.use(verificarToken);

// ─── GET /api/estadisticas/hoy ────────────────────────────────────────────────
router.get('/hoy', async (req, res) => {
  try {
    const usuarioId = req.usuario.id;
    const hoy = new Date().toISOString().split('T')[0];

    // Totales generales de hoy
    const [[totales]] = await pool.query(`
      SELECT
        COUNT(*)                                          AS total,
        SUM(estado = 'completada')                        AS completadas,
        SUM(estado = 'pendiente')                         AS pendientes,
        SUM(estado = 'pospuesta')                         AS pospuestas,
        SUM(estado = 'cancelada')                         AS canceladas,
        SUM(estado = 'completada' AND fecha_limite = ?)   AS completadas_hoy,
        SUM(fecha_limite = ? AND estado != 'completada')  AS vencidas_hoy
      FROM tareas
      WHERE usuario_id = ? AND fecha_limite = ?
    `, [hoy, hoy, usuarioId, hoy]);
    // SUM(condición) = cuenta los registros donde la condición es verdadera
    // Es más eficiente que hacer múltiples queries separadas

    // Tareas completadas en cualquier fecha pero registradas hoy en el historial
    const [[completadasHoy]] = await pool.query(`
      SELECT COUNT(DISTINCT tarea_id) AS total
      FROM historial_tareas
      WHERE usuario_id = ?
        AND accion = 'completada'
        AND DATE(fecha_accion) = ?
    `, [usuarioId, hoy]);

    // Prioridad más frecuente entre las completadas hoy
    const [[prioridadTop]] = await pool.query(`
      SELECT t.prioridad, COUNT(*) AS cantidad
      FROM historial_tareas h
      JOIN tareas t ON h.tarea_id = t.id
      WHERE h.usuario_id = ?
        AND h.accion = 'completada'
        AND DATE(h.fecha_accion) = ?
      GROUP BY t.prioridad
      ORDER BY cantidad DESC
      LIMIT 1
    `, [usuarioId, hoy]);

    const total       = totales.total || 0;
    const completadas = totales.completadas || 0;
    const porcentaje  = total > 0 ? Math.round((completadas / total) * 100) : 0;

    // Mensaje motivacional según el porcentaje
    const mensaje = _mensajeMotivacional(porcentaje, completadas, total);

    res.json({
      fecha:      hoy,
      total,
      completadas,
      pendientes:  totales.pendientes  || 0,
      pospuestas:  totales.pospuestas  || 0,
      canceladas:  totales.canceladas  || 0,
      vencidas:    totales.vencidas_hoy || 0,
      completadas_hoy_historial: completadasHoy.total || 0,
      porcentaje,
      mensaje,
      prioridad_top: prioridadTop?.prioridad || null,
    });

  } catch (error) {
    console.error('Error en estadísticas:', error.message);
    res.status(500).json({ error: 'Error al obtener estadísticas' });
  }
});

// ─── GET /api/estadisticas/historial ─────────────────────────────────────────
router.get('/historial', async (req, res) => {
  try {
    const dias = parseInt(req.query.dias) || 7;
    // Cuántos días hacia atrás mostrar (default: 7)

    const [historial] = await pool.query(`
      SELECT
        DATE(h.fecha_accion)          AS fecha,
        COUNT(DISTINCT h.tarea_id)    AS completadas,
        GROUP_CONCAT(t.titulo SEPARATOR '|') AS titulos
        -- GROUP_CONCAT junta todos los títulos del día en un string separado por |
      FROM historial_tareas h
      JOIN tareas t ON h.tarea_id = t.id
      WHERE h.usuario_id = ?
        AND h.accion = 'completada'
        AND h.fecha_accion >= DATE_SUB(NOW(), INTERVAL ? DAY)
      GROUP BY DATE(h.fecha_accion)
      ORDER BY fecha DESC
    `, [req.usuario.id, dias]);

    res.json({ historial, dias });

  } catch (error) {
    console.error('Error en historial:', error.message);
    res.status(500).json({ error: 'Error al obtener el historial' });
  }
});

// ─── GET /api/estadisticas/racha ──────────────────────────────────────────────
router.get('/racha', async (req, res) => {
  try {
    // Obtenemos los días (sin hora) donde el usuario completó al menos una tarea
    const [dias] = await pool.query(`
      SELECT DISTINCT DATE(fecha_accion) AS fecha
      FROM historial_tareas
      WHERE usuario_id = ? AND accion = 'completada'
      ORDER BY fecha DESC
      LIMIT 365
    `, [req.usuario.id]);

    // Calculamos la racha de días consecutivos
    let racha = 0;
    const hoy = new Date();
    hoy.setHours(0, 0, 0, 0);

    for (let i = 0; i < dias.length; i++) {
      const fechaDia = new Date(dias[i].fecha);
      const diasAtras = Math.floor((hoy - fechaDia) / (1000 * 60 * 60 * 24));

      if (diasAtras === i) {
        racha++;
        // Si el día está exactamente i días atrás, es consecutivo
      } else {
        break;
        // Se rompió la racha
      }
    }

    res.json({ racha, mensaje_racha: _mensajeRacha(racha) });

  } catch (error) {
    console.error('Error en racha:', error.message);
    res.status(500).json({ error: 'Error al obtener la racha' });
  }
});

// ─── Funciones auxiliares ─────────────────────────────────────────────────────
function _mensajeMotivacional(porcentaje, completadas, total) {
  if (total === 0)        return { texto: 'Agregá tareas para empezar tu día', emoji: '📝', tipo: 'neutro' };
  if (porcentaje === 100) return { texto: '¡Completaste todo! Eres increíble', emoji: '🎉', tipo: 'excelente' };
  if (porcentaje >= 75)   return { texto: '¡Casi terminás! Un último esfuerzo', emoji: '💪', tipo: 'muy_bien' };
  if (porcentaje >= 50)   return { texto: 'Vas por la mitad, muy bien', emoji: '🚀', tipo: 'bien' };
  if (porcentaje >= 25)   return { texto: 'Buen comienzo, seguí adelante', emoji: '⚡', tipo: 'regular' };
  return { texto: 'Empecemos el día con energía', emoji: '✨', tipo: 'inicio' };
}

function _mensajeRacha(racha) {
  if (racha === 0)  return 'Completá una tarea hoy para iniciar tu racha';
  if (racha === 1)  return '¡Primer día de racha! Seguí mañana';
  if (racha < 7)    return `${racha} días seguidos. ¡Vas bien!`;
  if (racha < 30)   return `¡${racha} días de racha! Sos constante`;
  return `¡Increíble! ${racha} días consecutivos`;
}

module.exports = router;
