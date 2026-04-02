// db/connection.js
// ─────────────────────────────────────────────────────────────────────────────
// RESPONSABILIDAD: crear y exportar el pool de conexiones a MySQL.
// Este archivo no hace nada por sí solo — solo prepara la conexión.
// Otros archivos lo importan cuando necesitan hablar con la base de datos.
// ─────────────────────────────────────────────────────────────────────────────

const mysql = require('mysql2/promise');
// mysql2/promise es la versión moderna de mysql2.
// La diferencia: en lugar de callbacks (funciones anidadas), usa async/await.
// Siempre usamos esta versión — el código queda mucho más limpio.

require('dotenv').config();
// Lee el archivo .env y carga cada línea como variable de entorno.
// Después de esta línea, process.env.DB_HOST, process.env.DB_USER, etc. existen.
// Si no llamás esto antes de usar process.env, las variables son undefined.

const pool = mysql.createPool({
  // createPool crea un "grupo" de conexiones abiertas y listas.
  //
  // ¿Por qué pool y no una conexión simple?
  // Si usaras una sola conexión y llegan 5 peticiones al mismo tiempo,
  // 4 tendrían que esperar a que la primera termine.
  // Con un pool, cada petición toma una conexión libre del grupo.
  // Cuando termina, la devuelve al grupo para que otro la use.

  host: process.env.DB_HOST,          // dirección del servidor MySQL (localhost en desarrollo)
  user: process.env.DB_USER,          // nombre de usuario de MySQL
  password: process.env.DB_PASSWORD,  // contraseña
  database: process.env.DB_NAME,      // base de datos a usar (notas_db)
  waitForConnections: true,           // si todas las conexiones están ocupadas, espera en cola
  connectionLimit: 10,                // máximo 10 conexiones abiertas al mismo tiempo
  queueLimit: 0,                      // sin límite de peticiones en espera (0 = ilimitado)
  timezone: 'local'                   // usa la zona horaria del sistema operativo
                                      // importante para que las fechas de recordatorios sean correctas
});

// Función para verificar que la conexión funciona al arrancar
const verificarConexion = async () => {
  try {
    const connection = await pool.getConnection();
    // getConnection toma una conexión del pool
    // Si MySQL no está corriendo o las credenciales son incorrectas, lanza un error

    console.log('✓ Conexión a MySQL establecida correctamente');
    connection.release();
    // SIEMPRE liberar la conexión después de usarla
    // Si no la liberás, el pool se queda sin conexiones disponibles
    // y el servidor deja de responder peticiones
  } catch (error) {
    console.error('✗ Error al conectar con MySQL:', error.message);
    console.error('  Verificá que MySQL esté corriendo y las credenciales en .env sean correctas');
    process.exit(1);
    // Si no hay base de datos, no tiene sentido correr el servidor
    // process.exit(1) cierra el proceso con código de error (1 = falló)
  }
};

module.exports = { pool, verificarConexion };
// Exportamos dos cosas:
//   pool → para hacer queries en rutas y otros archivos
//   verificarConexion → para llamarla al arrancar el servidor
//
// module.exports es la forma de Node.js de decir "esto es lo público de este archivo"
// Lo que no está en module.exports es privado — nadie externo puede accederlo
