# Interfaz de películas y distribución de salas

## Avance de A-02

La aplicación está en `dev/`. Incluye listado, registro y edición de películas; listado y registro de salas; consulta de distribución; registro de zonas, asientos individuales y filas de asientos; listado, creación y edición de funciones. La capacidad se calcula desde los asientos, sin almacenarla por separado.

`app.py` contiene las operaciones de películas. `salas.py` y `funciones.py` agrupan sus operaciones mediante Blueprints de Flask. Todas las pantallas reutilizan `templates/base.html` y `static/estilos.css`, sin bibliotecas visuales externas.

## Creación de una fila

En la distribución de una sala se seleccionan zona, fila, número inicial y final. El rango incluye ambos extremos: 1 a 20 crea veinte asientos. Se permite un máximo de 1 000 por operación para evitar rangos accidentales excesivos. El formulario individual sigue disponible.

La aplicación verifica números positivos, rango no invertido, longitud de fila y pertenencia de la zona a la sala. Reutiliza un INSERT parametrizado mediante `executemany`, dentro de una sola transacción. Si cualquier asiento ya existe, se revierte todo el lote; no se omiten duplicados ni se guardan filas parciales. El mensaje conserva los datos para corregirlos.

## Pruebas realizadas

Las verificaciones de servidor usaron PostgreSQL con datos temporales revertidos al terminar.

| Caso | Resultado |
| --- | --- |
| Crear sala, zona y asiento individual | Aceptado; capacidad actualizada. |
| Nombres o asiento duplicados | Rechazados con mensaje. |
| Datos vacíos, longitudes excesivas, números inválidos y zona ajena | Rechazados. |
| Crear fila de 1 a 20 | Veinte asientos y capacidad correcta. |
| Lote B1–B5 con B3 ya existente | Rechazado; B1 y B2 también revertidos. Solo permanece el B3 original. |
| Rango invertido, números no enteros o lote mayor de 1 000 | Rechazado. |
| Rango con inicio igual al final | Crea un solo asiento. |
| Doce zonas con veinte asientos cada una | 240 asientos, creados mediante doce cargas por fila. |
| Listado de películas, formulario, salas, detalle y hoja de estilos | Respuestas correctas. |

Se comprobaron 32 casos de la gestión inicial de salas y 28 del lote y sus pantallas, además del escenario de 240 asientos. Se revisó visualmente la navegación, tablas y formulario de filas en el navegador. El CSS adapta las columnas a ventanas estrechas.

Para comprobar manualmente: crear una sala de ejemplo, agregar una zona y generar A1–A20; intentar repetir A1–A20 y verificar el rechazo sin cambios de capacidad. Para probar atomicidad, crear B3 individualmente e intentar después B1–B5: debe conservarse únicamente B3.

## Ejecución local

Desde `dev/`, con la base y el archivo `.env` configurados:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m flask --app app run
```

Si Flask ya estaba ejecutándose sin recarga automática, detenerlo y volverlo a iniciar para cargar los cambios de Python y plantillas. Abrir `http://127.0.0.1:5000`.

## Trabajo pendiente

Por decisión de Mauriart, A-02 se completa en el alcance funcional de A y la integración real de permisos y auditoría con C queda explícitamente en [T-02 / #23](https://github.com/Mauriart/BD_IMAX/issues/23). No se afirma que existan autenticación, autorización por rol o auditoría de escrituras en estas pantallas. La protección de distribución ante reservas o ventas activas pertenece a A-04 y debe integrarse con B. El prototipo actual permite configurar asientos físicos; no representa disponibilidad ni venta de entradas.

## Programación de funciones

El formulario selecciona película, sala, inicio local y estado activo. El servidor obtiene duración y zona horaria desde PostgreSQL; calcula fin = inicio + duración, sin aceptar un fin enviado por el navegador. Los instantes se guardan como TIMESTAMPTZ y se muestran en la zona del cine.

La duración queda fijada en inicio/fin de cada función: editar los metadatos de la película no recalcula automáticamente las funciones existentes. Guardar una función desde su formulario calcula el fin usando la duración de película vigente en ese momento.

El script [programacion_A.sql](programacion_A.sql) instala el trigger ya probado en DBeaver. Se puede reaplicar; primero rechaza horarios existentes incompatibles. Su intervalo ocupado es [inicio, fin + 15 minutos); una siguiente función puede empezar exactamente al terminar esa limpieza. Solo las funciones activas ocupan horario. Reactivar una función también comprueba conflictos.

La escritura bloquea la sala hasta confirmar o revertir la transacción. La protección también reside en el trigger para los INSERT/UPDATE directos. El bloqueo de sala de la aplicación se toma antes de escribir para evitar conversiones simultáneas de bloqueo compartido a exclusivo.

El ajuste de A-01 continúa impidiendo cambiar de sala una función que ya tiene tarifas. El formulario presenta ese rechazo sin alterar la función. El tratamiento futuro de reservas, ventas y reprogramaciones se integra en A-04/T-02.

## Verificación automatizada de A-02

Desde `dev/`:

```powershell
.\.venv\Scripts\python.exe verificar_a02.py
```

La cuenta de conexión debe tener permiso para crear un esquema en la base de prueba. El script crea un esquema propio `ensayo_a02_<uuid>`, instala allí el modelo y los dos ajustes, y lo elimina al terminar. No modifica las tablas de `public`. La instalación y eliminación de ese esquema son parte del ensayo; no se debe ejecutar contra producción.

Resultado obtenido: **11 pruebas aprobadas**, con subcasos de validación. Incluyen:

- Pantallas, estilos, alta/edición de películas y rechazo de metadatos incompletos.
- Salas, zonas, filas de asientos y reversión completa de un lote con duplicados.
- Cálculo de fin y conversión del inicio de Costa Rica a UTC.
- Traslape directo, función anterior incompatible y limpieza insuficiente rechazados.
- Inicio exactamente 15 minutos después del fin aceptado.
- UPDATE incompatible rechazado conservando el horario original; edición válida aceptada.
- Función inactiva aceptada sin ocupar horario y reactivación incompatible rechazada.
- Identificadores inexistentes, fecha inválida y valores manipulados rechazados.
- Cambio de sala de una función con tarifas rechazado.
- Dos conexiones independientes: B se observa esperando un bloqueo en pg_stat_activity; después del COMMIT de A, B rechaza el traslape y queda una sola función en la sala de ensayo.

La prueba de concurrencia repite automáticamente el caso ya confirmado manualmente en DBeaver. No pretende medir capacidad global ni rendimiento de producción.

Orden de instalación desde una base vacía: relacional_A.sql → ajuste_integridad_A.sql → programacion_A.sql → datos_A.sql. En la base de DBeaver el trigger de programación ya estaba instalado; no es necesario volver a cargar datos.

## Guion de comprobación de A-02

1. Agregar una película con todos sus metadatos; intentar otra sin sinopsis y comprobar el rechazo.
2. Editar un título y confirmar que conserva el ID y actualiza sus datos.
3. Crear sala y zona, generar una fila de asientos y comprobar capacidad calculada.
4. Programar función desde el menú Funciones y comprobar que el fin corresponde a la duración.
5. Intentar otro horario incompatible; comprobar el mensaje y que no se creó la función.
6. Probar el límite exacto de limpieza y un UPDATE incompatible.
7. Ejecutar la verificación automatizada para demostrar concurrencia y los casos negativos.
8. Indicar el pendiente de permisos/auditoría de C en T-02; no presentar un rol administrativo simulado como autorización real.

## Integración posterior de permisos y auditoría

El pendiente del paso 8 del guion se implementó para las operaciones actuales de A usando el esquema real de C-01. Antes de probar las pantallas, preparar el acceso local e iniciar sesión como se indica en [permisos_auditoria_A.md](permisos_auditoria_A.md). Los cambios ahora requieren un motivo. Las 11 pruebas funcionales originales siguen aprobadas; se agregaron 15 pruebas específicas de seguridad. T-02 conserva pendiente la integración completa del proyecto.
