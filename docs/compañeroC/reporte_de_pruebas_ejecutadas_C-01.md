# Reporte de Pruebas y Comprobaciones del Esquema C

## Entorno de Ejecución
- **Motor BD:** PostgreSQL
- **Cliente:** DBeaver
- **Base de datos:** `imax_c`
- **Estado global:** EXITOSO. Todas las comprobaciones negativas arrojaron las excepciones esperadas (`SQL Error`) y las pruebas positivas procesaron correctamente.

## Comprobaciones Positivas

| Caso | Operación | Resultado Esperado | Resultado Obtenido |
| --- | --- | --- | --- |
| **P1** | Insertar registro válido en `admin_operacion_audit` | Fila registrada correctamente | **EXITOSO** (Insertado correctamente) |
| **P2** | Insertar registro pendiente en `solicitud_reembolso` | Fila registrada correctamente | **EXITOSO** (Insertado correctamente) |

## Comprobaciones Negativas (Validación de Restricciones)

| Código Test | Excepción Levantada | Constraint / Feature | Detalle de Fallo Evaluado / Mensaje de Error | Status |
| --- | --- | --- | --- | --- |
| **N1** | `SQL Error [23505]` | `uq_usuario_correo` | Key `(correo)=(cliente1@imax.test)` already exists. | **PASÓ** |
| **N2** | `SQL Error [23514]` | `ck_usuario_correo_normalizado` | Failing row contains `(CLIENTE9@IMAX.TEST)`. Reject upper-case emails. | **PASÓ** |
| **N3** | `SQL Error [23503]` | `fk_usuario_rol` | Key `(id_rol)=(999)` is not present in table `rol`. | **PASÓ** |
| **N4** | `SQL Error [23514]` | `ck_audit_motivo` | Failing row contains empty string `' '` in `motivo`. | **PASÓ** |
| **N5** | `SQL Error [42501]` | `trg_admin_audit_inmutable` | UPDATE rejected by trigger: *"Los registros de admin_operacion_audit no se pueden modificar ni eliminar."* | **PASÓ** |
| **N6** | `SQL Error [42501]` | `trg_admin_audit_inmutable` | DELETE rejected by trigger: *"Los registros de admin_operacion_audit no se pueden modificar ni eliminar."* | **PASÓ** |
| **N7** | `SQL Error [23514]` | `ck_solicitud_estado` | Failing row contains invalid state `estado = 'inventado'`. | **PASÓ** |
| **N8** | `SQL Error [23514]` | `ck_solicitud_resolucion` | Executed refund request without specifying resolver user (`id_usuario_resuelve` NULL). | **PASÓ** |
| **N9** | `SQL Error [23514]` | `ck_puerta_resultado` | Access log containing invalid result `resultado = 'quizas'`. | **PASÓ** |

## Resumen

Todos los controles de integridad referencial, de dominio (`CHECK`), unicidad y triggers de inmutabilidad respondieron conforme a la especificación requerida en el Issue C-01.