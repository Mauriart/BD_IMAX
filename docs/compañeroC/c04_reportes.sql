-- =============================================================================
-- PROYECTO BD IMAX - BLOQUE C - ISSUE C-04 (#18)
-- Archivo sugerido: sql/c04_reportes.sql
-- Contenido: cuatro reportes analíticos con RBAC en servidor.
--

-- Definiciones comunes (acuerdos §4 y §11):
--   * Moneda: USD (CHECK en compra/tarifa). No se mezclan monedas.
--   * Ventanas móviles: semana = 168 h, mes = 720 h, intervalos [desde, hasta)
--     con un único instante de corte.
--   * Venta "cobrada": compra en pagada | parcialmente_reembolsada | reembolsada.
--   * Un boleto 'Anulado' solo se origina en un reembolso (revertir_venta), por lo que
--     el importe devuelto = suma de total_linea de los boletos anulados.
--   * Cada reporte preagrega por función/película/método ANTES de unir, para no
--     multiplicar importes ni conteos.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- REPORTE 1. Ocupación y recaudación por función (todas o una función)
--   Capacidad  = asientos de todas las zonas de la sala de la función.
--   Vendidos   = boletos emitidos + usados (los anulados no ocupan asiento).
--   Bruto      = suma de total_linea de las líneas de compras cobradas.
--   Devuelto   = suma de total_linea de los boletos anulados de esas compras.
--   Neto       = Bruto - Devuelto.  (No se resta dos veces: el bruto incluye las
--                líneas luego reembolsadas.)
--   Incluye funciones sin ventas (LEFT JOIN): ocupación 0 % e ingresos 0.00.
--   Filtro opcional por función y por rango del inicio de la función.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reporte_ocupacion_recaudacion(
    p_id_usuario integer,
    p_id_funcion integer     DEFAULT NULL,
    p_desde      timestamptz DEFAULT NULL,
    p_hasta      timestamptz DEFAULT NULL)
RETURNS TABLE (
    id_funcion           integer,
    pelicula             text,
    cine                 text,
    sala                 text,
    inicio               timestamptz,
    capacidad            bigint,
    boletos_vendidos     bigint,
    boletos_usados       bigint,
    porcentaje_ocupacion numeric,
    ingreso_bruto        numeric,
    total_devuelto       numeric,
    ingreso_neto         numeric,
    moneda               text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
    IF NOT autorizar_accion(p_id_usuario, 'ver_reportes_financieros') THEN
        RAISE EXCEPTION 'El usuario no posee permiso para consultar reportes financieros.'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    WITH capacidad AS (
        SELECT z.id_sala, count(a.id_asiento) AS asientos
        FROM zona z
        INNER JOIN asiento a ON a.id_zona = z.id_zona
        GROUP BY z.id_sala
    ),
    ventas AS (
        SELECT c.id_funcion,
               count(b.id_boleto) FILTER (WHERE b.estado IN ('Emitido', 'Usado')) AS vendidos,
               count(b.id_boleto) FILTER (WHERE b.estado = 'Usado')               AS usados,
               coalesce(sum(cd.total_linea), 0)                                   AS bruto,
               coalesce(sum(cd.total_linea) FILTER (WHERE b.estado = 'Anulado'), 0) AS devuelto
        FROM compra c
        INNER JOIN compra_detalle cd ON cd.id_compra = c.id_compra
        LEFT  JOIN boleto b          ON b.id_compra = cd.id_compra AND b.id_asiento = cd.id_asiento
        WHERE c.estado IN ('Pagada', 'ParcialmenteReembolsada', 'Reembolsada')
        GROUP BY c.id_funcion
    )
    SELECT f.id_funcion,
           p.titulo::text,
           ci.nombre::text,
           s.nombre::text,
           f.inicio,
           coalesce(cap.asientos, 0)::bigint,
           coalesce(v.vendidos, 0)::bigint,
           coalesce(v.usados, 0)::bigint,
           round(100.0 * coalesce(v.vendidos, 0) / nullif(cap.asientos, 0), 2),
           coalesce(v.bruto, 0)::numeric(12,2),
           coalesce(v.devuelto, 0)::numeric(12,2),
           (coalesce(v.bruto, 0) - coalesce(v.devuelto, 0))::numeric(12,2),
           'USD'::text
    FROM funcion f
    INNER JOIN pelicula p  ON p.id_pelicula = f.id_pelicula
    INNER JOIN sala s      ON s.id_sala = f.id_sala
    INNER JOIN cine ci     ON ci.id_cine = s.id_cine
    LEFT  JOIN capacidad cap ON cap.id_sala = f.id_sala
    LEFT  JOIN ventas v      ON v.id_funcion = f.id_funcion
    WHERE (p_id_funcion IS NULL OR f.id_funcion = p_id_funcion)
      AND (p_desde IS NULL OR f.inicio >= p_desde)
      AND (p_hasta IS NULL OR f.inicio <  p_hasta)
    ORDER BY f.inicio DESC, f.id_funcion;
END;
$$;

-- -----------------------------------------------------------------------------
-- REPORTE 2. Top 5 películas por boletos vendidos en los últimos 7 días
--   Ventana: [corte - 168 h, corte). Fecha usada: boleto.emitido_en.
--   Cuenta boletos emitidos/usados al corte (excluye anulados) de compras cobradas.
--   Los boletos de cortesía (total 0) cuentan como boleto emitido: son demanda real.
--   Desempate: menor id_pelicula.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reporte_top5_peliculas_semana(
    p_id_usuario integer,
    p_corte      timestamptz DEFAULT CURRENT_TIMESTAMP)
RETURNS TABLE (
    posicion         integer,
    id_pelicula      integer,
    titulo           text,
    clasificacion    text,
    boletos_vendidos bigint,
    recaudacion      numeric,
    moneda           text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
    IF NOT autorizar_accion(p_id_usuario, 'ver_reportes_financieros') THEN
        RAISE EXCEPTION 'El usuario no posee permiso para consultar reportes financieros.'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    WITH por_pelicula AS (
        SELECT f.id_pelicula,
               count(b.id_boleto)   AS vendidos,
               sum(cd.total_linea)  AS recaudado
        FROM boleto b
        INNER JOIN compra_detalle cd ON cd.id_compra = b.id_compra AND cd.id_asiento = b.id_asiento
        INNER JOIN compra c          ON c.id_compra = cd.id_compra
        INNER JOIN funcion f         ON f.id_funcion = c.id_funcion
        WHERE b.emitido_en >= p_corte - INTERVAL '168 hours'
          AND b.emitido_en <  p_corte
          AND b.estado IN ('Emitido', 'Usado')
          AND c.estado IN ('Pagada', 'ParcialmenteReembolsada')
        GROUP BY f.id_pelicula
    )
    SELECT (row_number() OVER (ORDER BY pp.vendidos DESC, pe.id_pelicula))::integer,
           pe.id_pelicula,
           pe.titulo::text,
           pe.clasificacion::text,
           pp.vendidos::bigint,
           pp.recaudado::numeric(12,2),
           'USD'::text
    FROM por_pelicula pp
    INNER JOIN pelicula pe ON pe.id_pelicula = pp.id_pelicula
    ORDER BY pp.vendidos DESC, pe.id_pelicula
    LIMIT 5;
END;
$$;

-- -----------------------------------------------------------------------------
-- REPORTE 3. Métodos de pago preferidos
--   Depende de la tabla `pago` de B (acuerdos §5: id_pago, id_compra, estado, metodo,
--   monto, moneda, creado_en), que AÚN NO EXISTE en imax.sql. Mientras B no la entregue,
--   la función falla con un mensaje claro y no inventa datos.
--   Denominadores explícitos (acuerdos §11), solo pagos 'Aprobado' del periodo:
--     pct_compras = compras pagadas con el método / compras pagadas totales
--     pct_monto   = monto del método / monto aprobado total
--   Las devoluciones NO cuentan como pagos nuevos y se muestran aparte.
--   Periodo por omisión: [corte - 720 h, corte).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reporte_metodos_pago(
    p_id_usuario integer,
    p_desde      timestamptz DEFAULT NULL,
    p_hasta      timestamptz DEFAULT NULL)
RETURNS TABLE (
    metodo       text,
    compras      bigint,
    pct_compras  numeric,
    monto        numeric,
    pct_monto    numeric,
    moneda       text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_hasta timestamptz := coalesce(p_hasta, CURRENT_TIMESTAMP);
    v_desde timestamptz := coalesce(p_desde, coalesce(p_hasta, CURRENT_TIMESTAMP) - INTERVAL '720 hours');
BEGIN
    IF NOT autorizar_accion(p_id_usuario, 'ver_reportes_financieros') THEN
        RAISE EXCEPTION 'El usuario no posee permiso para consultar reportes financieros.'
            USING ERRCODE = '42501';
    END IF;
    IF to_regclass('public.pago') IS NULL THEN
        RAISE EXCEPTION 'La tabla pago (B-01/B-03) aún no existe: el reporte de métodos de pago no puede calcularse.'
            USING ERRCODE = '55000';
    END IF;

    RETURN QUERY
    WITH por_metodo AS (
        SELECT pg.metodo::text AS met,
               count(DISTINCT pg.id_compra) AS n_compras,
               sum(pg.monto)                AS monto_met
        FROM pago pg
        WHERE pg.estado = 'Aprobado'
          AND pg.creado_en >= v_desde AND pg.creado_en < v_hasta
        GROUP BY pg.metodo
    ),
    totales AS (
        SELECT sum(pm.n_compras) AS t_compras, sum(pm.monto_met) AS t_monto
        FROM por_metodo pm
    )
    SELECT m.met,
           m.n_compras::bigint,
           round(100.0 * m.n_compras / nullif(t.t_compras, 0), 2),
           m.monto_met::numeric(12,2),
           round(100.0 * m.monto_met / nullif(t.t_monto, 0), 2),
           'USD'::text
    FROM por_metodo m CROSS JOIN totales t
    ORDER BY m.n_compras DESC, m.met;
END;
$$;

-- -----------------------------------------------------------------------------
-- REPORTE 4a. Auditoría crítica del último mes AGRUPADA por administrador
--   Ventana por omisión: [corte - 720 h, corte). Solo acciones del rol administrador;
--   los intentos denegados ('denegado:*') se cuentan aparte, no como acciones manuales.
--   Misma lógica que C-05 (consultas_sql_c_05.sql, Q2a), con control RBAC.
--   Permiso: ver_auditoria (contador y administrador).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reporte_auditoria_por_administrador(
    p_id_usuario integer,
    p_desde      timestamptz DEFAULT NULL,
    p_hasta      timestamptz DEFAULT NULL)
RETURNS TABLE (
    id_administrador               integer,
    nombre_administrador           text,
    acciones_manuales              bigint,
    cortesias                      bigint,
    reembolsos                     bigint,
    reembolsos_forzados            bigint,
    reembolsos_rechazados          bigint,
    cambios_asiento                bigint,
    cambios_politica               bigint,
    cambios_catalogo_precios_roles bigint,
    intentos_denegados             bigint,
    ultima_accion                  timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_hasta timestamptz := coalesce(p_hasta, CURRENT_TIMESTAMP);
    v_desde timestamptz := coalesce(p_desde, coalesce(p_hasta, CURRENT_TIMESTAMP) - INTERVAL '720 hours');
BEGIN
    IF NOT autorizar_accion(p_id_usuario, 'ver_auditoria') THEN
        RAISE EXCEPTION 'El usuario no posee permiso para consultar la auditoría.'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT a.id_usuario_actor,
           u.nombre::text,
           count(*) FILTER (WHERE a.accion NOT LIKE 'denegado:%'),
           count(*) FILTER (WHERE a.accion = 'otorgar_cortesia'),
           count(*) FILTER (WHERE a.accion IN ('reembolso_ordinario', 'reembolso_forzado')),
           count(*) FILTER (WHERE a.accion = 'reembolso_forzado'),
           count(*) FILTER (WHERE a.accion = 'rechazar_reembolso'),
           count(*) FILTER (WHERE a.accion = 'cambio_asiento'),
           count(*) FILTER (WHERE a.accion = 'configurar_politica'),
           count(*) FILTER (WHERE a.accion ~ '^(insert|update|delete)_'),
           count(*) FILTER (WHERE a.accion LIKE 'denegado:%'),
           max(a.fecha)
    FROM admin_operacion_audit a
    INNER JOIN usuario u ON u.id_usuario = a.id_usuario_actor
    WHERE a.rol_al_actuar = 'administrador'
      AND a.fecha >= v_desde AND a.fecha < v_hasta
    GROUP BY a.id_usuario_actor, u.nombre
    ORDER BY a.id_usuario_actor;
END;
$$;

-- -----------------------------------------------------------------------------
-- REPORTE 4b. Detalle consultable de las mismas acciones (misma ventana y filtro).
--   "cambios" no contiene password_hash: auditar_cambio_critico() lo elimina.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reporte_auditoria_detalle(
    p_id_usuario integer,
    p_desde      timestamptz DEFAULT NULL,
    p_hasta      timestamptz DEFAULT NULL)
RETURNS TABLE (
    id_administrador integer,
    fecha            timestamptz,
    accion           text,
    entidad          text,
    id_entidad       text,
    ip               text,
    motivo           text,
    cambios          jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_hasta timestamptz := coalesce(p_hasta, CURRENT_TIMESTAMP);
    v_desde timestamptz := coalesce(p_desde, coalesce(p_hasta, CURRENT_TIMESTAMP) - INTERVAL '720 hours');
BEGIN
    IF NOT autorizar_accion(p_id_usuario, 'ver_auditoria') THEN
        RAISE EXCEPTION 'El usuario no posee permiso para consultar la auditoría.'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT a.id_usuario_actor,
           a.fecha,
           a.accion::text,
           a.entidad::text,
           a.id_entidad::text,
           a.ip::text,
           a.motivo,
           a.cambios
    FROM admin_operacion_audit a
    WHERE a.rol_al_actuar = 'administrador'
      AND a.accion NOT LIKE 'denegado:%'
      AND a.fecha >= v_desde AND a.fecha < v_hasta
    ORDER BY a.id_usuario_actor, a.fecha DESC, a.id_admin_operacion_audit DESC;
END;
$$;

-- -----------------------------------------------------------------------------
-- PRIVILEGIOS: solo la cuenta de aplicación puede ejecutar los reportes; el permiso
-- de negocio lo decide autorizar_accion dentro de cada función (SECURITY DEFINER).
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.reporte_ocupacion_recaudacion(integer, integer, timestamptz, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reporte_top5_peliculas_semana(integer, timestamptz)                       FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reporte_metodos_pago(integer, timestamptz, timestamptz)                   FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reporte_auditoria_por_administrador(integer, timestamptz, timestamptz)    FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reporte_auditoria_detalle(integer, timestamptz, timestamptz)              FROM PUBLIC;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'imax_app') THEN
        GRANT EXECUTE ON FUNCTION public.reporte_ocupacion_recaudacion(integer, integer, timestamptz, timestamptz) TO imax_app;
        GRANT EXECUTE ON FUNCTION public.reporte_top5_peliculas_semana(integer, timestamptz)                       TO imax_app;
        GRANT EXECUTE ON FUNCTION public.reporte_metodos_pago(integer, timestamptz, timestamptz)                   TO imax_app;
        GRANT EXECUTE ON FUNCTION public.reporte_auditoria_por_administrador(integer, timestamptz, timestamptz)    TO imax_app;
        GRANT EXECUTE ON FUNCTION public.reporte_auditoria_detalle(integer, timestamptz, timestamptz)              TO imax_app;
    END IF;
END $$;

COMMENT ON FUNCTION public.reporte_ocupacion_recaudacion(integer, integer, timestamptz, timestamptz) IS
  'C-04: ocupación y recaudación neta por función; preagrega ventas antes de unir; incluye funciones sin ventas.';
COMMENT ON FUNCTION public.reporte_top5_peliculas_semana(integer, timestamptz) IS
  'C-04: top 5 películas por boletos emitidos/usados en 168 h móviles; desempate por id_pelicula.';
COMMENT ON FUNCTION public.reporte_metodos_pago(integer, timestamptz, timestamptz) IS
  'C-04: porcentaje de compras y de monto por método de pago aprobado; requiere la tabla pago de B.';
COMMENT ON FUNCTION public.reporte_auditoria_por_administrador(integer, timestamptz, timestamptz) IS
  'C-04: acciones manuales de los últimos 720 h agrupadas por administrador (RN-20).';

COMMIT;
