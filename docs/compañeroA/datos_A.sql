-- Ejecutar una sola vez después de relacional_A.sql, sobre tablas vacías.
-- Se esperan los IDs desde 1. Comprobar los SELECT y ajustar las FK
-- si las secuencias ya se utilizaron, incluso por intentos fallidos.

INSERT INTO cine (nombre, ubicacion, zona_horaria)
VALUES ('IMAX Central', 'San José, Costa Rica', 'America/Costa_Rica');
SELECT * FROM cine;

INSERT INTO sala (id_cine, nombre)
VALUES (1, 'Sala 1');
SELECT * FROM sala;

INSERT INTO zona (id_sala, nombre)
VALUES (1, 'General'), (1, 'VIP');
SELECT * FROM zona;

INSERT INTO asiento (id_zona, fila, numero)
VALUES (1, 'A', 1), (1, 'A', 2), (1, 'A', 3),
       (2, 'B', 1), (2, 'B', 2), (2, 'B', 3);

INSERT INTO pelicula (
    titulo, sinopsis, clasificacion, duracion_min, poster_url
)
VALUES (
    'Horizonte estelar',
    'Una tripulación explora un planeta desconocido.',
    'Todo público', 120, '/static/img/horizonte_estelar.png'
);
SELECT * FROM pelicula;

INSERT INTO genero (nombre)
VALUES ('Ciencia ficción'), ('Aventura');
SELECT * FROM genero;

INSERT INTO pelicula_genero (id_pelicula, id_genero)
VALUES (1, 1), (1, 2);

INSERT INTO categoria_entrada (nombre, requiere_acreditacion)
VALUES ('Adulto', FALSE), ('Niño', TRUE),
       ('Estudiante', TRUE), ('Tercera edad', TRUE);
SELECT * FROM categoria_entrada;

INSERT INTO funcion (id_pelicula, id_sala, inicio, fin, activa)
VALUES (1, 1, '2026-11-01 18:00:00-06:00',
        '2026-11-01 20:00:00-06:00', TRUE);
SELECT * FROM funcion;

INSERT INTO tarifa (
    id_funcion, id_zona, id_categoria_entrada,
    monto, moneda, vigente_desde, vigente_hasta
)
VALUES
    (1, 1, 1, 8.00, 'USD', '2026-10-01 00:00:00-06:00', '2026-11-01 18:00:00-06:00'),
    (1, 1, 2, 5.00, 'USD', '2026-10-01 00:00:00-06:00', '2026-11-01 18:00:00-06:00'),
    (1, 1, 3, 6.00, 'USD', '2026-10-01 00:00:00-06:00', '2026-11-01 18:00:00-06:00'),
    (1, 1, 4, 5.00, 'USD', '2026-10-01 00:00:00-06:00', '2026-11-01 18:00:00-06:00'),
    (1, 2, 1, 12.00, 'USD', '2026-10-01 00:00:00-06:00', '2026-11-01 18:00:00-06:00'),
    (1, 2, 2, 9.00, 'USD', '2026-10-01 00:00:00-06:00', '2026-11-01 18:00:00-06:00'),
    (1, 2, 3, 10.00, 'USD', '2026-10-01 00:00:00-06:00', '2026-11-01 18:00:00-06:00'),
    (1, 2, 4, 9.00, 'USD', '2026-10-01 00:00:00-06:00', '2026-11-01 18:00:00-06:00');

INSERT INTO promocion (
    nombre, tipo, condicion, vigente_desde, vigente_hasta, activa
)
VALUES (
    'Pareja General', '2x1',
    'Dos entradas de adulto en zona General de la misma función.',
    '2026-10-01 00:00:00-06:00', '2026-11-01 18:00:00-06:00', TRUE
);
SELECT * FROM promocion;

INSERT INTO funcion_promocion (id_funcion, id_promocion)
VALUES (1, 1);
