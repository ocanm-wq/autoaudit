<?php
/**
 * AutoAudit - Sesión y control de acceso
 *
 * No hay tabla de usuarios en la aplicación. La identidad y los permisos
 * vienen de PostgreSQL:
 *   - entrar  = lograr conectarse a la base con usuario y contraseña
 *   - ser administrador = pertenecer al rol aud_admin
 *   - poder consultar   = pertenecer al rol aud_consulta
 *
 * Nota: las credenciales se guardan en la sesión del servidor (no en una
 * cookie ni en el navegador) porque cada petición abre su propia conexión
 * con el usuario real. Para un entorno de producción conviene servir la
 * aplicación por HTTPS.
 */

require_once __DIR__ . '/db.php';

function aa_sesion_iniciar(): void
{
    if (session_status() === PHP_SESSION_ACTIVE) {
        return;
    }
    session_set_cookie_params([
        'httponly' => true,
        'samesite' => 'Lax',
    ]);
    session_start();
}

/** Token para proteger los formularios (CSRF). */
function aa_token(): string
{
    aa_sesion_iniciar();
    if (empty($_SESSION['token'])) {
        $_SESSION['token'] = bin2hex(random_bytes(16));
    }
    return $_SESSION['token'];
}

function aa_token_valido(?string $token): bool
{
    aa_sesion_iniciar();
    return !empty($_SESSION['token'])
        && is_string($token)
        && hash_equals($_SESSION['token'], $token);
}

/**
 * Intenta iniciar sesión. Devuelve null si todo salió bien
 * o el mensaje de error si falló.
 */
function aa_login(string $usuario, string $password): ?string
{
    aa_sesion_iniciar();

    try {
        $pdo = aa_conectar($usuario, $password);
    } catch (PDOException $e) {
        return 'No se pudo iniciar sesión. Verifique el usuario y la contraseña.';
    }

    // Qué roles del sistema de auditoría tiene este usuario
    $stmt = $pdo->query(
        "SELECT pg_has_role(session_user, 'aud_admin',    'USAGE') AS es_admin,
                pg_has_role(session_user, 'aud_consulta', 'USAGE') AS es_consulta,
                session_user                                       AS usuario"
    );
    $roles = $stmt->fetch();

    if (!$roles['es_admin'] && !$roles['es_consulta']) {
        return 'El usuario ' . $usuario . ' no tiene acceso al sistema de auditoría. '
             . 'Debe pertenecer al rol aud_admin o aud_consulta.';
    }

    session_regenerate_id(true);
    $_SESSION['usuario']     = $roles['usuario'];
    $_SESSION['password']    = $password;
    $_SESSION['es_admin']    = (bool) $roles['es_admin'];
    $_SESSION['es_consulta'] = (bool) $roles['es_consulta'];
    $_SESSION['token']       = bin2hex(random_bytes(16));

    return null;
}

function aa_logout(): void
{
    aa_sesion_iniciar();
    $_SESSION = [];
    if (ini_get('session.use_cookies')) {
        setcookie(session_name(), '', time() - 3600, '/');
    }
    session_destroy();
}

function aa_hay_sesion(): bool
{
    aa_sesion_iniciar();
    return !empty($_SESSION['usuario']);
}

function aa_usuario(): string
{
    aa_sesion_iniciar();
    return $_SESSION['usuario'] ?? '';
}

function aa_es_admin(): bool
{
    aa_sesion_iniciar();
    return !empty($_SESSION['es_admin']);
}

/** Conexión de la petición actual, con las credenciales de la sesión. */
function aa_pdo(): PDO
{
    static $pdo = null;
    if ($pdo === null) {
        aa_sesion_iniciar();
        $pdo = aa_conectar($_SESSION['usuario'], $_SESSION['password']);
    }
    return $pdo;
}

/** Exige sesión abierta; si no la hay, manda al login. */
function aa_exigir_sesion(): void
{
    if (!aa_hay_sesion()) {
        header('Location: login.php');
        exit;
    }
}

/** Exige además pertenecer a aud_admin. */
function aa_exigir_admin(): void
{
    aa_exigir_sesion();
    if (!aa_es_admin()) {
        http_response_code(403);
        require_once __DIR__ . '/layout.php';
        aa_encabezado('Acceso denegado');
        aa_aviso('error',
            '<strong>Acceso denegado.</strong> Solo los usuarios del rol '
            . '<span class="aa-ident">aud_admin</span> pueden configurar la auditoría. '
            . 'Su usuario pertenece a <span class="aa-ident">aud_consulta</span>.',
            false);
        echo '<a href="index.php" class="btn btn-outline-primary"><i class="bx bx-arrow-back me-1"></i>Volver al panel</a>';
        aa_pie();
        exit;
    }
}
