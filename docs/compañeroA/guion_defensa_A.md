# Guion de defensa del bloque A

## Qué se va a demostrar

El bloque A prepara lo que después necesita la venta: películas, salas, asientos físicos, funciones, tarifas y promociones. También permite consultar la cartelera y controla quién puede modificar esa información.

Este es un guion preparado para practicar. Las pruebas automatizadas tienen evidencia en [pruebas_modulo_A.md](pruebas_modulo_A.md), pero todavía no se ha ejecutado este recorrido completo como ensayo de defensa. La compra, el pago y el ingreso se explican junto con B/C cuando estén integrados.

## Preparación

Usar una base de ensayo con A y C-01 instalados. El SQL instalacion_completa_A.sql de esta carpeta instala A con datos de ejemplo en una base vacía; no debe repetirse sobre la base que ya tiene sus tablas. Para una instalación existente basta comprobar sus datos y acceso.

El usuario administrador debe tener su contraseña local configurada. Para mostrar la vista de contador, preparar también contador@imax.test con configurar_acceso.py si todavía conserva el marcador de prueba. Las contraseñas se eligen en la computadora y no se incluyen en la presentación.

Desde dev, iniciar la aplicación:

    .\.venv\Scripts\python.exe -m flask --app app run

Abrir http://127.0.0.1:5000/cartelera. Tener DBeaver conectado a la misma base para las consultas finales. No es necesario mostrar el archivo .env.

Escoger una fecha futura cercana y una sala de ensayo sin funciones previas. Los ejemplos siguientes usan una película de 120 minutos y una primera función a las 18:00, hora local del cine.

## 1. Presentar la cartelera

Sin iniciar sesión, abrir Cartelera, seleccionar cine, fecha y género, y mostrar los horarios disponibles.

Explicación sugerida:

> La cartelera consulta las funciones activas que todavía no han comenzado. Los filtros permiten buscar una opción concreta y la fecha se interpreta según la zona horaria del cine.

Si no aparece ninguna función, comprobar la fecha y el estado antes de continuar. Los datos antiguos pueden haber dejado de ser futuros.

## 2. Entrar y registrar una película

Iniciar sesión como administrador. En Películas, agregar Prueba defensa A con sinopsis, clasificación, duración de 120 minutos y una ruta de póster. Seleccionar un género existente si se quiere usar ese filtro. Indicar como motivo Preparación de defensa.

Mostrar un intento con información obligatoria incompleta. El navegador puede detenerlo antes del envío; la evidencia del rechazo del servidor está en test_metadatos_pelicula. No presentar una validación visual del navegador como prueba de la base de datos.

Guardar los datos completos y editar el título o la sinopsis.

Explicación sugerida:

> Python recibe y valida el formulario. La película se guarda en PostgreSQL con su identificador. Al editar conservamos ese identificador para mantener sus relaciones.

La dirección del póster puede no corresponder a una imagen disponible; no utilizar la ausencia de la imagen como prueba de un fallo del registro.

## 3. Mostrar sala, zona y carga de asientos

Crear una sala con un nombre propio de la práctica dentro de un cine existente. Agregar una zona General.

Para demostrar que un lote se guarda completo o se revierte completo:

1. Crear solamente el asiento A3 mediante el formulario individual.
2. Intentar generar la fila A del número 1 al 5.
3. Mostrar el rechazo y comprobar que siguen existiendo solo A3 y capacidad 1.
4. Generar A1–A2 y después A4–A5.
5. Comprobar que la capacidad queda en 5.

Usar un motivo en cada formulario. Si se repite la práctica, elegir otra sala o fila para empezar desde las mismas condiciones.

Explicación sugerida:

> La capacidad se obtiene contando los asientos, así no guardamos otro número que pueda quedar desactualizado. El lote se ejecuta en una transacción: si A3 está repetido, también se deshacen A1 y A2 que se habían intentado insertar antes.

## 4. Programar y comprobar la limpieza

En la sala de práctica, programar la película a las 18:00 de la fecha futura elegida. Comprobar que finaliza a las 20:00.

Intentar otra función en esa sala a las 20:10. Debe rechazarse porque no deja los quince minutos de limpieza. Después intentar a las 20:15 y comprobar que se acepta.

Explicación sugerida:

> Python calcula el final con la duración de la película. El trigger de PostgreSQL impide el cruce de horarios e incluye la limpieza. Además bloquea la sala durante la validación para coordinar dos operaciones simultáneas.

Si preguntan por concurrencia, mostrar el caso test_programacion_simultanea y su salida. La prueba observa la espera entre dos conexiones y comprueba el rechazo después de confirmar la primera. No equivale a una prueba de miles de usuarios.

## 5. Configurar tarifa y promoción

En Tarifas, abrir la primera función de práctica:

1. Registrar una tarifa de 8,00 USD para General/Adulto.
2. Elegir una vigencia que incluya el momento actual y llegue hasta el inicio de la función.
3. Intentar otra tarifa para esa misma función, zona y categoría con fechas superpuestas. Debe rechazarse.
4. Registrar una promoción 2x1 con nombre, descripción, vigencia actual, días aplicables, General y Adulto. Para simplificar la práctica se pueden seleccionar los siete días.
5. Volver a Cartelera y abrir Ver precios de esa función.

La categoría Adulto debe existir; si falta, crearla desde el formulario correspondiente. No utilizar una tarifa preexistente de otra función como dato de esta demostración.

Explicación sugerida:

> Cada tarifa corresponde a una función, una zona y una categoría. Las vigencias no pueden cruzarse para esa combinación. La promoción guarda condiciones estructuradas para que B pueda comprobarlas y aplicar el descuento al comprar.

A configura y consulta el 2x1. El cálculo del descuento en la compra pertenece a B y no se demuestra aquí.

## 6. Mostrar permisos y auditoría

Salir e ingresar con contador@imax.test si se preparó su contraseña. Mostrar que puede consultar tarifas y promociones, pero no tiene formularios para cambiarlas. Si se intenta abrir /salas directamente, debe recibir una denegación.

Volver como administrador y consultar en DBeaver los eventos recientes:

    SELECT fecha, id_usuario_actor, rol_al_actuar,
           accion, entidad, id_entidad, motivo
    FROM admin_operacion_audit
    ORDER BY id_admin_operacion_audit DESC
    LIMIT 10;

Explicación sugerida:

> El servidor toma la identidad de la sesión y consulta los permisos de C. El cambio y su auditoría se confirman juntos: si no se puede dejar el registro, tampoco se guarda el cambio.

Con C-01 un lote de asientos deja un evento del lote. Con los triggers de C-03 deja uno por asiento; A evita agregar el mismo registro otra vez. No se debe esperar siempre la misma cantidad de eventos en ambas instalaciones.

El guion demuestra las pantallas y auditoría de A con C-01. Las cinco pruebas de compatibilidad con C-03 ensayan sus mecanismos pertinentes de forma aislada; no prueban su instalación completa.

## 7. Relacionar la pantalla con SQL

Si se quiere comprobar la distribución desde DBeaver, esta consulta permite localizar la sala de práctica por su nombre sin asumir que tiene ID 1:

    SELECT s.id_sala, s.nombre, COUNT(a.id_asiento) AS capacidad
    FROM sala s
    LEFT JOIN zona z ON z.id_sala = s.id_sala
    LEFT JOIN asiento a ON a.id_zona = z.id_zona
    GROUP BY s.id_sala, s.nombre
    ORDER BY s.id_sala;

Explicación sugerida:

> La clave primaria identifica cada registro. Las claves foráneas conectan sala con cine, zona con sala y asiento con zona. Estas relaciones permiten consultar la distribución sin repetir toda la información en cada tabla.

## 8. Cerrar el alcance de la demostración

Mostrar las cinco salidas de prueba y explicar el total: 11 de catálogo/programación, 5 de cartelera, 11 de precios, 15 de seguridad y 5 de compatibilidad con C-03.

Explicación sugerida:

> Lo demostrado corresponde a A y a sus conexiones verificadas con C. Todavía falta comprobar que una sala con reservas o ventas activas no pueda modificarse de forma incompatible; eso necesita las operaciones reales de B y es A-04.

No presentar la protección de una función con tarifas como si fuera protección por ventas. Son reglas distintas.

## Preguntas para practicar

| Pregunta | Respuesta breve |
| --- | --- |
| ¿Por qué separar sala, zona y asiento? | La sala contiene zonas y cada zona agrupa asientos. Permite describir la distribución y asociar precios por zona sin repetirla por función. |
| ¿Por qué el asiento no tiene un campo ocupado global? | El mismo asiento puede venderse para funciones distintas. La disponibilidad se maneja por asiento y función en B. |
| ¿Por qué SERIAL e INT? | SERIAL genera el identificador entero automáticamente. INT es suficiente para el alcance elegido del prototipo; la propuesta de escala global requiere su propio dimensionamiento. |
| ¿UNIQUE es una clave foránea? | No. UNIQUE impide repetir una combinación; FOREIGN KEY exige que el registro relacionado exista. |
| ¿Para qué usar una transacción? | Para guardar juntas las partes de una operación o deshacerlas juntas si algo falla. |
| ¿Por qué el trigger y no solo el formulario? | La regla de horarios también debe aplicarse a escrituras que no pasen por esa pantalla. |
| ¿Qué contiene el motivo? | La razón que da el usuario para un cambio; se guarda junto con su identidad y los datos afectados. |
| ¿La prueba local demuestra la capacidad mundial propuesta? | No. Demuestra reglas funcionales y los casos concretos de concurrencia probados. |

## Cómo registrar el ensayo

Después de practicar, anotar qué pasos se ejecutaron, qué ocurrió y cualquier diferencia respecto al esperado. Las capturas y consultas que se conserven deben corresponder a ese ensayo real. PA-15 permanece pendiente hasta ejecutarlo y completar la parte de A-04 cuando esté disponible.
