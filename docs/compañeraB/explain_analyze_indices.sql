-- PARTE 1: datos de prueba genera ~100.000 compras sinteticas
BEGIN;
-- Eliminar temporalmente el índice de boletos para permitir la carga masiva sintética en pocos asientos
DROP INDEX IF EXISTS uq_boleto_vigente;

CREATE TEMP TABLE _sint ON COMMIT DROP AS
WITH base AS (
    SELECT (SELECT COALESCE(MAX(id_compra), 0) FROM compra) + g AS id_compra, g
      FROM generate_series(1, 100000) AS g
), cli AS (
    SELECT array_agg(id_usuario ORDER BY id_usuario) AS ids FROM usuario
), asi AS (
    SELECT array_agg(id_asiento ORDER BY id_asiento) AS ids FROM asiento
), fun AS (
    SELECT MIN(id_funcion) AS id_funcion FROM funcion
)
SELECT b.id_compra,
       cli.ids[1 + (b.g % cardinality(cli.ids))] AS id_usuario,
       asi.ids[1 + (b.g % cardinality(asi.ids))] AS id_asiento,
       fun.id_funcion,
       now() - (random() * interval '365 days') AS creada_en
  FROM base b CROSS JOIN cli CROSS JOIN asi CROSS JOIN fun;

-- Agregar el precio de la tarifa (categoria 1) de la zona de cada asiento
ALTER TABLE _sint ADD COLUMN id_tarifa INT;
ALTER TABLE _sint ADD COLUMN monto NUMERIC(12,2);

UPDATE _sint s
   SET id_tarifa = t.id_tarifa, monto = t.monto
  FROM asiento a
  JOIN LATERAL (SELECT t2.id_tarifa, t2.monto
                  FROM tarifa t2
                 WHERE t2.id_zona = a.id_zona AND t2.id_categoria_entrada = 1
                 ORDER BY t2.vigente_desde DESC LIMIT 1) t ON true
 WHERE a.id_asiento = s.id_asiento;

DELETE FROM _sint WHERE id_tarifa IS NULL;

-- Insertar en compra (respetando el CHECK de estado 'Pagada')
INSERT INTO compra (id_compra, id_usuario_cliente, id_usuario_actor, id_funcion,
                    estado, total, moneda, creada_en)
OVERRIDING SYSTEM VALUE
SELECT id_compra, id_usuario, id_usuario, id_funcion,
       'Pagada', monto, 'USD', creada_en
  FROM _sint;

-- Insertar en compra_detalle
INSERT INTO compra_detalle (id_compra, id_asiento, id_categoria_entrada, id_tarifa,
                            precio_base, total_linea)
SELECT id_compra, id_asiento, 1, id_tarifa, monto, monto
  FROM _sint;

-- Insertar en pago (respetando el CHECK de estado 'Aprobado')
INSERT INTO pago (id_compra, estado, metodo, referencia, monto, moneda, creado_en)
SELECT id_compra, 'Aprobado',
       (ARRAY['tarjeta', 'transferencia', 'efectivo'])[1 + (id_compra % 3)::int],
       'SINT-PAGO-' || id_compra, monto, 'USD', creada_en
  FROM _sint;

-- Insertar en boleto con las columnas reales de la tabla
INSERT INTO boleto (id_compra, id_funcion, id_asiento, estado, emitido_en)
SELECT id_compra, id_funcion, id_asiento, 'Emitido', creada_en
  FROM _sint;

-- Que el contador de ids siga despues del ultimo id insertado
SELECT setval(pg_get_serial_sequence('compra', 'id_compra'),
              (SELECT MAX(id_compra) FROM compra));

COMMIT;

ANALYZE compra;
ANALYZE compra_detalle;
ANALYZE pago;
ANALYZE boleto;

-- Comprobar: debe decir mas de 90.000 pagos
SELECT count(*) AS pagos_sinteticos FROM pago WHERE referencia LIKE 'SINT-PAGO-%';


-- PARTE 2: Antes del indice
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) AS pagos, SUM(monto) AS total
  FROM pago
 WHERE estado = 'Aprobado'
   AND creado_en >= now() - interval '7 days';

-- PARTE 3: crear el indice
CREATE INDEX idx_pago_aprobado_fecha
    ON pago (creado_en)
 WHERE estado = 'Aprobado';

ANALYZE pago;

-- PARTE 4: Se debe ejecutar la parte dos después de crear los indices.


-- En caso de que se desee borrar los datos de prueba:
-- DELETE FROM boleto d USING pago p WHERE d.id_compra = p.id_compra AND p.referencia LIKE 'SINT-PAGO-%';
-- DELETE FROM compra_detalle cd USING pago p WHERE cd.id_compra = p.id_compra AND p.referencia LIKE 'SINT-PAGO-%';
-- DELETE FROM compra c USING pago p WHERE c.id_compra = p.id_compra AND p.referencia LIKE 'SINT-PAGO-%';
-- DELETE FROM pago WHERE referencia LIKE 'SINT-PAGO-%';
