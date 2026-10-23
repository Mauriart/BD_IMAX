# Pruebas del esquema C

## Condiciones

Las comprobaciones manuales se realizaron en PostgreSQL desde DBeaver, en la base `imax_c`, después de instalar `instalacion_completa_A.sql` y `relacional_C.sql`. Los resultados fueron comunicados por el integrante al ejecutarlas, con el texto de los errores. No se adjuntan capturas de cada caso, salvo el listado de las 22 tablas. La tabla registra el resultado comunicado, no una ejecución automatizada independiente.

Las sentencias de error se ejecutan por separado. Tras un error, DBeaver puede dejar la transacción abortada y requiere Rollback. Los fallos consumen números de secuencia sin insertar registros; esto es normal con SERIAL.

## Comprobaciones positivas

| Caso | Comprobación | Esperado | Resultado comunicado |
| --- | --- | --- | --- |
| C-P01 | Listar las tablas del esquema public. | 22 tablas: 15 de A y 7 de C. | Confirmado; 22 tablas, con captura. |
| C-P02 | Consultar `rol`, `usuario` y contar `rol_permiso`. | 5 roles, 7 usuarios y 24 permisos. | Confirmado. |
| C-P03 | `autorizar_accion` de un administrador sobre `gestionar_catalogo`. | true | Confirmado. |
| C-P04 | `autorizar_accion` de un cliente sobre `gestionar_catalogo`. | false | Confirmado. |
| C-P05 | Contador sobre `ver_auditoria`. | true | Confirmado. |
| C-P06 | Operador de puerta sobre `validar_ingreso`. | true | Confirmado. |
| C-P07 | Operador de puerta sobre `resolver_reembolso`. | false | Confirmado. |
| C-P08 | Usuario inexistente. | false, sin error. | Confirmado. |
| C-P09 | Insertar una fila de auditoría con motivo válido. | Aceptada. | Aceptada. |
| C-P10 | Insertar una solicitud de reembolso pendiente. | Aceptada. | Aceptada. |

## Comprobaciones negativas

| Caso | Instrucción de prueba | Esperado | Resultado comunicado |
| --- | --- | --- | --- |
| C-N01 | Usuario con un correo ya registrado. | Rechazo por `uq_usuario_correo`. | Rechazado: `23505`, `uq_usuario_correo`. |
| C-N02 | Usuario con correo en mayúsculas. | Rechazo por `ck_usuario_correo_normalizado`. | Rechazado: `23514`, `ck_usuario_correo_normalizado`. |
| C-N03 | Usuario con `id_rol` inexistente. | Rechazo por `fk_usuario_rol`. | Rechazado: `23503`, `fk_usuario_rol`. |
| C-N04 | Auditoría con motivo en blanco. | Rechazo por `ck_audit_motivo`. | Rechazado: `23514`, `ck_audit_motivo`. |
| C-N05 | UPDATE sobre `admin_operacion_audit`. | Rechazo del trigger. | Rechazado: `42501`, «Los registros de admin_operacion_audit no se pueden modificar ni eliminar». |
| C-N06 | DELETE sobre `admin_operacion_audit`. | Rechazo del trigger. | Rechazado: `42501`, mismo mensaje. |
| C-N07 | Solicitud con estado `inventado`. | Rechazo por `ck_solicitud_estado`. | Rechazado: `23514`, `ck_solicitud_estado`. |
| C-N08 | Solicitud `ejecutada` sin quien la resolvió. | Rechazo por `ck_solicitud_resolucion`. | Rechazado: `23514`, `ck_solicitud_resolucion`. |
| C-N09 | Registro de puerta con resultado `quizas`. | Rechazo por `ck_puerta_resultado`. | Rechazado: `23514`, `ck_puerta_resultado`. |

Las sentencias están en [pruebas_C.sql](pruebas_C.sql). Las restricciones esperadas se identificaron a partir del DDL y coinciden con las comunicadas en los nueve casos.

## Efectos de las pruebas en la base

Las pruebas positivas C-P09 y C-P10 dejaron una fila de auditoría y una solicitud de reembolso en `imax_c`. La fila de auditoría **no puede borrarse** con DELETE, porque el trigger lo impide: es el comportamiento que se probó. En una base de ensayo se resuelve recreándola. [verificacion_C.sql](verificacion_C.sql) evita este efecto: se ejecuta dentro de una transacción que termina con ROLLBACK.

## Verificaciones adicionales

Estos scripts amplían las pruebas manuales. Se ejecutaron en una instancia temporal de PostgreSQL 16.15, sobre una réplica reducida de A (solo las tablas que C referencia, con sus mismas definiciones), no sobre `instalacion_completa_A.sql`. **Deben repetirse en `imax_c` desde DBeaver** (Alt+X) antes de darlos por verificados en la base del equipo.

| Verificación | Qué comprueba | Resultado en la instancia temporal |
| --- | --- | --- |
| [verificacion_C.sql](verificacion_C.sql) | Esquema, rechazos de restricciones, inmutabilidad, usuario inactivo | Todos los casos OK; sin residuos |
| [verificacion_matriz_C.sql](verificacion_matriz_C.sql) | Las 75 combinaciones rol-acción contra la lista esperada de los acuerdos | OK; con un permiso eliminado a propósito detecta la discrepancia |
| [verificacion_privilegios_C.sql](verificacion_privilegios_C.sql) | TRUNCATE bloqueado; `imax_app` solo agrega a los logs, no cambia la matriz ni borra usuarios | Todos los casos OK |
| [fixtures_B_sinteticos_C.sql](fixtures_B_sinteticos_C.sql) e [integracion_C_B.sql](integracion_C_B.sql) | Boletos de ejemplo; FK hacia compra y boleto; rechazo de un boleto de otra compra y de referencias inexistentes | OK |

## Alcance de los resultados

Los casos anteriores fueron ejecutados por el integrante en DBeaver. [verificacion_C.sql](verificacion_C.sql) automatiza los mismos casos con bloques EXCEPTION y se agrega como ayuda de repetición.

No se han ejecutado pruebas de concurrencia ni de rendimiento, ni integración con las tablas reales de B. Corresponden a C-07 y a las tareas posteriores.

Orden usado: `instalacion_completa_A.sql` → `relacional_C.sql` → pruebas positivas → pruebas negativas.
