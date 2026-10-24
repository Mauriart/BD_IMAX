WITH corte AS (SELECT CURRENT_TIMESTAMP - INTERVAL '720 hours' AS desde, CURRENT_TIMESTAMP AS hasta)
SELECT l.id_usuario_operador,
       u.nombre                                   AS nombre_operador,
       l.id_funcion_solicitada,
       count(*)                                   AS total_rechazos,
       count(DISTINCT l.id_boleto)                AS boletos_distintos,
       string_agg(DISTINCT CASE
            WHEN l.motivo ILIKE 'Código QR no registrado%'            THEN 'QR_INEXISTENTE'
            WHEN l.motivo ILIKE 'Entrada ya utilizada%'               THEN 'ENTRADA_YA_UTILIZADA'
            WHEN l.motivo ILIKE 'Boleto anulado%'                     THEN 'BOLETO_ANULADO'
            WHEN l.motivo ILIKE 'El boleto corresponde a otra función%' THEN 'FUNCION_INCORRECTA'
            WHEN l.motivo ILIKE 'Ingreso muy temprano%'
              OR l.motivo ILIKE 'Ingreso fuera de horario%'           THEN 'FUERA_DE_HORARIO'
            ELSE 'OTRO' END, ', ')                AS tipos_rechazo,
       min(l.fecha)                               AS primer_rechazo,
       max(l.fecha)                               AS ultimo_rechazo
FROM public.acceso_puerta_log l
INNER JOIN public.usuario u ON u.id_usuario = l.id_usuario_operador
CROSS JOIN corte c
WHERE l.resultado = 'rechazado'
  AND l.fecha >= c.desde AND l.fecha < c.hasta
GROUP BY l.id_usuario_operador, u.nombre, l.id_funcion_solicitada
HAVING count(*) >= 3
ORDER BY total_rechazos DESC, l.id_usuario_operador, l.id_funcion_solicitada;


-- Q2a. AUDITORÍA DE OPERACIONES MANUALES POR ADMINISTRADOR — últimos 720 h (RN-20 / consigna)
-- Cortesías, reembolsos (ordinarios y forzados), cambios de asiento, políticas y cambios de
-- catálogo/precios/roles registrados por trigger. Excluye los intentos denegados (se cuentan aparte).
-- Equivale a resumen_auditoria_admin(), pero con la ventana de 720 h de los acuerdos
-- (la función usa INTERVAL '1 month'; ver observación en la documentación C-05 9).

WITH corte AS (SELECT CURRENT_TIMESTAMP - INTERVAL '720 hours' AS desde, CURRENT_TIMESTAMP AS hasta)
SELECT a.id_usuario_actor                                         AS id_administrador,
       u.nombre                                                   AS nombre_administrador,
       count(*) FILTER (WHERE a.accion NOT LIKE 'denegado:%')     AS acciones_manuales,
       count(*) FILTER (WHERE a.accion = 'otorgar_cortesia')      AS cortesias,
       count(*) FILTER (WHERE a.accion IN ('reembolso_ordinario','reembolso_forzado')) AS reembolsos,
       count(*) FILTER (WHERE a.accion = 'reembolso_forzado')     AS reembolsos_forzados,
       count(*) FILTER (WHERE a.accion = 'rechazar_reembolso')    AS reembolsos_rechazados,
       count(*) FILTER (WHERE a.accion = 'cambio_asiento')        AS cambios_asiento,
       count(*) FILTER (WHERE a.accion = 'configurar_politica')   AS cambios_politica,
       count(*) FILTER (WHERE a.accion ~ '^(insert|update|delete)_') AS cambios_catalogo_precios_roles,
       count(*) FILTER (WHERE a.accion LIKE 'denegado:%')         AS intentos_denegados,
       max(a.fecha)                                               AS ultima_accion
FROM public.admin_operacion_audit a
INNER JOIN public.usuario u ON u.id_usuario = a.id_usuario_actor
CROSS JOIN corte c
WHERE a.rol_al_actuar = 'administrador'
  AND a.fecha >= c.desde AND a.fecha < c.hasta
GROUP BY a.id_usuario_actor, u.nombre
ORDER BY a.id_usuario_actor;

-- Q2b. Detalle consultable de las mismas acciones (misma ventana y filtro; sin password_hash porque
--      auditar_cambio_critico() ya lo elimina de "cambios").
WITH corte AS (SELECT CURRENT_TIMESTAMP - INTERVAL '720 hours' AS desde, CURRENT_TIMESTAMP AS hasta)
SELECT a.id_usuario_actor AS id_administrador, a.fecha, a.accion, a.entidad, a.id_entidad,
       a.ip, a.motivo, a.cambios
FROM public.admin_operacion_audit a
CROSS JOIN corte c
WHERE a.rol_al_actuar = 'administrador'
  AND a.accion NOT LIKE 'denegado:%'
  AND a.fecha >= c.desde AND a.fecha < c.hasta
ORDER BY a.id_usuario_actor, a.fecha DESC, a.id_admin_operacion_audit DESC;


-- Q3. RITMO DE COMPRAS POR MINUTO — últimas 2 horas (monitoreo de ventana de alta demanda)
-- nota: cuenta COMPRAS, no transacciones. Los 50 000 TPS de la consigna incluyen lecturas y operaciones
--      SQL; esta consulta no mide TPS ni capacidad. Sirve para observar la forma de la curva de ventas.
-- El ingreso bruto solo suma compras cobradas (pagada / parcialmente_reembolsada / reembolsada);
-- el neto (menos devoluciones) corresponde al reporte financiero de C-04.
WITH corte AS (SELECT CURRENT_TIMESTAMP - INTERVAL '2 hours' AS desde, CURRENT_TIMESTAMP AS hasta)
SELECT date_trunc('minute', c.creada_en)                                         AS minuto,
       count(*)                                                                  AS compras_creadas,
       count(*) FILTER (WHERE c.estado IN ('pagada','parcialmente_reembolsada','reembolsada')) AS compras_cobradas,
       count(*) FILTER (WHERE c.estado = 'pendiente')                            AS compras_pendientes,
       count(*) FILTER (WHERE c.estado IN ('cancelada','expirada'))              AS compras_no_concretadas,
       round(count(*) / 60.0, 2)                                                 AS compras_por_segundo_prom,
       coalesce(sum(c.total) FILTER (WHERE c.estado IN ('pagada','parcialmente_reembolsada','reembolsada')), 0) AS ingreso_bruto_usd
FROM public.compra c
CROSS JOIN corte k
WHERE c.creada_en >= k.desde AND c.creada_en < k.hasta
GROUP BY date_trunc('minute', c.creada_en)
ORDER BY minuto DESC;


-- Q4. EFECTIVIDAD DE INGRESOS POR SALA — día local de hoy (zona IANA de cada cine)

WITH dia AS (
    SELECT ci.id_cine, ci.nombre AS cine,
           date_trunc('day', CURRENT_TIMESTAMP AT TIME ZONE ci.zona_horaria)                           AS ini_local
    FROM public.cine ci
), ventana AS (
    SELECT d.id_cine, d.cine,
           d.ini_local                         AT TIME ZONE ci.zona_horaria AS desde,
           (d.ini_local + INTERVAL '1 day')    AT TIME ZONE ci.zona_horaria AS hasta
    FROM dia d INNER JOIN public.cine ci ON ci.id_cine = d.id_cine
)
SELECT v.cine, s.id_sala, s.nombre AS sala,
       count(*) FILTER (WHERE l.resultado = 'aceptado')  AS ingresos_aceptados,
       count(*) FILTER (WHERE l.resultado = 'rechazado') AS ingresos_rechazados,
       count(*)                                          AS escaneos,
       round(100.0 * count(*) FILTER (WHERE l.resultado = 'aceptado') / NULLIF(count(*), 0), 2) AS porcentaje_aceptados
FROM public.acceso_puerta_log l
INNER JOIN public.funcion f ON f.id_funcion = l.id_funcion_solicitada
INNER JOIN public.sala s    ON s.id_sala    = f.id_sala
INNER JOIN ventana v        ON v.id_cine    = s.id_cine
WHERE l.fecha >= v.desde AND l.fecha < v.hasta
GROUP BY v.cine, s.id_sala, s.nombre
ORDER BY v.cine, s.id_sala;