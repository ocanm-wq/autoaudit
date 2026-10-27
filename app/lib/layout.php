<?php
/**
 * AutoAudit - Plantilla de páginas (basada en Sneat, Bootstrap 5)
 *
 * Uso en una página nueva:
 *
 *   require_once __DIR__ . '/lib/layout.php';
 *   aa_exigir_sesion();                         // o aa_exigir_admin()
 *   aa_encabezado('Consulta del historial', 'Auditoría');
 *   // ... contenido con componentes de Bootstrap/Sneat (card, table, form) ...
 *   aa_pie();
 *
 * Todo lo que se imprime entre aa_encabezado() y aa_pie() queda dentro del
 * área de contenido, con el menú lateral y la barra superior ya armados.
 */

require_once __DIR__ . '/auth.php';

/** Escapa texto para HTML. Usar SIEMPRE al imprimir datos de la base. */
function aa_esc(?string $texto): string
{
    return htmlspecialchars((string) $texto, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

/** Logo de AutoAudit (escudo con marca de verificación). */
function aa_logo_svg(): string
{
    return '<svg viewBox="0 0 26 30" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">'
         . '<path d="M13 1 2 5v8.5C2 21 6.8 26.7 13 29c6.2-2.3 11-8 11-15.5V5L13 1Z" fill="#0e7490"/>'
         . '<path d="M13 1v28c6.2-2.3 11-8 11-15.5V5L13 1Z" fill="#fff" fill-opacity=".14"/>'
         . '<path d="m8.4 15.2 3.1 3.1 6.1-6.6" fill="none" stroke="#fff" stroke-width="2.4" '
         . 'stroke-linecap="round" stroke-linejoin="round"/>'
         . '</svg>';
}

/** Etiquetas <link> comunes a todas las páginas. */
function aa_head_comun(string $titulo): void
{
    ?>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= aa_esc($titulo) ?> · AutoAudit</title>
    <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,<?= rawurlencode(aa_logo_svg()) ?>">
    <link rel="stylesheet" href="assets/vendor/fonts/boxicons.css">
    <link rel="stylesheet" href="assets/vendor/css/core.css">
    <link rel="stylesheet" href="assets/vendor/css/theme-default.css">
    <link rel="stylesheet" href="assets/vendor/libs/perfect-scrollbar/perfect-scrollbar.css">
    <link rel="stylesheet" href="assets/css/autoaudit.css">
    <script src="assets/vendor/js/helpers.js"></script>
    <?php
}

/** Scripts comunes, al final del <body>. */
function aa_scripts_comunes(): void
{
    ?>
    <script src="assets/vendor/libs/jquery/jquery.js"></script>
    <script src="assets/vendor/libs/popper/popper.js"></script>
    <script src="assets/vendor/js/bootstrap.js"></script>
    <script src="assets/vendor/libs/perfect-scrollbar/perfect-scrollbar.js"></script>
    <script src="assets/vendor/js/menu.js"></script>
    <script src="assets/js/main.js"></script>
    <?php
}

/** Un ítem del menú lateral. */
function aa_menu_item(string $href, string $icono, string $texto): void
{
    $actual = basename($_SERVER['SCRIPT_NAME'] ?? '');
    $activo = $actual === $href ? ' active' : '';
    ?>
    <li class="menu-item<?= $activo ?>">
        <a href="<?= aa_esc($href) ?>" class="menu-link">
            <i class="menu-icon tf-icons bx <?= aa_esc($icono) ?>"></i>
            <div><?= aa_esc($texto) ?></div>
        </a>
    </li>
    <?php
}

/**
 * Abre la página con el menú lateral y la barra superior.
 *
 * @param string      $titulo  Título de la página (pestaña y encabezado)
 * @param string|null $seccion Texto gris antes del título, p. ej. "Auditoría"
 */
function aa_encabezado(string $titulo, ?string $seccion = null): void
{
    $usuario  = aa_usuario();
    // Inicial del avatar (sin depender de la extensión mbstring)
    $inicial  = strtoupper(substr(preg_replace('/^demo_/', '', $usuario), 0, 1));
    $rol      = aa_es_admin() ? 'Administrador' : 'Consulta';
    ?><!DOCTYPE html>
<html lang="es" class="light-style layout-menu-fixed" dir="ltr"
      data-theme="theme-default" data-assets-path="assets/" data-template="vertical-menu-template-free">
<head>
    <?php aa_head_comun($titulo); ?>
</head>
<body>
<div class="layout-wrapper layout-content-navbar">
    <div class="layout-container">

        <!-- Menú lateral -->
        <aside id="layout-menu" class="layout-menu menu-vertical menu bg-menu-theme">
            <div class="app-brand aa-brand">
                <a href="index.php" class="app-brand-link">
                    <span class="app-brand-logo"><?= aa_logo_svg() ?></span>
                    <span class="ms-2 aa-brand-textos">
                        <span class="aa-brand-text">Auto<span>Audit</span></span>
                        <span class="aa-brand-sub">Auditoría de datos</span>
                    </span>
                </a>
                <a href="javascript:void(0);" class="layout-menu-toggle menu-link text-large ms-auto d-block d-xl-none">
                    <i class="bx bx-chevron-left bx-sm align-middle"></i>
                </a>
            </div>

            <div class="menu-inner-shadow"></div>

            <ul class="menu-inner py-1">
                <?php aa_menu_item('index.php', 'bx-grid-alt', 'Panel'); ?>

                <li class="menu-header small text-uppercase">
                    <span class="menu-header-text">Auditoría</span>
                </li>
                <?php if (aa_es_admin()): ?>
                    <?php aa_menu_item('configuracion.php', 'bx-slider-alt', 'Configuración'); ?>
                <?php endif; ?>
                <?php aa_menu_item('consulta.php', 'bx-history', 'Historial de cambios'); ?>

                <li class="menu-header small text-uppercase">
                    <span class="menu-header-text">Sesión</span>
                </li>
                <?php aa_menu_item('logout.php', 'bx-log-out', 'Cerrar sesión'); ?>
            </ul>
        </aside>
        <!-- / Menú lateral -->

        <div class="layout-page">

            <!-- Barra superior -->
            <nav class="layout-navbar container-xxl navbar navbar-expand-xl navbar-detached align-items-center bg-navbar-theme"
                 id="layout-navbar">
                <div class="layout-menu-toggle navbar-nav align-items-xl-center me-3 me-xl-0 d-xl-none">
                    <a class="nav-item nav-link px-0 me-xl-4" href="javascript:void(0)">
                        <i class="bx bx-menu bx-sm"></i>
                    </a>
                </div>

                <div class="navbar-nav-right d-flex align-items-center" id="navbar-collapse">
                    <ul class="navbar-nav flex-row align-items-center ms-auto">
                        <li class="nav-item navbar-dropdown dropdown-user dropdown">
                            <a class="nav-link dropdown-toggle hide-arrow d-flex align-items-center" href="javascript:void(0);"
                               data-bs-toggle="dropdown">
                                <div class="avatar avatar-online me-2">
                                    <span class="avatar-initial rounded-circle bg-label-primary"><?= aa_esc($inicial) ?></span>
                                </div>
                                <div class="d-none d-md-block lh-sm">
                                    <span class="fw-semibold d-block"><?= aa_esc($usuario) ?></span>
                                    <small class="text-muted"><?= aa_esc($rol) ?></small>
                                </div>
                            </a>
                            <ul class="dropdown-menu dropdown-menu-end">
                                <li>
                                    <div class="dropdown-item-text">
                                        <span class="fw-semibold d-block"><?= aa_esc($usuario) ?></span>
                                        <small class="text-muted">
                                            Rol <span class="aa-ident"><?= aa_es_admin() ? 'aud_admin' : 'aud_consulta' ?></span>
                                        </small>
                                    </div>
                                </li>
                                <li><div class="dropdown-divider"></div></li>
                                <li>
                                    <a class="dropdown-item" href="logout.php">
                                        <i class="bx bx-power-off me-2"></i>
                                        <span class="align-middle">Cerrar sesión</span>
                                    </a>
                                </li>
                            </ul>
                        </li>
                    </ul>
                </div>
            </nav>
            <!-- / Barra superior -->

            <div class="content-wrapper">
                <div class="container-xxl flex-grow-1 container-p-y">
                    <h4 class="fw-bold py-3 mb-3">
                        <?php if ($seccion !== null): ?>
                            <span class="text-muted fw-light"><?= aa_esc($seccion) ?> /</span>
                        <?php endif; ?>
                        <?= aa_esc($titulo) ?>
                    </h4>
<?php
}

/** Cierra la página abierta con aa_encabezado(). */
function aa_pie(): void
{
    ?>
                </div>

                <footer class="content-footer footer bg-footer-theme">
                    <div class="container-xxl d-flex flex-wrap justify-content-between py-2 flex-md-row flex-column">
                        <div class="mb-2 mb-md-0">
                            AutoAudit · Sistema de auditoría automatizado
                        </div>
                        <div class="text-muted">
                            PostgreSQL · PL/pgSQL · PHP
                        </div>
                    </div>
                </footer>

                <div class="content-backdrop fade"></div>
            </div>
        </div>
    </div>

    <div class="layout-overlay layout-menu-toggle"></div>
</div>
<?php aa_scripts_comunes(); ?>
</body>
</html>
<?php
}

/** Página sin menú (inicio de sesión). */
function aa_encabezado_simple(string $titulo): void
{
    ?><!DOCTYPE html>
<html lang="es" class="light-style customizer-hide" dir="ltr"
      data-theme="theme-default" data-assets-path="assets/" data-template="vertical-menu-template-free">
<head>
    <?php aa_head_comun($titulo); ?>
    <link rel="stylesheet" href="assets/vendor/css/pages/page-auth.css">
</head>
<body class="aa-fondo-login">
<?php
}

function aa_pie_simple(): void
{
    aa_scripts_comunes();
    ?>
</body>
</html>
<?php
}

/**
 * Muestra un aviso de Bootstrap.
 * $tipo: exito | error | info | advertencia
 */
function aa_aviso(string $tipo, string $mensaje, bool $escapar = true): void
{
    $clases = [
        'exito'       => ['alert-success', 'bx-check-circle'],
        'error'       => ['alert-danger',  'bx-error-circle'],
        'info'        => ['alert-primary', 'bx-info-circle'],
        'advertencia' => ['alert-warning', 'bx-error'],
    ];
    [$clase, $icono] = $clases[$tipo] ?? $clases['info'];

    echo '<div class="alert ' . $clase . ' d-flex align-items-start" role="alert">'
       . '<i class="bx ' . $icono . ' me-2 mt-1"></i>'
       . '<div>' . ($escapar ? aa_esc($mensaje) : $mensaje) . '</div>'
       . '</div>';
}

/** Insignia de color para un evento (INSERT, UPDATE, DELETE). */
function aa_insignia_evento(string $evento): string
{
    $clases = [
        'INSERT' => 'bg-label-success',
        'UPDATE' => 'bg-label-warning',
        'DELETE' => 'bg-label-danger',
    ];
    $clase = $clases[strtoupper($evento)] ?? 'bg-label-secondary';

    return '<span class="badge aa-evento ' . $clase . '">' . aa_esc(strtoupper($evento)) . '</span>';
}

/** Muestra un valor de la bitácora; NULL se ve como un guion tenue. */
function aa_valor(?string $valor): string
{
    if ($valor === null) {
        return '<span class="aa-valor-vacio">—</span>';
    }
    return '<span class="aa-valor" title="' . aa_esc($valor) . '">' . aa_esc($valor) . '</span>';
}
