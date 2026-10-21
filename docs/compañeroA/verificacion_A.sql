-- Verificación adicional sobre los datos de ejemplo, sin dejarlos modificados.
-- Ejecutar después de relacional_A.sql, ajuste_integridad_A.sql y datos_A.sql.
-- En psql usar ON_ERROR_STOP=1. Cada rechazo se comprueba en un bloque EXCEPTION.
BEGIN;

DO $$
BEGIN
    IF (SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE') <> 12 THEN
        RAISE EXCEPTION 'Se esperaban 12 tablas en public.';
    END IF;
    IF (SELECT COUNT(*) FROM tarifa) <> 8 THEN
        RAISE EXCEPTION 'Se esperaban 8 tarifas de ejemplo.';
    END IF;
    IF (SELECT COUNT(*) FROM asiento a JOIN zona z ON a.id_zona = z.id_zona
        WHERE z.id_sala = 1) <> 6 THEN
        RAISE EXCEPTION 'Se esperaban 6 asientos en la sala 1.';
    END IF;
    RAISE NOTICE 'OK: 12 tablas, 8 tarifas y capacidad derivada de 6.';
END;
$$;

-- Datos auxiliares: una sala y una zona ajenas a la función de ejemplo.
INSERT INTO sala (id_sala, id_cine, nombre) VALUES (-2, 1, 'Sala auxiliar');
INSERT INTO zona (id_zona, id_sala, nombre) VALUES (-2, -2, 'Zona auxiliar');

DO $$
BEGIN
    BEGIN
        INSERT INTO asiento (id_zona, fila, numero) VALUES (1, 'A', 1);
        RAISE EXCEPTION 'ERROR: se aceptó un asiento duplicado.';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'OK: asiento duplicado rechazado.';
    END;
    BEGIN
        INSERT INTO pelicula (titulo, sinopsis, clasificacion, duracion_min, poster_url)
        VALUES ('Prueba', 'Prueba', 'Todo público', -10, '/prueba.png');
        RAISE EXCEPTION 'ERROR: se aceptó duración negativa.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: duración negativa rechazada.';
    END;
    BEGIN
        INSERT INTO funcion (id_pelicula, id_sala, inicio, fin)
        VALUES (1, 1, '2026-11-01 20:00-06', '2026-11-01 18:00-06');
        RAISE EXCEPTION 'ERROR: se aceptó horario invertido.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: horario invertido rechazado.';
    END;
    BEGIN
        INSERT INTO tarifa (id_funcion, id_zona, id_categoria_entrada, monto,
                            vigente_desde, vigente_hasta)
        VALUES (1, 1, 1, -5, '2026-10-01 00:00-06', '2026-11-01 18:00-06');
        RAISE EXCEPTION 'ERROR: se aceptó monto negativo.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: monto negativo rechazado.';
    END;
    BEGIN
        INSERT INTO sala (id_cine, nombre) VALUES (-1, 'Cine inexistente');
        RAISE EXCEPTION 'ERROR: se aceptó cine inexistente.';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'OK: cine inexistente rechazado.';
    END;
    BEGIN
        INSERT INTO tarifa (id_funcion, id_zona, id_categoria_entrada, monto,
                            vigente_desde, vigente_hasta)
        VALUES (1, -2, 1, 8, '2026-10-01 00:00-06', '2026-11-01 18:00-06');
        RAISE EXCEPTION 'ERROR: se aceptó tarifa de zona ajena.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: tarifa de zona ajena rechazada al insertar.';
    END;
    BEGIN
        UPDATE tarifa SET id_zona = -2 WHERE id_tarifa = 1;
        RAISE EXCEPTION 'ERROR: se aceptó tarifa de zona ajena al actualizar.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: tarifa de zona ajena rechazada al actualizar.';
    END;
    BEGIN
        UPDATE funcion SET id_sala = -2 WHERE id_funcion = 1;
        RAISE EXCEPTION 'ERROR: se permitió mover una función con tarifas.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: cambio de sala de función con tarifas rechazado.';
    END;
    BEGIN
        UPDATE zona SET id_sala = -2 WHERE id_zona = 1;
        RAISE EXCEPTION 'ERROR: se permitió mover una zona con tarifas.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: cambio de sala de zona con tarifas rechazado.';
    END;

    -- No bloquear actualizaciones que conservan la relación correcta.
    UPDATE tarifa SET monto = 8.50 WHERE id_tarifa = 1;
    UPDATE funcion SET id_sala = id_sala WHERE id_funcion = 1;
    UPDATE zona SET id_sala = id_sala WHERE id_zona = 1;
    UPDATE zona SET id_sala = 1 WHERE id_zona = -2;
    RAISE NOTICE 'OK: cambios válidos aceptados, incluida zona sin tarifas.';
END;
$$;

-- Dos funciones pueden referir a la misma sala y sus asientos físicos.
INSERT INTO funcion (id_pelicula, id_sala, inicio, fin)
VALUES (1, 1, '2026-11-02 18:00-06', '2026-11-02 20:00-06');
SELECT COUNT(*) AS funciones_sala_1 FROM funcion WHERE id_sala = 1;

ROLLBACK;
