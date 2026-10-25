# Protección de salas — A-04

## Avance y alcance

A incorpora una operación de eliminación de asientos con confirmación, permiso y motivo. PostgreSQL rechaza cambios de distribución cuando hay reservas o ventas activas y coordina esas comprobaciones con las escrituras de ocupación de B.

Se aprobaron 17 pruebas de protección con contrato reducido, 10 con los SQL reales de B y las 47 anteriores. Total de esta validación: 74 pruebas aprobadas. Las siete salidas reales están en [evidencias/a04](evidencias/a04/).

La protección se verificó tanto con un fixture reducido como con las tablas y funciones reales de reserva/pago de B. A-04 fue integrado y cerrado. Después se instaló en p2 mediante el PR #40, conservando los datos; las evidencias actuales están en [integración](../integracion/guia.md). Las 74 pruebas de este apartado corresponden a la etapa anterior y forman parte del conjunto actual. La nueva opción de eliminación permanece deshabilitada en una instalación que no tenga la migración de A-04.

## Qué hace SQL

[proteccion_salas_A04.sql](proteccion_salas_A04.sql) verifica que estén reserva, boleto e inventario_funcion con los campos compartidos. Espera el contrato de la rama Compañera_B: boleto tiene id_funcion e id_asiento. El modelo provisional de boleto que pasa por compra_detalle no cumple ese contrato y se rechaza antes de instalar.

También rechaza ocupaciones preexistentes cuyo asiento esté en otra sala. No corrige datos ni reemplaza tablas, funciones de pago, estados o índices de B. La instalación es transaccional y reejecutable.

Las modificaciones de sala, zona y asiento toman un bloqueo exclusivo de la fila de sala antes de comprobar la actividad. Las escrituras de reserva, boleto e inventario toman un bloqueo compartido de esa misma sala. Varias reservas pueden compartirlo, pero una modificación incompatible de distribución debe esperar.

Después de esperar se vuelve a comprobar el estado. Este prototipo exige READ COMMITTED; rechaza otros niveles para evitar validar contra una fotografía anterior de los datos.

Se impiden cambios de función con reservas activas y cambios directos con boletos vigentes. No se implementa aquí el flujo de reprogramación con venta; debe ser una operación administrativa propia que conserve la historia.

## Qué se considera actividad

- Reserva: estado activa y vencimiento posterior al reloj de la base.
- Boleto: Emitido o Usado en una función que todavía no terminó.
- Inventario: bloqueado o vendido en una función que todavía no terminó.

Un inventario que sigue bloqueado cuenta como ocupado aunque la reserva haya vencido. B debe completar su liberación para que el estado sea coherente. A no borra una reserva ni libera inventario para permitir un cambio de sala.

La actividad de una función protege la distribución de toda su sala, no solo el asiento vendido. Una función distinta puede programarse sin cambiar esa distribución. La edición de una función se verifica contra su propia actividad.

## Referencias e historia

Un asiento con referencias de inventario, reserva o boleto no puede cambiar de ubicación mediante UPDATE directo. Una zona con asientos referenciados por B no puede trasladarse a otra sala.

Las claves foráneas impiden eliminar un asiento referenciado, incluso si su boleto está anulado o la reserva ya venció. A conserva esos registros: no hace borrados en cascada. Se puede eliminar otro asiento sin referencias si no hay actividad vigente que proteja la sala.

Esto es una política conservadora para los campos actuales de B. Una futura baja lógica o remodelación necesita un diseño específico; no se agrega una columna de estado improvisada al asiento.

## Qué hace Python y cómo se usa

La nueva ruta es /salas/<id_sala>/asientos/<id_asiento>/eliminar. Se ofrece desde la tabla de asientos únicamente si la migración está disponible.

GET muestra la confirmación y no modifica datos. POST exige sesión de administrador, token CSRF válido y motivo. La operación vuelve a comprobar que el asiento pertenece a esa sala, toma primero el bloqueo de sala, bloquea el asiento y ejecuta DELETE.

El borrado y su auditoría forman una sola transacción. Si falla la auditoría, se recupera el asiento. La integración de auditoría distingue ahora DELETE de UPDATE: cuando el trigger real de C-03 ya registró el borrado, A no inserta un segundo evento.

Los rechazos aparecen como mensajes de reservas/ventas activas, referencias históricas o cambios simultáneos. Las altas actuales de zonas, asientos y lotes, y la edición de funciones, también traducen el rechazo de la protección.

Se revisaron en navegador la navegación, el enlace Eliminar, la confirmación con asiento/zona, el campo de motivo y Cancelar, usando una base temporal. Los éxitos y rechazos del POST se comprobaron con el cliente de pruebas de Flask y PostgreSQL.

## Evidencia de concurrencia

| Orden de ejecución | Qué espera | Resultado observado |
| --- | --- | --- |
| B inserta una reserva y todavía no confirma; A intenta bloquear la sala para borrar. | A espera mientras B retiene el bloqueo compartido. | Tras confirmar B, A rechaza el cambio con 55000 y el asiento permanece. |
| A bloquea la sala y borra el asiento sin confirmar; B intenta insertar una reserva. | B espera por la sala. | Tras confirmar A, B detecta que el asiento ya no pertenece a la sala y rechaza con 23503; no queda una reserva sobre un asiento eliminado. |

El ensayo consulta pg_stat_activity para observar la espera; no supone concurrencia solo por lanzar dos llamadas. Cada conexión tiene límites de espera.

La ruta de eliminación toma sala antes de asiento. El SQL directo y otras operaciones de B todavía pueden adquirir filas en otro orden: PostgreSQL puede abortar una transacción por deadlock. Eso debe manejarse con rollback y reintento acotado; no se afirma que todas las combinaciones de operaciones de B ya tengan un orden común verificado. Los casos probados de la tabla no produjeron un estado incompatible.

## Las 17 pruebas nuevas

La [salida real](evidencias/a04/verificar_salas_a04.txt) muestra:

1. Confirmación y eliminación permitida con auditoría.
2. Reserva activa rechaza borrado y altas de asiento/lote.
3. Boletos emitidos y usados protegen la sala.
4. Boleto anulado conserva referencias históricas.
5. Reserva vencida permite eliminar otro asiento sin referencias.
6. Reprogramación con reserva rechazada sin alterar el horario.
7. Zona con inventario no se puede trasladar.
8. Ocupación con asiento de otra sala rechazada.
9. Permiso, CSRF y pertenencia a la sala comprobados.
10. Fallo de auditoría revierte el borrado.
11. Instalación con columnas incompatibles rechazada.
12. Instalación con ocupaciones incompatibles rechazada.
13. Sin migración no se habilita la eliminación.
14. Nivel de aislamiento no admitido rechazado.
15. DELETE con el trigger real de C-03 deja un solo evento.
16. Carrera con reserva primero.
17. Carrera con borrado primero.

Además pasaron las 11 pruebas de A-02, 5 de cartelera, 11 de precios, 15 de seguridad y 5 de compatibilidad con C-03. No se suman las pruebas financieras de A-06 a ese conteo.

## Reproducir y límites de instalación

Desde dev:

    .\.venv\Scripts\python.exe verificar_salas_a04.py --c03 RUTA_AL_SQL_C03

El archivo real de C-03 usado fue el del commit f19dd9b01fc643805b2cb0baefc334fee7b2b0a1. La forma de extraerlo está en [permisos_auditoria_A.md](permisos_auditoria_A.md#compatibilidad-con-c-03). Sin --c03, el caso que necesita ese archivo se omite: no debe contarse como aprobado.

[pruebas_contrato_B_A04.sql](pruebas_contrato_B_A04.sql) es solo un fixture reducido para estos ensayos. Comprueba el nombre del esquema de ensayo antes de crear nada. No sustituye al DDL de B ni instala su checkout. La suite crea su esquema, carga A y C-01, agrega el fixture y la protección y elimina el esquema al terminar.

Para integrar la protección real, primero debe existir el esquema definitivo de B y conciliarse con el modelo provisional de C. No se debe ejecutar el fixture en la base de trabajo. La instalación de A-04 requiere comprobar también los privilegios de la cuenta técnica sobre las tablas compartidas; esta suite usa la cuenta configurada de ensayo.

## Integración comprobada con B real

Se incorporaron a esta rama los tres SQL de B desde Compañera_B, commit c9085e7c73282d4b346683cf9170214b911d3aed, con los ajustes mínimos autorizados por Mauriart:

- sql_20_ventas_tablas.sql usa las tablas de identidad y solicitud de reembolso de C-01, sin recrearlas ni insertar un usuario provisional. Inventario se crea después de boleto y termina con punto y coma. El índice de reservas usa los estados en minúsculas que admite su CHECK.
- sql_21_ventas_logs.sql llama a su bloqueo de logs bloquear_modificacion_log_b para conservar la función de C con su código de error.
- sql_22_ventas_funciones.sql recupera calcular_total, que reservar_asientos ya invocaba. Su cuerpo procede del SQL original de B en c16e010; suma total_linea y actualiza compra.total.

No se incorporó la rama completa de B ni sus pantallas. Estos archivos son copias corregidas para integración; al reunir las ramas debe conservarse esta versión de los tres SQL. No se cambiaron las reglas de pago, reembolso, precios o autorización de B.

Desde dev se reproduce con:

    .\.venv\Scripts\python.exe verificar_integracion_b_a04.py

La suite carga A, C-01, los tres SQL reales de B y la protección A-04 en un esquema temporal. Comprueba que B no modifica los usuarios ni la función de logs de C. La protección se instala dos veces para verificar su reejecución.

| Caso real | Resultado comprobado |
| --- | --- |
| reservar_asientos y consultar_disponibilidad | Compra de USD 8, inventario bloqueado y cambios incompatibles rechazados. |
| procesar_pago aprobado y consultar_boletos_usuario | Compra pagada, boleto emitido, inventario vendido y distribución/horario protegidos. |
| Pago rechazado | Compra cancelada, inventario disponible y borrado de otro asiento permitido y auditado. |
| liberar_reservas_vencidas | El inventario bloqueado protege hasta su liberación; después permite un cambio sin referencias. |
| revertir_venta | Anula el boleto y libera inventario; conserva historia y rechaza borrar el asiento referenciado. |
| Índice de reservas activas | Rechaza el duplicado directo, además del control de disponibilidad de B. |
| Reserva de varios asientos con uno no disponible | Revierte compra, detalles y reservas de ese intento. |
| Logs de B y C | Ambos siguen siendo inalterables y usan sus funciones independientes. |
| Reserva real primero, cambio después | Se observa espera; tras confirmar la reserva se rechaza el cambio con 55000. |
| Cambio permitido primero, reserva real después | B espera por la sala; tras confirmar el borrado de un asiento sin inventario, reserva otro asiento válido. |

En las carreras se reserva un asiento con inventario y se intenta borrar otro sin referencias de la misma sala. No se inventa un borrado permitido sobre inventario existente: sus FK conservan la historia. Se observó la espera en pg_stat_activity y se verificaron las filas finales.

La [salida real de integración](evidencias/a04/verificar_integracion_b_a04.txt) contiene los 10 casos aprobados. Los 64 anteriores se repitieron y aprobaron en esta versión.

Esta validación cubre las funciones SQL de B y las rutas de A. No certifica las pantallas, permisos ni todas las reglas comerciales de B; tampoco su pasarela externa. Los datos usan una sola categoría y tarifa vigente: no se presenta el fallback de precios ni la elección de categoría de B como integración completa de A-03. La conciliación del boleto provisional de C, su instalación completa y los privilegios de despliegue siguen en T-02. Las pruebas usan la cuenta local configurada y no demuestran privilegios mínimos de una cuenta nueva.

Las pruebas de reserva, pago, expiración y reversión con los SQL reales de B ya se reprodujeron en esta validación. La interfaz integrada, el despliegue y la revisión global de bloqueos permanecen en T-02; la evidencia de A-04 se incorpora a la entrega final de A-07.


## Ajuste al integrar el flujo completo

El alta de funcion crea inventario y el mapa agrega solo los asientos nuevos mediante ON CONFLICT DO NOTHING. Para borrar un asiento nunca utilizado, A-04 elimina primero sus filas de inventario disponible dentro de la misma transaccion. Las reservas, boletos e historia de ventas siguen impidiendo el borrado mediante FK. La eliminacion de inventario tambien se revierte si falla la operacion. Ver [integracion](../integracion/guia.md).
