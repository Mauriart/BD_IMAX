# Modelo de Identidad, Autorización y Auditoría (Bloque C)

## Alcance

Este modelo corresponde al bloque C y al issue [C-01](https://github.com/Mauriart/BD_IMAX/issues/15). Representa usuarios, roles, la matriz de permisos, solicitudes de reembolso, el registro de acceso en puerta y la auditoría de operaciones administrativas. Compras, pagos, boletos e inventario pertenecen a B; el catálogo y la programación pertenecen a A. El esquema implementado se encuentra en `relacional_C.sql`.

No se duplican tablas de otros bloques. Las referencias a `compra` y `boleto` (de B) quedan como columnas enteras sin FK hasta que B entregue esas tablas.

## Decisiones de diseño

- Se usa `SERIAL PRIMARY KEY` e `INT` en las referencias, igual que el esquema de A, para que las FK entre bloques sean compatibles.
- Un usuario tiene un solo rol, como indican los acuerdos para el prototipo.
- La matriz de roles de la sección 9 de los acuerdos del proyecto se guarda como datos en `rol_permiso`, no como código hardcodear en la aplicación. Cambiar un permiso es una fila, no una modificación de código.
- Los logs de puerta y de administración no llevan FK hacia boleto o función, porque un QR inexistente o fallido también debe registrarse.
- Los dos logs son inmutables mediante un trigger en PL/pgSQL: no admiten `UPDATE` ni `DELETE`.

## Modelo relacional

| Tabla | PK | FK | Otras restricciones |
| --- | --- | --- | --- |
| `rol` | `id_rol` | — | `nombre` único |
| `usuario` | `id_usuario` | `id_rol` → `rol` | `correo` único y normalizado; `nombre` no vacío |
| `rol_permiso` | (`id_rol`, `accion`) | `id_rol` → `rol` | La PK impide repetir un permiso |
| `solicitud_reembolso` | `id_solicitud_reembolso` | `id_usuario_actor` → `usuario`; `id_usuario_resuelve` → `usuario` | `estado` permitido; `motivo` no vacío; coherencia estado/resolución |
| `solicitud_reembolso_detalle` | (`id_solicitud_reembolso`, `id_boleto`) | `id_solicitud_reembolso` → `solicitud_reembolso` | La PK impide repetir un boleto en la misma solicitud |
| `acceso_puerta_log` | `id_acceso_puerta_log` | `id_usuario_operador` → `usuario` | `resultado`: aceptado o rechazado |
| `admin_operacion_audit` | `id_admin_operacion_audit` | `id_usuario_actor` → `usuario` | `motivo` no vacío |

## Diccionario de datos

| Tabla | Columna | Tipo | Significado y restricción |
| --- | --- | --- | --- |
| `rol` | `id_rol` | `SERIAL` | Identificador único del rol (PK). |
| `rol` | `nombre` | `VARCHAR(30)` | Nombre único: cliente, taquillero, operador_puerta, contador, administrador. |
| `usuario` | `id_usuario` | `SERIAL` | Identificador único de usuario (PK). |
| `usuario` | `id_rol` | `INT` | FK al rol del usuario. |
| `usuario` | `nombre` | `VARCHAR(100)` | Nombre del usuario; no puede estar en blanco. |
| `usuario` | `correo` | `VARCHAR(150)` | Único; debe estar en minúsculas y sin espacios laterales. |
| `usuario` | `password_hash` | `TEXT` | Hash de la contraseña. |
| `usuario` | `activo` | `BOOLEAN` | Estado de cuenta (DEFAULT `TRUE`). Inactivo no obtiene permisos. |
| `usuario` | `creado_en` | `TIMESTAMPTZ` | Instante de creación. |
| `rol_permiso` | `id_rol` | `INT` | FK al rol (PK compartida). |
| `rol_permiso` | `accion` | `VARCHAR(60)` | Nombre de la acción permitida (PK compartida). |
| `solicitud_reembolso` | `id_solicitud_reembolso` | `SERIAL` | Identificador único de la solicitud (PK). |
| `solicitud_reembolso` | `id_compra` | `INT` | Referencia a la compra de B. Sin FK temporalmente. |
| `solicitud_reembolso` | `id_usuario_actor` | `INT` | FK al usuario solicitante. |
| `solicitud_reembolso` | `motivo` | `TEXT` | Justificación; no vacía. |
| `solicitud_reembolso` | `estado` | `VARCHAR(20)` | pendiente, ejecutada o rechazada. |
| `solicitud_reembolso` | `creada_en` | `TIMESTAMPTZ` | Fecha/hora de creación. |
| `solicitud_reembolso` | `resuelta_en` | `TIMESTAMPTZ` | Fecha/hora de resolución (NULL mientras esté pendiente). |
| `solicitud_reembolso` | `id_usuario_resuelve` | `INT` | FK al usuario que resuelve (NULL mientras esté pendiente). |
| `solicitud_reembolso_detalle` | `id_solicitud_reembolso` | `INT` | FK a la solicitud (PK compartida). |
| `solicitud_reembolso_detalle` | `id_boleto` | `INT` | Referencia a boleto de B (PK compartida). Sin FK temporalmente. |
| `acceso_puerta_log` | `id_acceso_puerta_log` | `SERIAL` | Identificador único de log de puerta (PK). |
| `acceso_puerta_log` | `fecha` | `TIMESTAMPTZ` | Momento de lectura. |
| `acceso_puerta_log` | `id_boleto` | `INT` | Boleto escaneado (acepta NULL si el QR es inválido). |
| `acceso_puerta_log` | `id_funcion_solicitada` | `INT` | Función de destino (acepta NULL). |
| `acceso_puerta_log` | `id_usuario_operador` | `INT` | FK al operador en puerta. |
| `acceso_puerta_log` | `dispositivo` | `VARCHAR(100)` | Identificador del dispositivo de lectura. |
| `acceso_puerta_log` | `resultado` | `VARCHAR(20)` | aceptado o rechazado. |
| `acceso_puerta_log` | `motivo` | `VARCHAR(200)` | Causa en caso de rechazo. |
| `admin_operacion_audit` | `id_admin_operacion_audit` | `SERIAL` | Identificador de auditoría (PK). |
| `admin_operacion_audit` | `fecha` | `TIMESTAMPTZ` | Fecha y hora del evento. |
| `admin_operacion_audit` | `id_usuario_actor` | `INT` | FK al usuario que ejecutó la acción. |
| `admin_operacion_audit` | `rol_al_actuar` | `VARCHAR(30)` | Copia del rol al momento de la acción. |
| `admin_operacion_audit` | `ip` | `VARCHAR(45)` | Dirección IP del cliente. |
| `admin_operacion_audit` | `accion` | `VARCHAR(60)` | Identificador de la acción realizada. |
| `admin_operacion_audit` | `entidad` | `VARCHAR(60)` | Tabla/Entidad afectada. |
| `admin_operacion_audit` | `id_entidad` | `VARCHAR(60)` | Clave del registro afectado. |
| `admin_operacion_audit` | `motivo` | `TEXT` | Explicación requerida de la operación. |
| `admin_operacion_audit` | `cambios` | `JSONB` | Payload con los valores anteriores/nuevos. |

Las 7 tablas del Bloque C suman 39 columnas. Junto con las 15 tablas del Bloque A, la base de datos se conforma de 22 tablas en total.

## Normalización

- **Primera forma normal (1FN):** Atributos atómicos. Los permisos de un rol son registros individuales en `rol_permiso` y los boletos de una solicitud están individualizados en `solicitud_reembolso_detalle`.
- **Segunda forma normal (2FN):** En las tablas de clave primaria compuesta (`rol_permiso`, `solicitud_reembolso_detalle`), todos los atributos dependen funcionalmente de la totalidad de la clave.
- **Tercera forma normal (3FN):** Los datos descriptivos se ubican en su respectiva entidad (ej. el nombre del rol reside únicamente en `rol`).
  - *Excepción deliberada:* `rol_al_actuar` en `admin_operacion_audit` duplica el rol del usuario de forma intencional como snapshot histórico inmutable, previendo cambios futuros de rol del usuario.

## Límites conocidos

- **Sin FK hacia Bloque B:** `id_compra` e `id_boleto` se agregarán vía script de integración cuando el módulo B provea sus DDL.
- **Inmutabilidad en Aplicación:** Los triggers bloquean `UPDATE` y `DELETE` en las tablas de auditoría.