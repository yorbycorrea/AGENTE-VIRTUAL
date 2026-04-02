// routes/tareas.js
// ─────────────────────────────────────────────────────────────────────────────
// RUTAS DE TAREAS — todas requieren token JWT válido
//
// GET    /api/tareas              → listar tareas (con filtros opcionales)
// GET    /api/tareas/hoy          → tareas de hoy
// GET    /api/tareas/:id          → una tarea específica
// POST   /api/tareas              → crear tarea
// PUT    /api/tareas/:id          → editar tarea completa
// PATCH  /api/tareas/:id/estado   → solo cambiar el estado
// DELETE /api/tareas/:id          → borrar tarea
// ─────────────────────────────────────────────────────────────────────────────

const express        = require('express');
const { pool }       = require('../db/connection');
const verificarToken = require('../middleware/auth');

const router = express.Router();

router.use(verificarToken);
// Al poner verificarToken acá (en el router, no en cada ruta individual),
// se aplica automáticamente a TODAS las rutas de este archivo.
// Es más limpio que repetirlo en cada ruta.

// ─── Función auxiliar: registrar en historial ────────────────────────────────
// La usamos cada vez que una tarea cambia de estado.
// La definimos acá arriba para poder usarla en las rutas de abajo.
const registrarHistorial = async (tareaId, usuarioId, accion, notas = null) => {
  await pool.query(
    'INSERT INTO historial_tareas (tarea_id, usuario_id, accion, notas) VALUES (?, ?, ?, ?)',
    [tareaId, usuarioId, accion, notas]
  );
};

// ─── GET /api/tareas/hoy ──────────────────────────────────────────────────────
// IMPORTANTE: esta ruta debe ir ANTES de GET /api/tareas/:id
// Si estuviera después, Express interpretaría "hoy" como un :id
router.get('/hoy', async (req, res) => {
  try {
    const hoy = new Date().toISOString().split('T')[0];
    // toISOString() → "2026-03-29T14:30:00.000Z"
    // split('T')[0] → "2026-03-29"
    // Así obtenemos solo la fecha en formato YYYY-MM-DD que usa MySQL

    const [tareas] = await pool.query(`
      SELECT
        t.*,
        c.nombre  AS categoria_nombre,
        c.color   AS categoria_color,
        c.icono   AS categoria_icono
      FROM tareas t
      LEFT JOIN categorias c ON t.categoria_id = c.id
      WHERE t.usuario_id = ?
        AND t.fecha_limite = ?
        AND t.estado IN ('pendiente', 'pospuesta')
      ORDER BY t.hora_limite ASC, t.prioridad DESC
    `, [req.usuario.id, hoy]);
    // LEFT JOIN: trae los datos de la categoría aunque la tarea no tenga categoría
    // Si no hay categoría, categoria_nombre será NULL (no rompe la query)
    // ORDER BY hora_limite ASC: primero las más tempranas
    // prioridad DESC: dentro de la misma hora, primero las de mayor prioridad

    res.json({ tareas, fecha: hoy, total: tareas.length });

  } catch (error) {
    console.error('Error al obtener tareas de hoy:', error.message);
    res.status(500).json({ error: 'Error al obtener las tareas de hoy' });
  }
});

// ─── GET /api/tareas ──────────────────────────────────────────────────────────
router.get('/', async (req, res) => {
  try {
    const {
      estado,
      categoria_id,
      fecha_desde,
      fecha_hasta,
      prioridad,
      buscar
    } = req.query;
    // req.query contiene los parámetros de la URL
    // Ejemplo: GET /api/tareas?estado=pendiente&prioridad=alta
    // Todos son opcionales — si no vienen, no se aplica ese filtro

    // Construimos la query dinámicamente según los filtros que lleguen
    let query = `
      SELECT
        t.*,
        c.nombre AS categoria_nombre,
        c.color  AS categoria_color,
        c.icono  AS categoria_icono
      FROM tareas t
      LEFT JOIN categorias c ON t.categoria_id = c.id
      WHERE t.usuario_id = ?
    `;
    const params = [req.usuario.id];
    // params es el array de valores para los ? de la query
    // Vamos agregando condiciones y sus valores en paralelo

    if (estado)       { query += ' AND t.estado = ?';          params.push(estado); }
    if (categoria_id) { query += ' AND t.categoria_id = ?';    params.push(categoria_id); }
    if (prioridad)    { query += ' AND t.prioridad = ?';        params.push(prioridad); }
    if (fecha_desde)  { query += ' AND t.fecha_limite >= ?';    params.push(fecha_desde); }
    if (fecha_hasta)  { query += ' AND t.fecha_limite <= ?';    params.push(fecha_hasta); }
    if (buscar) {
      query += ' AND (t.titulo LIKE ? OR t.descripcion LIKE ?)';
      params.push(`%${buscar}%`, `%${buscar}%`);
      // LIKE con % = contiene ese texto en cualquier posición
      // Buscamos en título Y en descripción
    }

    query += ' ORDER BY t.fecha_limite ASC, t.creada_en DESC';

    const [tareas] = await pool.query(query, params);

    res.json({ tareas, total: tareas.length });

  } catch (error) {
    console.error('Error al obtener tareas:', error.message);
    res.status(500).json({ error: 'Error al obtener las tareas' });
  }
});

// ─── GET /api/tareas/:id ──────────────────────────────────────────────────────
router.get('/:id', async (req, res) => {
  try {
    const [tareas] = await pool.query(`
      SELECT
        t.*,
        c.nombre AS categoria_nombre,
        c.color  AS categoria_color
      FROM tareas t
      LEFT JOIN categorias c ON t.categoria_id = c.id
      WHERE t.id = ? AND t.usuario_id = ?
    `, [req.params.id, req.usuario.id]);
    // req.params.id = el :id de la URL
    // Siempre filtramos también por usuario_id — un usuario no puede ver tareas de otro

    if (tareas.length === 0) {
      return res.status(404).json({ error: 'Tarea no encontrada' });
    }

    // Traemos también el historial de esta tarea
    const [historial] = await pool.query(`
      SELECT accion, fecha_accion, notas
      FROM historial_tareas
      WHERE tarea_id = ?
      ORDER BY fecha_accion DESC
    `, [req.params.id]);

    res.json({ tarea: tareas[0], historial });

  } catch (error) {
    console.error('Error al obtener tarea:', error.message);
    res.status(500).json({ error: 'Error al obtener la tarea' });
  }
});

// ─── POST /api/tareas ─────────────────────────────────────────────────────────
router.post('/', async (req, res) => {
  const {
    titulo,
    descripcion,
    prioridad,
    categoria_id,
    fecha_limite,
    hora_limite,
    posponer_automatico
  } = req.body;

  if (!titulo || titulo.trim() === '') {
    return res.status(400).json({ error: 'El título es obligatorio' });
  }

  try {
    const [resultado] = await pool.query(`
      INSERT INTO tareas
        (usuario_id, titulo, descripcion, prioridad, categoria_id,
         fecha_limite, hora_limite, posponer_automatico)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `, [
      req.usuario.id,
      titulo.trim(),
      descripcion   || null,
      prioridad     || 'media',
      categoria_id  || null,
      fecha_limite  || null,
      hora_limite   || null,
      posponer_automatico || false
    ]);

    // Registramos en el historial que la tarea fue creada
    await registrarHistorial(resultado.insertId, req.usuario.id, 'creada');

    // Buscamos la tarea recién creada para devolverla completa
    const [tareas] = await pool.query(
      'SELECT * FROM tareas WHERE id = ?',
      [resultado.insertId]
    );

    res.status(201).json({
      mensaje: 'Tarea creada',
      tarea: tareas[0]
    });

  } catch (error) {
    console.error('Error al crear tarea:', error.message);
    res.status(500).json({ error: 'Error al crear la tarea' });
  }
});

// ─── PUT /api/tareas/:id ──────────────────────────────────────────────────────
router.put('/:id', async (req, res) => {
  const {
    titulo,
    descripcion,
    prioridad,
    categoria_id,
    fecha_limite,
    hora_limite,
    posponer_automatico
  } = req.body;

  if (!titulo || titulo.trim() === '') {
    return res.status(400).json({ error: 'El título es obligatorio' });
  }

  try {
    // Verificamos que la tarea existe y pertenece al usuario
    const [existente] = await pool.query(
      'SELECT id FROM tareas WHERE id = ? AND usuario_id = ?',
      [req.params.id, req.usuario.id]
    );

    if (existente.length === 0) {
      return res.status(404).json({ error: 'Tarea no encontrada' });
    }

    await pool.query(`
      UPDATE tareas SET
        titulo              = ?,
        descripcion         = ?,
        prioridad           = ?,
        categoria_id        = ?,
        fecha_limite        = ?,
        hora_limite         = ?,
        posponer_automatico = ?
      WHERE id = ? AND usuario_id = ?
    `, [
      titulo.trim(),
      descripcion         || null,
      prioridad           || 'media',
      categoria_id        || null,
      fecha_limite        || null,
      hora_limite         || null,
      posponer_automatico || false,
      req.params.id,
      req.usuario.id
    ]);

    await registrarHistorial(req.params.id, req.usuario.id, 'editada');

    const [tareas] = await pool.query(
      'SELECT * FROM tareas WHERE id = ?',
      [req.params.id]
    );

    res.json({ mensaje: 'Tarea actualizada', tarea: tareas[0] });

  } catch (error) {
    console.error('Error al actualizar tarea:', error.message);
    res.status(500).json({ error: 'Error al actualizar la tarea' });
  }
});

// ─── PATCH /api/tareas/:id/estado ────────────────────────────────────────────
// Solo actualiza el estado — no toca el resto de los campos
router.patch('/:id/estado', async (req, res) => {
  const { estado, notas } = req.body;
  const estadosValidos = ['pendiente', 'completada', 'cancelada', 'pospuesta'];

  if (!estado || !estadosValidos.includes(estado)) {
    return res.status(400).json({
      error: 'Estado inválido',
      estados_validos: estadosValidos
    });
  }

  try {
    const [existente] = await pool.query(
      'SELECT id, estado, dias_pospuesta FROM tareas WHERE id = ? AND usuario_id = ?',
      [req.params.id, req.usuario.id]
    );

    if (existente.length === 0) {
      return res.status(404).json({ error: 'Tarea no encontrada' });
    }

    const tarea = existente[0];
    let camposExtra = '';
    let valoresExtra = [];

    if (estado === 'completada') {
      camposExtra = ', completada_en = NOW()';
      // NOW() = fecha y hora actual de MySQL
      // La guardamos para las estadísticas del día
    }

    if (estado === 'pospuesta') {
      // Mover la fecha_limite al día siguiente
      camposExtra = `, fecha_limite = DATE_ADD(fecha_limite, INTERVAL 1 DAY),
                      dias_pospuesta = dias_pospuesta + 1`;
      // DATE_ADD: función de MySQL para sumar intervalos a fechas
      // Así la tarea aparece mañana automáticamente
    }

    await pool.query(`
      UPDATE tareas SET estado = ? ${camposExtra}
      WHERE id = ? AND usuario_id = ?
    `, [estado, ...valoresExtra, req.params.id, req.usuario.id]);

    await registrarHistorial(req.params.id, req.usuario.id, estado, notas || null);

    const [tareas] = await pool.query(
      'SELECT * FROM tareas WHERE id = ?',
      [req.params.id]
    );

    res.json({ mensaje: `Tarea marcada como ${estado}`, tarea: tareas[0] });

  } catch (error) {
    console.error('Error al cambiar estado:', error.message);
    res.status(500).json({ error: 'Error al cambiar el estado' });
  }
});

// ─── DELETE /api/tareas/:id ───────────────────────────────────────────────────
router.delete('/:id', async (req, res) => {
  try {
    const [existente] = await pool.query(
      'SELECT id FROM tareas WHERE id = ? AND usuario_id = ?',
      [req.params.id, req.usuario.id]
    );

    if (existente.length === 0) {
      return res.status(404).json({ error: 'Tarea no encontrada' });
    }

    await pool.query(
      'DELETE FROM tareas WHERE id = ? AND usuario_id = ?',
      [req.params.id, req.usuario.id]
    );
    // El historial se borra automáticamente por ON DELETE CASCADE en el schema

    res.json({ mensaje: 'Tarea eliminada correctamente' });

  } catch (error) {
    console.error('Error al eliminar tarea:', error.message);
    res.status(500).json({ error: 'Error al eliminar la tarea' });
  }
});

module.exports = router;
