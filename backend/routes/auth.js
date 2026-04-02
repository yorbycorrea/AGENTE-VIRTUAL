// routes/auth.js
// ─────────────────────────────────────────────────────────────────────────────
// RUTAS:
//   POST /api/auth/registro  → crear cuenta nueva
//   POST /api/auth/login     → iniciar sesión
//   GET  /api/auth/perfil    → ver perfil (requiere token)
// ─────────────────────────────────────────────────────────────────────────────

const express        = require('express');
const bcrypt         = require('bcryptjs');
const jwt            = require('jsonwebtoken');
const { pool }       = require('../db/connection');
const verificarToken = require('../middleware/auth');

const router = express.Router();
// Router es un "mini Express" — agrupa rutas relacionadas
// Después lo registramos en server.js con app.use('/api/auth', router)
// Así cada ruta acá es relativa: '/' = '/api/auth/'

// ─── POST /api/auth/registro ──────────────────────────────────────────────────
router.post('/registro', async (req, res) => {
  const { nombre, email, password } = req.body;
  // Destructuring: extraemos estos tres campos del body que mandó Flutter
  // Si Flutter mandó: { "nombre": "Ana", "email": "ana@mail.com", "password": "123" }
  // entonces nombre = "Ana", email = "ana@mail.com", password = "123"

  // ── Validaciones básicas ──
  if (!nombre || !email || !password) {
    return res.status(400).json({
      error: 'Todos los campos son obligatorios',
      campos_requeridos: ['nombre', 'email', 'password']
    });
    // 400 = Bad Request — el cliente mandó datos incompletos
  }

  if (password.length < 6) {
    return res.status(400).json({
      error: 'La contraseña debe tener al menos 6 caracteres'
    });
  }

  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  // Expresión regular para validar formato de email
  // No es perfecta, pero filtra los casos más obvios
  if (!emailRegex.test(email)) {
    return res.status(400).json({ error: 'El email no tiene un formato válido' });
  }

  try {
    // ── Verificar que el email no esté registrado ──
    const [usuariosExistentes] = await pool.query(
      'SELECT id FROM usuarios WHERE email = ?',
      [email]
      // El "?" es un placeholder — mysql2 reemplaza el ? con el valor de forma segura
      // NUNCA concatenes strings en SQL: 'WHERE email = ' + email
      // Eso abre la puerta a SQL Injection (el ataque más común en bases de datos)
    );

    if (usuariosExistentes.length > 0) {
      return res.status(409).json({
        error: 'Ya existe una cuenta con ese email'
        // 409 = Conflict — el recurso ya existe
      });
    }

    // ── Encriptar la contraseña ──
    const salt = await bcrypt.genSalt(10);
    // genSalt(10): genera un "salt" — datos aleatorios que se mezclan con la contraseña
    // El 10 es el "cost factor" — cuánto trabajo le cuesta a la CPU calcular el hash
    // Más alto = más seguro pero más lento. 10 es el estándar para producción.
    // Con cost 10, hashear tarda ~100ms — suficientemente lento para frenar ataques de fuerza bruta

    const passwordHash = await bcrypt.hash(password, salt);
    // Genera el hash irreversible de la contraseña
    // Ejemplo: "miperro123" → "$2b$10$xK9mN2pL8qR7sT1vU3wX5e..."
    // Cada vez que lo corrés genera un hash diferente (por el salt aleatorio)
    // pero bcrypt.compare() sabe verificar si la contraseña original coincide

    // ── Guardar el usuario ──
    const [resultado] = await pool.query(
      'INSERT INTO usuarios (nombre, email, password_hash) VALUES (?, ?, ?)',
      [nombre, email.toLowerCase(), passwordHash]
      // email.toLowerCase(): guardamos el email en minúsculas siempre
      // Así "Ana@Mail.com" y "ana@mail.com" son la misma cuenta
    );

    // ── Crear categorías por defecto ──
    const categoriasDefault = [
      ['Personal',  '#6C63FF', 'person',      resultado.insertId],
      ['Trabajo',   '#FF6584', 'work',         resultado.insertId],
      ['Salud',     '#43C59E', 'favorite',     resultado.insertId],
      ['Urgente',   '#FF4757', 'priority_high', resultado.insertId],
    ];
    // resultado.insertId = el id del usuario que acaba de ser creado
    // Creamos categorías para que el usuario ya tenga algo útil al abrir la app

    for (const cat of categoriasDefault) {
      await pool.query(
        'INSERT INTO categorias (nombre, color, icono, usuario_id) VALUES (?, ?, ?, ?)',
        cat
      );
    }

    // ── Generar token JWT ──
    const token = jwt.sign(
      { id: resultado.insertId, email: email.toLowerCase() },
      // Payload: qué datos guardamos en el token
      // NO guardes la contraseña ni datos sensibles acá — el token es legible

      process.env.JWT_SECRET,
      // Clave secreta para firmar el token

      { expiresIn: '30d' }
      // El token expira en 30 días
      // Después de eso, el usuario tiene que volver a hacer login
    );

    res.status(201).json({
      mensaje: 'Cuenta creada exitosamente',
      token,
      usuario: {
        id:     resultado.insertId,
        nombre,
        email:  email.toLowerCase()
      }
      // 201 = Created — se creó un recurso nuevo
    });

  } catch (error) {
    console.error('Error en registro:', error.message);
    res.status(500).json({ error: 'Error al crear la cuenta' });
  }
});

// ─── POST /api/auth/login ─────────────────────────────────────────────────────
router.post('/login', async (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ error: 'Email y contraseña son obligatorios' });
  }

  try {
    // ── Buscar el usuario ──
    const [usuarios] = await pool.query(
      'SELECT id, nombre, email, password_hash FROM usuarios WHERE email = ?',
      [email.toLowerCase()]
    );

    if (usuarios.length === 0) {
      return res.status(401).json({ error: 'Credenciales incorrectas' });
      // IMPORTANTE: no decimos "el email no existe"
      // Decimos "credenciales incorrectas" para ambos casos (email o contraseña mal)
      // Así no le damos información a alguien que intenta adivinar cuentas
    }

    const usuario = usuarios[0];

    // ── Verificar la contraseña ──
    const passwordCorrecta = await bcrypt.compare(password, usuario.password_hash);
    // bcrypt.compare compara el texto plano con el hash guardado
    // Internamente aplica el mismo proceso de hash y compara
    // Devuelve true o false

    if (!passwordCorrecta) {
      return res.status(401).json({ error: 'Credenciales incorrectas' });
    }

    // ── Generar token ──
    const token = jwt.sign(
      { id: usuario.id, email: usuario.email },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    res.json({
      mensaje: 'Login exitoso',
      token,
      usuario: {
        id:     usuario.id,
        nombre: usuario.nombre,
        email:  usuario.email
      }
    });

  } catch (error) {
    console.error('Error en login:', error.message);
    res.status(500).json({ error: 'Error al iniciar sesión' });
  }
});

// ─── GET /api/auth/perfil ─────────────────────────────────────────────────────
router.get('/perfil', verificarToken, async (req, res) => {
  // verificarToken es el middleware — se ejecuta ANTES del handler
  // Si el token es válido, req.usuario tiene { id, email }
  // Si el token es inválido, el middleware ya respondió con 401 y esto no se ejecuta

  try {
    const [usuarios] = await pool.query(
      'SELECT id, nombre, email, avatar_url, creado_en FROM usuarios WHERE id = ?',
      [req.usuario.id]
      // req.usuario.id viene del payload del token, puesto por el middleware
    );

    if (usuarios.length === 0) {
      return res.status(404).json({ error: 'Usuario no encontrado' });
    }

    res.json({ usuario: usuarios[0] });

  } catch (error) {
    console.error('Error al obtener perfil:', error.message);
    res.status(500).json({ error: 'Error al obtener el perfil' });
  }
});

module.exports = router;
