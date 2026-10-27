<?php
/**
 * AutoAudit - Panel principal
 *
 * Resumen con datos reales de la bitácora: cuántas tablas se auditan,
 * cuántos cambios hay registrados y su reparto por evento. Todo se lee a través de la vista auditoria.v_historial,
 * así que sirve igual para aud_admin y para aud_consulta.
 */

require_once __DIR__ . '/lib/layout.php';

aa_exigir_sesion();

$error    = null;
$tablas   = ['auditadas' => 0, 'total' => 0, 'combinaciones' => 0];
$totales  = ['cambios' => 0, 'hoy' => 0, 'usuarios' => 0];
$eventos  = ['INSERT' => 0, 'UPDATE' => 0, 'DELETE' => 0];

try {
    $pdo = aa_pdo();

    $tablas = $pdo->query(
        'SELECT count(*) FILTER (WHERE tiene_trigger) AS auditadas,
                count(*)                               AS total,
                COALESCE(sum(eventos_activos), 0)      AS combinaciones
         FROM auditoria.listar_tablas()'
    )->fetch();

    $totales = $pdo->query(
        "SELECT count(*)                                              AS cambios,
                count(*) FILTER (WHERE fecha_hora >= date_trunc('day', now())) AS hoy,
                count(DISTINCT usuario)                               AS usuarios
         FROM auditoria.v_historial"
    )->fetch();

    foreach ($pdo->query('SELECT evento, count(*) AS n FROM auditoria.v_historial GROUP BY evento') as $fila) {
        $eventos[$fila['evento']] = (int) $fila['n'];
    }
} catch (Throwable $e) {
    $error = aa_mensaje_error($e);
}

$total_eventos = max(1, array_sum($eventos));

aa_encabezado('Panel');

if ($error !== null) {
    aa_aviso('error', $error);
}
?>

<!-- Bienvenida -->
<div class="card mb-4">
    <div class="card-body d-flex flex-column flex-md-row align-items-md-center justify-content-between gap-3">
        <div>
            <h5 class="card-title text-primary mb-1">Hola, <?= aa_esc(aa_usuario()) ?></h5>
            <p class="mb-0 text-muted">
                <?php if (aa_es_admin()): ?>
                    Tiene rol <span class="aa-ident">aud_admin</span>: puede configurar qué se audita
                    y consultar el historial completo.
                <?php else: ?>
                    Tiene rol <span class="aa-ident">aud_consulta</span>: puede consultar el historial,
                    pero no modificar la configuración.
                <?php endif; ?>
                Los permisos los aplica PostgreSQL.
            </p>
        </div>
        <div class="d-flex gap-2 flex-shrink-0">
            <?php if (aa_es_admin()): ?>
                <a href="configuracion.php" class="btn btn-primary">
                    <i class="bx bx-slider-alt me-1"></i> Configurar
                </a>
            <?php endif; ?>
            <a href="consulta.php" class="btn btn-outline-primary">
                <i class="bx bx-history me-1"></i> Ver historial
            </a>
        </div>
    </div>
</div>

<!-- Tarjetas de resumen -->
<div class="row">
    <?php
    $tarjetas = [
        ['bx-table',      'primary', 'Tablas auditadas',
            (int) $tablas['auditadas'], 'de ' . (int) $tablas['total'] . ' en la base'],
        ['bx-list-check', 'info',    'Columna y evento',
            (int) $tablas['combinaciones'], 'combinaciones activas'],
        ['bx-data',       'success', 'Cambios registrados',
            (int) $totales['cambios'], (int) $totales['hoy'] . ' hoy'],
        ['bx-group',      'warning', 'Usuarios auditados',
            (int) $totales['usuarios'], 'con actividad en la bitácora'],
    ];
    foreach ($tarjetas as [$icono, $color, $titulo, $valor, $nota]):
    ?>
        <div class="col-sm-6 col-xl-3 mb-4">
            <div class="card aa-stat h-100">
                <div class="card-body d-flex align-items-center gap-3">
                    <div class="avatar flex-shrink-0">
                        <span class="avatar-initial rounded bg-label-<?= $color ?>"><i class="bx <?= $icono ?>"></i></span>
                    </div>
                    <div>
                        <span class="d-block text-muted small"><?= aa_esc($titulo) ?></span>
                        <span class="aa-stat-valor"><?= number_format($valor) ?></span>
                        <small class="d-block text-muted"><?= aa_esc($nota) ?></small>
                    </div>
                </div>
            </div>
        </div>
    <?php endforeach; ?>
</div>

<!-- Reparto por evento -->
<div class="card mb-4">
    <div class="card-header">
        <h5 class="card-title mb-0">Cambios por evento</h5>
        <small class="text-muted">Total registrado en la bitácora</small>
    </div>
    <div class="card-body">
        <div class="row">
            <?php
            $colores = ['INSERT' => 'success', 'UPDATE' => 'warning', 'DELETE' => 'danger'];
            foreach ($eventos as $evento => $n):
                $pct = round($n * 100 / $total_eventos);
            ?>
                <div class="col-md-4 mb-3 mb-md-0">
                    <div class="d-flex justify-content-between mb-1">
                        <?= aa_insignia_evento($evento) ?>
                        <span class="fw-semibold"><?= number_format($n) ?>
                            <small class="text-muted fw-normal">(<?= $pct ?>%)</small></span>
                    </div>
                    <div class="progress" style="height: 6px">
                        <div class="progress-bar bg-<?= $colores[$evento] ?>" role="progressbar"
                             style="width: <?= $pct ?>%" aria-valuenow="<?= $pct ?>"
                             aria-valuemin="0" aria-valuemax="100"></div>
                    </div>
                </div>
            <?php endforeach; ?>
        </div>
        <p class="text-muted small mb-0 mt-3">
            Un UPDATE solo se registra si el valor de la columna realmente cambió.
        </p>
    </div>
</div>

<?php
aa_pie();
