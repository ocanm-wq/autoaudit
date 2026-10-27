"""Pruebas reales de consultas PHP, con datos desechables y sin paquetes externos."""
import argparse
import csv
import datetime as dt
import hashlib
from html import unescape
from http.cookiejar import CookieJar
import io
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.error import HTTPError
from urllib.parse import urlencode, urlparse
from urllib.request import build_opener, HTTPCookieProcessor, Request

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://127.0.0.1:18087')
    parser.add_argument('--container', default='autoaudit-ui-20261026')
    parser.add_argument('--database', default='autoaudit_test_http')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--confirmar-cluster-aislado', action='store_true', required=True)
    a = parser.parse_args()
    if urlparse(a.url).hostname not in ('127.0.0.1','localhost') or not re.fullmatch(r'autoaudit_test_[a-z0-9_]+', a.database):
        parser.error('Solo URL local y base autoaudit_test_<sufijo>')
    a.output.mkdir(parents=True, exist_ok=False)
    results = []
    prefix = ['wsl.exe','-d','Ubuntu-24.04','--exec'] if os.name == 'nt' else []
    sqlcmd = prefix + ['docker','exec','-i',a.container,'psql','-X','-h','/tmp','-U','postgres','-d',a.database,'-v','ON_ERROR_STOP=1','-A','-t']
    def sql(text):
        p = subprocess.run(sqlcmd,input=text,text=True,encoding='utf-8',capture_output=True,check=True)
        return p.stdout.strip()
    def check(name, condition, detail=''):
        results.append({'id':name,'estado':'PASS' if condition else 'FAIL','detalle':str(detail)[:300]})
    class Client:
        def __init__(self): self.opener=build_opener(HTTPCookieProcessor(CookieJar()))
        def request(self,path,data=None):
            request=Request(a.url+path,data=None if data is None else urlencode(data,doseq=True).encode())
            try: r=self.opener.open(request,timeout=15)
            except HTTPError as error: r=error
            return r.status,dict(r.headers),r.read(),r.geturl()
        def login(self,name,password):
            _,_,body,_=self.request('/login.php')
            match=re.search(rb'name="token" value="([^"]+)"',body)
            assert match, 'Token CSRF ausente'
            return self.request('/login.php',{'token':match.group(1).decode(),'usuario':name,'password':password})
    def bodytext(response): return response[2].decode('utf-8','replace')
    def consult(client,**params): return client.request('/consulta.php'+('?' + urlencode(params) if params else ''))
    def table_rows(response):
        match=re.search(r'<tbody>(.*?)</tbody>',bodytext(response),re.S)
        return [] if not match else [unescape(re.sub('<[^>]+>',' ',row)).strip() for row in re.findall(r'<tr>(.*?)</tr>',match.group(1),re.S)]
    def count(response,n): return f'{n} resultado(s)' in bodytext(response)
    def csv_rows(response): return list(csv.DictReader(io.StringIO(response[2].decode('utf-8-sig'))))
    keys=dict(re.findall(r"\('(demo_(?:maria|luis|ana))',\s*'([^']+)'\)",(ROOT/'sql/09_interfaz.sql').read_text(encoding='utf-8-sig')))
    fixture=False
    try:
        assert sql('SELECT current_database()') == a.database
        baseline=int(sql('SELECT count(*) FROM auditoria.v_historial'))
        anonymous=Client(); r=anonymous.request('/consulta.php')
        check('anonimo_login',r[0]==200 and r[3].endswith('/login.php'),'Redirección sin sesión')
        bad=Client(); r=bad.login('demo_maria','credencial-incorrecta-de-prueba')
        check('password_incorrecto',r[3].endswith('/login.php') and 'Verifique el usuario y la contraseña' in bodytext(r))
        ana=Client(); r=ana.login('demo_ana',keys['demo_ana'])
        check('ana_rechazo_rol',r[3].endswith('/login.php') and 'no tiene acceso al sistema de auditoría' in bodytext(r))
        maria=Client(); r=maria.login('demo_maria',keys['demo_maria'])
        check('maria_admin_autenticada',r[3].endswith('/index.php') and 'demo_maria' in bodytext(r) and 'Cerrar sesión' in bodytext(r))
        r=maria.request('/configuracion.php')
        check('maria_configura',r[0]==200 and 'Guardar' not in bodytext(r) and 'cliente' in bodytext(r))
        r=maria.request('/configuracion.php?esquema=public&tabla=cliente')
        link=re.search(r'href="(consulta\.php\?[^"]+)"',bodytext(r))
        linked=maria.request('/'+unescape(link.group(1))) if link else None
        expected=int(sql("SELECT count(*) FROM auditoria.v_historial WHERE esquema='public' AND tabla='cliente'"))
        check('enlace_ver_historial',linked is not None and linked[0]==200 and count(linked,expected),f'cliente={expected}')
        before=sql("SELECT md5(string_agg(row_to_json(c)::text,',' ORDER BY id_configuracion)) FROM auditoria.aud_configuracion c")
        r=maria.request('/configuracion.php',{'token':'invalido','accion':'desactivar','esquema':'public','tabla':'cliente'})
        after=sql("SELECT md5(string_agg(row_to_json(c)::text,',' ORDER BY id_configuracion)) FROM auditoria.aud_configuracion c")
        check('csrf_config_sin_mutacion','La sesión expiró' in bodytext(r) and before==after)
        luis=Client(); r=luis.login('demo_luis',keys['demo_luis'])
        check('luis_autenticado',r[3].endswith('/index.php') and 'demo_luis' in bodytext(r))
        r=luis.request('/configuracion.php')
        check('luis_403_configuracion',r[0]==403 and 'Acceso denegado' in bodytext(r))
        r=consult(luis)
        check('historial_inicial',r[0]==200 and count(r,baseline) and len(table_rows(r))==baseline,f'baseline={baseline}')
        producto=json.dumps(['public','producto'],separators=(',',':'))
        cliente=json.dumps(['public','cliente'],separators=(',',':'))
        r=consult(luis,usuario='demo_luis')
        check('filtro_usuario',count(r,6) and len(table_rows(r))==6 and all('demo_luis' in x for x in table_rows(r)))
        r=consult(luis,tabla=producto,columna='precio')
        check('filtro_columna',count(r,6) and len(table_rows(r))==6 and all('precio' in x for x in table_rows(r)))
        r=consult(luis,usuario='demo_luis',tabla=producto,columna='precio',evento='UPDATE')
        check('filtros_combinados',count(r,1) and len(table_rows(r))==1 and '150.00' in table_rows(r)[0] and '135.00' in table_rows(r)[0])
        r=consult(luis,tabla=cliente,id_registro='3')
        check('registro_eliminado',count(r,4) and sum('DELETE' in x for x in table_rows(r))==2)
        r=consult(luis,id_registro="' OR 1=1 --")
        check('inyeccion_filtro_no_amplia',r[0]==200 and count(r,0) and 'No hay resultados' in bodytext(r))
        r=consult(luis,tabla=producto,columna='correo')
        check('columna_ajena_rechazada','La columna no pertenece a la tabla' in bodytext(r))
        r=consult(luis,tabla=json.dumps({'a':'public','b':'cliente'}))
        check('json_objeto_rechazado','La tabla seleccionada no es válida' in bodytext(r) and 'Warning' not in bodytext(r))
        r=consult(luis,evento='TRUNCATE')
        check('evento_rechazado','El evento seleccionado no es válido' in bodytext(r))
        r=consult(luis,desde='2026-02-31T12:00')
        check('fecha_inexistente','La fecha inicial no es válida' in bodytext(r))
        r=consult(luis,desde='2026-10-27T00:00',hasta='2026-10-26T00:00')
        check('rango_invertido','La fecha final debe ser posterior' in bodytext(r))
        start,end=sql("SELECT to_char(min(fecha_hora) AT TIME ZONE 'America/Guatemala' - interval '1 minute','YYYY-MM-DD\"T\"HH24:MI')||'|'||to_char(max(fecha_hora) AT TIME ZONE 'America/Guatemala' + interval '1 minute','YYYY-MM-DD\"T\"HH24:MI') FROM auditoria.v_historial").split('|')
        r=consult(luis,desde=start,hasta=end)
        check('rango_local_valido',count(r,baseline))
        r=consult(luis,desde=start,hasta=start)
        check('rango_vacio_rechazado','La fecha final debe ser posterior' in bodytext(r))
        bad_arrays=[]
        for key in ['usuario','tabla','columna','desde','pagina','por_pagina','csv']:
            r=luis.request('/consulta.php?'+urlencode({key+'[]':'x'}))
            bad_arrays.append(r[0] in (200,400) and 'no puede ser múltiple' in bodytext(r) and 'Fatal error' not in bodytext(r))
        check('arrays_get_rechazados',all(bad_arrays),str(bad_arrays))
        r=consult(luis,csv=1,desde='2026-02-31T12:00')
        check('csv_invalido_400',r[0]==400 and 'text/plain' in r[1].get('Content-Type','') and 'fecha inicial' in bodytext(r))
        sql("""BEGIN;
          DO $$ BEGIN IF to_regclass('public.aa_http_casos') IS NOT NULL THEN RAISE EXCEPTION 'Fixture preexistente'; END IF; END $$;
          CREATE TABLE public.aa_http_casos(id integer PRIMARY KEY,valor text);
          GRANT SELECT,INSERT ON public.aa_http_casos TO demo_app;
          INSERT INTO auditoria.aud_tabla(esquema,nombre_tabla) VALUES('public','aa_http_casos');
          INSERT INTO auditoria.aud_columna(id_tabla,nombre_columna) SELECT id_tabla,'valor' FROM auditoria.aud_tabla WHERE nombre_tabla='aa_http_casos';
          INSERT INTO auditoria.aud_configuracion(id_columna,id_evento) SELECT id_columna,1 FROM auditoria.aud_columna c JOIN auditoria.aud_tabla t USING(id_tabla) WHERE t.nombre_tabla='aa_http_casos';
          SELECT auditoria.generar_trigger(id_tabla) FROM auditoria.aud_tabla WHERE nombre_tabla='aa_http_casos';
          SET SESSION AUTHORIZATION demo_maria;
          SET application_name='AutoAudit-HTTP-Test';
          INSERT INTO public.aa_http_casos SELECT g,'Fila '||g FROM generate_series(1,60) g;
          INSERT INTO public.aa_http_casos VALUES(61,'=2+3'),(62,E' \\t@SUM(1,2)'),(63,'<script id="aa-http-xss">alert(1)</script>'),(64,'-2+3'),(65,'+1+1'),(66,E'\\t=SUM(1,2)'),(67,''),(68,NULL);
          RESET SESSION AUTHORIZATION;
          COMMIT;""")
        fixture=True
        table=json.dumps(['public','aa_http_casos'],separators=(',',':'))
        r=consult(luis,tabla=table,por_pagina=25)
        check('pagina_25',count(r,68) and len(table_rows(r))==25 and 'Página 1 de 3' in bodytext(r))
        check('enlace_siguiente',bool(re.search(r'class="page-link" href="[^"]*pagina=2[^\"]*">Siguiente',bodytext(r))))
        r=consult(luis,tabla=table,por_pagina=25,pagina=2)
        check('pagina_2',len(table_rows(r))==25 and 'Página 2 de 3' in bodytext(r))
        r=consult(luis,tabla=table,por_pagina=50)
        check('pagina_50',len(table_rows(r))==50 and 'Página 1 de 2' in bodytext(r))
        r=consult(luis,tabla=table,por_pagina=100)
        check('pagina_100',len(table_rows(r))==68)
        check('xss_escapado','&lt;script id=' in bodytext(r) and '<script id="aa-http-xss">' not in bodytext(r))
        r=consult(luis,tabla=table,por_pagina=25,pagina='9'*70)
        check('pagina_enorme_ajustada',r[0]==200 and len(table_rows(r))==18 and 'Página 3 de 3' in bodytext(r))
        r=consult(luis,tabla=table,por_pagina=25,csv=1)
        rows=csv_rows(r)
        check('csv_todas_las_paginas',r[0]==200 and len(rows)==68 and 'text/csv' in r[1].get('Content-Type',''))
        check('csv_origen_campos',{'ip_origen','nombre_host'} <= set(rows[0]))
        data={x['id_registro']:x['valor_nuevo'] for x in rows}
        check('csv_formulas_neutralizadas',all(data[str(i)].startswith("'") for i in [61,62,64,65,66]))
        check('csv_null_y_vacio',data['67']=='' and data['68']=='\\N')
        check('csv_sin_html',b'<!DOCTYPE' not in r[2] and r[2].startswith(b'\xef\xbb\xbf'))
        (a.output/'exportacion_fixture.csv').write_bytes(r[2])
        r=luis.request('/logout.php');r=consult(luis)
        check('logout_cierra_acceso',r[3].endswith('/login.php'))
    except Exception as error:
        check('ejecucion_completa',False,type(error).__name__+': '+str(error))
    finally:
        if fixture:
            try:
                sql("""BEGIN;
                ALTER TABLE auditoria.aud_bitacora DISABLE TRIGGER trg_bitacora_inmutable;
                DELETE FROM auditoria.aud_bitacora WHERE id_configuracion IN(SELECT cf.id_configuracion FROM auditoria.aud_configuracion cf JOIN auditoria.aud_columna c USING(id_columna) JOIN auditoria.aud_tabla t USING(id_tabla) WHERE t.nombre_tabla='aa_http_casos' AND t.esquema='public');
                ALTER TABLE auditoria.aud_bitacora ENABLE TRIGGER trg_bitacora_inmutable;
                SELECT auditoria.eliminar_trigger(id_tabla) FROM auditoria.aud_tabla WHERE nombre_tabla='aa_http_casos' AND esquema='public';
                DELETE FROM auditoria.aud_configuracion WHERE id_columna IN(SELECT c.id_columna FROM auditoria.aud_columna c JOIN auditoria.aud_tabla t USING(id_tabla) WHERE t.nombre_tabla='aa_http_casos' AND t.esquema='public');
                DELETE FROM auditoria.aud_columna WHERE id_tabla IN(SELECT id_tabla FROM auditoria.aud_tabla WHERE nombre_tabla='aa_http_casos' AND esquema='public');
                DELETE FROM auditoria.aud_tabla WHERE nombre_tabla='aa_http_casos' AND esquema='public';
                DROP TABLE public.aa_http_casos;
                DELETE FROM auditoria.aud_estacion e WHERE nombre_host='AutoAudit-HTTP-Test' AND NOT EXISTS(SELECT FROM auditoria.aud_bitacora b WHERE b.id_estacion=e.id_estacion);
                COMMIT;""")
                check('limpieza_fixture',int(sql('SELECT count(*) FROM auditoria.v_historial'))==baseline and sql("SELECT to_regclass('public.aa_http_casos') IS NULL")=='t')
            except Exception as error: check('limpieza_fixture',False,str(error))
        summary={x:sum(c['estado']==x for c in results) for x in ('PASS','FAIL','BLOCKED')}
        (a.output/'resultados.json').write_text(json.dumps({'fecha_utc':dt.datetime.now(dt.timezone.utc).isoformat(),'url':a.url,'database':a.database,'resumen':summary,'casos':results,'fuente_sha256':hashlib.sha256((ROOT/'app/consulta.php').read_bytes()).hexdigest()},indent=2,ensure_ascii=False),encoding='utf-8')
        print(json.dumps(summary))
    return int(bool(summary['FAIL']))

if __name__=='__main__': raise SystemExit(main())
