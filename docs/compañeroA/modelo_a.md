# Modelo de catálogo, salas y programación

## Alcance

Este modelo corresponde al bloque A y al issue [A-01](https://github.com/Mauriart/BD_IMAX/issues/2). Representa cines, salas, distribución de asientos, películas, funciones, tarifas y promociones. Reservas, ventas, pagos, boletos, usuarios y auditoría se integrarán con los otros bloques.

El diseño conceptual está en [el Chen](modelochenA%20%281%29.png) y en su [archivo editable](copiamodeloA.drawio). El esquema implementado se encuentra en [relacional_A.sql](relacional_A.sql).

## Paso del Chen a tablas

- Cada entidad se convierte en una tabla con identificador `SERIAL PRIMARY KEY`.
- Las relaciones 1:N se representan con una FK de tipo `INT` en el lado N, declarada mediante `CONSTRAINT fk_... FOREIGN KEY (...) REFERENCES ...`.
- El género multivalorado de Película se transforma en `genero` y `pelicula_genero`.
- La relación N:M entre Función y Promoción se transforma en `funcion_promocion`.
- Las tablas intermedias tienen PK compuesta, para impedir repetir una asociación.
- La capacidad de Sala es derivada: se cuentan los asientos a través de sus zonas. No se guarda una columna de capacidad.
- La sala de un asiento se obtiene mediante su zona; no se duplica `id_sala` en `asiento`.
- El asiento no guarda disponibilidad global: ese estado dependerá de la función en el inventario de B.

## Modelo relacional

| Tabla | PK | FK | Otras restricciones de unicidad |
| --- | --- | --- | --- |
| cine | id_cine | — | — |
| pelicula | id_pelicula | — | — |
| genero | id_genero | — | nombre |
| categoria_entrada | id_categoria_entrada | — | nombre |
| promocion | id_promocion | — | — |
| sala | id_sala | id_cine → cine | (id_cine, nombre) |
| zona | id_zona | id_sala → sala | (id_sala, nombre) |
| asiento | id_asiento | id_zona → zona | (id_zona, fila, numero) |
| funcion | id_funcion | id_pelicula → pelicula; id_sala → sala | — |
| tarifa | id_tarifa | id_funcion → funcion; id_zona → zona; id_categoria_entrada → categoria_entrada | — |
| pelicula_genero | (id_pelicula, id_genero) | id_pelicula → pelicula; id_genero → genero | La PK impide parejas repetidas. |
| funcion_promocion | (id_funcion, id_promocion) | id_funcion → funcion; id_promocion → promocion | La PK impide parejas repetidas. |

## Diccionario de datos

Todas las columnas son obligatorias. En los identificadores, `SERIAL` genera valores enteros mediante una secuencia; una PK también impide duplicados y valores nulos. Las columnas FK son enteros que deben referir a registros existentes.

| Tabla | Columna | Tipo | Significado y restricción |
| --- | --- | --- | --- |
| cine | id_cine | SERIAL | Identificador; PK. |
| cine | nombre | VARCHAR(100) | Nombre del cine. |
| cine | ubicacion | TEXT | Ubicación del establecimiento. |
| cine | zona_horaria | VARCHAR(100) | Nombre de zona horaria; el SQL actual no valida el catálogo IANA. |
| pelicula | id_pelicula | SERIAL | Identificador; PK. |
| pelicula | titulo | VARCHAR(200) | Título de la película. |
| pelicula | sinopsis | TEXT | Descripción de la película. |
| pelicula | clasificacion | VARCHAR(30) | Clasificación de público. |
| pelicula | duracion_min | INT | Duración en minutos; mayor que cero. |
| pelicula | poster_url | TEXT | Ruta o dirección del póster; su existencia no se comprueba con el DDL. |
| genero | id_genero | SERIAL | Identificador; PK. |
| genero | nombre | VARCHAR(50) | Nombre único del género. |
| categoria_entrada | id_categoria_entrada | SERIAL | Identificador; PK. |
| categoria_entrada | nombre | VARCHAR(50) | Nombre único de la categoría. |
| categoria_entrada | requiere_acreditacion | BOOLEAN | Indica acreditación en puerta; predeterminado FALSE. |
| promocion | id_promocion | SERIAL | Identificador; PK. |
| promocion | nombre | VARCHAR(100) | Nombre de la promoción. |
| promocion | tipo | VARCHAR(30) | Tipo, por ejemplo 2x1; sin catálogo restringido en el DDL actual. |
| promocion | condicion | TEXT | Descripción de las condiciones; no es una regla ejecutable por sí sola. |
| promocion | vigente_desde | TIMESTAMPTZ | Instante inicial de vigencia. |
| promocion | vigente_hasta | TIMESTAMPTZ | Instante final, posterior al inicial. |
| promocion | activa | BOOLEAN | Habilitación; predeterminado TRUE. |
| sala | id_sala | SERIAL | Identificador; PK. |
| sala | id_cine | INT | FK al cine al que pertenece. |
| sala | nombre | VARCHAR(100) | Nombre único dentro de su cine. |
| zona | id_zona | SERIAL | Identificador; PK. |
| zona | id_sala | INT | FK a la sala a la que pertenece. |
| zona | nombre | VARCHAR(50) | Nombre único dentro de su sala. |
| asiento | id_asiento | SERIAL | Identificador; PK. |
| asiento | id_zona | INT | FK a la zona a la que pertenece. |
| asiento | fila | VARCHAR(10) | Fila dentro de la zona. |
| asiento | numero | INT | Número positivo; (zona, fila, número) único. |
| funcion | id_funcion | SERIAL | Identificador; PK. |
| funcion | id_pelicula | INT | FK a la película proyectada. |
| funcion | id_sala | INT | FK a la sala asignada. |
| funcion | inicio | TIMESTAMPTZ | Instante de inicio. |
| funcion | fin | TIMESTAMPTZ | Instante de fin, posterior al inicio. |
| funcion | activa | BOOLEAN | Habilitación; predeterminado TRUE. |
| tarifa | id_tarifa | SERIAL | Identificador; PK. |
| tarifa | id_funcion | INT | FK a la función. |
| tarifa | id_zona | INT | FK a la zona tarifada. |
| tarifa | id_categoria_entrada | INT | FK a la categoría de entrada. |
| tarifa | monto | NUMERIC(12,2) | Precio exacto, mayor o igual que cero. |
| tarifa | moneda | VARCHAR(3) | Solo USD; predeterminado USD. |
| tarifa | vigente_desde | TIMESTAMPTZ | Instante inicial de vigencia. |
| tarifa | vigente_hasta | TIMESTAMPTZ | Instante final, posterior al inicial. |
| pelicula_genero | id_pelicula | INT | FK a película y parte de la PK compuesta. |
| pelicula_genero | id_genero | INT | FK a género y parte de la PK compuesta. |
| funcion_promocion | id_funcion | INT | FK a función y parte de la PK compuesta. |
| funcion_promocion | id_promocion | INT | FK a promoción y parte de la PK compuesta. |

`TIMESTAMPTZ` representa un instante; la visualización depende de la zona de la sesión. La zona local del cine se guarda por separado. `NOT NULL` impide ausencia de valor, pero no rechaza textos vacíos.

## Normalización

### Primera forma normal

Cada columna guarda un solo valor del dominio elegido. Los géneros de una película no se almacenan como una lista separada por comas: cada asociación ocupa una fila en `pelicula_genero`. Lo mismo ocurre con las promociones de una función.

### Segunda forma normal

En cada tabla de PK simple, el identificador determina sus atributos: por ejemplo, `id_pelicula → titulo, sinopsis, clasificacion, duracion_min, poster_url`. Las tablas de PK compuesta solo contienen los dos identificadores de la relación, sin atributos que dependan de una sola parte de la clave.

### Tercera forma normal

Los datos descriptivos se guardan en su entidad. `funcion` referencia película y sala sin copiar título, duración o nombre de sala; `sala` referencia cine sin repetir su ubicación; `asiento` referencia zona sin repetir la sala. Así, actualizar un dato descriptivo no exige modificar todas sus referencias.

Dependencias y claves alternativas relevantes:

- `id_cine → nombre, ubicacion, zona_horaria`.
- `id_sala → id_cine, nombre`; (id_cine, nombre) también identifica una sala.
- `id_zona → id_sala, nombre`; (id_sala, nombre) también identifica una zona.
- `id_asiento → id_zona, fila, numero`; (id_zona, fila, numero) también identifica un asiento.
- `id_funcion → id_pelicula, id_sala, inicio, fin, activa`.
- `id_tarifa → id_funcion, id_zona, id_categoria_entrada, monto, moneda, vigente_desde, vigente_hasta`.
- `id_promocion → nombre, tipo, condicion, vigente_desde, vigente_hasta, activa`.
- En género y categoría, tanto el ID como el nombre único son claves candidatas.

El diseño evita duplicación descriptiva y dependencias parciales/transitivas bajo estas reglas. Esto no sustituye las restricciones temporales o de negocio pendientes.

## Restricciones implementadas y límites

El DDL impide referencias inexistentes, asociaciones duplicadas, nombres de sala/zona repetidos dentro de su propietario, asientos repetidos dentro de una zona, duraciones y números de asiento no positivos, precios negativos, monedas diferentes de USD y vigencias/horarios invertidos.

[ajuste_integridad_A.sql](ajuste_integridad_A.sql) comprueba además que la zona de una tarifa pertenezca a la sala de su función, al insertar o actualizar la tarifa. También impide reasignar de sala una función o zona que ya tenga tarifas. Esta regla conserva la relación sin duplicar id_sala en tarifa ni modificar el Chen. Se verifican primero los datos existentes y se detiene el ajuste si hay una incoherencia.

La validación utiliza triggers: se ejecutan automáticamente en las escrituras y sus errores revierten la operación. Los bloqueos de fila FOR SHARE mantienen las referencias estables durante la comprobación. Referencias: [triggers de PostgreSQL](https://www.postgresql.org/docs/18/trigger-definition.html) y [bloqueos de fila](https://www.postgresql.org/docs/18/explicit-locking.html#LOCKING-ROWS).

La numeración se identifica por zona, fila y número: puede repetirse en otra zona de la sala. La zona forma parte de la ubicación del asiento.

Todavía deben implementarse y verificarse:

- Evitar traslapes de funciones considerando limpieza y concurrencia (A-02).
- Impedir vigencias superpuestas para función, zona y categoría.
- Aplicar filtros de cartelera, promociones y acreditación en los flujos reales (A-03).
- Proteger distribución con reservas/ventas activas, permisos y auditoría (A-04 e integración B/C).

El modelo actual usa `SERIAL`, obtiene sala mediante zona y conserva las condiciones de promoción como texto, según el desarrollo simplificado. Estas decisiones se deben conciliar con las especificaciones generales al integrar; no se deben dar por implementadas columnas o reglas distintas solo por figurar en los acuerdos iniciales.

## Uso de los scripts

1. Ejecutar [relacional_A.sql](relacional_A.sql) en una base de prueba sin estas tablas.
2. Ejecutar [ajuste_integridad_A.sql](ajuste_integridad_A.sql). Si las 12 tablas ya existen, ejecutar solo este ajuste; no volver a crear tablas ni cargar datos.
3. En una instalación nueva, ejecutar [datos_A.sql](datos_A.sql) por secciones. Espera IDs desde 1; comprobar los SELECT y ajustar referencias si las secuencias ya se utilizaron. No es una carga repetible sobre datos existentes.
4. Ejecutar [consultas_A.sql](consultas_A.sql) para revisar funciones, tarifas y capacidad.
5. Ejecutar cada sentencia de [pruebas_A.sql](pruebas_A.sql) por separado: todas deben fallar. Si la sesión queda abortada, usar Rollback antes de continuar. Confirmar primero los datos válidos para no perderlos.
6. Para repetir las comprobaciones adicionales sobre el conjunto de ejemplo, ejecutar [verificacion_A.sql](verificacion_A.sql). Comprueba los errores esperados y termina con ROLLBACK para retirar sus cambios auxiliares. Las secuencias pueden avanzar aunque se reviertan los registros.

La carga representa un cine, una sala, dos zonas, seis asientos, una película, dos géneros, cuatro categorías, una función, ocho tarifas y una promoción. La imagen del póster es una ruta de ejemplo, no un recurso incluido. Las fechas de función/vigencias son fijas; deberán actualizarse para demostraciones posteriores al 1 de noviembre de 2026.

Los archivos recibidos tenían nombres y contenidos cruzados: `datos_A.sql` contenía consultas y `consultas_A.sql` repetía pruebas. Aquí las consultas están en su archivo correspondiente y la carga se reconstruye a partir de los INSERT sencillos utilizados. Los originales locales no se modifican.

Los resultados y límites de verificación están en [pruebas_a.md](pruebas_a.md). Este material se integrará con los otros bloques en el diseño y las pruebas del informe final; no constituye un informe final independiente.

## Entrega de A-01

Se revisó la correspondencia Chen–SQL: relaciones 1:N mediante FK; género multivalorado y promoción/función mediante tablas puente; capacidad derivada sin columna almacenada. Las 12 tablas y las 50 columnas están descritas arriba. Los [campos y firmas para B/C](contratos_a.md) completan el contrato inicial del módulo.

La instalación limpia, los datos y los rechazos se verificaron en una instancia temporal independiente. La integración real con B/C y las operaciones de A-02/A-03/A-04 se realizan en sus tareas; no son una condición pendiente del diseño parcial A-01. Por indicación de Mauriart, esta entrega se completa sin requerir revisión de otra persona ni PR adicional.
