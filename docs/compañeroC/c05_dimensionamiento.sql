\pset format aligned
\pset border 1
\pset null '-'

DROP TABLE IF EXISTS tmp_sup, tmp_der, tmp_tab, tmp_esc, tmp_res;


-- 1. SUPUESTOS (S-xx). Los S-01..S-02 vienen de la consigna; el resto son del equipo.

CREATE TEMP TABLE tmp_sup (id text PRIMARY KEY, nombre text, valor numeric, fuente text);
INSERT INTO tmp_sup VALUES
 ('S-01','boletos_mes',                    15000000,'Consigna (15 M boletos mensuales)'),
 ('S-02','meses_retencion',                60,      'RN-20 / consigna (mínimo 5 años)'),
 ('S-03','boletos_por_compra',             2.5,     'Equipo: promedio; tope RN-04 = 6'),
 ('S-04','conversion_reserva_a_pago',      0.60,    'Equipo: 60 % de las reservas termina pagada'),
 ('S-05','pct_no_pagadas_que_expiran',     0.75,    'Equipo: el resto son pagos rechazados'),
 ('S-06','pct_colision_sobre_bloqueos',    0.10,    'Equipo: intentos sobre asiento ya tomado (estrenos)'),
 ('S-07','pct_no_show',                    0.05,    'Equipo: boletos que nunca se escanean'),
 ('S-08','pct_rechazo_puerta_sobre_aceptados',0.10, 'Equipo: 2.º escaneo, función/horario/QR inválido'),
 ('S-09','pct_boletos_reembolsados',       0.03,    'Equipo'),
 ('S-10','funciones_mes',                  15000,   'Consigna: 500 funciones diarias x 30 días'),
 ('S-11','filas_tarifa_por_funcion',       12,      'Equipo: 3 zonas x 4 categorías'),
 ('S-12','otros_eventos_admin_mes',        35000,   'Equipo: cortesías, cambios de asiento, políticas, roles y denegados'),
 ('S-13','ocupacion_media',                0.70,    'Equipo (solo para inventario_funcion; ver ambigüedad de capacidad)'),
 ('S-14','meses_calientes',                6,       'Equipo: meses en PostgreSQL (NVMe)'),
 ('S-15','crecimiento_anual',              0.10,    'Ejemplo de la consigna (OPEX +10 %/año)'),
 ('S-16','factor_espacio_operativo',       1.25,    'Equipo: bloat, fillfactor, espacio libre'),
 ('S-17','copias_calientes_extra',         2,       'Equipo: réplica en la región + réplica DR'),
 ('S-18','compresion_archivo',             4.0,     'Equipo: Parquet+zstd; DEBE medirse (no medido)'),
 ('S-19','copias_archivo',                 2,       'Equipo: región principal + región DR'),
 ('S-20','compresion_backup',              2.0,     'Equipo: pgBackRest; DEBE medirse'),
 ('S-21','fulls_retenidos',                5,       'Equipo: 4 semanales + 1 (retención 30 días)'),
 ('S-22','multiplicador_wal',              2.5,     'Equipo: WAL generado / datos+índices insertados; DEBE medirse'),
 ('S-23','tps_pico',                       50000,   'Consigna'),
 ('S-24','segundos_pico',                  600,     'Consigna');


-- 2. VOLÚMENES DERIVADOS (se calculan; no se digitan)

CREATE TEMP TABLE tmp_der AS
WITH s AS (SELECT max(valor) FILTER (WHERE nombre='boletos_mes') AS bol,
                  max(valor) FILTER (WHERE nombre='boletos_por_compra') AS bpc,
                  max(valor) FILTER (WHERE nombre='conversion_reserva_a_pago') AS conv,
                  max(valor) FILTER (WHERE nombre='pct_no_pagadas_que_expiran') AS pexp,
                  max(valor) FILTER (WHERE nombre='pct_colision_sobre_bloqueos') AS pcol,
                  max(valor) FILTER (WHERE nombre='pct_no_show') AS pns,
                  max(valor) FILTER (WHERE nombre='pct_rechazo_puerta_sobre_aceptados') AS prp,
                  max(valor) FILTER (WHERE nombre='pct_boletos_reembolsados') AS pre,
                  max(valor) FILTER (WHERE nombre='funciones_mes') AS fun,
                  max(valor) FILTER (WHERE nombre='filas_tarifa_por_funcion') AS ftf,
                  max(valor) FILTER (WHERE nombre='otros_eventos_admin_mes') AS otr,
                  max(valor) FILTER (WHERE nombre='ocupacion_media') AS ocu FROM tmp_sup)
SELECT bol                                   AS boletos,
       bol/bpc                               AS compras_pagadas,
       bol/bpc/conv                          AS reservas,                 -- = filas de compra/reserva
       bol/bpc/conv - bol/bpc                AS no_convertidas,
       (bol/bpc/conv - bol/bpc)*pexp         AS expiradas,
       (bol/bpc/conv - bol/bpc)*(1-pexp)     AS pagos_rechazados,
       bol + (bol/bpc/conv - bol/bpc)*bpc    AS asientos_bloqueados,      -- vendidos + no convertidos
       bol/bpc + (bol/bpc/conv - bol/bpc)*(1-pexp) AS intentos_pago,
       bol*pre                               AS boletos_reembolsados,
       bol*pre/bpc                           AS solicitudes_reembolso,
       bol*(1-pns)                           AS ingresos_aceptados,
       bol*(1-pns)*prp                       AS ingresos_rechazados,
       pcol                                  AS pcol,
       fun*1.5 + fun*ftf*1.1 + bol*pre/bpc + otr AS eventos_admin,       -- altas/ediciones + tarifas + reembolsos + otros
       (bol/(fun))/ocu*fun                   AS filas_inventario
FROM s;


-- 3. TABLAS: eventos/mes x bytes medidos por fila (pg_relation_size / filas, 300 000 filas sintéticas, PG 16)
--    bytes_heap = datos de la fila con cabecera y relleno; bytes_idx = índices propuestos (ver md §5.3)

CREATE TEMP TABLE tmp_tab (cat text, bloque text, tabla text, ddl text, duena text,
                           eventos_mes numeric, b_heap numeric, b_idx numeric, archivable boolean);
INSERT INTO tmp_tab
SELECT 'L1 Financiero','LOG','transaccion_log','provisional (B pendiente)','B',
       2*intentos_pago + boletos + 2*solicitudes_reembolso, 135, 46, true FROM tmp_der
UNION ALL SELECT 'L2 Inventario','LOG','asiento_auditoria_log','provisional (B pendiente)','B',
       2*asientos_bloqueados + asientos_bloqueados*pcol + boletos_reembolsados, 126, 55, true FROM tmp_der
UNION ALL SELECT 'L3 Puerta','LOG','acceso_puerta_log','existe en imax.sql','C',
       ingresos_aceptados + ingresos_rechazados, 119, 80, true FROM tmp_der
UNION ALL SELECT 'L4 Administración','LOG','admin_operacion_audit','existe en imax.sql','C',
       eventos_admin, 376, 100, true FROM tmp_der
UNION ALL SELECT 'D1 Operativo histórico','OPER','compra','existe en imax.sql','B',reservas,77,76,true FROM tmp_der
UNION ALL SELECT 'D1 Operativo histórico','OPER','compra_detalle','existe en imax.sql','B',asientos_bloqueados,76,52,true FROM tmp_der
UNION ALL SELECT 'D1 Operativo histórico','OPER','boleto','existe en imax.sql','B',boletos,69,85,true FROM tmp_der
UNION ALL SELECT 'D1 Operativo histórico','OPER','pago','provisional (B pendiente)','B',intentos_pago,117,95,true FROM tmp_der
UNION ALL SELECT 'D1 Operativo histórico','OPER','reserva','provisional (B pendiente)','B',reservas,69,45,true FROM tmp_der
UNION ALL SELECT 'D1 Operativo histórico','OPER','reserva_detalle','provisional (B pendiente)','B',asientos_bloqueados,45,32,true FROM tmp_der
UNION ALL SELECT 'D2 Solo operación activa','OPER','inventario_funcion','provisional (B pendiente)','B',filas_inventario,61,23,false FROM tmp_der;


-- 4. ESCENARIOS: A = base sin crecimiento (900 M boletos); B = +10 %/anual

CREATE TEMP TABLE tmp_esc AS
WITH g AS (SELECT valor AS g FROM tmp_sup WHERE nombre='crecimiento_anual'),
     h AS (SELECT valor AS h FROM tmp_sup WHERE nombre='meses_calientes')
SELECT 'A sin crecimiento'::text AS escenario, 60::numeric AS k_total, 1::numeric AS m_ultimo, h AS k_hot FROM h
UNION ALL
SELECT 'B crecimiento anual', 12*(1+(1+g)+power(1+g,2)+power(1+g,3)+power(1+g,4)),
       power(1+g,4), h*power(1+g,4) FROM g, h;
-- k_total = meses-equivalentes acumulados; m_ultimo = multiplicador del mes 60; k_hot = meses-equivalentes calientes


-- 5. RESULTADOS

\echo
\echo '== R1. Volúmenes mensuales derivados (escenario sin crecimiento) =='
SELECT to_char(boletos,'FM999,999,999') boletos, to_char(reservas,'FM999,999,999') reservas_compras,
       to_char(compras_pagadas,'FM999,999,999') compras_pagadas, to_char(asientos_bloqueados,'FM999,999,999') asientos_bloqueados,
       to_char(ingresos_aceptados+ingresos_rechazados,'FM999,999,999') escaneos_puerta,
       to_char(eventos_admin,'FM999,999,999') eventos_admin FROM tmp_der;

\echo
\echo '== R2. Tabla de cálculo por tabla (sin crecimiento, GiB) =='
SELECT cat, tabla, ddl,
       to_char(eventos_mes,'FM999,999,999') AS eventos_mes, b_heap, b_idx,
       round(eventos_mes*b_heap/1073741824.0,2) AS gib_datos_mes,
       round(eventos_mes*b_idx /1073741824.0,2) AS gib_idx_mes,
       round(eventos_mes*b_heap/1073741824.0*60,1) AS gib_datos_60m,
       round(eventos_mes*(b_heap+b_idx)/1073741824.0*60,1) AS gib_datos_idx_60m
FROM tmp_tab ORDER BY cat, tabla;

\echo
\echo '== R3. Resumen por categoría: mensual y acumulado 60 meses, sin crecimiento y con crecimiento (GiB) =='
SELECT t.cat, e.escenario,
       round(sum(t.eventos_mes*(t.b_heap+t.b_idx))/1073741824.0*e.m_ultimo,2)  AS gib_mes_ultimo_mes,
       round(sum(t.eventos_mes*t.b_heap)/1073741824.0*e.k_total,1)             AS gib_datos_60m,
       round(sum(t.eventos_mes*t.b_idx )/1073741824.0*e.k_total,1)             AS gib_indices_60m,
       round(sum(t.eventos_mes*(t.b_heap+t.b_idx))/1073741824.0*e.k_total,1)   AS gib_total_60m
FROM tmp_tab t CROSS JOIN tmp_esc e GROUP BY t.cat, e.escenario, e.k_total, e.m_ultimo
ORDER BY e.escenario, t.cat;

\echo
\echo '== R4. Operación activa vs archivo histórico vs réplicas vs backups, a mes 60 (GiB) =='
CREATE TEMP TABLE tmp_res AS
WITH p AS (SELECT max(valor) FILTER (WHERE nombre='factor_espacio_operativo') fo,
                  max(valor) FILTER (WHERE nombre='copias_calientes_extra') rep,
                  max(valor) FILTER (WHERE nombre='compresion_archivo') ca,
                  max(valor) FILTER (WHERE nombre='copias_archivo') cpa,
                  max(valor) FILTER (WHERE nombre='compresion_backup') cb,
                  max(valor) FILTER (WHERE nombre='fulls_retenidos') fl,
                  max(valor) FILTER (WHERE nombre='multiplicador_wal') wal FROM tmp_sup),
     m AS (SELECT t.bloque, e.escenario, e.k_total, e.m_ultimo, e.k_hot,
                  sum(t.eventos_mes*t.b_heap)/1073741824.0 AS d_mes, sum(t.eventos_mes*t.b_idx)/1073741824.0 AS i_mes,
                  sum(t.eventos_mes*t.b_heap) FILTER (WHERE t.archivable)/1073741824.0 AS d_arch
           FROM tmp_tab t CROSS JOIN tmp_esc e GROUP BY t.bloque, e.escenario, e.k_total, e.m_ultimo, e.k_hot)
SELECT m.bloque, m.escenario,
       (m.d_mes+m.i_mes)*m.k_hot*p.fo                             AS caliente_primario,
       (m.d_mes+m.i_mes)*m.k_hot*p.fo*p.rep                       AS caliente_replicas,
       coalesce(m.d_arch,0)*m.k_total/p.ca*p.cpa                  AS archivo_comprimido_copias,
       (m.d_mes+m.i_mes)*m.k_hot*p.fo/p.cb*p.fl                   AS backup_fulls,
       (m.d_mes+m.i_mes)*m.m_ultimo/p.cb                          AS backup_incrementales_30d,
       (m.d_mes+m.i_mes)*m.m_ultimo*p.wal/p.cb                    AS backup_wal_30d
FROM m CROSS JOIN p;

SELECT bloque, escenario,
       round(caliente_primario,1)  AS primario_nvme,
       round(caliente_replicas,1)  AS replicas_nvme,
       round(archivo_comprimido_copias,1) AS archivo_frio_total,
       round(backup_fulls+backup_incrementales_30d+backup_wal_30d,1) AS backups_30d,
       round(caliente_primario+caliente_replicas+archivo_comprimido_copias+backup_fulls+backup_incrementales_30d+backup_wal_30d,1) AS total_gib,
       round((caliente_primario+caliente_replicas+archivo_comprimido_copias+backup_fulls+backup_incrementales_30d+backup_wal_30d)/1024,2) AS total_tib
FROM tmp_res ORDER BY bloque, escenario;

\echo
\echo '== R5. Totales que se entregan a A-06 (GiB y TiB) =='
SELECT escenario,
       round(sum(caliente_primario),1)       AS primario_nvme_gib,
       round(sum(caliente_replicas),1)       AS replicas_nvme_gib,
       round(sum(archivo_comprimido_copias),1) AS archivo_frio_gib,
       round(sum(backup_fulls+backup_incrementales_30d+backup_wal_30d),1) AS backups_gib,
       round(sum(caliente_primario+caliente_replicas+archivo_comprimido_copias+backup_fulls+backup_incrementales_30d+backup_wal_30d)/1024,2) AS total_tib
FROM tmp_res GROUP BY escenario ORDER BY escenario;

\echo
\echo '== R6. Solo los 4 logs de RN-20 (sin datos operativos), GiB =='
SELECT escenario,
       round(caliente_primario,1) primario_nvme, round(caliente_replicas,1) replicas_nvme,
       round(archivo_comprimido_copias,1) archivo_frio,
       round(backup_fulls+backup_incrementales_30d+backup_wal_30d,1) backups_30d,
       round((caliente_primario+caliente_replicas+archivo_comprimido_copias+backup_fulls+backup_incrementales_30d+backup_wal_30d)/1024,3) AS total_tib
FROM tmp_res WHERE bloque='LOG' ORDER BY escenario;

\echo
\echo '== R7. Ventana pico: 50 000 TPS x 600 s (cota de ingesta; NO se suma al mes) =='
WITH p AS (SELECT max(valor) FILTER (WHERE nombre='tps_pico') tps, max(valor) FILTER (WHERE nombre='segundos_pico') seg,
                  max(valor) FILTER (WHERE nombre='multiplicador_wal') wal FROM tmp_sup),
     r AS (SELECT sum(eventos_mes*(b_heap+b_idx))/sum(eventos_mes) AS b_medio, sum(eventos_mes) AS ev_mes FROM tmp_tab WHERE bloque='LOG')
SELECT to_char(p.tps*p.seg,'FM999,999,999')                      AS operaciones_en_ventana,
       round(r.b_medio)                                           AS bytes_medios_por_evento_log,
       round(p.tps*r.b_medio/1048576.0,1)                              AS mib_s_datos_e_indices_si_todo_fuera_log,
       round(p.tps*r.b_medio*p.wal/1048576.0,1)                        AS mib_s_wal_estimado,
       round(p.tps*p.seg*r.b_medio/1073741824.0,2)                        AS gib_en_la_ventana_cota_superior,
       to_char(r.ev_mes,'FM999,999,999')                          AS eventos_log_mes_modelados,
       round(100*p.tps*p.seg/r.ev_mes,1)                          AS pct_de_eventos_mes_si_todo_fuera_escritura
FROM p, r;
\echo 'Lectura: es una cota para dimensionar IOPS/WAL. La mayoría de las 50 000 operaciones/s son lecturas o intentos'
\echo 'rechazados; los 15 M boletos/mes limitan las ventas confirmadas. No se extrapola el pico al mes.'
