-- C-07 · Verificación de los reportes 1, 2 y 4 contra resultados conocidos.
-- Ejecutar como postgres sobre imax_c07_rep después de c07_fixture_reportes.sql.
-- Cualquier diferencia aborta con ASSERTION FAILED. El reporte 3 está bloqueado (falta `pago`).
\set ON_ERROR_STOP on
\echo '== Reporte 1: ocupación y recaudación por función =='

CREATE OR REPLACE TEMP VIEW rep1 AS
WITH vend AS (
  SELECT f.id_funcion, count(a.id_asiento) AS vendibles
  FROM funcion f
  JOIN zona z ON z.id_sala = f.id_sala
  JOIN asiento a ON a.id_zona = z.id_zona
  GROUP BY f.id_funcion),
ven AS (   -- preagregado: una fila por función, sin multiplicar importes
  SELECT c.id_funcion,
         count(*) FILTER (WHERE b.estado <> 'anulado')                           AS boletos,
         COALESCE(sum(cd.total_linea), 0)                                        AS bruto,
         COALESCE(sum(cd.total_linea) FILTER (WHERE b.estado = 'anulado'), 0)    AS devuelto
  FROM compra c
  JOIN compra_detalle cd ON cd.id_compra = c.id_compra
  JOIN boleto b ON b.id_compra_detalle = cd.id_compra_detalle
  WHERE c.estado IN ('pagada', 'parcialmente_reembolsada', 'reembolsada')
  GROUP BY c.id_funcion)
SELECT v.id_funcion, v.vendibles,
       COALESCE(n.boletos, 0)  AS boletos,
       round(100.0 * COALESCE(n.boletos, 0) / NULLIF(v.vendibles, 0), 2) AS ocupacion_pct,
       COALESCE(n.bruto, 0)    AS bruto,
       COALESCE(n.devuelto, 0) AS devuelto,
       COALESCE(n.bruto, 0) - COALESCE(n.devuelto, 0) AS neto
FROM vend v LEFT JOIN ven n ON n.id_funcion = v.id_funcion;

SELECT * FROM rep1 WHERE id_funcion <= 2 ORDER BY id_funcion;

DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM rep1 WHERE id_funcion = 1;
  ASSERT r.vendibles = 6 AND r.boletos = 3 AND r.ocupacion_pct = 50.00,
         'Reporte 1 / función 1: ocupación incorrecta';
  ASSERT r.bruto = 33.00 AND r.devuelto = 12.00 AND r.neto = 21.00,
         'Reporte 1 / función 1: recaudación incorrecta';
  SELECT * INTO r FROM rep1
   WHERE id_funcion = (SELECT f.id_funcion FROM funcion f JOIN sala s USING (id_sala) WHERE s.nombre = 'R-vacia');
  ASSERT r.vendibles = 4 AND r.boletos = 0 AND r.ocupacion_pct = 0 AND r.neto = 0,
         'Reporte 1 / función sin ventas debe aparecer con ceros';
END $$;

\echo '== Reporte 2: top 5 películas, ventana móvil de 168 h =='
CREATE OR REPLACE TEMP VIEW rep2 AS
SELECT p.id_pelicula, p.titulo, count(*) AS boletos
FROM boleto b
JOIN compra_detalle cd ON cd.id_compra_detalle = b.id_compra_detalle
JOIN compra c ON c.id_compra = cd.id_compra
JOIN funcion f ON f.id_funcion = c.id_funcion
JOIN pelicula p ON p.id_pelicula = f.id_pelicula
WHERE b.emitido_en >= now() - interval '168 hours' AND b.emitido_en < now()
  AND b.estado <> 'anulado'
GROUP BY p.id_pelicula, p.titulo
ORDER BY boletos DESC, p.id_pelicula
LIMIT 5;

SELECT * FROM rep2;
DO $$
DECLARE t text[]; n int[];
BEGIN
  SELECT array_agg(titulo ORDER BY boletos DESC, id_pelicula), array_agg(boletos::int ORDER BY boletos DESC, id_pelicula)
    INTO t, n FROM rep2;
  ASSERT t = ARRAY['Rep P2','Rep P3','Rep P4','Horizonte estelar','Rep P5'], 'Reporte 2: orden/desempate incorrecto: ' || t::text;
  ASSERT n = ARRAY[5,4,4,3,2], 'Reporte 2: conteos incorrectos: ' || n::text;
  -- Rep P6 (1) queda fuera del top 5; Rep P7 (solo boletos >168 h) no aparece; el anulado de P2 no cuenta.
END $$;

\echo '== Reporte 3: métodos de pago =='
\echo 'BLOQUEADO: no existe la tabla pago en el volcado (dependencia B-01/B-03).'

\echo '== Reporte 4: auditoría crítica por administrador =='
SELECT * FROM resumen_auditoria_admin(7);
DO $$
DECLARE n int; r record;
BEGIN
  SELECT count(*) INTO n FROM resumen_auditoria_admin(7);
  ASSERT n = 1, 'Reporte 4: se esperaba 1 fila con la línea base';
  SELECT * INTO r FROM resumen_auditoria_admin(7);
  ASSERT r.id_usuario_actor = 7 AND r.accion = 'prueba' AND r.total = 1, 'Reporte 4: fila incorrecta';
  PERFORM 1 FROM resumen_auditoria_admin(6);       -- contador: permitido
  BEGIN
    PERFORM 1 FROM resumen_auditoria_admin(2);     -- cliente: debe fallar
    RAISE EXCEPTION 'El cliente no debió poder consultar la auditoría';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
\echo 'Verificación de reportes 1, 2 y 4: OK'
