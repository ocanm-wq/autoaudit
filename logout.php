<?php
/**
 * AutoAudit - Cerrar sesión
 */

require_once __DIR__ . '/lib/auth.php';

aa_logout();

header('Location: login.php');
exit;
