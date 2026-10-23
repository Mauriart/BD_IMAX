# Datos y operaciones compartidos del bloque C

## Identificadores publicados

Los identificadores simples son enteros generados con SERIAL. A y B deben usar los IDs devueltos por las consultas, sin asumir que empiezan en 1.

| Dato | Campos compartidos | Uso |
| --- | --- | --- |
| Rol | id_rol, nombre | Identificar el rol de un usuario. |
| Usuario | id_usuario, id_rol, nombre, correo, activo | Actor de las operaciones. `password_hash` no se comparte. |
| Permiso | id_rol, accion | Matriz de permisos consultada por `autorizar_accion`. |
| Solicitud de reembolso | id_solicitud_reembolso, id_compra, id_usuario_actor, estado | B ejecuta la reversión de las solicitudes autorizadas. |

## Autorizar una acción

`autorizar_accion(p_id_usuario INT, p_accion TEXT) → BOOLEAN`

Implementada en `relacional_C.sql`. Devuelve verdadero solo si el usuario existe, está activo y su rol tiene la acción. Devuelve falso para un usuario inexistente, inactivo o una acción desconocida. No lanza error por esos casos: quien la llama decide cómo rechazar (por ejemplo, con el código `NO_AUTORIZADO` de los acuerdos).

Esta función **responde, no aplica**. Cada operación de A y B debe invocarla en el servidor con el usuario de la sesión autenticada, nunca con un ID recibido del navegador. Ocultar un botón no sustituye esta comprobación.

### Acciones válidas

| Acción | Roles con permiso |
| --- | --- |
| consultar_cartelera | cliente, taquillero, operador_puerta, contador, administrador |
| gestionar_catalogo | administrador |
| configurar_tarifas | administrador |
| ver_tarifas | contador, administrador |
| reservar_comprar | cliente |
| venta_presencial | taquillero |
| consultar_boletos_propios | cliente |
| consultar_boletos_venta | taquillero |
| consultar_boletos_admin | administrador |
| validar_ingreso | operador_puerta |
| solicitar_reembolso | cliente, taquillero, administrador |
| resolver_reembolso | administrador |
| ver_reportes_financieros | contador, administrador |
| ver_auditoria | contador, administrador |
| administrar_usuarios | administrador |

La matriz procede de la sección 9 de `00_acuerdos.md`. El administrador no hereda venta ni puerta. Una función que verifique la **propiedad** de un recurso (por ejemplo, que un boleto sea del cliente) no está en esta entrega: `autorizar_accion` solo decide por rol.

## Registrar una acción administrativa

Las acciones críticas de A y B (cambio de precios, programación, distribución, cortesías, cambios manuales de asiento) deben insertar una fila en `admin_operacion_audit` con: actor, rol al actuar, IP, acción, entidad, identificador, motivo (obligatorio) y cambios. La inserción debe estar en la **misma transacción** que el cambio, para que el éxito y su registro se confirmen juntos. La operación `auditar_accion` descrita en los acuerdos se implementa en C-03; hasta entonces A y B pueden insertar directamente.

No se guardan contraseñas, tokens QR completos ni datos financieros sensibles en estos registros.

## Lo que C necesita de B

| De B | Para qué |
| --- | --- |
| Tabla `compra` con `id_compra` | FK de `solicitud_reembolso.id_compra`. |
| Tabla `boleto` con `id_boleto` y su estado | FK de `solicitud_reembolso_detalle.id_boleto` y validación de ingreso. |
| `consumir_boleto` (cambio atómico `emitido → usado`) | `validar_ingreso` de C-02 registra el resultado en `acceso_puerta_log` en la misma transacción. |
| `revertir_venta` | Ejecuta la reversión cuando C autoriza un reembolso (C-03). |

Mientras B no entregue estas tablas, C trabaja con [fixtures_B_sinteticos_C.sql](fixtures_B_sinteticos_C.sql): `compra`, `compra_detalle` y `boleto` provisionales con los campos de `00_acuerdos.md` y cuatro boletos de ejemplo (dos emitidos, uno usado, uno anulado). Cuando B entregue las suyas se usan sus datos, no este fixture, y [integracion_C_B.sql](integracion_C_B.sql) agrega las FK pendientes.

## Cuenta de la aplicación

[privilegios_C.sql](privilegios_C.sql) crea el rol `imax_app` (sin LOGIN ni superusuario). Puede consultar la matriz y ejecutar `autorizar_accion`, crear y modificar usuarios y solicitudes, y solo **agregar** a los logs. No puede borrar usuarios ni modificar o vaciar los logs. A y B deben conectarse con una cuenta que pertenezca a este rol (`GRANT imax_app TO <cuenta>`).

## Lo que C entrega a A

A no define tablas de usuario ni de auditoría: usa `usuario`, `rol` y `admin_operacion_audit`. El pendiente T-02 (#23) de A, permisos y auditoría de las pantallas de catálogo, salas, funciones y precios, depende de esta entrega y de C-03.

## Coordinación pendiente

- La aplicación de `autorizar_accion` en las rutas de A (`dev/`) y de B se integra en C-03 y T-02.
- El login real y la gestión de sesión (hashes de Werkzeug, protección CSRF) se implementan con la aplicación.
- Las FK hacia `compra` y `boleto` se agregan al recibir las tablas de B.
