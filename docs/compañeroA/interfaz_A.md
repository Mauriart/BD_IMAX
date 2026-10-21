# Interfaz de películas y distribución de salas

## Avance de A-02

La aplicación está en `dev/`. Incluye listado, registro y edición de películas; listado y registro de salas; consulta de distribución; registro de zonas, asientos individuales y filas de asientos. La capacidad se calcula desde los asientos, sin almacenarla por separado.

`app.py` contiene las operaciones de películas. `salas.py` agrupa las operaciones de salas mediante un Blueprint de Flask. Las cuatro pantallas reutilizan `templates/base.html` y `static/estilos.css`, sin bibliotecas visuales externas.

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

Este avance no cierra A-02. Faltan la interfaz de programación de funciones y la integración de permisos/auditoría con C. La protección de distribución ante reservas o ventas activas pertenece a A-04 y debe integrarse con B. El prototipo actual permite configurar asientos físicos; no representa disponibilidad ni venta de entradas.
