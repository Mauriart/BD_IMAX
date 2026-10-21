# Tarifas y promociones — bloque A

## Qué cambió y por qué

El SQL base ya tenía categorías, tarifas, promociones y la asociación función/promoción. Faltaba impedir vigencias superpuestas y guardar condiciones promocionales que B pudiera consultar sin interpretar frases.

[tarifas_promociones_A.sql](tarifas_promociones_A.sql) agrega un trigger y tres tablas. Se instala después de `relacional_A.sql`, `ajuste_integridad_A.sql` y `programacion_A.sql`. Puede reinstalarse sin eliminar registros. Antes de instalar el trigger verifica los datos existentes y se detiene si encuentra tarifas superpuestas.

| Tabla nueva | Clave primaria | Referencias y propósito |
| --- | --- | --- |
| promocion_dia | (id_promocion, dia_semana) | FK a promoción; día ISO de 1 (lunes) a 7 (domingo), con CHECK. |
| promocion_zona | (id_promocion, id_zona) | FK a promoción y zona; permite elegir varias zonas. |
| promocion_categoria | (id_promocion, id_categoria_entrada) | FK a promoción y categoría; permite elegir varias categorías. |

Las PK compuestas impiden repetir una condición. Las FK impiden referencias inexistentes. No se agregan columnas a las doce tablas originales: el esquema extendido de A tiene quince tablas y 56 columnas.

En el modelo conceptual global, promoción debe relacionarse N:M con zona y categoría, y tener día de semana multivalorado. Las tres tablas anteriores representan esa normalización. El PNG y el archivo Chen de A-01 conservan su versión original; esta extensión debe incorporarse al consolidar el DER.

## Validación de tarifas en PostgreSQL

`validar_vigencia_tarifa()` se ejecuta antes de insertar o actualizar una tarifa. Primero bloquea la función correspondiente y después busca otra tarifa con la misma función, zona y categoría cuyos intervalos se crucen. Si la encuentra, rechaza la operación.

El bloqueo coordina escrituras simultáneas: con el aislamiento habitual `READ COMMITTED`, la segunda conexión espera a que termine la primera y comprueba lo que esta confirmó. Se probó esta situación con dos conexiones independientes. Una actualización que cambia de función bloquea ambas en orden de identificador.

Las vigencias se interpretan como `[desde, hasta)`: el inicio está incluido y el final excluido. Por ejemplo, una tarifa que termina a las 12:00 puede ir seguida de otra que empieza exactamente a las 12:00. El trigger de `ajuste_integridad_A.sql` continúa comprobando que la zona pertenezca a la sala de la función.

## Qué hace Python

`dev/precios.py` registra dos pantallas:

- `/funciones/<id_funcion>/precios`: agregar categorías, tarifas y promociones 2x1; consultar las vigencias registradas. Se accede desde **Funciones → Tarifas y promociones**.
- `/cartelera/<id_funcion>/precios`: matriz de precios base vigentes por zona/categoría y promociones aplicables. Se accede mediante **Ver precios** en cada horario de cartelera. Las funciones pasadas o inactivas no ofrecen esta página.

Python valida los formularios y utiliza parámetros SQL. Convierte las vigencias locales a `TIMESTAMPTZ` mediante la zona horaria del cine. Usa `Decimal` para validar dinero, admite cero y rechaza importes negativos, no finitos o con más de dos decimales. La moneda es USD.

Al registrar una promoción, inserta en una sola transacción su descripción, asociación con la función, días, zonas y categorías. Si falla alguna inserción, revierte todo. Se exige al menos una selección en cada grupo; no seleccionar condiciones no significa «todos».

La matriz obtiene las tarifas en una consulta y agrupa los resultados en Python. Una celda sin tarifa vigente o con varias tarifas se muestra como **No disponible**, nunca como precio cero ni como una tarifa seleccionada arbitrariamente.

## Promociones y consumo por B

El tipo implementado es `2x1`. La vigencia se evalúa en el instante de cotización; los días permitidos se comparan con el **día local de inicio de la función**, no con el día en que se consulta. Las zonas deben pertenecer a la sala de la función. La descripción sigue visible, pero las condiciones de días, zonas y categorías proceden de las tablas relacionadas.

Las promociones antiguas que solo tienen texto se conservan, pero no se devuelven como aplicables. Debe registrarse una nueva promoción con las condiciones seleccionadas. El sistema no deduce ni ejecuta reglas a partir de texto.

Operaciones importables desde `precios`:

```python
consultar_tarifas(id_funcion, id_zona, id_categoria_entrada, instante)
consultar_promociones(id_funcion, instante, id_zona=None, id_categoria_entrada=None)
```

`instante` debe ser un `datetime` con zona horaria; B debe utilizar el mismo instante para sus consultas de cotización.

La primera operación devuelve un diccionario con los campos de la tarifa, nombre de zona, nombre de categoría y `requiere_acreditacion`. El monto se conserva como `Decimal`. Lanza `ValueError` si no existe exactamente una tarifa vigente o la función ya no está disponible.

La segunda devuelve una lista ordenada por ID con los campos de promoción y las listas de identificadores `dias`, `zonas` y `categorias`. Los filtros opcionales limitan las promociones a la zona y categoría solicitadas. Solo devuelve promociones activas, de tipo 2x1, vigentes, asociadas a la función y con condiciones completas aplicables. Una lista vacía significa que no hay promoción aplicable.

A entrega datos, no calcula la compra. B debe agrupar parejas de la misma función, zona y categoría; cobrar la entrada sobrante si la cantidad es impar; no acumular promociones; seleccionar el mayor descuento y, en empate, el menor ID. B también distribuye el descuento entre líneas y conserva precio base, descuento y referencias históricos. Estas operaciones de lectura no reservan precios ni sustituyen la transacción de compra de B.

La interfaz agrega nuevas tarifas y promociones, sin editar ni eliminar versiones anteriores. Una nueva tarifa debe tener una vigencia que no cruce otra de la misma combinación. Las restricciones de autorización y auditoría de C siguen pendientes en T-02 (#23); esta entrega corresponde al flujo funcional de A.

## Acreditación física

La categoría devuelve `requiere_acreditacion`, visible tanto al configurar como en la matriz pública. La carga inicial marca niño, estudiante y tercera edad. Una selección en el navegador no prueba la acreditación ni debe impedir que se informe el precio.

C debe verificar en la entrada el documento o credencial que respalde la categoría, siguiendo la política aprobada por el grupo. Esta parte no fija edades, documentos válidos ni una política de rechazo que el grupo no haya definido. Tampoco almacena documentos personales. La consulta de precios y la validación física son pasos distintos.

## Pruebas y resultados

Desde `dev`:

```powershell
.\.venv\Scripts\python.exe verificar_a02.py
.\.venv\Scripts\python.exe verificar_cartelera_a03.py
.\.venv\Scripts\python.exe verificar_precios_a03.py
```

Resultados: 11 pruebas de A-02, 5 de cartelera y 11 de tarifas/promociones aprobadas; 27 en total. Los ensayos utilizan esquemas temporales propios y los eliminan al terminar. No modifican los datos de negocio de `public`.

Las once pruebas de precios cubren:

1. Inicio incluido, final excluido y monto decimal exacto.
2. Cruces rechazados en INSERT/UPDATE y vigencias contiguas permitidas.
3. Formulario de tarifa/categoría y matriz pública con acreditación.
4. Datos inválidos y zonas de otra sala, sin guardar tarifas inválidas.
5. Promoción estructurada, filtros por zona/categoría, límites de vigencia e inactividad.
6. Día local de función cercano a medianoche y promoción antigua incompleta.
7. Condiciones inválidas sin registros parciales.
8. Función pasada, inactiva o inexistente.
9. Dos altas simultáneas de tarifa: espera y rechazo de la segunda.
10. Tarifas ambiguas: la consulta rechaza la cotización incluso sin el trigger.
11. Fallo en la última condición: reversión completa de la promoción.

El ajuste también quedó instalado en `p2/public`. Los conteos se conservaron: cinco funciones, ocho tarifas, una promoción y cuatro categorías. Se revisaron en navegador el formulario administrativo y la matriz pública de la función 1. La promoción antigua aparece como incompleta y no como descuento aplicable.

## Comprobación manual sugerida

1. Reiniciar la aplicación y abrir **Funciones → Tarifas y promociones** de una función futura.
2. Revisar las tarifas existentes. Probar una tarifa con la misma zona/categoría y una vigencia que se cruce: debe rechazarse.
3. Registrar una promoción 2x1 con el día de esa función, una zona y una categoría. Usar una vigencia que incluya el momento actual.
4. Abrir **Cartelera → Ver precios** de esa función: deben aparecer la matriz y la promoción con sus condiciones.
5. Revisar la acreditación de las categorías especiales. La aplicación informa el requisito; C verificará la credencial en puerta.

La integración de cotización e históricos con B y la comprobación física/autorización con C se validan con sus módulos. No se declaran implementadas por estas pruebas aisladas de A.
