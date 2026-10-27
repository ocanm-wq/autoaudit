CREATE OR REPLACE FUNCTION auditoria.medir_rendimiento(p_filas INT)
RETURNS TABLE (
    operacion          TEXT,
    filas              INT,
    ms_sin_auditoria   NUMERIC,
    ms_con_auditoria   NUMERIC,
    sobrecosto_pct     NUMERIC,
    registros_bitacora BIGINT
)
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_tablas   TEXT[]    := ARRAY['t_rend_sin', 't_rend_con'];
    v_ins      NUMERIC[] := ARRAY[0, 0];   -- milisegundos [sin, con]
    v_upd      NUMERIC[] := ARRAY[0, 0];
    v_del      NUMERIC[] := ARRAY[0, 0];
    v_bi       BIGINT[]  := ARRAY[0, 0];   -- registros creados en bitácora [sin, con]
    v_bu       BIGINT[]  := ARRAY[0, 0];
    v_bd       BIGINT[]  := ARRAY[0, 0];
    v_t0       TIMESTAMPTZ;
    v_c0       BIGINT;
    v_c1       BIGINT;
    v_id_tabla INT;
    i          INT;
BEGIN
    IF p_filas IS NULL OR p_filas < 1 THEN
        RAISE EXCEPTION 'p_filas debe ser un número mayor que 0';
    END IF;

    BEGIN
        -- Tablas de prueba (se revierten al final)
        EXECUTE 'CREATE TABLE public.t_rend_sin (
                     id       SERIAL PRIMARY KEY,
                     nombre   VARCHAR(100),
                     correo   VARCHAR(100),
                     telefono VARCHAR(20))';
        EXECUTE 'CREATE TABLE public.t_rend_con (
                     id       SERIAL PRIMARY KEY,
                     nombre   VARCHAR(100),
                     correo   VARCHAR(100),
                     telefono VARCHAR(20))';

        -- Configurar auditoría solo en t_rend_con
        INSERT INTO auditoria.aud_tabla (esquema, nombre_tabla)
        VALUES ('public', 't_rend_con')
        RETURNING id_tabla INTO v_id_tabla;

        INSERT INTO auditoria.aud_columna (id_tabla, nombre_columna)
        SELECT v_id_tabla, c.nombre_col
        FROM unnest(ARRAY['nombre', 'correo']) AS c(nombre_col);

        INSERT INTO auditoria.aud_configuracion (id_columna, id_evento)
        SELECT col.id_columna, e.id_evento
        FROM auditoria.aud_columna col
        CROSS JOIN auditoria.aud_evento e
        WHERE col.id_tabla = v_id_tabla;

        PERFORM auditoria.generar_trigger(v_id_tabla);

        -- Medición: i = 1 sin auditoría, i = 2 con auditoría
        FOR i IN 1..2 LOOP
            -- INSERT
            SELECT count(*) INTO v_c0 FROM auditoria.aud_bitacora;
            v_t0 := clock_timestamp();
            EXECUTE format($q$
                INSERT INTO public.%I (nombre, correo, telefono)
                SELECT 'Persona ' || g,
                       'persona' || g || '@mail.com',
                       '5555-' || lpad(g::text, 7, '0')
                FROM generate_series(1, %s) AS g
            $q$, v_tablas[i], p_filas);
            v_ins[i] := extract(epoch FROM clock_timestamp() - v_t0) * 1000;
            SELECT count(*) INTO v_c1 FROM auditoria.aud_bitacora;
            v_bi[i] := v_c1 - v_c0;

            -- UPDATE (cambia solo correo)
            v_c0 := v_c1;
            v_t0 := clock_timestamp();
            EXECUTE format($q$
                UPDATE public.%I SET correo = 'nuevo' || id || '@mail.com'
            $q$, v_tablas[i]);
            v_upd[i] := extract(epoch FROM clock_timestamp() - v_t0) * 1000;
            SELECT count(*) INTO v_c1 FROM auditoria.aud_bitacora;
            v_bu[i] := v_c1 - v_c0;

            -- DELETE
            v_c0 := v_c1;
            v_t0 := clock_timestamp();
            EXECUTE format('DELETE FROM public.%I', v_tablas[i]);
            v_del[i] := extract(epoch FROM clock_timestamp() - v_t0) * 1000;
            SELECT count(*) INTO v_c1 FROM auditoria.aud_bitacora;
            v_bd[i] := v_c1 - v_c0;
        END LOOP;

        -- Forzar la reversión de todo lo anterior
        RAISE EXCEPTION USING ERRCODE = 'AU001',
                              MESSAGE = 'fin de la prueba (se revierten los datos)';
    EXCEPTION WHEN SQLSTATE 'AU001' THEN
        NULL;  -- esperado: los datos se revierten, las variables se conservan
    END;

    RETURN QUERY VALUES
        ('INSERT'::text, p_filas, round(v_ins[1], 1), round(v_ins[2], 1),
         round((v_ins[2] - v_ins[1]) / NULLIF(v_ins[1], 0) * 100, 1), v_bi[2]),
        ('UPDATE'::text, p_filas, round(v_upd[1], 1), round(v_upd[2], 1),
         round((v_upd[2] - v_upd[1]) / NULLIF(v_upd[1], 0) * 100, 1), v_bu[2]),
        ('DELETE'::text, p_filas, round(v_del[1], 1), round(v_del[2], 1),
         round((v_del[2] - v_del[1]) / NULLIF(v_del[1], 0) * 100, 1), v_bd[2]);
END;
$fn$;
REVOKE ALL ON FUNCTION auditoria.medir_rendimiento(INT) FROM PUBLIC;