// server.js
// ─────────────────────────────────────────────────────────────────────────────
// PUNTO DE ENTRADA del servidor.
// Es el primer archivo que corre cuando ejecutás "npm run dev".
// Su responsabilidad: configurar Express, registrar rutas, conectar la BD y arrancar.
// ─────────────────────────────────────────────────────────────────────────────

const express = require('express');
const cors    = require('cors');
require('dotenv').config();
// dotenv debe cargarse PRIMERO — antes de cualquier cosa que use process.env

const { verificarConexion } = require('./db/connection');
const crearTablas           = require('./db/schema');

// ─── CREAR LA APP ─────────────────────────────────────────────────────────────
const app  = express();
const PORT = process.env.PORT || 3000;

// ─── MIDDLEWARES ──────────────────────────────────────────────────────────────
// Un middleware es código que se ejecuta en CADA petición antes de llegar a la ruta.
// app.use() registra un middleware global.

app.use(cors());
// Permite que Flutter (que corre en otro puerto/origen) haga peticiones al servidor.
// Sin esto, Flutter bloquea todas las peticiones por seguridad.

app.use(express.json());
// Lee el body de cada petición y lo convierte a objeto JS.
// Sin esto, req.body siempre sería undefined en los POST/PUT.

app.use((req, res, next) => {
  // Middleware de logging: imprime en consola cada petición que llega.
  // Útil para debuggear — podés ver en tiempo real qué está pidiendo Flutter.
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  next();
  // next() le dice a Express: "terminé, pasá al siguiente middleware o a la ruta"
  // Si no llamás next(), la petición queda colgada para siempre
});

// ─── RUTAS BASE ───────────────────────────────────────────────────────────────

app.get('/health', (req, res) => {
  // Ruta de diagnóstico — Flutter la llama al iniciar para saber si hay conexión
  res.json({
    status:    'ok',
    mensaje:   'Servidor funcionando correctamente',
    timestamp: new Date().toISOString()
  });
});

app.get('/info', (req, res) => {
  res.json({
    app:     'Agenda App',
    version: '1.0.0'
  });
});

// ─── RUTAS DE LA API ──────────────────────────────────────────────────────────
const rutasAuth = require('./routes/auth');
app.use('/api/auth', rutasAuth);

const rutasTareas = require('./routes/tareas');
app.use('/api/tareas', rutasTareas);

// Se agregan a medida que avanzamos en los sprints:
// const rutasTareas       = require('./routes/tareas');
// const rutasCategorias   = require('./routes/categorias');
// const rutasEstadisticas = require('./routes/estadisticas');
// app.use('/api/tareas',        rutasTareas);
// app.use('/api/categorias',    rutasCategorias);
// app.use('/api/estadisticas',  rutasEstadisticas);

// ─── RUTA NO ENCONTRADA ───────────────────────────────────────────────────────
app.use((req, res) => {
  // Se ejecuta si NINGUNA ruta anterior respondió
  res.status(404).json({
    error:  'Ruta no encontrada',
    ruta:   req.url,
    metodo: req.method
  });
});

// ─── MANEJO GLOBAL DE ERRORES ─────────────────────────────────────────────────
app.use((err, req, res, next) => {
  // 4 parámetros = Express lo reconoce como manejador de errores
  // Cualquier error no manejado en las rutas llega acá
  console.error('Error no manejado:', err.message);
  res.status(500).json({
    error:   'Error interno del servidor',
    detalle: process.env.NODE_ENV === 'development' ? err.message : 'Contactá al administrador'
    // En desarrollo mostramos el error real para debuggear
    // En producción lo ocultamos por seguridad
  });
});

// ─── ARRANQUE ─────────────────────────────────────────────────────────────────
const iniciarServidor = async () => {
  console.log('\n─── Iniciando Agenda App ───────────────────────────\n');

  await verificarConexion();
  // Paso 1: verificar que MySQL está accesible
  // Si falla, el servidor se cierra antes de aceptar peticiones

  await crearTablas();
  // Paso 2: crear las tablas si no existen
  // Solo crea las que faltan — no toca datos existentes

  app.listen(PORT, () => {
    console.log(`✓ Servidor corriendo en http://localhost:${PORT}`);
    console.log(`✓ Health check: http://localhost:${PORT}/health`);
    console.log('\n────────────────────────────────────────────────────\n');
  });
};

iniciarServidor();
