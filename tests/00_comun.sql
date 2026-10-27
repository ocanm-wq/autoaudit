-- Cargar este archivo y una suite en LA MISMA conexión de pruebas.
-- SQL estándar/PLpgSQL; sin metacomandos de psql ni extensiones adicionales.
DO $$ BEGIN
  IF current_database() !~ '^autoaudit_test(_[a-z0-9]+)?$' THEN
    RAISE EXCEPTION 'Solo se permite una base aislada autoaudit_test o autoaudit_test_<sufijo>';
  END IF;
END $$;

CREATE TEMP TABLE aa_results (
  id text PRIMARY KEY, estado text NOT NULL CHECK (estado IN ('PASS','FAIL','BLOCKED')),
  detalle text NOT NULL
) ON COMMIT PRESERVE ROWS;

CREATE FUNCTION pg_temp.aa_guard() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF current_database() !~ '^autoaudit_test(_[a-z0-9]+)?$' THEN
    RAISE EXCEPTION 'Base no autorizada: %', current_database();
  END IF;
  IF to_regclass('auditoria.aud_bitacora') IS NULL THEN
    RAISE EXCEPTION 'Primero instalar 01 en una base NUEVA de un clúster dedicado';
  END IF;
END $$;

CREATE FUNCTION pg_temp.aa_check(p_id text, p_ok boolean, p_detalle text DEFAULT '')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO pg_temp.aa_results VALUES
    (p_id, CASE WHEN p_ok IS TRUE THEN 'PASS' ELSE 'FAIL' END, coalesce(p_detalle,''));
END $$;

CREATE FUNCTION pg_temp.aa_skip(p_id text, p_detalle text) RETURNS void LANGUAGE sql AS $$
  INSERT INTO pg_temp.aa_results VALUES (p_id, 'BLOCKED', p_detalle);
$$;

CREATE FUNCTION pg_temp.aa_error(p_id text, p_sql text, p_estados text[])
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_estado text; v_mensaje text;
BEGIN
  BEGIN
    EXECUTE p_sql;
    -- También revierte una operación aceptada inesperadamente.
    RAISE EXCEPTION USING ERRCODE='AA009', MESSAGE='operación aceptada inesperadamente';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_estado=RETURNED_SQLSTATE, v_mensaje=MESSAGE_TEXT;
  END;
  PERFORM pg_temp.aa_check(p_id,v_estado=ANY(p_estados),v_estado||': '||v_mensaje);
END $$;

-- Ejecuta como rol real y revierte SIEMPRE el intento en una subtransacción.
-- No es SECURITY DEFINER ni concede privilegios al rol que se está probando.
CREATE FUNCTION pg_temp.aa_as_role(p_id text, p_rol text, p_sql text,
  p_estados text[] DEFAULT ARRAY['00000'], p_valor text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_estado text; v_mensaje text; v_valor text; v_rol text := current_user;
BEGIN
  BEGIN
    EXECUTE format('SET LOCAL ROLE %I',p_rol);
    IF p_valor IS NULL THEN EXECUTE p_sql;
    ELSE EXECUTE p_sql INTO v_valor; END IF;
    RAISE EXCEPTION USING ERRCODE='AA009',MESSAGE='fin del intento: revertir';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_estado=RETURNED_SQLSTATE,v_mensaje=MESSAGE_TEXT;
    IF v_estado='AA009' THEN v_estado:='00000'; v_mensaje:='ejecución autorizada'; END IF;
  END;
  EXECUTE format('SET LOCAL ROLE %I',v_rol);
  PERFORM pg_temp.aa_check(p_id,
    v_estado=ANY(p_estados) AND (p_valor IS NULL OR v_valor IS NOT DISTINCT FROM p_valor),
    p_rol||' SQLSTATE='||v_estado||' valor='||coalesce(v_valor,'NULL')||' '||v_mensaje);
END $$;

CREATE FUNCTION pg_temp.aa_report() RETURNS SETOF pg_temp.aa_results LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM pg_temp.aa_results ORDER BY id LOOP
    RAISE NOTICE 'AA_RESULT|%|%|%',r.id,r.estado,
      replace(replace(r.detalle,E'\n',' '),E'\r',' ');
  END LOOP;
  RAISE NOTICE 'AA_SUMMARY|PASS=%|FAIL=%|BLOCKED=%',
    (SELECT count(*) FROM pg_temp.aa_results WHERE estado='PASS'),
    (SELECT count(*) FROM pg_temp.aa_results WHERE estado='FAIL'),
    (SELECT count(*) FROM pg_temp.aa_results WHERE estado='BLOCKED');
  RETURN QUERY SELECT * FROM pg_temp.aa_results ORDER BY id;
END $$;
