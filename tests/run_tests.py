"""Ejecutor sin dependencias externas. Nunca llama a Git ni modifica sql/01..07."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TABLES = ['aud_evento', 'aud_tabla', 'aud_columna', 'aud_configuracion',
          'aud_usuario', 'aud_estacion', 'aud_bitacora']


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--database', default='autoaudit_test')
    p.add_argument('--docker-container', help='Contenedor dedicado; usa docker exec, sin puertos')
    p.add_argument('--psql', default='psql', help='Ruta del ejecutable psql, si no se usa Docker')
    p.add_argument('--confirmar-cluster-aislado', action='store_true', required=True)
    p.add_argument('--incluir-100000', action='store_true', help='Carga costosa, opt-in')
    p.add_argument('--output', type=Path, help='Directorio NUEVO para evidencia')
    a = p.parse_args()
    if not re.fullmatch(r'autoaudit_test(?:_[a-z0-9]+)?', a.database):
        p.error('Nombre permitido: autoaudit_test o autoaudit_test_<sufijo>')
    out = a.output or ROOT / 'tests' / 'resultados' / dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    out.mkdir(parents=True, exist_ok=False)
    command = (['docker', 'exec', '-i', a.docker_container, 'psql', '-U', 'postgres']
               if a.docker_container else [a.psql])
    command += ['-X', '-v', 'ON_ERROR_STOP=1', '-A', '-t', '-d', a.database]
    results = []
    benches = []
    sources = {str(f.relative_to(ROOT)): hashlib.sha256(f.read_bytes()).hexdigest()
               for f in sorted((ROOT / 'sql').glob('*.sql'))}
    context = {'fecha_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
               'sistema_ejecutor': platform.platform(), 'cpu_ejecutor': os.cpu_count(),
               'database': a.database, 'docker_container': a.docker_container,
               'usa_fuentes_locales_sin_transformar': True,
               'incluir_100000': a.incluir_100000, 'sha256_sql': sources}

    def sql(label, text, report=True):
        proc = subprocess.run(command, input=text, text=True, encoding='utf-8',
                              errors='replace', capture_output=True, timeout=1800)
        log = proc.stdout + '\n' + proc.stderr
        (out / (label + '.log')).write_text(log, encoding='utf-8')
        if report:
            results.append({'suite': 'instalacion', 'id': label,
                            'estado': 'PASS' if proc.returncode == 0 else 'FAIL',
                            'detalle': 'Ver ' + label + '.log'})
        return proc.returncode, log

    def snapshot():
        query = 'SELECT json_build_object(' + ','.join(
            "'%s',(SELECT count(*) FROM auditoria.%s)" % (t, t) for t in TABLES) + ')::text;'
        code, log = sql('snapshot_' + str(len(list(out.glob('snapshot_*.log')))), query, False)
        if code:
            raise RuntimeError('No se pudo obtener snapshot; revisar evidencia')
        return json.loads(next(line for line in log.splitlines() if line.startswith('{')))

    def install(label, source):
        return sql(label, 'BEGIN;\n' + source + '\nCOMMIT;\n')

    try:
        if a.docker_container:
            cfg = json.loads(subprocess.check_output(
                ['docker', 'inspect', '--format', '{{json .HostConfig}}', a.docker_container], text=True))
            if cfg.get('NetworkMode') != 'none':
                raise RuntimeError('El contenedor de prueba debe usar --network none')
            context['contenedor'] = {k: cfg.get(k) for k in ('NetworkMode', 'Memory', 'NanoCpus', 'Tmpfs')}
            context['imagen'] = subprocess.check_output(
                ['docker', 'inspect', '--format', '{{.Config.Image}} {{.Image}}', a.docker_container], text=True).strip()
            context['os_servidor'] = subprocess.check_output(
                ['docker', 'exec', a.docker_container, 'cat', '/etc/os-release'], text=True).strip()
            context['cliente_psql'] = subprocess.check_output(
                ['docker', 'exec', a.docker_container, 'psql', '--version'], text=True).strip()
            packages = subprocess.run(['docker', 'exec', a.docker_container, 'dpkg-query', '-W',
                                      'postgresql-18', 'postgresql-client-18'], text=True, capture_output=True)
            if packages.returncode == 0:
                context['paquetes_servidor'] = packages.stdout.strip().splitlines()
        code, log = sql('00_entorno', "SELECT json_build_object('version',version(),'database',current_database(),"
            "'usuario',current_user,'timezone',current_setting('TimeZone'),"
            "'shared_buffers',current_setting('shared_buffers'),'jit',current_setting('jit'),"
            "'synchronous_commit',current_setting('synchronous_commit'),"
            "'max_connections',current_setting('max_connections'))::text;\n"
            "DO $$ BEGIN IF to_regnamespace('auditoria') IS NOT NULL THEN "
            "RAISE EXCEPTION 'Se exige una base nueva: auditoria ya existe'; END IF; END $$;")
        if code:
            raise RuntimeError('Precondición fallida: no se instalará sobre una base existente')
        context['servidor'] = json.loads(next(line for line in log.splitlines() if line.startswith('{')))
        src = {n: (ROOT / 'sql' / n).read_text(encoding='utf-8-sig') for n in
               ['01_estructura_autoaudit.sql', '03_generador_triggers.sql', '05_consultas_historial.sql',
                '06_seguridad.sql', '07_pruebas_rendimiento.sql']}
        if install('01_estructura', src['01_estructura_autoaudit.sql'])[0]:
            raise RuntimeError('No se pudo instalar la estructura')
        if src['03_generador_triggers.sql'].strip():
            install('03_generador', src['03_generador_triggers.sql'])
        else:
            results.append({'suite': 'instalacion', 'id': '03_generador', 'estado': 'BLOCKED',
                            'detalle': 'Archivo vacío; no se implementa ni simula'})
        if install('05_historial', src['05_consultas_historial.sql'])[0]:
            raise RuntimeError('Falló 05: no se sustituyen ni corrigen fuentes durante las pruebas')
        if install('06_seguridad', src['06_seguridad.sql'])[0]:
            raise RuntimeError('Falló 06: revisar el error real, sin omitir sentencias')
        performance = re.search(r'CREATE OR REPLACE FUNCTION auditoria\.medir_rendimiento\(p_filas INT\).*?\$fn\$;',
                                src['07_pruebas_rendimiento.sql'], re.S)
        if not performance:
            raise RuntimeError('07 cambió: revisar delimitador de definición')
        # Jamás ejecutar las llamadas de ejemplo, especialmente la de 100000.
        performance_setup = performance.group() + '\nREVOKE ALL ON FUNCTION auditoria.medir_rendimiento(INT) FROM PUBLIC;'
        (out / '07_solo_definicion.sql').write_text(performance_setup, encoding='utf-8')
        install('07_solo_definicion', performance_setup)
        context['snapshot_antes_suites'] = snapshot()
        common = (ROOT / 'tests' / '00_comun.sql').read_text(encoding='utf-8')
        for filename in ['10_funcionales.sql', '20_seguridad.sql', 'performance/30_rendimiento.sql']:
            label = Path(filename).stem
            setting = "SET autoaudit_test.incluir_100000 = '%s';\n" % ('on' if a.incluir_100000 else 'off')
            code, log = sql(label, setting + common + '\n' + (ROOT / 'tests' / filename).read_text(encoding='utf-8'), False)
            matches = re.findall(r'AA_RESULT\|([^|\n]+)\|(PASS|FAIL|BLOCKED)\|([^\n]*)', log)
            for case, state, detail in matches:
                results.append({'suite': label, 'id': case, 'estado': state, 'detalle': detail.strip()})
            if code or not matches:
                results.append({'suite': label, 'id': 'ejecucion_completa', 'estado': 'FAIL',
                                'detalle': 'Error SQL o sin resultados: ver ' + label + '.log'})
            benches.extend(line.strip() for line in log.splitlines() if 'AA_BENCH' in line)
        context['snapshot_despues_suites'] = snapshot()
        results.append({'suite': 'limpieza', 'id': 'conteos_siete_tablas',
                        'estado': 'PASS' if context['snapshot_antes_suites'] == context['snapshot_despues_suites'] else 'FAIL',
                        'detalle': 'Comparación por tabla; secuencias pueden avanzar'})
        code, log = sql('99_limpieza', "SELECT json_build_object('objetos_fuente',(SELECT count(*) FROM pg_class c "
            "JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND "
            "(c.relname LIKE 'aa_%' OR c.relname IN ('t_rend_sin','t_rend_con'))),"
            "'funciones_fixture',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace "
            "WHERE n.nspname='auditoria' AND p.proname LIKE 'aa_%'),"
            "'roles_fixture',(SELECT count(*) FROM pg_roles WHERE rolname IN ('aa_public_probe','aa_actor')))::text;", False)
        clean = json.loads(next((line for line in log.splitlines() if line.startswith('{')), '{}'))
        context['limpieza'] = clean
        results.append({'suite': 'limpieza', 'id': 'objetos_fuente',
                        'estado': 'PASS' if code == 0 and clean and all(v == 0 for v in clean.values()) else 'FAIL',
                        'detalle': 'Sin tablas/índices/secuencias, funciones o roles de fixtures'})
    except (RuntimeError, subprocess.SubprocessError, OSError, ValueError) as exc:
        results.append({'suite': 'ejecutor', 'id': 'error', 'estado': 'FAIL', 'detalle': str(exc)})
    finally:
        context['sha256_sql_despues'] = {str(f.relative_to(ROOT)): hashlib.sha256(f.read_bytes()).hexdigest()
                                        for f in sorted((ROOT / 'sql').glob('*.sql'))}
        results.append({'suite': 'integridad', 'id': 'originales_sql_intactos',
                        'estado': 'PASS' if sources == context['sha256_sql_despues'] else 'FAIL',
                        'detalle': 'SHA256 antes/después de todos los originales SQL'})
        summary = {state: sum(r['estado'] == state for r in results) for state in ('PASS', 'FAIL', 'BLOCKED')}
        (out / 'resultados.json').write_text(json.dumps({'resumen': summary, 'contexto': context,
                'casos': results, 'benchmark': benches}, ensure_ascii=False, indent=2), encoding='utf-8')
        print(json.dumps({'directorio': str(out), **summary}, ensure_ascii=False))
    return 1 if summary['FAIL'] else 2 if summary['BLOCKED'] else 0


if __name__ == '__main__':
    sys.exit(main())
