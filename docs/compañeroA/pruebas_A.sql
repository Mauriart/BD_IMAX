-- Pruebas negativas: ejecutar cada INSERT por separado.
-- Se espera un error en cada caso. Requieren los datos de ejemplo.
-- Si la sesión queda abortada, usar Rollback antes de la siguiente prueba.

INSERT INTO asiento (id_zona, fila, numero)
VALUES (1, 'A', 1);

INSERT INTO pelicula (
    titulo, sinopsis, clasificacion, duracion_min, poster_url
)
VALUES (
    'Película de prueba',
    'Prueba de duración inválida.',
    'Todo público',
    -10,
    '/prueba.png'
);

INSERT INTO funcion (id_pelicula, id_sala, inicio, fin)
VALUES (
    1,
    1,
    '2026-11-01 20:00:00-06:00',
    '2026-11-01 18:00:00-06:00'
);

-- Cine inexistente: debe fallar por fk_sala_cine.
INSERT INTO sala (id_cine, nombre)
VALUES (-1, 'Sala de prueba');

INSERT INTO tarifa (
    id_funcion, id_zona, id_categoria_entrada,
    monto, moneda, vigente_desde, vigente_hasta
)
VALUES (
    1, 1, 1, -5.00, 'USD',
    '2026-10-01 00:00:00-06:00',
    '2026-11-01 18:00:00-06:00'
);
