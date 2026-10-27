<?php
/**
 * AutoAudit - Configuración de la interfaz web
 *
 * Datos de conexión al servidor de PostgreSQL. Aquí NO se guardan usuarios
 * ni contraseñas: cada persona entra con su propio usuario de PostgreSQL y
 * los permisos los aplica la base de datos (roles aud_admin y aud_consulta).
 */

return [
    'host'     => getenv('AUTOAUDIT_DB_HOST') ?: '127.0.0.1',
    'port'     => getenv('AUTOAUDIT_DB_PORT') ?: '5432',
    'dbname'   => getenv('AUTOAUDIT_DB_NAME') ?: 'autoaudit',

    // Nombre que la bitácora guarda como estación de trabajo (application_name)
    'app_name' => getenv('AUTOAUDIT_APP_NAME') ?: 'AutoAudit-Web',
    'timezone' => getenv('AUTOAUDIT_TIMEZONE') ?: 'America/Guatemala',
];
