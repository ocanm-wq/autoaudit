-- AutoAudit - 30: wrapper reproducible para medir rendimiento.
-- Requiere cargar el harness común (tests/00_comun.sql) antes de este archivo.
-- La función de medición se instala desde sql/07_pruebas_rendimiento.sql.
BEGIN;
SELECT pg_temp.aa_guard();

DO $guard$
BEGIN
  IF current_database() !~ '^autoaudit_test(_[a-z0-9]+)?$' THEN
    RAISE EXCEPTION 'base de pruebas no permitida: %', current_database();
  END IF;
END $guard$;

CREATE TEMP TABLE aa_bench (
  rep integer, volumen integer, operacion text, ms_sin numeric, ms_con numeric,
  pct numeric, eventos bigint
) ON COMMIT DROP;

DO $suite$
DECLARE
  v integer;
  r integer;
  x record;
  incluir boolean := coalesce(current_setting('autoaudit_test.incluir_100000', true), '') = 'on';
  existe boolean;
  nombres text[] := ARRAY['aud_tabla','aud_columna','aud_configuracion','aud_usuario','aud_estacion','aud_bitacora','aud_evento'];
  volumenes integer[];
  n integer;
  snap bigint[];
  snap_after bigint[];
  rows_seen integer;
  distinct_ops integer;
  tabla text;
BEGIN
  IF to_regprocedure('auditoria.medir_rendimiento(integer)') IS NULL THEN
    PERFORM pg_temp.aa_skip('rendimiento_100_1000_10000','falta auditoria.medir_rendimiento(integer)');
    RETURN;
  END IF;
  FOREACH n IN ARRAY ARRAY[0,-1] LOOP
    BEGIN PERFORM auditoria.medir_rendimiento(n); PERFORM pg_temp.aa_check(format('rendimiento_rechaza_%s',n),false,'debía rechazar');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN PERFORM pg_temp.aa_check(format('rendimiento_rechaza_%s',n),true,'P0001 esperado');
      WHEN OTHERS THEN PERFORM pg_temp.aa_check(format('rendimiento_rechaza_%s',n),false,SQLSTATE||' '||SQLERRM); END;
  END LOOP;
  PERFORM pg_temp.aa_error('rendimiento_rechaza_null','SELECT auditoria.medir_rendimiento(NULL)',ARRAY['P0001']);
  volumenes := CASE WHEN incluir THEN ARRAY[100,1000,10000,100000] ELSE ARRAY[100,1000,10000] END;
  IF to_regprocedure('auditoria.generar_trigger(integer)') IS NULL THEN
    FOREACH v IN ARRAY ARRAY[100,1000,10000] LOOP
      PERFORM pg_temp.aa_skip(format('rendimiento_%s',v),'BLOCKED: falta auditoria.generar_trigger(integer)');
    END LOOP;
    IF incluir THEN PERFORM pg_temp.aa_skip('rendimiento_100000','BLOCKED: falta auditoria.generar_trigger(integer)'); END IF;
    RETURN;
  END IF;

  FOREACH v IN ARRAY volumenes LOOP
    FOR r IN 1..3 LOOP
      BEGIN
        SELECT count(*) INTO n FROM pg_class WHERE relname IN ('t_rend_sin','t_rend_con') AND relnamespace = 'public'::regnamespace;
        IF n <> 0 THEN
          PERFORM pg_temp.aa_skip(format('rendimiento_%s_%s',v,r),'BLOCKED: tablas de trabajo preexistentes');
          CONTINUE;
        END IF;
        snap := ARRAY[]::bigint[];
        FOREACH tabla IN ARRAY nombres LOOP
          EXECUTE format('SELECT count(*) FROM auditoria.%I', tabla) INTO n;
          snap := snap || n;
        END LOOP;
        IF v = 100 AND r = 1 THEN
          PERFORM auditoria.medir_rendimiento(v); -- calentamiento descartado
          snap_after := ARRAY[]::bigint[];
          FOREACH tabla IN ARRAY nombres LOOP
            EXECUTE format('SELECT count(*) FROM auditoria.%I', tabla) INTO n;
            snap_after := snap_after || n;
          END LOOP;
          IF snap_after IS DISTINCT FROM snap OR to_regclass('public.t_rend_con') IS NOT NULL
             OR to_regclass('public.t_rend_sin') IS NOT NULL THEN
            RAISE EXCEPTION 'El calentamiento dejó residuos';
          END IF;
        END IF;
        rows_seen := 0;
        FOR x IN SELECT * FROM auditoria.medir_rendimiento(v) LOOP
          rows_seen := rows_seen + 1;
          INSERT INTO aa_bench VALUES (r,v,x.operacion,x.ms_sin_auditoria,x.ms_con_auditoria,
            round((x.ms_con_auditoria-x.ms_sin_auditoria)/NULLIF(x.ms_sin_auditoria,0)*100,1),x.registros_bitacora);
          RAISE NOTICE 'AA_BENCH_RAW|%|%|%|%|%|%|%',r,v,x.operacion,x.ms_sin_auditoria,x.ms_con_auditoria,x.sobrecosto_pct,x.registros_bitacora;
          PERFORM pg_temp.aa_check(format('rendimiento_filas_%s_%s_%s',v,r,x.operacion), x.filas=v, 'filas reportadas');
          PERFORM pg_temp.aa_check(format('rendimiento_tiempos_%s_%s_%s',v,r,x.operacion), x.ms_sin_auditoria >= 0 AND x.ms_con_auditoria >= 0, 'tiempos no negativos');
          PERFORM pg_temp.aa_check(format('rendimiento_pct_%s_%s_%s',v,r,x.operacion),
            x.sobrecosto_pct IS NULL OR x.sobrecosto_pct >= -100,
            'Original usa tiempos internos sin redondear; resumen recalcula con los tiempos publicados');
          PERFORM pg_temp.aa_check(format('rendimiento_eventos_%s_%s_%s',v,r,x.operacion), x.registros_bitacora = CASE x.operacion WHEN 'INSERT' THEN 2*v WHEN 'UPDATE' THEN v WHEN 'DELETE' THEN 2*v ELSE -1 END, 'eventos esperados');
        END LOOP;
        PERFORM pg_temp.aa_check(format('rendimiento_cardinalidad_%s_%s',v,r), rows_seen=3, 'exactamente tres filas');
        SELECT count(DISTINCT operacion) INTO distinct_ops FROM aa_bench WHERE volumen=v AND rep=r;
        PERFORM pg_temp.aa_check(format('rendimiento_operaciones_%s_%s',v,r), distinct_ops=3, 'INSERT/UPDATE/DELETE sin duplicados');
        SELECT count(*) INTO n FROM pg_class WHERE relname IN ('t_rend_sin','t_rend_con') AND relnamespace = 'public'::regnamespace;
        PERFORM pg_temp.aa_check(format('rendimiento_limpieza_%s_%s',v,r), n=0, 'tablas temporales revertidas');
        snap_after := ARRAY[]::bigint[];
        FOREACH tabla IN ARRAY nombres LOOP
          EXECUTE format('SELECT count(*) FROM auditoria.%I', tabla) INTO n;
          snap_after := snap_after || n;
        END LOOP;
        PERFORM pg_temp.aa_check(format('rendimiento_snapshot_%s_%s',v,r), snap_after=snap, 'conteos de las siete tablas sin residuos');
      EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.aa_check(format('rendimiento_%s_%s',v,r), false, SQLSTATE||' '||SQLERRM);
      END;
    END LOOP;
  END LOOP;
END $suite$;

DO $report$
DECLARE x record; detalle text;
BEGIN
  FOR x IN SELECT volumen,operacion,count(*) muestras,avg(ms_sin) sin,avg(ms_con) con,
      min(ms_sin) min_sin,max(ms_sin) max_sin,stddev_samp(ms_sin) sd_sin,
      min(ms_con) min_con,max(ms_con) max_con,stddev_samp(ms_con) sd_con,
      avg(pct) pct,avg(eventos) eventos, stddev_samp(ms_sin)/NULLIF(avg(ms_sin),0) cv_sin, stddev_samp(ms_con)/NULLIF(avg(ms_con),0) cv_con FROM aa_bench GROUP BY volumen,operacion ORDER BY volumen,operacion
  LOOP
    PERFORM pg_temp.aa_check(format('rendimiento_muestras_%s_%s',x.volumen,x.operacion),x.muestras=3,'Tres repeticiones completas por operación');
    detalle := format('muestras=%s; sin=%sms (min %s max %s sd %s cv %s); con=%sms (min %s max %s sd %s cv %s); sobrecosto=%s%%; eventos_prom=%s', x.muestras,round(x.sin,1),round(x.min_sin,1),round(x.max_sin,1),coalesce(round(x.sd_sin,1)::text,'NULL'),coalesce(round(x.cv_sin*100,1)::text,'NULL'),round(x.con,1),round(x.min_con,1),round(x.max_con,1),coalesce(round(x.sd_con,1)::text,'NULL'),coalesce(round(x.cv_con*100,1)::text,'NULL'),coalesce(round(x.pct,1)::text,'NULL'),round(x.eventos));
    RAISE NOTICE 'AA_BENCH|%|%|%|%',x.volumen,x.operacion,x.muestras,detalle;
  END LOOP;
END $report$;
SELECT * FROM pg_temp.aa_report();
ROLLBACK;
