# Modelo de identidad, autorización y auditoría

## Alcance

Este modelo corresponde al bloque C y al issue [C-01](https://github.com/Mauriart/BD_IMAX/issues/15). Representa usuarios, roles, la matriz de permisos, solicitudes de reembolso, el registro de acceso en puerta y la auditoría de operaciones administrativas. Compras, pagos, boletos e inventario pertenecen a B; el catálogo y la programación pertenecen a A. El esquema implementado se encuentra en [relacional_C.sql](relacional_C.sql).

No se duplican tablas de otros bloques. Las referencias a `compra` y `boleto` (de B) quedan como columnas enteras sin FK hasta que B entregue esas tablas (ver límites).

## Decisiones de diseño

- Se usa `SERIAL PRIMARY KEY` e `INT` en las referencias, igual que el esquema de A, para que las FK entre bloques sean compatibles. `00_acuerdos.md` propone `BIGINT IDENTITY`; en A-01 se acordó que el SQL construido prevalece, y C lo sigue.
- Un usuario tiene un solo rol, como indican los acuerdos para el prototipo.
- La matriz de roles de `00_acuerdos.md` (sección 9) se guarda como datos en `rol_permiso`, no como código. Cambiar un permiso es una fila, no una modificación de la aplicación.
- Los logs de puerta y de administración no llevan FK hacia boleto o función, porque un QR inexistente también debe registrarse.
- Los dos logs son inmutables mediante un trigger: no admiten UPDATE ni DELETE.

## Modelo relacional

| Tabla | PK | FK | Otras restricciones |
| --- | --- | --- | --- |
| rol | id_rol | — | nombre único |
| usuario | id_usuario | id_rol → rol | correo único y normalizado; nombre no vacío |
| rol_permiso | (id_rol, accion) | id_rol → rol | La PK impide repetir un permiso. |
| solicitud_reembolso | id_solicitud_reembolso | id_usuario_actor → usuario; id_usuario_resuelve → usuario | estado permitido; motivo no vacío; coherencia estado/resolución |
| solicitud_reembolso_detalle | (id_solicitud_reembolso, id_boleto) | id_solicitud_reembolso → solicitud_reembolso | La PK impide repetir un boleto en la misma solicitud. |
| acceso_puerta_log | id_acceso_puerta_log | id_usuario_operador → usuario | resultado: aceptado o rechazado |
| admin_operacion_audit | id_admin_operacion_audit | id_usuario_actor → usuario | motivo no vacío |

## Diccionario de datos

| Tabla | Columna | Tipo | Significado y restricción |
| --- | --- | --- | --- |
| rol | id_rol | SERIAL | Identificador; PK. |
| rol | nombre | VARCHAR(30) | Nombre único: cliente, taquillero, operador_puerta, contador, administrador. |
| usuario | id_usuario | SERIAL | Identificador; PK. |
| usuario | id_rol | INT | FK al rol del usuario. |
| usuario | nombre | VARCHAR(100) | Nombre; no puede ser vacío. |
| usuario | correo | VARCHAR(150) | Único; debe estar en minúsculas y sin espacios en los extremos. |
| usuario | password_hash | TEXT | Hash de la contraseña. Nunca la contraseña en claro. |
| usuario | activo | BOOLEAN | Habilitación; predeterminado TRUE. Un usuario inactivo no obtiene permisos. |
| usuario | creado_en | TIMESTAMPTZ | Instante de creación; predeterminado el momento actual. |
| rol_permiso | id_rol | INT | FK al rol; parte de la PK. |
| rol_permiso | accion | VARCHAR(60) | Nombre de la acción permitida; parte de la PK. |
| solicitud_reembolso | id_solicitud_reembolso | SERIAL | Identificador; PK. |
| solicitud_reembolso | id_compra | INT | Compra de B a la que se refiere. Sin FK por ahora. |
| solicitud_reembolso | id_usuario_actor | INT | FK al usuario que solicita. |
| solicitud_reembolso | motivo | TEXT | Motivo; no vacío. |
| solicitud_reembolso | estado | VARCHAR(20) | pendiente, ejecutada o rechazada; predeterminado pendiente. |
| solicitud_reembolso | creada_en | TIMESTAMPTZ | Instante de creación. |
| solicitud_reembolso | resuelta_en | TIMESTAMPTZ | Instante de resolución; NULL mientras esté pendiente. |
| solicitud_reembolso | id_usuario_resuelve | INT | FK al usuario que resuelve; NULL mientras esté pendiente. |
| solicitud_reembolso_detalle | id_solicitud_reembolso | INT | FK a la solicitud; parte de la PK. |
| solicitud_reembolso_detalle | id_boleto | INT | Boleto de B incluido en la solicitud; parte de la PK. Sin FK por ahora. |
| acceso_puerta_log | id_acceso_puerta_log | SERIAL | Identificador; PK. |
| acceso_puerta_log | fecha | TIMESTAMPTZ | Instante del intento; predeterminado el momento actual. |
| acceso_puerta_log | id_boleto | INT | Boleto, si se identificó. Admite NULL (QR inexistente). |
| acceso_puerta_log | id_funcion_solicitada | INT | Función para la que se intentó entrar. Admite NULL. |
| acceso_puerta_log | id_usuario_operador | INT | FK al operador de puerta. |
| acceso_puerta_log | dispositivo | VARCHAR(100) | Dispositivo de lectura. |
| acceso_puerta_log | resultado | VARCHAR(20) | aceptado o rechazado. |
| acceso_puerta_log | motivo | VARCHAR(200) | Motivo del rechazo. Admite NULL. |
| admin_operacion_audit | id_admin_operacion_audit | SERIAL | Identificador; PK. |
| admin_operacion_audit | fecha | TIMESTAMPTZ | Instante de la acción. |
| admin_operacion_audit | id_usuario_actor | INT | FK al usuario que actuó. |
| admin_operacion_audit | rol_al_actuar | VARCHAR(30) | Rol que tenía al actuar. Se copia a propósito: si el usuario cambia de rol después, el registro conserva el original. |
| admin_operacion_audit | ip | VARCHAR(45) | Dirección IP (cabe IPv6). No se valida su formato. |
| admin_operacion_audit | accion | VARCHAR(60) | Acción realizada. |
| admin_operacion_audit | entidad | VARCHAR(60) | Tipo de dato afectado. |
| admin_operacion_audit | id_entidad | VARCHAR(60) | Identificador afectado. Admite NULL. |
| admin_operacion_audit | motivo | TEXT | Motivo; no vacío. |
| admin_operacion_audit | cambios | JSONB | Cambios relevantes. Admite NULL. |

Las 7 tablas suman 39 columnas. Con las 15 tablas y 56 columnas de A, la base tiene 22 tablas.

## Normalización

**Primera forma normal.** Cada columna guarda un valor. Los permisos de un rol no son una lista en una celda: cada uno es una fila de `rol_permiso`. Los boletos de una solicitud están en `solicitud_reembolso_detalle`, una fila por boleto.

**Segunda forma normal.** En las tablas de PK simple, el identificador determina el resto. Las tablas de PK compuesta (`rol_permiso`, `solicitud_reembolso_detalle`) solo contienen las columnas de la clave, sin atributos que dependan de una parte.

**Tercera forma normal.** Los datos descriptivos viven en su entidad: el nombre del rol está en `rol`, no repetido en cada usuario.

Dependencias funcionales relevantes:

- `id_rol → nombre`; `nombre → id_rol` (clave alterna).
- `id_usuario → id_rol, nombre, correo, password_hash, activo, creado_en`; `correo → id_usuario` (clave alterna).
- `id_solicitud_reembolso → id_compra, id_usuario_actor, motivo, estado, creada_en, resuelta_en, id_usuario_resuelve`.
- `id_acceso_puerta_log → fecha, id_boleto, id_funcion_solicitada, id_usuario_operador, dispositivo, resultado, motivo`.
- `id_admin_operacion_audit → fecha, id_usuario_actor, rol_al_actuar, ip, accion, entidad, id_entidad, motivo, cambios`.

Excepción deliberada: `rol_al_actuar` en el log de auditoría podría obtenerse de `usuario.id_rol`, pero ese valor puede cambiar con el tiempo. Se copia porque un registro histórico debe reflejar el rol del momento. No es una redundancia accidental.

## Restricciones implementadas y límites

El DDL impide referencias inexistentes, correos repetidos o sin normalizar, estados inválidos de solicitud y de resultado de puerta, motivos vacíos y una solicitud resuelta sin su fecha y resolutor (o una pendiente con ellos).

Dos triggers impiden modificar o borrar filas de `acceso_puerta_log` y `admin_operacion_audit`. La función `autorizar_accion(id_usuario, accion)` consulta la matriz y devuelve falso para usuarios inactivos o inexistentes.

Límites que no deben presentarse como resueltos:

- **FK hacia B.** `id_compra` e `id_boleto` no tienen FK porque `compra` y `boleto` aún no existen. [integracion_C_B.sql](integracion_C_B.sql) las agrega, junto con la regla de que un boleto solicitado pertenezca a la compra de la solicitud, cuando esas tablas existan. Hasta que B entregue las suyas, [fixtures_B_sinteticos_C.sql](fixtures_B_sinteticos_C.sql) crea tablas **provisionales** con los campos mínimos de los acuerdos; no son el modelo de B y no deben instalarse sobre sus tablas reales.
- **Hashes de prueba.** Los 7 usuarios cargados tienen `HASH_DE_PRUEBA`; no permiten iniciar sesión. Deben reemplazarse con hashes reales de Werkzeug al implementar el acceso.
- **Acciones como texto libre.** `rol_permiso.accion` no está validada contra un catálogo. Un error de escritura crea un permiso que nada consulta. Las acciones válidas se documentan en [contratos_c.md](contratos_c.md).
- **Inmutabilidad.** Los triggers impiden UPDATE, DELETE y (con [privilegios_C.sql](privilegios_C.sql)) TRUNCATE de los logs, incluso para el propietario. Un propietario o superusuario aún podría eliminar el trigger; frente a eso solo ayudan el archivo histórico protegido y la separación de cuentas, que se diseñan en C-05 y C-06.
- **Datos de ejemplo.** Los usuarios, compras y boletos son sintéticos.
- **Sin pruebas de concurrencia ni rendimiento.** Corresponden a C-07.
- **Privilegios de A y B.** `privilegios_C.sql` cubre solo las tablas de C. Los privilegios del rol `imax_app` sobre las tablas de A y B los define cada bloque.
- **DER global.** El Chen de C está en `modeloC.drawio` y `modeloC.png`; su incorporación al DER consolidado del equipo queda pendiente.

## Uso de los scripts

1. Instalar A con [instalacion_completa_A.sql](../compa%C3%B1eroA/instalacion_completa_A.sql) en una base vacía.
2. Ejecutar [relacional_C.sql](relacional_C.sql). Es una transacción: si falla, no queda nada creado. No es reejecutable sobre una base que ya lo tiene; para repetir, recrear la base.
3. Ejecutar [privilegios_C.sql](privilegios_C.sql): crea el rol técnico `imax_app` con privilegios mínimos y bloquea TRUNCATE en los logs. Se puede reejecutar.
4. Ejecutar [fixtures_B_sinteticos_C.sql](fixtures_B_sinteticos_C.sql) (compras y boletos provisionales: emitido, usado y anulado) y después [integracion_C_B.sql](integracion_C_B.sql).
5. Ejecutar las verificaciones, que no dejan cambios: [verificacion_C.sql](verificacion_C.sql) (esquema y rechazos), [verificacion_matriz_C.sql](verificacion_matriz_C.sql) (las 75 combinaciones rol-acción) y [verificacion_privilegios_C.sql](verificacion_privilegios_C.sql).
6. Ejecutar cada sentencia de [pruebas_C.sql](pruebas_C.sql) por separado para repetir los casos manuales.

## Entrega de C-01

El esquema, los datos por rol, el mecanismo común de autorización, los privilegios mínimos, el diccionario, la normalización, el DER ([modeloC.drawio](modeloC.drawio) y [modeloC.png](modeloC.png)), los contratos, los boletos sintéticos y las pruebas están en esta carpeta. Las pruebas manuales están registradas en [pruebas_c.md](pruebas_c.md). La integración con las tablas de B y la aplicación de permisos en las pantallas de A y B se realizan en C-03 y en sus tareas.
