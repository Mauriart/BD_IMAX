-- Pruebas manuales del margen de limpieza de A-02.
-- Ejecutar cada INSERT por separado en una base de prueba con datos_A.sql
-- y programacion_A.sql aplicados. Se usan pelicula 1 y sala 1.
-- Debe existir la función del 01/11/2026 de 18:00 a 20:00.
-- Confirmar los datos iniciales antes de comenzar.
-- Si un error deja la transacción abortada, ejecutar ROLLBACK antes de seguir.

-- Caso 1: RECHAZADO.
-- La función anterior termina a las 20:00 y la limpieza acaba a las 20:15.
INSERT INTO funcion (
    id_pelicula, id_sala, inicio, fin, activa
)
VALUES (
    1, 1,
    '2026-11-01 20:10:00-06:00',
    '2026-11-01 22:10:00-06:00',
    TRUE
);

-- Caso 2: ACEPTADO.
-- Inicia exactamente al terminar los 15 minutos de limpieza.
-- Si ya se ejecutó y confirmó esta prueba, repetirla producirá un traslape.
INSERT INTO funcion (
    id_pelicula, id_sala, inicio, fin, activa
)
VALUES (
    1, 1,
    '2026-11-01 20:15:00-06:00',
    '2026-11-01 22:15:00-06:00',
    TRUE
);

-- Comprobación: deben aparecer 18:00-20:00 y 20:15-22:15 para ese día.
SELECT id_funcion, id_sala, inicio, fin
FROM funcion
WHERE id_sala = 1
  AND inicio >= '2026-11-01 00:00:00-06:00'
  AND inicio < '2026-11-02 00:00:00-06:00'
ORDER BY inicio;
