// middleware/auth.js
// ─────────────────────────────────────────────────────────────────────────────
// RESPONSABILIDAD: verificar que cada petición tiene un token JWT válido.
// Se usa como "guardia" en las rutas que requieren estar logueado.
//
// Uso en una ruta:
//   const verificarToken = require('../middleware/auth');
//   router.get('/mis-tareas', verificarToken, (req, res) => { ... });
//                             ↑ se ejecuta antes del handler de la ruta
// ─────────────────────────────────────────────────────────────────────────────

const jwt = require('jsonwebtoken');

const verificarToken = (req, res, next) => {
  // Un middleware recibe req, res, y next
  // next() = "todo bien, seguí a la ruta"
  // res.status(401) = "no autorizado, pará acá"

  const authHeader = req.headers['authorization'];
  // Leemos el header Authorization de la petición
  // Flutter lo manda así: Authorization: Bearer eyJhbGciOiJIUzI1NiJ9...
  // Si no viene el header, authHeader es undefined

  if (!authHeader) {
    return res.status(401).json({
      error: 'Token requerido',
      detalle: 'Incluí el header Authorization: Bearer <token>'
    });
    // return para cortar la ejecución acá
    // sin return, Node seguiría ejecutando el resto de la función
  }

  const token = authHeader.split(' ')[1];
  // El header tiene formato: "Bearer eyJhbGciOiJIUzI1NiJ9..."
  // split(' ') lo divide en: ["Bearer", "eyJhbGciOiJIUzI1NiJ9..."]
  // [1] toma el segundo elemento = el token en sí

  if (!token) {
    return res.status(401).json({
      error: 'Formato de token inválido',
      detalle: 'El formato correcto es: Bearer <token>'
    });
  }

  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    // jwt.verify hace dos cosas:
    //   1. Verifica que el token fue firmado con JWT_SECRET (no es falso)
    //   2. Verifica que el token no expiró
    // Si algo falla, lanza un error que atrapa el catch
    // Si todo está bien, devuelve el payload (los datos que guardamos al crear el token)

    req.usuario = payload;
    // Adjuntamos los datos del usuario al objeto req
    // Así la ruta que sigue puede acceder a req.usuario.id, req.usuario.email, etc.
    // sin tener que volver a buscar en la base de datos

    next();
    // Todo bien — pasá a la ruta que sigue

  } catch (error) {
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({
        error: 'Token expirado',
        detalle: 'Volvé a iniciar sesión'
      });
    }
    return res.status(401).json({
      error: 'Token inválido',
      detalle: 'El token no es válido o fue manipulado'
    });
  }
};

module.exports = verificarToken;
