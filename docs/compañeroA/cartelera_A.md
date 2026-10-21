# Cartelera — bloque A

## Alcance implementado

La ruta `/cartelera` muestra películas agrupadas con sus próximas funciones. Cada película presenta título, sinopsis, clasificación, duración, géneros y póster si su dirección está disponible. Cada horario indica cine, sala, ubicación y zona horaria.

Solo aparecen funciones activas cuyo inicio sea posterior al momento de la consulta. Una función que ya comenzó deja de aparecer. La fecha del filtro corresponde al día local del cine, no al día UTC.

Los filtros por cine/ubicación, fecha y género pueden utilizarse juntos. Una película con varios géneros no duplica sus horarios. Los filtros inválidos presentan un mensaje y las búsquedas sin coincidencias muestran un estado vacío.

El formulario de agregar o editar películas permite seleccionar varios géneros del catálogo existente. La película y sus asociaciones se guardan en una misma transacción. Los géneros son opcionales; quitar todas las selecciones elimina sus asociaciones sin eliminar la película.

## Consulta reutilizable

`consultar_funciones(id_cine=None, fecha_local=None, id_genero=None)` en `dev/cartelera.py` devuelve una lista de diccionarios con los identificadores de función, película, sala y cine; los metadatos de la película; los nombres de sala y cine; ubicación, zona horaria, inicio local y lista de géneros.

Los parámetros opcionales filtran por igualdad y se envían como parámetros SQL. El filtro de género utiliza `EXISTS` para evitar multiplicar filas. Los resultados se ordenan por inicio de función.

## Verificación

Desde `dev`, con la conexión configurada en `.env`:

```powershell
.\.venv\Scripts\python.exe verificar_a02.py
.\.venv\Scripts\python.exe verificar_cartelera_a03.py
```

Las 11 pruebas de A-02 y las 5 pruebas de cartelera pasaron. Estas últimas verifican funciones futuras y activas, agrupación sin duplicados, filtros combinados, fecha local cercana a medianoche, filtros inválidos, búsquedas vacías y guardado/edición de géneros. Los ensayos crean un esquema temporal propio y lo eliminan al terminar; requieren permiso `CREATE` en la base de prueba.

Se verificó en navegador la cartelera y una búsqueda combinada por cine, fecha y género.

## Prueba manual

1. Iniciar la aplicación y abrir `/cartelera`.
2. Comprobar que cada película agrupa sus horarios y muestra sus metadatos.
3. Elegir un cine, una fecha con funciones y un género de la película; buscar y comprobar los horarios.
4. Probar una fecha sin funciones y después limpiar los filtros.
5. Editar los géneros de una película desde Películas y comprobar el cambio en la búsqueda.

## Tarifas y promociones de A-03

Cada horario ofrece **Ver precios**, con la matriz por zona/categoría y las promociones aplicables. La configuración, el ajuste SQL y los contratos para B están documentados en [tarifas_promociones_A.md](tarifas_promociones_A.md). La integración con B debe utilizar esos datos para la venta. El issue permanece abierto mientras se verifica la entrega.
