<?php
require_once __DIR__ . '/lib/layout.php';

/** Consulta del historial: todos los valores externos se validan antes de usarse. */
aa_exigir_sesion();
$errores = [];
try { $pdo = aa_pdo(); } catch (Throwable $e) { $pdo = null; $errores[] = 'No se pudo conectar con la base de datos.'; }

$scalar = static function (string $key, array &$errors): string {
    if (!array_key_exists($key, $_GET)) return '';
    if (is_array($_GET[$key])) { $errors[] = "El parámetro $key no puede ser múltiple."; return ''; }
    return trim((string) $_GET[$key]);
};
$usuario = $scalar('usuario', $errores); $columna = $scalar('columna', $errores);
$idRegistro = $scalar('id_registro', $errores); $evento = strtoupper($scalar('evento', $errores));
$desde = $scalar('desde', $errores); $hasta = $scalar('hasta', $errores);
$tablaClave = $scalar('tabla', $errores); $paginaRaw = $scalar('pagina', $errores); $porRaw = $scalar('por_pagina', $errores);
$csvRaw = $scalar('csv', $errores);
$csv = array_key_exists('csv', $_GET);
$eventos = ['INSERT', 'UPDATE', 'DELETE'];
$tablas = $columnas = $usuarios = [];

$pagina = ctype_digit($paginaRaw) && (int)$paginaRaw > 0 ? (int)$paginaRaw : 1;
$porPagina = in_array((int)$porRaw, [25, 50, 100], true) ? (int)$porRaw : 50;
if ($evento !== '' && !in_array($evento, $eventos, true)) $errores[] = 'El evento seleccionado no es válido.';

$esquema = $tabla = '';
if ($pdo) {
    try {
        $tablas = $pdo->query('SELECT * FROM auditoria.listar_tablas()')->fetchAll();
        $usuarios = $pdo->query('SELECT * FROM auditoria.listar_usuarios()')->fetchAll();
        if ($tablaClave !== '') {
            $decoded = json_decode($tablaClave, true);
            if (!is_array($decoded) || !array_is_list($decoded) || count($decoded) !== 2 || !is_string($decoded[0]) || !is_string($decoded[1]) || $decoded[0] === '' || $decoded[1] === '') {
                $errores[] = 'La tabla seleccionada no es válida.';
            } else { [$esquema, $tabla] = $decoded; }
        }
        if ($esquema !== '' && $tabla !== '') {
            $found = false; foreach ($tablas as $item) if ($item['esquema'] === $esquema && $item['tabla'] === $tabla) $found = true;
            if (!$found) { $errores[] = 'La tabla seleccionada no está disponible.'; $esquema = $tabla = ''; }
            else { $stmt = $pdo->prepare('SELECT * FROM auditoria.listar_columnas(?, ?)'); $stmt->execute([$esquema, $tabla]); $columnas = $stmt->fetchAll(); }
        }
        if ($columna !== '' && !array_filter($columnas, static fn($c) => $c['columna'] === $columna)) { $errores[] = 'La columna no pertenece a la tabla.'; $columna = ''; }
    } catch (Throwable $e) { $errores[] = 'No se pudieron cargar los filtros del diccionario.'; }
}

$parseDate = static function (string $value, string $label, array &$errors): ?string {
    if ($value === '') return null;
    $zone = new DateTimeZone('America/Guatemala');
    $date = DateTimeImmutable::createFromFormat('!Y-m-d\\TH:i', $value, $zone);
    $details = DateTimeImmutable::getLastErrors();
    if (!$date || ($details !== false && ($details['warning_count'] || $details['error_count'])) || $date->format('Y-m-d\\TH:i') !== $value) {
        $errors[] = "La fecha $label no es válida."; return null;
    }
    return $date->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d H:i:sP');
};
$desdeSql = $parseDate($desde, 'inicial', $errores); $hastaSql = $parseDate($hasta, 'final', $errores);
if ($desdeSql && $hastaSql && $desdeSql >= $hastaSql) $errores[] = 'La fecha final debe ser posterior a la inicial (el final es exclusivo).';

$where = []; $params = [];
foreach ([['h.usuario', $usuario], ['h.esquema', $esquema], ['h.tabla', $tabla], ['h.columna', $columna], ['h.id_registro', $idRegistro], ['h.evento', $evento]] as [$field, $value]) {
    if ($value !== '') { $where[] = "$field = ?"; $params[] = $value; }
}
if ($desdeSql) { $where[] = 'h.fecha_hora >= ?::timestamptz'; $params[] = $desdeSql; }
if ($hastaSql) { $where[] = 'h.fecha_hora < ?::timestamptz'; $params[] = $hastaSql; }
$base = ' FROM auditoria.v_historial h' . ($where ? ' WHERE ' . implode(' AND ', $where) : '');
$total = 0; $filas = [];
if ($pdo && !$errores) {
    try {
        $stmt = $pdo->prepare('SELECT count(*)' . $base); $stmt->execute($params); $total = (int)$stmt->fetchColumn();
        $pages = max(1, (int)ceil($total / $porPagina)); $pagina = min($pagina, $pages);
        if ($csv) {
            $stmt = $pdo->prepare('SELECT id_bitacora,fecha_hora,usuario,ip_origen,nombre_host,esquema,tabla,columna,evento,id_registro,valor_anterior,valor_nuevo' . $base . ' ORDER BY h.fecha_hora DESC,h.id_bitacora DESC');
            $stmt->execute($params);
            header('Content-Type: text/csv; charset=UTF-8'); header('Content-Disposition: attachment; filename="autoaudit-historial.csv"');
            session_write_close();
            $out = fopen('php://output', 'w'); fwrite($out, "\xEF\xBB\xBF");
            fputcsv($out, ['id_bitacora','fecha_hora','usuario','ip_origen','nombre_host','esquema','tabla','columna','evento','id_registro','valor_anterior','valor_nuevo']);
            while ($row = $stmt->fetch()) {
                foreach ($row as &$value) { if ($value === null) $value = '\\N'; elseif (is_string($value) && preg_match('/^\\s*[=+\\-@]/', $value)) $value = "'" . $value; } unset($value); fputcsv($out, $row);
            }
            fclose($out); exit;
        }
        $stmt = $pdo->prepare('SELECT *' . $base . ' ORDER BY h.fecha_hora DESC,h.id_bitacora DESC LIMIT ? OFFSET ?'); $stmt->execute(array_merge($params, [$porPagina, ($pagina - 1) * $porPagina])); $filas = $stmt->fetchAll();
    } catch (Throwable $e) { $errores[] = 'No se pudo consultar el historial: ' . aa_mensaje_error($e); }
}
if ($csv && $errores) { http_response_code(400); header('Content-Type: text/plain; charset=UTF-8'); echo implode("\n", $errores); exit; }

if (!$csv) {
    aa_encabezado('Historial de cambios', 'Auditoría'); foreach ($errores as $error) aa_aviso('error', $error);
    $query = $_GET; unset($query['csv']); $tableJson = static fn($s, $t) => json_encode([$s, $t], JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT);
    ?>
    <div class="card mb-4"><div class="card-body"><form method="get" class="row g-3">
      <div class="col-md-3"><label for="f-usuario" class="form-label">Usuario</label><select id="f-usuario" name="usuario" class="form-select"><option value="">Todos</option><?php foreach($usuarios as $u): ?><option value="<?=aa_esc($u['nombre_usuario'])?>" <?=$usuario===$u['nombre_usuario']?'selected':''?>><?=aa_esc($u['nombre_usuario'])?></option><?php endforeach;?></select></div>
      <div class="col-md-3"><label for="f-tabla" class="form-label">Tabla</label><select id="f-tabla" name="tabla" class="form-select" onchange="this.form.columna.value='';this.form.submit()"><option value="">Todas</option><?php foreach($tablas as $t): $key=$tableJson($t['esquema'],$t['tabla']); ?><option value="<?=aa_esc($key)?>" <?=$esquema===$t['esquema']&&$tabla===$t['tabla']?'selected':''?>><?=aa_esc($t['esquema'].'.'.$t['tabla'])?></option><?php endforeach;?></select></div>
      <div class="col-md-3"><label for="f-columna" class="form-label">Columna</label><select id="f-columna" name="columna" class="form-select"><option value="">Todas</option><?php foreach($columnas as $c): ?><option <?=$columna===$c['columna']?'selected':''?>><?=aa_esc($c['columna'])?></option><?php endforeach;?></select></div>
      <div class="col-md-3"><label for="f-evento" class="form-label">Evento</label><select id="f-evento" name="evento" class="form-select"><option value="">Todos</option><?php foreach($eventos as $ev): ?><option <?=$evento===$ev?'selected':''?>><?=$ev?></option><?php endforeach;?></select></div>
      <div class="col-md-3"><label for="f-id" class="form-label">Id de registro</label><input id="f-id" name="id_registro" class="form-control" value="<?=aa_esc($idRegistro)?>"></div>
      <div class="col-md-3"><label for="f-desde" class="form-label">Desde (Guatemala)</label><input id="f-desde" type="datetime-local" name="desde" class="form-control" value="<?=aa_esc($desde)?>"></div>
      <div class="col-md-3"><label for="f-hasta" class="form-label">Hasta exclusivo (Guatemala)</label><input id="f-hasta" type="datetime-local" name="hasta" class="form-control" value="<?=aa_esc($hasta)?>"></div>
      <div class="col-md-3"><label for="f-por" class="form-label">Por página</label><select id="f-por" name="por_pagina" class="form-select"><option <?=$porPagina===25?'selected':''?>>25</option><option <?=$porPagina===50?'selected':''?>>50</option><option <?=$porPagina===100?'selected':''?>>100</option></select></div>
      <div class="col-12"><button class="btn btn-primary me-2">Consultar</button><a class="btn btn-outline-secondary me-2" href="consulta.php">Limpiar filtros</a><?php $csvQuery=$query;$csvQuery['csv']=1; ?><a class="btn btn-outline-success" href="?<?=http_build_query($csvQuery)?>">CSV completo</a><span class="text-muted ms-3">Zona horaria: America/Guatemala · <?=$total?> resultado(s) · Página <?=$pagina?> de <?=$pages??1?></span></div>
    </form></div></div>
    <?php if (($pages??1)>1): ?><nav aria-label="Paginación"><ul class="pagination"><li class="page-item <?=$pagina<=1?'disabled':''?>"><?php $q=$query;$q['pagina']=max(1,$pagina-1); ?><a class="page-link" href="?<?=http_build_query($q)?>">Anterior</a></li><li class="page-item <?=$pagina>=($pages??1)?'disabled':''?>"><?php $q['pagina']=min($pages,$pagina+1); ?><a class="page-link" href="?<?=http_build_query($q)?>">Siguiente</a></li></ul></nav><?php endif; ?>
    <div class="card"><div class="table-responsive"><table class="table table-hover"><thead><tr><th>Fecha</th><th>Usuario</th><th>Tabla</th><th>Columna</th><th>Evento</th><th>Registro</th><th>Anterior</th><th>Nuevo</th></tr></thead><tbody><?php foreach($filas as $row): ?><tr><td><?=aa_esc($row['fecha_hora'])?></td><td><?=aa_esc($row['usuario'])?></td><td><?=aa_esc($row['esquema'].'.'.$row['tabla'])?></td><td><?=aa_esc($row['columna'])?></td><td><?=aa_insignia_evento($row['evento'])?></td><td><?=aa_valor($row['id_registro'])?></td><td><?=aa_valor($row['valor_anterior'])?></td><td><?=aa_valor($row['valor_nuevo'])?></td></tr><?php endforeach;?><?php if(!$filas):?><tr><td colspan="8" class="text-center text-muted py-4">No hay resultados para los filtros indicados.</td></tr><?php endif;?></tbody></table></div></div><?php aa_pie();
}
