# Guion de defensa del bloque A

## Qué se va a demostrar

El bloque A prepara lo que después necesita la venta: películas, salas, asientos físicos, funciones, tarifas y promociones. También permite consultar la cartelera y controla quién puede modificar esa información.

Este guion sirve para practicar la explicación del programa integrado. Sus pasos se contrastaron con las 97 pruebas y las pantallas revisadas en [pruebas_modulo_A.md](pruebas_modulo_A.md). La práctica oral del equipo sigue pendiente; las comprobaciones técnicas no se presentan como ese ensayo humano.

## Preparación

Para una base de ensayo vacía, usar [instalacion_completa.sql](../integracion/instalacion_completa.sql), que instala A/B/C. No repetirlo sobre p2: esa base ya está actualizada. Si se usa p2 para practicar, los datos creados permanecerán; identificarlos como práctica.

El usuario administrador debe tener su contraseña local configurada. Para mostrar la vista de contador, preparar también contador@imax.test con configurar_acceso.py si todavía conserva el marcador de prueba. Las contraseñas se eligen en la computadora y no se incluyen en la presentación.

Desde dev, iniciar la aplicación:

    .\.venv\Scripts\python.exe iniciar.py

El iniciador también libera reservas vencidas. Abrir http://127.0.0.1:5000/cartelera. Tener DBeaver conectado a la misma base para las consultas finales. No es necesario mostrar el archivo .env.

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
4. Registrar una promoción 2x1 con nombre, descripción, vigencia actual, días aplicables, General y Adulto. Seleccionar miércoles y una función de ese día, con vigencia que incluya la cotización. La promoción inicial quedó definida para miércoles; las otras promociones permiten configurar sus días.
5. Volver a Cartelera y abrir Ver precios de esa función.

La categoría Adulto debe existir; si falta, crearla desde el formulario correspondiente. No utilizar una tarifa preexistente de otra función como dato de esta demostración.

Explicación sugerida:

> Cada tarifa corresponde a una función, una zona y una categoría. Las vigencias no pueden cruzarse para esa combinación. La promoción guarda condiciones estructuradas para que B pueda comprobarlas y aplicar el descuento al comprar.

A configura las condiciones; B las consulta al reservar y guarda la cotización. A USD 8 por adulto de General, dos adultos cuestan USD 8 con 2x1; tres cuestan USD 16. Se evalúa el día local de la función. Cambiar la tarifa después de reservar no cambia ese precio guardado. Evidencia: test_2x1_impar_cotizacion_congelada.

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

La instalación global incluye C-03. La suite global también comprueba que una cortesía se revierta si falla su auditoría; los cinco casos de compatibilidad conservan la comprobación específica de los triggers de A.

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

## 8. Mostrar protección con una reserva real

Como cliente, abrir la función de práctica, seleccionar Adulto y reservar un asiento. Antes de pagar, volver como administrador e intentar borrar ese asiento o agregar otro a la distribución de su sala. Debe rechazarse mientras la reserva esté vigente. Si vence durante la demostración, repetir la reserva antes de comprobar el rechazo.

Pagar usando el resultado simulado de éxito del prototipo. Mostrar factura, boleto y QR; volver a intentar el cambio incompatible. El boleto emitido mantiene la protección. Usar otra sala de práctica para repetir; no borrar la historia.

> El asiento físico pertenece a una zona; su disponibilidad pertenece a una función. Reserva y distribución coordinan el bloqueo de la sala para evitar referencias incompatibles. Una venta conserva historia incluso después del reembolso.

Mostrar PA-13 si preguntan por simultaneidad: se ensayaron ambos órdenes de reserva y borrado con conexiones independientes. No es necesario reproducir a mano esa carrera en la exposición.

## 9. Conectar con ingreso y reportes

Puerta necesita un boleto dentro de su ventana de ingreso: desde 30 minutos antes hasta 15 minutos después del inicio. Una función de la semana siguiente permite vender, pero su ingreso todavía debe rechazarse. No alterar la hora de la computadora ni afirmar que se aceptó ese boleto.

El operador elige la función, pega el token y confirma acreditación cuando corresponde. El primer ingreso válido se acepta; el segundo se rechaza. Evidencia: test_qr_una_vez_y_rol_puerta y test_acreditacion_y_qr_de_otra_funcion.

Abrir Reportes con un usuario autorizado y un periodo que incluya las compras de práctica. Mostrar cobros y devoluciones por separado. El reembolso parcial anula solamente los boletos seleccionados y libera esos asientos. Evidencia: test_reembolso_parcial_reventa_y_reportes.

> SQL guarda estados, aplica reglas y coordina operaciones simultáneas. Python conecta la sesión con los permisos, recibe formularios y confirma o revierte. La pantalla presenta lo ocurrido.

Mostrar las ocho salidas: 11 + 5 + 11 + 15 + 5 + 17 + 10 + 23 = 97. La propuesta de capacidad y los costos requieren su propia explicación y evidencia.

## Preguntas para practicar

| Pregunta | Respuesta breve |
| --- | --- |
| ¿Por qué separar sala, zona y asiento? | La sala contiene zonas y cada zona agrupa asientos. Permite describir la distribución y asociar precios por zona sin repetirla por función. |
| ¿Por qué el asiento no tiene un campo ocupado global? | El mismo asiento puede venderse para funciones distintas. La disponibilidad se maneja por asiento y función en B. |
| ¿Por qué SERIAL e INT? | SERIAL genera el identificador entero automáticamente. INT cubre los identificadores de A en este prototipo. B conserva BIGINT en compras/boletos y sus referencias compartidas. La escala global requiere su propio dimensionamiento. |
| ¿UNIQUE es una clave foránea? | No. UNIQUE impide repetir una combinación; FOREIGN KEY exige que el registro relacionado exista. |
| ¿Para qué usar una transacción? | Para guardar juntas las partes de una operación o deshacerlas juntas si algo falla. |
| ¿Por qué el trigger y no solo el formulario? | La regla de horarios también debe aplicarse a escrituras que no pasen por esa pantalla. |
| ¿Qué contiene el motivo? | La razón que da el usuario para un cambio; se guarda junto con su identidad y los datos afectados. |
| ¿La prueba local demuestra la capacidad mundial propuesta? | No. Demuestra reglas funcionales y los casos concretos de concurrencia probados. |

## Cómo registrar el ensayo

Antes de exponer, recorrer las pantallas con usuarios y datos de práctica y anotar diferencias. La evidencia técnica actual incluye A-04 y B/C real. No presentarla como si otro integrante hubiera realizado ya el ensayo oral o lo hubiera ejecutado en su computadora.
