// db/schema.js
// ─────────────────────────────────────────────────────────────────────────────
// RESPONSABILIDAD: crear todas las tablas de la base de datos si no existen.
// Se ejecuta UNA VEZ al arrancar el servidor.
// Usa "CREATE TABLE IF NOT EXISTS" → si la tabla ya existe, no hace nada.
// Así podés reiniciar el servidor sin miedo a perder datos.
//
// TABLAS QUE CREA:
//   1. usuarios          → cuentas de usuario (login/registro)
//   2. categorias        → categorías de tareas (trabajo, personal, etc.)
//   3. tareas            → las tareas/notas principales
//   4. recordatorios     → recordatorios configurables por tarea
//   5. historial_tareas  → registro de todo lo que pasó con cada tarea
// ─────────────────────────────────────────────────────────────────────────────

const { pool } = require('./connection');
// Importamos el pool del archivo que acabamos de crear
// La sintaxis { pool } es "destructuring" — sacamos solo pool del objeto exportado
// Es equivalente a: const connection = require('./connection'); const pool = connection.pool;

const crearTablas = async () => {
  // async porque vamos a usar await (operaciones que tardan)

  let connection;
  // Declaramos connection fuera del try para poder liberarla en el finally

  try {
    connection = await pool.getConnection();
    // Tomamos una conexión del pool para ejecutar todas las queries

    // ─── TABLA 1: usuarios ───────────────────────────────────────────────────
    // Guarda las cuentas de cada persona que usa la app.
    // Necesaria para sincronizar datos entre mobile y escritorio.
    await connection.query(`
      CREATE TABLE IF NOT EXISTS usuarios (
        id            INT AUTO_INCREMENT PRIMARY KEY,
        nombre        VARCHAR(100) NOT NULL,
        email         VARCHAR(255) NOT NULL UNIQUE,
        -- UNIQUE: no pueden existir dos usuarios con el mismo email
        -- Es la forma de evitar cuentas duplicadas
        password_hash VARCHAR(255) NOT NULL,
        -- Nunca guardamos la contraseña en texto plano
        -- Guardamos el "hash" — una versión encriptada irreversible
        -- Si alguien roba la base de datos, no puede recuperar las contraseñas
        avatar_url    VARCHAR(500) NULL,
        -- URL de la foto de perfil (opcional)
        creado_en     DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    `);
    console.log('  ✓ Tabla usuarios');

    // ─── TABLA 2: categorias ─────────────────────────────────────────────────
    // Permite organizar tareas por tipo: trabajo, personal, salud, etc.
    // Cada usuario tiene sus propias categorías.
    await connection.query(`
      CREATE TABLE IF NOT EXISTS categorias (
        id         INT AUTO_INCREMENT PRIMARY KEY,
        usuario_id INT NOT NULL,
        nombre     VARCHAR(100) NOT NULL,
        color      VARCHAR(7) DEFAULT '#6C63FF',
        -- Color en formato hexadecimal (#RRGGBB)
        -- Se usa en la UI para mostrar cada categoría con su color
        icono      VARCHAR(50) DEFAULT 'label',
        -- Nombre del ícono de Material Design a mostrar
        creada_en  DATETIME DEFAULT CURRENT_TIMESTAMP,

        FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE CASCADE
        -- FOREIGN KEY: usuario_id debe existir en usuarios.id
        -- ON DELETE CASCADE: si el usuario se borra, sus categorías se borran también
        -- Evita "categorías huérfanas" sin dueño
      )
    `);
    console.log('  ✓ Tabla categorias');

    // ─── TABLA 3: tareas ─────────────────────────────────────────────────────
    // La tabla principal. Cada fila es una tarea o nota del usuario.
    // Tiene todo lo necesario para las features pedidas:
    //   - estado para marcar como completada
    //   - posponer_automatico para moverla al día siguiente
    //   - fecha_completada para el historial y estadísticas
    await connection.query(`
      CREATE TABLE IF NOT EXISTS tareas (
        id                   INT AUTO_INCREMENT PRIMARY KEY,
        usuario_id           INT NOT NULL,
        categoria_id         INT NULL,
        -- NULL: una tarea puede no tener categoría asignada

        titulo               VARCHAR(255) NOT NULL,
        descripcion          TEXT NULL,
        prioridad            ENUM('baja', 'media', 'alta') DEFAULT 'media',
        -- ENUM: solo acepta uno de estos tres valores exactos
        -- Si intentás guardar 'urgente', MySQL lo rechaza

        estado               ENUM('pendiente', 'completada', 'cancelada', 'pospuesta') DEFAULT 'pendiente',
        -- pendiente  → tarea activa, no completada
        -- completada → el usuario la marcó como hecha
        -- cancelada  → el usuario la descartó
        -- pospuesta  → se movió a otro día

        fecha_limite         DATE NULL,
        -- DATE guarda solo la fecha: 2026-03-29
        hora_limite          TIME NULL,
        -- TIME guarda solo la hora: 14:30:00
        -- Los separamos para que sea fácil filtrar por fecha sin importar la hora

        posponer_automatico  BOOLEAN DEFAULT FALSE,
        -- Si es TRUE y la tarea no se completó en su día,
        -- node-cron la mueve automáticamente al día siguiente a medianoche
        -- Si es FALSE, queda como "vencida" y el usuario decide qué hacer

        dias_pospuesta       INT DEFAULT 0,
        -- Contador de cuántas veces se pospuso esta tarea
        -- Útil para las estadísticas y para mostrar alertas ("esta tarea lleva 3 días pospuesta")

        completada_en        DATETIME NULL,
        -- Cuándo exactamente se completó
        -- NULL si todavía está pendiente
        -- Necesario para calcular estadísticas del día

        creada_en            DATETIME DEFAULT CURRENT_TIMESTAMP,
        actualizada_en       DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        -- ON UPDATE CURRENT_TIMESTAMP: cada vez que actualizás esta fila,
        -- MySQL actualiza este campo automáticamente con la fecha/hora actual

        FOREIGN KEY (usuario_id)    REFERENCES usuarios(id)   ON DELETE CASCADE,
        FOREIGN KEY (categoria_id)  REFERENCES categorias(id) ON DELETE SET NULL
        -- ON DELETE SET NULL: si borrás una categoría, las tareas no se borran
        -- solo su categoria_id pasa a NULL — la tarea sobrevive sin categoría
      )
    `);
    console.log('  ✓ Tabla tareas');

    // ─── TABLA 4: recordatorios ───────────────────────────────────────────────
    // Cada tarea puede tener múltiples recordatorios configurados.
    // Ejemplo: recordatorio 30 min antes, y otro 5 min antes.
    await connection.query(`
      CREATE TABLE IF NOT EXISTS recordatorios (
        id            INT AUTO_INCREMENT PRIMARY KEY,
        tarea_id      INT NOT NULL,
        usuario_id    INT NOT NULL,

        tipo          ENUM('unico', 'repetir') DEFAULT 'unico',
        -- unico   → se dispara una vez en fecha_hora exacta
        -- repetir → se dispara cada X minutos/horas hasta que se complete la tarea

        fecha_hora    DATETIME NOT NULL,
        -- Cuándo disparar el recordatorio (para tipo 'unico')

        intervalo_minutos INT NULL,
        -- Cada cuántos minutos repetir (para tipo 'repetir')
        -- Ejemplos: 30 = cada media hora, 60 = cada hora, 1440 = cada día

        mensaje       VARCHAR(500) NULL,
        -- Mensaje personalizado del recordatorio
        -- Si es NULL, se usa el título de la tarea

        enviado       BOOLEAN DEFAULT FALSE,
        -- FALSE: todavía no se envió
        -- TRUE: ya se envió, node-cron no lo vuelve a enviar

        activo        BOOLEAN DEFAULT TRUE,
        -- Permite desactivar un recordatorio sin borrarlo

        creado_en     DATETIME DEFAULT CURRENT_TIMESTAMP,

        FOREIGN KEY (tarea_id)   REFERENCES tareas(id)    ON DELETE CASCADE,
        FOREIGN KEY (usuario_id) REFERENCES usuarios(id)  ON DELETE CASCADE
      )
    `);
    console.log('  ✓ Tabla recordatorios');

    // ─── TABLA 5: historial_tareas ────────────────────────────────────────────
    // Registra CADA ACCIÓN que ocurre con una tarea.
    // Con esta tabla podés reconstruir toda la historia de una tarea.
    // También es la fuente de verdad para las estadísticas del día.
    await connection.query(`
      CREATE TABLE IF NOT EXISTS historial_tareas (
        id          INT AUTO_INCREMENT PRIMARY KEY,
        tarea_id    INT NOT NULL,
        usuario_id  INT NOT NULL,

        accion      ENUM('creada', 'completada', 'pospuesta', 'cancelada', 'reabierta', 'editada') NOT NULL,
        -- creada    → cuando se crea la tarea (registro automático)
        -- completada → cuando se marca como hecha
        -- pospuesta  → cuando se mueve al día siguiente
        -- cancelada  → cuando se descarta
        -- reabierta  → si se desmarca como completada
        -- editada    → cuando se modifica el título, fecha, etc.

        fecha_accion DATETIME DEFAULT CURRENT_TIMESTAMP,
        -- Cuándo ocurrió esta acción exactamente
        -- Fundamental para calcular "tareas completadas HOY"

        notas        VARCHAR(500) NULL,
        -- Información extra opcional
        -- Ejemplo: "pospuesta por 1 día" o "editado el título"

        FOREIGN KEY (tarea_id)   REFERENCES tareas(id)   ON DELETE CASCADE,
        FOREIGN KEY (usuario_id) REFERENCES usuarios(id) ON DELETE CASCADE
      )
    `);
    console.log('  ✓ Tabla historial_tareas');

    console.log('\n✓ Base de datos lista\n');

  } catch (error) {
    console.error('\n✗ Error al crear las tablas:', error.message);
    process.exit(1);
  } finally {
    // finally se ejecuta SIEMPRE — haya error o no
    // Es el lugar correcto para liberar la conexión
    // Así nos aseguramos de que SIEMPRE se devuelve al pool,
    // incluso si ocurrió un error en el try
    if (connection) connection.release();
  }
};

module.exports = crearTablas;
