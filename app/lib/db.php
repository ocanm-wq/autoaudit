<?php
/**
 * AutoAudit - Conexión a PostgreSQL
 */

/** Devuelve la configuración de conexión. */
function aa_config(): array
{
    static $cfg = null;
    if ($cfg === null) {
        $cfg = require __DIR__ . '/../config.php';
    }
    return $cfg;
}

/**
 * Abre una conexión a PostgreSQL con el usuario y la contraseña indicados.
 *
 * Se conecta con las credenciales de la persona, no con una cuenta de la
 * aplicación: así los permisos de aud_admin y aud_consulta los aplica el
 * motor de base de datos y la bitácora registra al usuario real
 * (la función obtener_usuario() usa session_user).
 *
 * @throws PDOException si las credenciales no son válidas
 */
function aa_conectar(string $usuario, string $password): PDO
{
    $cfg = aa_config();

    $dsn = sprintf(
        'pgsql:host=%s;port=%s;dbname=%s',
        $cfg['host'],
        $cfg['port'],
        $cfg['dbname']
    );

    $pdo = new PDO($dsn, $usuario, $password, [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false,
    ]);

    // La estación de trabajo que queda en la bitácora
    $stmt = $pdo->prepare('SELECT set_config(?, ?, false)');
    $stmt->execute(['application_name', $cfg['app_name']]);
    $stmt->execute(['TimeZone', $cfg['timezone']]);

    return $pdo;
}

/**
 * Extrae el mensaje que PostgreSQL devolvió, sin el prefijo técnico de PDO.
 * Sirve para mostrar las validaciones de generar_trigger tal como las
 * escribió la base de datos.
 */
function aa_mensaje_error(Throwable $e): string
{
    $msg = $e->getMessage();

    // Quita prefijos tipo: SQLSTATE[P0001]: Raise exception: 7 ERROR:
    $msg = preg_replace('/^SQLSTATE\[[^\]]+\]:?\s*/', '', $msg);
    $msg = preg_replace('/^[^:]*:\s*\d+\s*ERROR:\s*/', '', $msg);

    // Deja solo la primera línea útil (quita CONTEXT, HINT, etc.)
    $lineas = preg_split('/\R/', trim($msg));
    foreach ($lineas as $linea) {
        $linea = trim($linea);
        if ($linea !== '' && stripos($linea, 'CONTEXT:') !== 0) {
            return $linea;
        }
    }

    return trim($msg) !== '' ? trim($msg) : 'Error desconocido en la base de datos.';
}
