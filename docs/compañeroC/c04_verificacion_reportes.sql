-- C-04 · Verificación de los cuatro reportes con dataset conocidos
-- Ejecutar con un usuario propietario (postgres), NO con imax_app: se insertan filas de
-- ensayo directamente. Todo ocurre en una transacción que termina en ROLLBACK:
-- no deja filas ni la tabla pago de ensayo.
-- Resultado esperado: todas las filas con resultado = 'OK' (o 'OMITIDO' donde se indica).
--

BEGIN;

CREATE TEMP TABLE _v (n int, caso text, esperado text, resultado text) ON COMMIT DROP;

CREATE FUNCTION pg_temp.c04_chk(p_n int, p_caso text, p_esperado text, p_obtenido text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO _v VALUES (p_n, p_caso, p_esperado,
        CASE WHEN p_esperado IS NOT DISTINCT FROM p_obtenido THEN 'OK'
             ELSE 'FALLO: ' || coalesce(p_obtenido, 'NULL') END);
END $$;

DO $$
DECLARE
    r        record;
    v_state  text;
    v_pel    int;
    v_fun    int;
    v_cmp    int;
    v_cd     int;
    v_f1     int;
    v_fsin   int;
    v_adm2   int;
    k        int;
    i        int;
    j        int;
    t0       timestamptz;
    n        int;
BEGIN
    SELECT min(id_funcion) INTO v_f1 FROM funcion;

    ------------------------------------------------------------------ Reporte 1
    SELECT * INTO r FROM reporte_ocupacion_recaudacion(6, v_f1);   -- contador
    PERFORM pg_temp.c04_chk(1,  'R1 capacidad de la sala (6 asientos)', '6', r.capacidad::text);
    PERFORM pg_temp.c04_chk(2,  'R1 boletos vendidos (emitidos+usados, sin anulados)', '3', r.boletos_vendidos::text);
    PERFORM pg_temp.c04_chk(3,  'R1 boletos usados', '1', r.boletos_usados::text);
    PERFORM pg_temp.c04_chk(4,  'R1 porcentaje de ocupación', '50.00', to_char(r.porcentaje_ocupacion, 'FM990.00'));
    PERFORM pg_temp.c04_chk(5,  'R1 ingreso bruto (incluye la línea luego reembolsada)', '33.00', to_char(r.ingreso_bruto, 'FM99990.00'));
    PERFORM pg_temp.c04_chk(6,  'R1 total devuelto (boletos anulados)', '12.00', to_char(r.total_devuelto, 'FM99990.00'));
    PERFORM pg_temp.c04_chk(7,  'R1 ingreso neto = bruto - devuelto (sin doble resta)', '21.00', to_char(r.ingreso_neto, 'FM99990.00'));
    PERFORM pg_temp.c04_chk(8,  'R1 moneda', 'USD', r.moneda);

    -- Función sin ventas
    SELECT id_pelicula INTO v_pel FROM pelicula ORDER BY id_pelicula LIMIT 1;
    INSERT INTO funcion (id_pelicula, id_sala, inicio, fin, activa)
    VALUES (v_pel, 1, '2026-12-01 18:00:00-06', '2026-12-01 20:00:00-06', true)
    RETURNING id_funcion INTO v_fsin;
    SELECT * INTO r FROM reporte_ocupacion_recaudacion(7, v_fsin);  -- administrador
    PERFORM pg_temp.c04_chk(9,  'R1 función sin ventas aparece (LEFT JOIN)', '1', (SELECT count(*) FROM reporte_ocupacion_recaudacion(7, v_fsin))::text);
    PERFORM pg_temp.c04_chk(10, 'R1 función sin ventas: 0 vendidos y 0.00 % de ocupación', '0|0.00',
                            r.boletos_vendidos::text || '|' || to_char(r.porcentaje_ocupacion, 'FM990.00'));
    PERFORM pg_temp.c04_chk(11, 'R1 función sin ventas: bruto, devuelto y neto en 0.00', '0.00|0.00|0.00',
                            to_char(r.ingreso_bruto, 'FM99990.00') || '|' || to_char(r.total_devuelto, 'FM99990.00') || '|' || to_char(r.ingreso_neto, 'FM99990.00'));

    -- Dataset para Reporte 2
    -- Películas 2..7 con una función y una compra pagada cada una; boletos emitidos el 24-oct 10:00.
    FOR i IN 2..7 LOOP
        INSERT INTO pelicula (titulo, sinopsis, clasificacion, duracion_min, poster_url)
        VALUES ('Pelicula C04 ' || i, 'Ensayo C-04', 'Todo público', 90, '/static/img/c04.png')
        RETURNING id_pelicula INTO v_pel;
        t0 := '2026-11-01 18:00:00-06'::timestamptz + (i * INTERVAL '1 day');
        INSERT INTO funcion (id_pelicula, id_sala, inicio, fin, activa)
        VALUES (v_pel, 1, t0, t0 + INTERVAL '2 hours', true)
        RETURNING id_funcion INTO v_fun;
        k := CASE i WHEN 2 THEN 1 WHEN 3 THEN 1 WHEN 4 THEN 2 WHEN 5 THEN 2 WHEN 6 THEN 3 ELSE 1 END;
        INSERT INTO compra (id_usuario_cliente, id_usuario_actor, id_funcion, estado, total, moneda, creada_en)
        VALUES (1, 1, v_fun, 'pagada', 8 * k, 'USD', '2026-10-24 09:59:00-06')
        RETURNING id_compra INTO v_cmp;
        FOR j IN 1..k LOOP
            INSERT INTO compra_detalle (id_compra, id_asiento, id_categoria_entrada, id_tarifa,
                                        precio_base, descuento, cargo_servicio, total_linea)
            VALUES (v_cmp, j, 1, 1, 8.00, 0.00, 0.00, 8.00)
            RETURNING id_compra_detalle INTO v_cd;
            INSERT INTO boleto (id_compra_detalle, estado, emitido_en)
            VALUES (v_cd, 'emitido', '2026-10-24 10:00:00-06');
        END LOOP;
    END LOOP;
    -- Esperado: Horizonte estelar 3 (id menor), Pelicula C04 6 = 3, C04 4 = 2, C04 5 = 2, C04 2 = 1.
    -- C04 3 y C04 7 (1 boleto) quedan fuera del top 5.

    ------------------------------------------------------------------ Reporte 2
    SELECT count(*) INTO n FROM reporte_top5_peliculas_semana(6, '2026-10-24 12:00:00-06');
    PERFORM pg_temp.c04_chk(12, 'R2 devuelve exactamente 5 filas (LIMIT)', '5', n::text);
    PERFORM pg_temp.c04_chk(13, 'R2 orden y desempate por id_pelicula', 'Horizonte estelar|Pelicula C04 6|Pelicula C04 4|Pelicula C04 5|Pelicula C04 2',
        (SELECT string_agg(titulo, '|' ORDER BY posicion) FROM reporte_top5_peliculas_semana(6, '2026-10-24 12:00:00-06')));
    PERFORM pg_temp.c04_chk(14, 'R2 conteos 3|3|2|2|1', '3|3|2|2|1',
        (SELECT string_agg(boletos_vendidos::text, '|' ORDER BY posicion) FROM reporte_top5_peliculas_semana(6, '2026-10-24 12:00:00-06')));
    PERFORM pg_temp.c04_chk(15, 'R2 recaudación de Horizonte estelar = 21.00 (excluye anulado)', '21.00',
        (SELECT to_char(recaudacion, 'FM99990.00') FROM reporte_top5_peliculas_semana(6, '2026-10-24 12:00:00-06') WHERE posicion = 1));
    PERFORM pg_temp.c04_chk(16, 'R2 fuera de la ventana de 168 h: 0 filas', '0',
        (SELECT count(*) FROM reporte_top5_peliculas_semana(6, '2026-11-05 00:00:00-06'))::text);

    ------------------------------------------------------------------ No duplicación (R1 global)
    PERFORM pg_temp.c04_chk(17, 'R1 suma de brutos = suma de compra.total de compras cobradas (sin duplicar)',
        (SELECT to_char(sum(total), 'FM99990.00') FROM compra WHERE estado IN ('pagada','parcialmente_reembolsada','reembolsada')),
        (SELECT to_char(sum(ingreso_bruto), 'FM99990.00') FROM reporte_ocupacion_recaudacion(7)));
    PERFORM pg_temp.c04_chk(18, 'R1 suma de vendidos = boletos emitidos/usados de compras cobradas',
        (SELECT count(*) FROM boleto b JOIN compra_detalle cd USING (id_compra_detalle) JOIN compra c USING (id_compra)
          WHERE b.estado IN ('emitido','usado') AND c.estado IN ('pagada','parcialmente_reembolsada','reembolsada'))::text,
        (SELECT sum(boletos_vendidos) FROM reporte_ocupacion_recaudacion(7))::text);

    ------------------------------------------------------------------ Reporte 3
    BEGIN PERFORM 1 FROM reporte_metodos_pago(6);
          IF to_regclass('public.pago') IS NULL THEN
              PERFORM pg_temp.c04_chk(19, 'R3 sin tabla pago: error claro 55000', '55000', 'SE EJECUTÓ');
          ELSE
              PERFORM pg_temp.c04_chk(19, 'R3 con tabla pago real: sin error', 'sin error', 'sin error');
          END IF;
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          IF to_regclass('public.pago') IS NULL THEN
              PERFORM pg_temp.c04_chk(19, 'R3 sin tabla pago: error claro 55000', '55000', v_state);
          ELSE
              PERFORM pg_temp.c04_chk(19, 'R3 con tabla pago real: sin error', 'sin error', v_state);
          END IF;
    END;

    IF to_regclass('public.pago') IS NULL THEN
        -- Tabla de ensayo con las columnas acordadas (acuerdos §5); se elimina con el ROLLBACK.
        CREATE TABLE public.pago (id_pago serial PRIMARY KEY, id_compra integer NOT NULL,
            estado varchar(20) NOT NULL, metodo varchar(30) NOT NULL, monto numeric(12,2) NOT NULL,
            moneda varchar(3) NOT NULL DEFAULT 'USD', creado_en timestamptz NOT NULL);
        INSERT INTO pago (id_compra, estado, metodo, monto, creado_en) VALUES
            (1, 'aprobado',  'tarjeta', 13.00, '2026-10-23 14:33:20-06'),
            (2, 'aprobado',  'tarjeta', 12.00, '2026-10-23 14:33:20-06'),
            (3, 'aprobado',  'paypal',   8.00, '2026-10-23 14:33:20-06'),
            (3, 'rechazado', 'paypal',  99.00, '2026-10-23 14:30:00-06'),   -- rechazado: no cuenta
            (1, 'aprobado',  'paypal',   5.00, '2026-01-01 10:00:00-06');   -- fuera del periodo
        SELECT string_agg(metodo || ':' || compras || ':' || to_char(pct_compras,'FM990.00') || ':' || to_char(monto,'FM99990.00') || ':' || to_char(pct_monto,'FM990.00'),
                          '|' ORDER BY compras DESC, metodo)
          INTO v_state
        FROM reporte_metodos_pago(7, '2026-10-01 00:00:00-06', '2026-11-01 00:00:00-06');
        PERFORM pg_temp.c04_chk(20, 'R3 porcentajes por compras y por monto (rechazados y fuera de periodo excluidos)',
            'tarjeta:2:66.67:25.00:75.76|paypal:1:33.33:8.00:24.24', v_state);
        PERFORM pg_temp.c04_chk(21, 'R3 los porcentajes suman 100',
            '100.00|100.00',
            (SELECT to_char(sum(pct_compras),'FM990.00') || '|' || to_char(sum(pct_monto),'FM990.00')
               FROM reporte_metodos_pago(7, '2026-10-01 00:00:00-06', '2026-11-01 00:00:00-06')));
        PERFORM pg_temp.c04_chk(22, 'R3 periodo sin pagos: 0 filas (sin división por cero)', '0',
            (SELECT count(*) FROM reporte_metodos_pago(7, '2025-01-01 00:00:00-06', '2025-02-01 00:00:00-06'))::text);
    ELSE
        INSERT INTO _v VALUES (20, 'R3 con datos (ya existe pago real)', 'ver nota', 'OMITIDO: probar con los datos de B');
    END IF;

    ------------------------------------------------------------------ Reporte 4
    -- Segundo administrador y acciones con fechas fijas (ventana de ensayo 24-oct .. 01-nov).
    INSERT INTO usuario (id_rol, nombre, correo, password_hash)
    SELECT id_rol, 'Administrador Dos', 'admin2.c04@imax.test', 'HASH_DE_PRUEBA' FROM rol WHERE nombre = 'administrador'
    RETURNING id_usuario INTO v_adm2;

    INSERT INTO admin_operacion_audit (fecha, id_usuario_actor, rol_al_actuar, ip, accion, entidad, id_entidad, motivo) VALUES
        ('2026-10-25 10:00:00-06', 7,      'administrador', '127.0.0.1', 'otorgar_cortesia',         'compra',             '1', 'ensayo C-04'),
        ('2026-10-25 10:01:00-06', 7,      'administrador', '127.0.0.1', 'reembolso_ordinario',      'solicitud_reembolso','1', 'ensayo C-04'),
        ('2026-10-25 10:02:00-06', 7,      'administrador', '127.0.0.1', 'reembolso_forzado',        'solicitud_reembolso','2', 'ensayo C-04'),
        ('2026-10-25 10:03:00-06', 7,      'administrador', '127.0.0.1', 'rechazar_reembolso',       'solicitud_reembolso','3', 'ensayo C-04'),
        ('2026-10-25 10:04:00-06', 7,      'administrador', '127.0.0.1', 'cambio_asiento',           'boleto',             '1', 'ensayo C-04'),
        ('2026-10-25 10:05:00-06', 7,      'administrador', '127.0.0.1', 'configurar_politica',      'politica_negocio',   'reembolso_horas_antes', 'ensayo C-04'),
        ('2026-10-25 10:06:00-06', 7,      'administrador', '127.0.0.1', 'update_tarifa',            'tarifa',             '1', 'ensayo C-04'),
        ('2026-10-25 10:07:00-06', 7,      'administrador', '127.0.0.1', 'denegado:forzar_reembolso','solicitud_reembolso','1', 'ensayo C-04'),
        ('2026-10-25 10:08:00-06', 7,      'administrador', '127.0.0.1', 'denegado:cambiar_asiento', 'boleto',             '1', 'ensayo C-04'),
        ('2026-10-26 09:00:00-06', v_adm2, 'administrador', '127.0.0.1', 'otorgar_cortesia',         'compra',             '2', 'ensayo C-04'),
        ('2026-09-01 09:00:00-06', 7,      'administrador', '127.0.0.1', 'otorgar_cortesia',         'compra',             '3', 'fuera de ventana'),
        ('2026-10-27 09:00:00-06', 6,      'contador',      '127.0.0.1', 'update_algo',              'tarifa',             '1', 'otro rol: no cuenta');

    SELECT * INTO r FROM reporte_auditoria_por_administrador(6, '2026-10-24 00:00:00-06', '2026-11-01 00:00:00-06')
     WHERE id_administrador = 7;
    PERFORM pg_temp.c04_chk(23, 'R4 admin 7: acciones manuales (sin denegados, sin fuera de ventana)', '7', r.acciones_manuales::text);
    PERFORM pg_temp.c04_chk(24, 'R4 admin 7: cortesías|reembolsos|forzados|rechazados', '1|2|1|1',
        r.cortesias || '|' || r.reembolsos || '|' || r.reembolsos_forzados || '|' || r.reembolsos_rechazados);
    PERFORM pg_temp.c04_chk(25, 'R4 admin 7: cambio asiento|política|catálogo-precios-roles|denegados', '1|1|1|2',
        r.cambios_asiento || '|' || r.cambios_politica || '|' || r.cambios_catalogo_precios_roles || '|' || r.intentos_denegados);
    PERFORM pg_temp.c04_chk(26, 'R4 agrupa por administrador: 2 administradores en la ventana', '2',
        (SELECT count(*) FROM reporte_auditoria_por_administrador(7, '2026-10-24 00:00:00-06', '2026-11-01 00:00:00-06'))::text);
    PERFORM pg_temp.c04_chk(27, 'R4 el rol contador no aparece como administrador', '0',
        (SELECT count(*) FROM reporte_auditoria_por_administrador(7, '2026-10-24 00:00:00-06', '2026-11-01 00:00:00-06') WHERE id_administrador = 6)::text);
    PERFORM pg_temp.c04_chk(28, 'R4 detalle: 8 acciones manuales (7 + 1), sin denegados', '8',
        (SELECT count(*) FROM reporte_auditoria_detalle(6, '2026-10-24 00:00:00-06', '2026-11-01 00:00:00-06'))::text);
    PERFORM pg_temp.c04_chk(29, 'R4 la fila de ensayo del 22-oct queda fuera de la ventana', '0',
        (SELECT count(*) FROM reporte_auditoria_detalle(7, '2026-10-24 00:00:00-06', '2026-11-01 00:00:00-06') WHERE accion = 'prueba')::text);

    ------------------------------------------------------------------ RBAC (RN-17)
    -- Usuarios del dataset: 1 y 2 clientes, 3 taquillero, 4 y 5 operadores de puerta, 6 contador, 7 administrador.
    FOR i IN 1..5 LOOP
        BEGIN PERFORM 1 FROM reporte_ocupacion_recaudacion(i);
              PERFORM pg_temp.c04_chk(30 + i, 'RBAC R1 usuario ' || i || ' sin permiso de reportes', '42501', 'SE PERMITIÓ');
        EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
              PERFORM pg_temp.c04_chk(30 + i, 'RBAC R1 usuario ' || i || ' sin permiso de reportes', '42501', v_state);
        END;
    END LOOP;
    BEGIN PERFORM 1 FROM reporte_top5_peliculas_semana(3);
          PERFORM pg_temp.c04_chk(36, 'RBAC R2 taquillero denegado', '42501', 'SE PERMITIÓ');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          PERFORM pg_temp.c04_chk(36, 'RBAC R2 taquillero denegado', '42501', v_state); END;
    BEGIN PERFORM 1 FROM reporte_auditoria_por_administrador(1);
          PERFORM pg_temp.c04_chk(37, 'RBAC R4 cliente denegado', '42501', 'SE PERMITIÓ');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          PERFORM pg_temp.c04_chk(37, 'RBAC R4 cliente denegado', '42501', v_state); END;
    BEGIN PERFORM 1 FROM reporte_auditoria_detalle(4);
          PERFORM pg_temp.c04_chk(38, 'RBAC R4 detalle: operador de puerta denegado', '42501', 'SE PERMITIÓ');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          PERFORM pg_temp.c04_chk(38, 'RBAC R4 detalle: operador de puerta denegado', '42501', v_state); END;
    BEGIN PERFORM 1 FROM reporte_ocupacion_recaudacion(987654321);
          PERFORM pg_temp.c04_chk(39, 'RBAC usuario inexistente denegado', '42501', 'SE PERMITIÓ');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          PERFORM pg_temp.c04_chk(39, 'RBAC usuario inexistente denegado', '42501', v_state); END;
    PERFORM pg_temp.c04_chk(40, 'RBAC contador y administrador sí leen R1', 'sin error',
        (SELECT CASE WHEN (SELECT count(*) FROM reporte_ocupacion_recaudacion(6)) >= 0
                      AND (SELECT count(*) FROM reporte_ocupacion_recaudacion(7)) >= 0 THEN 'sin error' END));
END $$;

SELECT n, caso, esperado, resultado FROM _v ORDER BY n;

ROLLBACK;
