-- Volumen: 20 películas, 200 salas x 100 asientos, 20.000 funciones, 400.000 compras,
-- 800.000 boletos, 500.000 filas de puerta y 100.000 de auditoría administrativa.
-- Se desactivan triggers (session_replication_role = replica) SOLO para la carga masiva;
-- los datos se generan consistentes con las FK y los CHECK.
\set ON_ERROR_STOP on
\timing on
SET session_replication_role = replica;

CREATE TEMP TABLE perf_base AS SELECT
  (SELECT coalesce(max(id_compra), 0)         FROM compra)         AS max_compra,
  (SELECT coalesce(max(id_boleto), 0)         FROM boleto)         AS max_boleto,
  (SELECT coalesce(max(id_compra_detalle), 0) FROM compra_detalle) AS max_detalle,
  (SELECT coalesce(max(id_funcion), 0)        FROM funcion)        AS max_funcion;

INSERT INTO pelicula(titulo, sinopsis, clasificacion, duracion_min, poster_url)
SELECT 'Perf ' || g, 'Sinopsis sintética ' || g, 'Todo público', 90 + (g % 60), '/static/img/perf_' || g || '.png'
FROM generate_series(1, 19) g;

INSERT INTO usuario(id_rol, nombre, correo, password_hash)
SELECT 5, 'Admin Perf ' || g, 'adminperf' || g || '@imax.test', 'HASH_DE_PRUEBA' FROM generate_series(1, 4) g;

INSERT INTO sala(id_cine, nombre) SELECT 1, 'P-' || g FROM generate_series(1, 200) g;
INSERT INTO zona(id_sala, nombre) SELECT id_sala, 'General' FROM sala WHERE nombre LIKE 'P-%';
INSERT INTO asiento(id_zona, fila, numero)
SELECT z.id_zona, chr(64 + f.n), s.n
FROM zona z
JOIN sala sa ON sa.id_sala = z.id_sala AND sa.nombre LIKE 'P-%'
CROSS JOIN generate_series(1, 10) f(n)
CROSS JOIN generate_series(1, 10) s(n);

-- 100 funciones por sala, separadas 4 h (sin traslapes), entre hace 20 y hace ~3 días
INSERT INTO funcion(id_pelicula, id_sala, inicio, fin)
SELECT pel.ids[1 + ((s.rn + k) % 19)], s.id_sala,
       date_trunc('hour', now()) - interval '20 days' + k * interval '4 hours',
       date_trunc('hour', now()) - interval '20 days' + k * interval '4 hours' + interval '2 hours'
FROM (SELECT id_sala, row_number() OVER (ORDER BY id_sala) AS rn FROM sala WHERE nombre LIKE 'P-%') s
CROSS JOIN generate_series(0, 99) k
CROSS JOIN (SELECT array_agg(id_pelicula ORDER BY id_pelicula) AS ids FROM pelicula WHERE titulo LIKE 'Perf %') pel;

INSERT INTO tarifa(id_funcion, id_zona, id_categoria_entrada, monto, vigente_desde, vigente_hasta)
SELECT f.id_funcion, z.id_zona, 1, 8, f.inicio - interval '30 days', f.inicio
FROM funcion f JOIN zona z ON z.id_sala = f.id_sala
WHERE f.id_funcion > (SELECT max_funcion FROM perf_base);

CREATE TEMP TABLE perf_fz AS
SELECT f.id_funcion, z.id_zona, t.id_tarifa
FROM funcion f JOIN zona z ON z.id_sala = f.id_sala JOIN tarifa t ON t.id_funcion = f.id_funcion
WHERE f.id_funcion > (SELECT max_funcion FROM perf_base);

CREATE TEMP TABLE perf_asiento AS
SELECT a.id_asiento, a.id_zona, row_number() OVER (PARTITION BY a.id_zona ORDER BY a.fila, a.numero) AS idx
FROM asiento a WHERE a.id_zona IN (SELECT id_zona FROM perf_fz);

-- 20 compras por función, 2 asientos cada una (asientos 1..40 de 100): sin doble venta
INSERT INTO compra(id_usuario_cliente, id_usuario_actor, id_funcion, estado, total, creada_en)
SELECT 1 + (f.id_funcion + j) % 2, 1 + (f.id_funcion + j) % 2, f.id_funcion,
       CASE WHEN j % 10 = 0 THEN 'reembolsada' ELSE 'pagada' END, 16,
       now() - ((f.id_funcion * 31 + j * 977) % 2160) * interval '1 hour'
FROM perf_fz f CROSS JOIN generate_series(1, 20) j
ORDER BY f.id_funcion, j;

CREATE TEMP TABLE perf_compra AS
SELECT id_compra, id_funcion, row_number() OVER (PARTITION BY id_funcion ORDER BY id_compra) AS j
FROM compra WHERE id_compra > (SELECT max_compra FROM perf_base);

INSERT INTO compra_detalle(id_compra, id_asiento, id_categoria_entrada, id_tarifa,
                           precio_base, descuento, cargo_servicio, total_linea)
SELECT pc.id_compra, pa.id_asiento, 1, fz.id_tarifa, 8, 0, 0, 8
FROM perf_compra pc
JOIN perf_fz fz ON fz.id_funcion = pc.id_funcion
CROSS JOIN generate_series(1, 2) k
JOIN perf_asiento pa ON pa.id_zona = fz.id_zona AND pa.idx = (pc.j - 1) * 2 + k
ORDER BY pc.id_compra, k;

INSERT INTO boleto(id_compra_detalle, estado, emitido_en, usado_en)
SELECT cd.id_compra_detalle, e.estado, c.creada_en,
       CASE WHEN e.estado = 'usado' THEN LEAST(now(), c.creada_en + interval '1 day') END
FROM compra_detalle cd
JOIN compra c ON c.id_compra = cd.id_compra
CROSS JOIN LATERAL (SELECT CASE WHEN c.estado = 'reembolsada' THEN 'anulado'
                                WHEN cd.id_compra_detalle % 7 = 0 THEN 'usado'
                                ELSE 'emitido' END AS estado) e
WHERE cd.id_compra_detalle > (SELECT max_detalle FROM perf_base)
ORDER BY cd.id_compra_detalle;

-- Log de puerta: 500.000 escaneos sobre boletos reales (coherentes con su función)
INSERT INTO acceso_puerta_log(fecha, id_boleto, id_funcion_solicitada, id_usuario_operador,
                              dispositivo, resultado, motivo)
SELECT LEAST(now(), b.emitido_en + interval '2 days'), b.id_boleto, c.id_funcion, 4 + (g % 2),
       'totem-' || (g % 20 + 1),
       CASE WHEN g % 10 = 0 THEN 'rechazado' ELSE 'aceptado' END,
       CASE WHEN g % 10 = 0 THEN 'Entrada ya utilizada' ELSE 'Acceso concedido exitosamente' END
FROM generate_series(1, 500000) g
JOIN boleto b ON b.id_boleto = (SELECT max_boleto FROM perf_base) + 1 + (g::bigint * 7919) % 800000
JOIN compra_detalle cd ON cd.id_compra_detalle = b.id_compra_detalle
JOIN compra c ON c.id_compra = cd.id_compra;

-- Auditoría administrativa: 100.000 eventos en 120 días, 5 % denegaciones de otros roles
INSERT INTO admin_operacion_audit(fecha, id_usuario_actor, rol_al_actuar, ip, accion, entidad, id_entidad, motivo, cambios)
SELECT now() - ((g::bigint * 104729) % (120 * 24)) * interval '1 hour',
       CASE WHEN g % 20 = 0 THEN 3 ELSE adm.ids[1 + g % cardinality(adm.ids)] END,
       CASE WHEN g % 20 = 0 THEN 'taquillero' ELSE 'administrador' END,
       '10.0.0.' || (1 + g % 250),
       CASE WHEN g % 20 = 0 THEN 'denegado:configurar_tarifas'
            ELSE (ARRAY['update_tarifa','insert_funcion','update_sala','otorgar_cortesia',
                        'reembolso_forzado','cambio_asiento'])[1 + g % 6] END,
       'entidad', g::text, 'Evento sintético ' || g, NULL
FROM generate_series(1, 100000) g
CROSS JOIN (SELECT array_agg(id_usuario ORDER BY id_usuario) AS ids FROM usuario WHERE id_rol = 5) adm;

RESET session_replication_role;
ANALYZE;

SELECT 'pelicula' t, count(*) FROM pelicula UNION ALL SELECT 'funcion', count(*) FROM funcion
UNION ALL SELECT 'compra', count(*) FROM compra UNION ALL SELECT 'boleto', count(*) FROM boleto
UNION ALL SELECT 'acceso_puerta_log', count(*) FROM acceso_puerta_log
UNION ALL SELECT 'admin_operacion_audit', count(*) FROM admin_operacion_audit;
