-- Función, película, sala y cine.
SELECT
    cine.nombre AS cine,
    sala.nombre AS sala,
    pelicula.titulo AS pelicula,
    funcion.inicio,
    funcion.fin
FROM funcion
INNER JOIN sala ON funcion.id_sala = sala.id_sala
INNER JOIN cine ON sala.id_cine = cine.id_cine
INNER JOIN pelicula ON funcion.id_pelicula = pelicula.id_pelicula;

-- Tarifas por función, zona y categoría.
SELECT
    funcion.id_funcion,
    pelicula.titulo,
    zona.nombre AS zona,
    categoria_entrada.nombre AS categoria,
    tarifa.monto,
    tarifa.moneda
FROM tarifa
INNER JOIN funcion
    ON tarifa.id_funcion = funcion.id_funcion
INNER JOIN pelicula
    ON funcion.id_pelicula = pelicula.id_pelicula
INNER JOIN zona
    ON tarifa.id_zona = zona.id_zona
INNER JOIN categoria_entrada
    ON tarifa.id_categoria_entrada =
       categoria_entrada.id_categoria_entrada
ORDER BY zona.nombre, tarifa.monto;

SELECT
    sala.id_sala,
    sala.nombre,
    COUNT(asiento.id_asiento) AS capacidad
FROM sala
LEFT JOIN zona
    ON sala.id_sala = zona.id_sala
LEFT JOIN asiento
    ON zona.id_zona = asiento.id_zona
GROUP BY sala.id_sala, sala.nombre;
