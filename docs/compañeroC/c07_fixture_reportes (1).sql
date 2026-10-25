-- C-07 · Fixture de reportes con resultados conocidos.
-- Ejecutar como postgres sobre imax_c07_rep (copia de imax_c07_base).
\set ON_ERROR_STOP on

-- Los 4 boletos de la línea base se fechan hace 1 día para que caigan dentro de 168 h.
UPDATE boleto SET emitido_en = now() - interval '1 day' WHERE id_boleto BETWEEN 1 AND 4;
UPDATE boleto SET usado_en = emitido_en WHERE id_boleto = 2;

DO $$
DECLARE
  r record; v_pel int; v_sala int; v_zona int; v_fn int; v_tar int; v_comp int;
  v_as int; v_det int; i int; n_tot int; v_emit timestamptz; v_est text;
BEGIN
  -- Función SIN ventas (debe aparecer en el reporte 1 con 0 boletos).
  INSERT INTO sala(id_cine, nombre) VALUES (1, 'R-vacia') RETURNING id_sala INTO v_sala;
  INSERT INTO zona(id_sala, nombre) VALUES (v_sala, 'General') RETURNING id_zona INTO v_zona;
  FOR i IN 1..4 LOOP INSERT INTO asiento(id_zona, fila, numero) VALUES (v_zona, 'A', i); END LOOP;
  INSERT INTO funcion(id_pelicula, id_sala, inicio, fin)
  VALUES (1, v_sala, now() + interval '3 days', now() + interval '3 days 2 hours');

  -- Películas del ranking: (titulo, recientes, anulados recientes, antiguos >168 h)
  FOR r IN SELECT * FROM (VALUES
      ('Rep P2', 5, 1, 0), ('Rep P3', 4, 0, 0), ('Rep P4', 4, 0, 0),
      ('Rep P5', 2, 0, 0), ('Rep P6', 1, 0, 0), ('Rep P7', 0, 0, 6)
  ) AS t(titulo, rec, anul, viejos)
  LOOP
    INSERT INTO pelicula(titulo, sinopsis, clasificacion, duracion_min, poster_url)
    VALUES (r.titulo, 'Sinopsis de ' || r.titulo, 'Todo público', 100, '/static/img/x.png')
    RETURNING id_pelicula INTO v_pel;
    INSERT INTO sala(id_cine, nombre) VALUES (1, 'R-' || r.titulo) RETURNING id_sala INTO v_sala;
    INSERT INTO zona(id_sala, nombre) VALUES (v_sala, 'General') RETURNING id_zona INTO v_zona;
    INSERT INTO funcion(id_pelicula, id_sala, inicio, fin)
    VALUES (v_pel, v_sala, now() + interval '2 days', now() + interval '2 days 2 hours')
    RETURNING id_funcion INTO v_fn;
    INSERT INTO tarifa(id_funcion, id_zona, id_categoria_entrada, monto, vigente_desde, vigente_hasta)
    VALUES (v_fn, v_zona, 1, 8, now() - interval '30 days', now() + interval '2 days')
    RETURNING id_tarifa INTO v_tar;
    n_tot := r.rec + r.anul + r.viejos;
    INSERT INTO compra(id_usuario_cliente, id_usuario_actor, id_funcion, estado, total)
    VALUES (2, 2, v_fn, 'pagada', 8 * n_tot) RETURNING id_compra INTO v_comp;
    FOR i IN 1..n_tot LOOP
      INSERT INTO asiento(id_zona, fila, numero) VALUES (v_zona, 'A', i) RETURNING id_asiento INTO v_as;
      INSERT INTO compra_detalle(id_compra, id_asiento, id_categoria_entrada, id_tarifa, precio_base, total_linea)
      VALUES (v_comp, v_as, 1, v_tar, 8, 8) RETURNING id_compra_detalle INTO v_det;
      v_emit := CASE WHEN i <= r.rec + r.anul THEN now() - interval '2 days' ELSE now() - interval '10 days' END;
      v_est  := CASE WHEN i > r.rec AND i <= r.rec + r.anul THEN 'anulado' ELSE 'emitido' END;
      INSERT INTO boleto(id_compra_detalle, estado, emitido_en) VALUES (v_det, v_est, v_emit);
    END LOOP;
  END LOOP;
END $$;
