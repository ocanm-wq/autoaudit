<?php
/**
 * AutoAudit - Módulo de configuración de auditoría
 *
 * Permite elegir, a partir del diccionario de datos, qué tablas y columnas
 * se auditan y en qué eventos (INSERT, UPDATE, DELETE). Al guardar, llama a
 * auditoria.generar_trigger(), que valida la configuración y crea o
 * reemplaza el trigger de la tabla.
 *
 * Solo lo pueden usar los miembros del rol aud_admin.
 */

require_once __DIR__ . '/lib/layout.php';

aa_exigir_admin();

const AA_EVENTOS = [1 => 'INSERT', 2 => 'UPDATE', 3 => 'DELETE'];

/** Guarda un mensaje para mostrarlo después de redirigir. */
function aa_flash(string $tipo, string $mensaje): void
{
    aa_sesion_iniciar();
    $_SESSION['flash'] = ['tipo' => $tipo, 'mensaje' => $mensaje];
}

function aa_flash_tomar(): ?array
{
    aa_sesion_iniciar();
    $flash = $_SESSION['flash'] ?? null;
    unset($_SESSION['flash']);
    return $flash;
}

/** Devuelve el id_tabla, registrándola en aud_tabla si hacía falta. */
function aa_id_tabla(PDO $pdo, string $esquema, string $tabla): int
{
    $pdo->prepare(
        'INSERT INTO auditoria.aud_tabla (esquema, nombre_tabla)
         VALUES (?, ?)
         ON CONFLICT (esquema, nombre_tabla) DO NOTHING'
    )->execute([$esquema, $tabla]);

    $stmt = $pdo->prepare(
        'SELECT id_tabla FROM auditoria.aud_tabla
         WHERE esquema = ? AND nombre_tabla = ?'
    );
    $stmt->execute([$esquema, $tabla]);

    return (int) $stmt->fetchColumn();
}

$error = null;

// ---------------------------------------------------------------------
// Acciones (POST)
// ---------------------------------------------------------------------
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $accion  = $_POST['accion']  ?? '';
    $esquema = $_POST['esquema'] ?? '';
    $tabla   = $_POST['tabla']   ?? '';

    if (!aa_token_valido($_POST['token'] ?? null)) {
        $error = 'La sesión expiró. Vuelva a enviar el formulario.';
    } else {
        try {
            $pdo = aa_pdo();
            $pdo->beginTransaction();

            $id_tabla = aa_id_tabla($pdo, $esquema, $tabla);

            if ($accion === 'guardar') {
                // La tabla queda activa; los eventos dependen de lo marcado
                $pdo->prepare('UPDATE auditoria.aud_tabla SET activa = TRUE WHERE id_tabla = ?')
                    ->execute([$id_tabla]);

                $columnas   = $_POST['cols'] ?? [];
                $marcados   = $_POST['ev']   ?? [];

                $ins_columna = $pdo->prepare(
                    'INSERT INTO auditoria.aud_columna (id_tabla, nombre_columna)
                     VALUES (?, ?)
                     ON CONFLICT (id_tabla, nombre_columna) DO NOTHING'
                );
                $sel_columna = $pdo->prepare(
                    'SELECT id_columna FROM auditoria.aud_columna
                     WHERE id_tabla = ? AND nombre_columna = ?'
                );
                $activar = $pdo->prepare(
                    'INSERT INTO auditoria.aud_configuracion (id_columna, id_evento, activa)
                     VALUES (?, ?, TRUE)
                     ON CONFLICT (id_columna, id_evento) DO UPDATE SET activa = TRUE'
                );
                $desactivar = $pdo->prepare(
                    'UPDATE auditoria.aud_configuracion SET activa = FALSE
                     WHERE id_columna = ? AND id_evento = ?'
                );

                foreach ($columnas as $columna) {
                    $columna  = (string) $columna;
                    $eventos  = array_map('intval', (array) ($marcados[$columna] ?? []));

                    if ($eventos === []) {
                        // Sin eventos: se desactiva lo que hubiera, no se borra
                        $sel_columna->execute([$id_tabla, $columna]);
                        $id_columna = $sel_columna->fetchColumn();
                        if ($id_columna !== false) {
                            foreach (array_keys(AA_EVENTOS) as $id_evento) {
                                $desactivar->execute([(int) $id_columna, $id_evento]);
                            }
                        }
                        continue;
                    }

                    $ins_columna->execute([$id_tabla, $columna]);
                    $sel_columna->execute([$id_tabla, $columna]);
                    $id_columna = (int) $sel_columna->fetchColumn();

                    foreach (array_keys(AA_EVENTOS) as $id_evento) {
                        if (in_array($id_evento, $eventos, true)) {
                            $activar->execute([$id_columna, $id_evento]);
                        } else {
                            $desactivar->execute([$id_columna, $id_evento]);
                        }
                    }
                }
            } elseif ($accion === 'desactivar') {
                $pdo->prepare('UPDATE auditoria.aud_tabla SET activa = FALSE WHERE id_tabla = ?')
                    ->execute([$id_tabla]);
            } elseif ($accion === 'activar') {
                $pdo->prepare('UPDATE auditoria.aud_tabla SET activa = TRUE WHERE id_tabla = ?')
                    ->execute([$id_tabla]);
            } else {
                throw new RuntimeException('Acción no reconocida.');
            }

            // Generar (o retirar) el trigger según la configuración guardada.
            // Aquí es donde la base de datos valida tabla, columnas y llave primaria.
            $stmt = $pdo->prepare('SELECT auditoria.generar_trigger(?)');
            $stmt->execute([$id_tabla]);
            $resultado = (string) $stmt->fetchColumn();

            $pdo->commit();

            aa_flash('exito', $resultado);
            header('Location: configuracion.php?esquema=' . urlencode($esquema)
                 . '&tabla=' . urlencode($tabla));
            exit;
        } catch (Throwable $e) {
            if (isset($pdo) && $pdo->inTransaction()) {
                $pdo->rollBack();
            }
            // Nada quedó guardado: la transacción se revirtió completa
            $error = aa_mensaje_error($e);
        }
    }
}

// ---------------------------------------------------------------------
// Lectura de datos para la vista
// ---------------------------------------------------------------------
$esquema_sel = $_GET['esquema'] ?? ($_POST['esquema'] ?? null);
$tabla_sel   = $_GET['tabla']   ?? ($_POST['tabla']   ?? null);

$tablas   = [];
$columnas = [];
$info_sel = null;

try {
    $pdo    = aa_pdo();
    $tablas = $pdo->query('SELECT * FROM auditoria.listar_tablas()')->fetchAll();

    if ($tabla_sel !== null && $esquema_sel !== null) {
        foreach ($tablas as $t) {
            if ($t['esquema'] === $esquema_sel && $t['tabla'] === $tabla_sel) {
                $info_sel = $t;
                break;
            }
        }

        if ($info_sel === null) {
            $error = $error ?? 'La tabla indicada no existe en la base de datos.';
            $tabla_sel = null;
        } else {
            $stmt = $pdo->prepare('SELECT * FROM auditoria.listar_columnas(?, ?)');
            $stmt->execute([$esquema_sel, $tabla_sel]);
            $columnas = $stmt->fetchAll();
        }
    }
} catch (Throwable $e) {
    $error = $error ?? aa_mensaje_error($e);
}

$flash = aa_flash_tomar();
$tiene_pk = false;
foreach ($columnas as $c) {
    if ($c['es_pk']) {
        $tiene_pk = true;
        break;
    }
}

// Cuántas columnas tienen al menos un evento marcado
$columnas_auditadas = 0;
foreach ($columnas as $c) {
    if ($c['aud_insert'] || $c['aud_update'] || $c['aud_delete']) {
        $columnas_auditadas++;
    }
}

aa_encabezado($tabla_sel !== null ? $tabla_sel : 'Configuración', $tabla_sel !== null ? 'Configuración' : 'Auditoría');

if ($flash !== null) {
    aa_aviso($flash['tipo'], $flash['mensaje']);
}
if ($error !== null) {
    aa_aviso('error', $error);
}

// ---------------------------------------------------------------------
// Vista: detalle de una tabla
// ---------------------------------------------------------------------
if ($tabla_sel !== null && $info_sel !== null):
?>
    <a href="configuracion.php" class="btn btn-sm btn-outline-secondary mb-3">
        <i class="bx bx-arrow-back me-1"></i> Todas las tablas
    </a>

    <div class="row">
        <div class="col-lg-8 mb-4">
            <div class="card">
                <div class="card-header d-flex flex-wrap justify-content-between align-items-center gap-2">
                    <div>
                        <h5 class="card-title mb-1">
                            <span class="aa-ident fs-6"><?= aa_esc($esquema_sel . '.' . $tabla_sel) ?></span>
                        </h5>
                        <small class="text-muted">Marque los eventos que se registran en cada columna.</small>
                    </div>
                    <?php if ($info_sel['tiene_trigger']): ?>
                        <span class="badge bg-label-success"><i class="bx bx-check-shield me-1"></i>Auditoría activa</span>
                    <?php elseif ($info_sel['id_tabla'] !== null): ?>
                        <span class="badge bg-label-secondary"><i class="bx bx-pause-circle me-1"></i>Desactivada</span>
                    <?php else: ?>
                        <span class="badge bg-label-secondary">Sin auditoría</span>
                    <?php endif; ?>
                </div>

                <?php if (!$tiene_pk): ?>
                    <div class="px-4">
                        <?php aa_aviso('advertencia',
                            'Esta tabla no tiene llave primaria. La bitácora la necesita para '
                            . 'identificar qué registro cambió, así que no se puede auditar.'); ?>
                    </div>
                <?php endif; ?>

                <form method="post" id="form-config">
                    <input type="hidden" name="token"   value="<?= aa_esc(aa_token()) ?>">
                    <input type="hidden" name="esquema" value="<?= aa_esc($esquema_sel) ?>">
                    <input type="hidden" name="tabla"   value="<?= aa_esc($tabla_sel) ?>">

                    <div class="table-responsive text-nowrap">
                        <table class="table aa-matriz mb-0">
                            <thead>
                                <tr>
                                    <th>Columna</th>
                                    <th>Tipo de dato</th>
                                    <?php foreach (AA_EVENTOS as $id_evento => $nombre): ?>
                                        <th class="aa-col-evento">
                                            <?= aa_insignia_evento($nombre) ?>
                                            <a class="aa-marcar-col" data-evento="<?= (int) $id_evento ?>"
                                               href="javascript:void(0)">marcar todas</a>
                                        </th>
                                    <?php endforeach; ?>
                                </tr>
                            </thead>
                            <tbody>
                            <?php foreach ($columnas as $col): ?>
                                <?php
                                $actual = [
                                    1 => (bool) $col['aud_insert'],
                                    2 => (bool) $col['aud_update'],
                                    3 => (bool) $col['aud_delete'],
                                ];
                                $auditada = in_array(true, $actual, true);
                                ?>
                                <tr class="<?= $auditada ? 'aa-fila-auditada' : '' ?>">
                                    <td>
                                        <span class="aa-ident"><?= aa_esc($col['columna']) ?></span>
                                        <?php if ($col['es_pk']): ?>
                                            <span class="badge bg-label-primary ms-1"
                                                  title="Llave primaria: identifica el registro en la bitácora">
                                                <i class="bx bx-key"></i> PK
                                            </span>
                                        <?php endif; ?>
                                        <input type="hidden" name="cols[]" value="<?= aa_esc($col['columna']) ?>">
                                    </td>
                                    <td class="aa-tipo"><?= aa_esc($col['tipo_dato']) ?></td>
                                    <?php foreach (AA_EVENTOS as $id_evento => $nombre): ?>
                                        <td class="aa-col-evento">
                                            <input class="form-check-input" type="checkbox"
                                                   name="ev[<?= aa_esc($col['columna']) ?>][]"
                                                   value="<?= (int) $id_evento ?>"
                                                   data-evento="<?= (int) $id_evento ?>"
                                                   aria-label="<?= aa_esc($nombre . ' en ' . $col['columna']) ?>"
                                                   <?= $actual[$id_evento] ? 'checked' : '' ?>>
                                        </td>
                                    <?php endforeach; ?>
                                </tr>
                            <?php endforeach; ?>
                            </tbody>
                        </table>
                    </div>

                    <div class="card-body d-flex flex-wrap gap-2 border-top">
                        <button type="submit" name="accion" value="guardar" class="btn btn-primary">
                            <i class="bx bx-save me-1"></i> Guardar y generar trigger
                        </button>

                        <?php if ($info_sel['activa'] && $info_sel['id_tabla'] !== null): ?>
                            <button type="submit" name="accion" value="desactivar" class="btn btn-outline-danger">
                                <i class="bx bx-power-off me-1"></i> Desactivar auditoría
                            </button>
                        <?php elseif ($info_sel['id_tabla'] !== null): ?>
                            <button type="submit" name="accion" value="activar" class="btn btn-outline-success">
                                <i class="bx bx-play-circle me-1"></i> Reactivar auditoría
                            </button>
                        <?php endif; ?>

                        <a href="consulta.php?esquema=<?= urlencode($esquema_sel) ?>&tabla=<?= urlencode($tabla_sel) ?>"
                           class="btn btn-outline-secondary">
                            <i class="bx bx-history me-1"></i> Ver historial
                        </a>
                    </div>
                </form>
            </div>
        </div>

        <!-- Panel lateral: estado de la auditoría -->
        <div class="col-lg-4 mb-4">
            <div class="card">
                <div class="card-body">
                    <h6 class="text-muted text-uppercase small mb-3">Estado</h6>
                    <ul class="list-unstyled mb-0">
                        <li class="d-flex justify-content-between mb-2">
                            <span>Columnas auditadas</span>
                            <span class="fw-semibold"><?= $columnas_auditadas ?> de <?= count($columnas) ?></span>
                        </li>
                        <li class="d-flex justify-content-between mb-2">
                            <span>Combinaciones activas</span>
                            <span class="fw-semibold"><?= (int) $info_sel['eventos_activos'] ?></span>
                        </li>
                        <li class="d-flex justify-content-between">
                            <span>Trigger</span>
                            <?php if ($info_sel['tiene_trigger']): ?>
                                <span class="aa-ident">trg_aud_<?= (int) $info_sel['id_tabla'] ?></span>
                            <?php else: ?>
                                <span class="text-muted">no existe</span>
                            <?php endif; ?>
                        </li>
                    </ul>
                </div>
            </div>
        </div>
    </div>

    <script>
    // "marcar todas": alterna todas las casillas de un evento
    document.querySelectorAll('.aa-marcar-col').forEach(function (enlace) {
        enlace.addEventListener('click', function () {
            var casillas = document.querySelectorAll('#form-config input[data-evento="' + enlace.dataset.evento + '"]');
            var marcar = Array.prototype.some.call(casillas, function (c) { return !c.checked; });
            casillas.forEach(function (c) { c.checked = marcar; });
        });
    });
    </script>

<?php
// ---------------------------------------------------------------------
// Vista: listado de tablas
// ---------------------------------------------------------------------
else:
    $n_auditadas = 0;
    foreach ($tablas as $t) {
        if ($t['tiene_trigger']) {
            $n_auditadas++;
        }
    }
?>
    <div class="card">
        <div class="card-header d-flex flex-wrap justify-content-between align-items-center gap-3">
            <div>
                <h5 class="card-title mb-1">Tablas de la base de datos</h5>
                <small class="text-muted">
                    Tomadas del diccionario de datos de <span class="aa-ident"><?= aa_esc(aa_config()['dbname']) ?></span>.
                    <?= $n_auditadas ?> de <?= count($tablas) ?> con auditoría activa.
                </small>
            </div>
            <div class="input-group input-group-merge" style="max-width: 260px">
                <span class="input-group-text"><i class="bx bx-search"></i></span>
                <input type="text" id="filtro-tablas" class="form-control" placeholder="Buscar tabla…">
            </div>
        </div>

        <div class="table-responsive text-nowrap">
            <table class="table table-hover mb-0" id="tabla-tablas">
                <thead>
                    <tr>
                        <th>Tabla</th>
                        <th>Esquema</th>
                        <th>Estado</th>
                        <th class="text-center">Combinaciones activas</th>
                        <th></th>
                    </tr>
                </thead>
                <tbody class="table-border-bottom-0">
                <?php if ($tablas === []): ?>
                    <tr><td colspan="5" class="text-center text-muted py-4">No hay tablas disponibles para auditar.</td></tr>
                <?php endif; ?>
                <?php foreach ($tablas as $t): ?>
                    <?php $url = 'configuracion.php?esquema=' . urlencode($t['esquema']) . '&tabla=' . urlencode($t['tabla']); ?>
                    <tr data-nombre="<?= aa_esc(strtolower($t['esquema'] . '.' . $t['tabla'])) ?>">
                        <td>
                            <i class="bx bx-table text-primary me-2"></i>
                            <a href="<?= aa_esc($url) ?>" class="fw-semibold"><?= aa_esc($t['tabla']) ?></a>
                        </td>
                        <td class="text-muted"><?= aa_esc($t['esquema']) ?></td>
                        <td>
                            <?php if ($t['tiene_trigger']): ?>
                                <span class="badge bg-label-success">Activa</span>
                            <?php elseif ($t['id_tabla'] !== null): ?>
                                <span class="badge bg-label-secondary">Desactivada</span>
                            <?php else: ?>
                                <span class="badge bg-label-secondary">Sin auditoría</span>
                            <?php endif; ?>
                        </td>
                        <td class="text-center"><?= (int) $t['eventos_activos'] ?></td>
                        <td class="text-end">
                            <a class="btn btn-sm btn-outline-primary" href="<?= aa_esc($url) ?>">
                                <i class="bx bx-slider-alt me-1"></i> Configurar
                            </a>
                        </td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>
    </div>

    <script>
    document.getElementById('filtro-tablas').addEventListener('input', function () {
        var q = this.value.trim().toLowerCase();
        document.querySelectorAll('#tabla-tablas tbody tr[data-nombre]').forEach(function (fila) {
            fila.style.display = fila.dataset.nombre.indexOf(q) === -1 ? 'none' : '';
        });
    });
    </script>
<?php endif;

aa_pie();
