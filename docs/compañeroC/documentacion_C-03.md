# Documentación C-03 — RBAC, reembolsos autorizados y auditoría de cambios críticos

**Proyecto II — Base de datos IMAX** · Bloque C · Integrante responsable: Ian (C)
**Issue:** [C-03 · #17](https://github.com/Mauriart/BD_IMAX/issues/17) · **Requisitos:** RN-17, RN-19, RN-20
**Entregable SQL:** `script_c03_rbac_reembolsos_auditoria.sql` (incremental sobre `imax.sql`)
**Estado:** parte de base de datos **completa y probada**; pendientes de interfaz e integración con B-04 en la sección 8.

> **Este documento reemplaza por completo** a `documentaci_n_integrante_c_issue_c_03.md` y a `script_de_base_de_datos_c_03.sql`, que describían otro proyecto (ver sección 1).

---

## 1. Veredicto de la revisión

| Pregunta | Respuesta |
| --- | --- |
| ¿Lo entregado antes cumplía el issue? | **No.** La documentación y el SQL trataban de «Eventos Recurrentes (RF-13/RF-14) — Agenda de Eventos y Tareas»: tablas `series_eventos` y `eventos`, que no existen en IMAX. Ningún requisito RN-17/19/20 estaba cubierto. |
| ¿El SQL anterior funcionaba? | **No.** Al ejecutarlo sobre `imax.sql` falla en el `ALTER TABLE eventos` con `relation "eventos" does not exist`. |
| ¿Qué había ya hecho en la BD? | C-01/C-02: `rol`, `rol_permiso`, `usuario`, `solicitud_reembolso(+detalle)`, `admin_operacion_audit`, `acceso_puerta_log`, la función `autorizar_accion`, triggers que impiden modificar/borrar/vaciar los logs y la validación de ingreso por QR. **No existían** las operaciones de reembolso, la política, ni la aplicación real de la matriz de roles. |
| ¿Se reparó y se completó? | **Sí.** Script nuevo y esta documentación. Se probó contra una instalación limpia de tu `imax.sql` (PostgreSQL 16): **94 comprobaciones aprobadas, 0 fallas**, más dos pruebas de concurrencia (sección 6). La versión final añade lo que faltaba del issue: **cortesías, cambio manual de asiento y consulta analítica de auditoría**. |
| ¿Necesita interfaz? | **Sí.** La tarea 2 del issue dice «con interfaz de gestión». **Por tu decisión se omite por ahora**; queda registrada como pendiente (sección 8) y el issue **no debe cerrarse** hasta hacerla. |

### Defectos encontrados en lo ya existente (y su corrección)

1. **Bug en C-02 (`validar_y_consumir_ingreso_qr`).** La variable `v_motivo_rechazo` era `VARCHAR(200)` pero la función devuelve `TEXT`. En **cada rechazo** (QR inexistente, boleto usado, anulado, otra función, fuera de horario) PostgreSQL lanzaba `structure of query does not match function result type`, y como la transacción se revertía, **el intento rechazado tampoco quedaba en `acceso_puerta_log`**. Esto rompía justo la demostración «reembolso → la puerta rechaza el boleto». Corregido en la sección 0 del script (solo cambia el tipo; el resto del cuerpo es idéntico).
2. **`search_path` sin fijar** en funciones `SECURITY DEFINER` (`validar_y_consumir_ingreso_qr`) y en `autorizar_accion`. Se fijó `public, pg_temp` para evitar suplantación de objetos.
3. **Dato de prueba incoherente:** la solicitud de reembolso nº 3 la creó el *Cliente Dos* (usuario 1) sobre la compra 1, que pertenece al *Cliente Uno* (usuario 2), y no tiene boletos asociados. Las funciones nuevas la rechazan (`DATOS_INVALIDOS`); el script solo avisa con un `NOTICE`. Se recomienda rechazarla o depurarla.

---

## 2. Trazabilidad: issue → implementación

| Elemento del issue | Implementación | Estado |
| --- | --- | --- |
| **T1** Aplicar matriz de roles en operaciones reales; colaborar con A/B | Triggers `trg_guardia_rbac` (BD) sobre las tablas de A + funciones con permiso explícito (`exigir_permiso`) | ✅ Lado BD. ⏳ A debe fijar `app.id_usuario` en su aplicación (secc. 5) |
| **T2** Solicitud/cancelación según política y permisos, con interfaz | `solicitar_reembolso()`, `politica_negocio` | ✅ Lógica. ⏳ **Interfaz omitida por ahora** |
| **T3** Invocar reversión de B; distinguir gestión/autorización de cambio transaccional | `resolver_reembolso()` (C autoriza) → `revertir_venta()` (B ejecuta) | ✅ Con **implementación provisional** de `revertir_venta`. ⏳ Sustituir por B-04 |
| **T4** Auditar cortesías, cambios de asiento, reembolsos forzados y configuración crítica con actor, rol, IP, fecha/hora, motivo | `auditar_accion()`, `auditar_cambio_critico()`, `cambiar_politica()`, `otorgar_cortesia()`, `cambiar_asiento_boleto()` | ✅ Reembolsos, configuración, programación, distribución, precios, roles, **cortesías y cambios de asiento** (operación y auditoría en la misma transacción) |
| **CA1** Cliente/taquillero no modifican salas/precios; operador no vende; contador no reprograma | Pruebas C03-01 y C03-02 | ✅ |
| **CA2** Ocultar botones no es la única protección | La protección está en la BD (triggers y funciones), no en la pantalla | ✅ |
| **CA3** Reembolso permitido invalida boleto y libera asiento; fuera de política se rechaza salvo override autorizado y auditado | Pruebas C03-08 a C03-14, C03-19 | ✅ Invalida boleto y actualiza compra; el asiento queda libre para la venta (`asiento_ocupado()` ya no lo cuenta; probado en C03-25). ⏳ Cuando B publique `inventario_funcion`, `revertir_venta` debe liberar también ese inventario |
| **CA4** Integración final usa B-04; historial administrativo consultable e inalterable | `consultar_auditoria_admin()`, triggers de inmutabilidad (C-01) | ✅ Historial. ⏳ Integración con B-04 |

---

## 3. Qué agrega el script

| Objeto | Tipo | Función |
| --- | --- | --- |
| `politica_negocio` | tabla | Políticas centralizadas. Inicial: `reembolso_horas_antes = 2`. |
| `rol_permiso` (4 filas nuevas, solo administrador) | datos | `forzar_reembolso`, `configurar_politicas`, `otorgar_cortesia`, `cambiar_asiento`. |
| `normalizar_ip`, `politica_entero` | funciones | Validación de IP y lectura de política. |
| `auditar_accion` | función | Escribe en `admin_operacion_audit`. **El rol se toma de la BD**, no de un parámetro, para que no se falsifique. |
| `exigir_permiso` | función | Comprueba permiso y, si se deniega, **registra el intento denegado**. |
| `solicitar_reembolso` | función | Alta de la solicitud (RN-19). |
| `resolver_reembolso` | función | Ejecutar o rechazar; override con `p_forzar`. |
| `revertir_venta` | función | **Contrato de B-04** (provisional, ver 4.3). |
| `cambiar_politica` | función | Configuración crítica auditada. |
| `consultar_auditoria_admin` | función | Historial consultable por rol con `ver_auditoria`. |
| `asiento_ocupado` | función | Indica si un asiento de una función está reservado/vendido (boleto no anulado en compra pendiente, pagada o parcialmente reembolsada). |
| `otorgar_cortesia` | función | El administrador otorga un boleto gratuito (total 0): crea compra, detalle y boleto, y audita. |
| `cambiar_asiento_boleto` | función | El administrador cambia el asiento de un boleto emitido (misma zona, función futura) y audita antes/después. |
| `resumen_auditoria_admin` | función | Consulta analítica: acciones manuales de administradores (último mes por omisión) agrupadas por ID de administrador y acción. |
| `guardia_rbac`, `auditar_cambio_critico`, `guardia_alta_usuario` | triggers | RBAC y auditoría automática sobre las tablas de A y `usuario`. |

Todas las funciones nuevas son `SECURITY DEFINER` con `search_path` fijo, **sin EXECUTE para PUBLIC**; solo `imax_app` puede llamarlas. `revertir_venta` **no** se concede a `imax_app`: solo se invoca desde la gestión de C.

---

## 4. Reglas de negocio implementadas

### 4.1 Matriz de roles (RN-17)

La matriz vive en `rol_permiso` y se consulta con `autorizar_accion(id_usuario, accion)`. Resumen de lo que ahora se hace cumplir:

| Acción | Cliente | Taquillero | Operador puerta | Contador | Administrador |
| --- | :-: | :-: | :-: | :-: | :-: |
| Gestionar catálogo, salas, funciones (`gestionar_catalogo`) | — | — | — | — | ✔ |
| Configurar tarifas/promociones (`configurar_tarifas`) | — | — | — | — | ✔ |
| Solicitar reembolso | ✔ propios | ✔ | — | — | ✔ |
| Resolver reembolso / forzar | — | — | — | — | ✔ / ✔ |
| Vender (`reservar_comprar`, `venta_presencial`) | ✔ / — | — / ✔ | — | — | — |
| Validar ingreso | — | — | ✔ | — | — |
| Ver historial administrativo (`ver_auditoria`) | — | — | — | ✔ | ✔ |
| Administrar usuarios / políticas | — | — | — | — | ✔ |

### 4.2 Política de reembolso (acuerdos, sección 6)

- **Ordinario:** se puede *solicitar y ejecutar* hasta **2 horas antes** del inicio, **inclusive** (`ahora <= inicio − 2 h`). Solo boletos `emitido`.
- **Excepcional:** únicamente el administrador, con `p_forzar = TRUE` y **motivo escrito**; queda auditado como `reembolso_forzado` con `fuera_de_politica = true`.
- **Nunca** se reembolsa un boleto `usado` o `anulado`, ni siquiera forzando.
- El cliente solo opera sobre sus compras; taquillero y administrador actúan en nombre de un cliente.
- Un boleto no puede estar en dos solicitudes pendientes a la vez.
- Se valida en **dos momentos** (al solicitar y al ejecutar), porque entre ambos puede cambiar la hora o el estado del boleto.
- El monto devuelto es el `total_linea` **histórico** de cada boleto (incluye descuento distribuido); nunca se recalcula con tarifas actuales.
- La compra pasa a `reembolsada` si no queda ningún boleto sin anular, o a `parcialmente_reembolsada` en otro caso (p. ej. queda uno usado).

### 4.3 Reparto C / B en la reversión

```
cliente/taquillero ──► solicitar_reembolso()      (C: permisos, propiedad, política)
administrador      ──► resolver_reembolso()       (C: autoriza, audita)
                          └──► revertir_venta()   (B: anula boleto, actualiza compra, libera)
```

`resolver_reembolso` bloquea solicitud → compra → boletos (en orden de ID, el mismo que usa la validación de ingreso), de modo que **un reembolso y un ingreso simultáneos compiten por el mismo boleto** y solo uno gana (probado, sección 6).

`revertir_venta(p_id_solicitud_reembolso integer, p_referencia text) → (monto_reembolsado numeric, boletos_anulados integer)` se crea **solo si B no publicó la suya**; si ya existe, el script no la toca. Faltan en el dump actual las tablas de B (`pago`, `reserva`, `inventario_funcion`, `reembolso`), por lo que la versión provisional **no libera inventario ni registra el reembolso/pago**. B debe completar eso en B-04 respetando esta firma.

### 4.4 Auditoría (RN-20)

Cada registro de `admin_operacion_audit` guarda actor, **rol al actuar** (tomado de la BD), IP, fecha/hora, acción, entidad, id, **motivo obligatorio** y `cambios` (JSON antes/después; nunca incluye `password_hash`).

| Acción registrada | Origen |
| --- | --- |
| `reembolso_ordinario`, `reembolso_forzado`, `rechazar_reembolso` | `resolver_reembolso` |
| `configurar_politica` | `cambiar_politica` |
| `otorgar_cortesia` | `otorgar_cortesia` (guarda boleto, asiento, cliente y valor de la cortesía) |
| `cambio_asiento` | `cambiar_asiento_boleto` (guarda el asiento antes/después) |
| `insert/update/delete_` + `sala`, `zona`, `asiento`, `funcion`, `tarifa`, `promocion`, `categoria_entrada` | trigger `auditar_cambio_critico` |
| `update/delete_usuario` (rol/estado), `insert_usuario` (no cliente) | triggers sobre `usuario` |
| `denegado:<permiso>`, `denegado:compra_ajena` | intentos denegados en las funciones |

**Inalterable:** los triggers de C-01 impiden `UPDATE`, `DELETE` y `TRUNCATE`; probado. **Consultable:** `consultar_auditoria_admin(id_usuario, desde, hasta, id_actor, accion)` (intervalo `[desde, hasta)`).

### 4.5 Cortesías y cambios manuales de asiento (RN-20)

Ambas son exclusivas del administrador (`otorgar_cortesia`, `cambiar_asiento`), exigen **IP válida y motivo escrito** y se ejecutan **junto con su auditoría en una sola transacción** (si la auditoría falla, la operación se revierte). Los intentos de otros roles se rechazan con `NO_AUTORIZADO` y quedan auditados como `denegado:<permiso>`.

| Regla | `otorgar_cortesia` | `cambiar_asiento_boleto` |
| --- | --- | --- |
| Función | Activa y futura | Futura (no ha iniciado) |
| Beneficiario / boleto | Cliente activo | Boleto `emitido` (no usado ni anulado) |
| Asiento | Pertenece a la sala de la función y está libre | Misma sala **y misma zona**; otra zona → `ZONA_DISTINTA` (implica recalcular precio, responsabilidad de B) |
| Importe | `precio_base` = tarifa de función/zona/categoría, `descuento` = tarifa, `total_linea` = 0 | No cambia |
| Códigos de rechazo | `DATOS_INVALIDOS`, `NO_ENCONTRADO`, `ESTADO_INVALIDO`, `REFERENCIA_CONFLICTIVA`, `NO_AUTORIZADO` | los mismos + `ZONA_DISTINTA` |

**Exclusión entre operaciones simultáneas:** mientras B no publique `inventario_funcion` con unicidad vigente por función/asiento, ambas funciones toman un bloqueo asesor `pg_advisory_xact_lock(id_funcion, id_asiento)` antes de verificar la disponibilidad. Dos cortesías al mismo asiento en paralelo producen un éxito y un `REFERENCIA_CONFLICTIVA` (prueba C03-27). Este bloqueo **solo protege frente a operaciones de C**; la venta en línea de B debe apoyarse en la restricción de unicidad de su inventario (sección 8). El boleto se bloquea primero, en el mismo orden que usan el ingreso y el reembolso, para evitar interbloqueos.

---

## 5. Cómo integrar con A y B

**A (Flask).** Al abrir la transacción de cualquier escritura administrativa, la aplicación debe fijar el actor **que sale de la sesión autenticada, nunca de un formulario**:

```python
cur.execute("SELECT set_config('app.id_usuario', %s, true), set_config('app.ip', %s, true), set_config('app.motivo', %s, true)",
            (str(session['id_usuario']), request.remote_addr, motivo))
```

Reglas del trigger `guardia_rbac`: con actor → exige el permiso; **sin actor y conectado como `imax_app` → rechaza**; sin actor con otra cuenta (migraciones, DBeaver) → permite. Así la aplicación actual de A **sigue funcionando** mientras se integra. Un rechazo por permiso aborta la transacción (SQLSTATE `42501`); para dejar constancia del intento, la app puede llamar luego a `exigir_permiso(...)`. Si falta `app.motivo`, el cambio se revierte (el motivo es obligatorio).

**B.** Reemplazar `revertir_venta` por la versión real (misma firma), liberar `inventario_funcion` y registrar reembolso/pago. Cuando exista el inventario, `asiento_ocupado()`, `otorgar_cortesia()` y `cambiar_asiento_boleto()` deben apoyarse en él (mismas firmas) en lugar del bloqueo asesor, y la venta en línea debe respetar la misma unicidad por función/asiento.

**Endurecimiento recomendado (no aplicado por no romper código de C-01):** `REVOKE SELECT, INSERT ON admin_operacion_audit FROM imax_app;` cuando todo pase por las funciones.

---

## 6. Casos de prueba y resultados

**Entorno:** PostgreSQL 16 en un entorno aislado, cargando tu `imax.sql` limpio (se retiraron las líneas `\restrict`/`\unrestrict` y `SET transaction_timeout` propias de `pg_dump` 18). Script ejecutado dos veces para comprobar que es repetible. Cada prueba corre dentro de una transacción que termina en `ROLLBACK`. **Resultado final: 94 comprobaciones aprobadas, 0 fallas** (script ejecutado dos veces para comprobar que es repetible). Conviene repetirlas en tu PostgreSQL 18 con el script del Anexo A.

| ID | Requisito | Qué se comprueba | Resultado |
| --- | --- | --- | --- |
| C03-01 | RN-17 | Cliente no configura tarifas; taquillero no gestiona catálogo; operador no vende; contador no reprograma; administrador sí | ✅ |
| C03-02 | RN-17 / CA1 | Usuarios 1, 3, 4 y 6 son rechazados al crear sala, cambiar precio y reprogramar; el precio queda intacto | ✅ |
| C03-03 | RN-20 | Administrador sin motivo: revertido. Con motivo: audita actor, rol, IP, motivo y antes/después (precio y asiento) | ✅ |
| C03-04 | RN-17 | Un cliente no puede crear un administrador ni ascenderse; el registro de clientes sigue permitido | ✅ |
| C03-05 | RN-17 | `imax_app` sin actor autenticado es rechazado | ✅ |
| C03-06 | RN-17 / RN-20 | Cliente sobre compra ajena y operador sin permiso: `NO_AUTORIZADO`; ambos intentos auditados | ✅ |
| C03-07 | RN-19 | Boleto usado, anulado o de otra compra: `ESTADO_INVALIDO`; motivo vacío/IP inválida/boletos repetidos: `DATOS_INVALIDOS` | ✅ |
| C03-08 | RN-19 | Solicitud propia dentro de política se crea; solicitud duplicada pendiente: `REFERENCIA_CONFLICTIVA` | ✅ |
| C03-09 | RN-17 | Taquillero y cliente no resuelven reembolsos; la app no puede llamar `revertir_venta` | ✅ |
| C03-10 | RN-19 / CA3 | Ejecución ordinaria: monto 8.00, boleto anulado, compra `parcialmente_reembolsada`, solicitud `ejecutada`, auditado; repetir → `ESTADO_INVALIDO`; no se reembolsa dos veces | ✅ |
| C03-11 | RN-19 | A 1 h del inicio, cliente y taquillero: `FUERA_DE_POLITICA`; el administrador sí puede crear la solicitud excepcional | ✅ |
| C03-12 | RN-19 / CA3 | Sin override: rechazado y el boleto sigue `emitido`; override sin motivo: rechazado; override con motivo: ejecuta y audita `reembolso_forzado` | ✅ |
| C03-13 | RN-19 | Boleto que se usa entre la solicitud y la resolución: no se reembolsa, ni siquiera forzando | ✅ |
| C03-14 | RN-19 | Rechazar exige motivo; solicitud heredada sin boletos no se ejecuta | ✅ |
| C03-15 | RN-20 | Administrador cambia política y queda auditado (`anterior: 2, nuevo: 4`); contador no puede | ✅ |
| C03-16 | CA4 | Contador consulta el historial y filtra por acción; cliente no | ✅ |
| C03-17 | CA4 | `UPDATE`, `DELETE` y `TRUNCATE` sobre la auditoría bloqueados | ✅ |
| C03-18 | RN-14 | Puerta acepta boleto emitido; segundo escaneo: «Entrada ya utilizada» | ✅ |
| C03-19 | RN-19 | Tras reembolso forzado, la puerta rechaza el boleto («Boleto anulado o reembolsado previamente») y el intento queda en `acceso_puerta_log`; QR inexistente también queda registrado | ✅ |
| C03-21 | RN-17 / RN-20 | Contador, taquillero y cliente no otorgan cortesías (`NO_AUTORIZADO`, 3 intentos auditados); motivo vacío/IP inválida, asiento ocupado y beneficiario que no es cliente se rechazan | ✅ |
| C03-22 | RN-20 | Cortesía válida: compra con total 0, boleto `emitido`, asiento ocupado; auditada con actor, IP, motivo y boleto; el asiento no se duplica | ✅ |
| C03-23 | RN-17 / RN-20 | Cambio de asiento: taquillero rechazado; asiento ocupado, boleto usado, mismo asiento, otra zona y motivo vacío rechazados | ✅ |
| C03-24 | RN-20 | Cambio válido dentro de la zona: el detalle apunta al asiento nuevo, auditoría antes/después, asiento anterior libre | ✅ |
| C03-25 | RN-19 | El reembolso de una cortesía anula el boleto y **libera el asiento** | ✅ |
| C03-26 | RN-20 / CA4 | `resumen_auditoria_admin`: el contador lo consulta (solo filas de administradores, sin denegados); el taquillero no | ✅ |
| C03-27 | RN-20 | **Concurrencia (dos conexiones):** dos cortesías al mismo asiento → una `OK` y otra `REFERENCIA_CONFLICTIVA`; queda una sola fila | ✅ |
| C03-20 | RN-14 / RN-19 | **Concurrencia (dos conexiones):** A ejecuta el reembolso y retiene el bloqueo; B intenta el ingreso. B espera, y al liberarse recibe «Boleto anulado o reembolsado previamente». Estado final: `anulado`, sin doble efecto | ✅ |

*Nota de método:* una consulta que modifica y lee la misma tabla en una sola sentencia no ve su propio cambio (comportamiento normal de PostgreSQL). En la revisión final se corrigió así la prueba C03-19 («QR inexistente»), que fallaba por ese motivo y no por la función; las pruebas nuevas usan `\gset` para separar la acción de su verificación. C03-20 se revisó en la entrega anterior; C03-27 se ejecutó en esta versión con dos sesiones simultáneas.

---

## 7. Instalación y ejecución

```bash
psql -v ON_ERROR_STOP=1 -d <tu_base> -f script_c03_rbac_reembolsos_auditoria.sql
```

Requisitos: haber cargado antes `imax.sql` (o su equivalente). Es repetible. No borra ni modifica datos; solo emite un `NOTICE` si encuentra solicitudes heredadas incoherentes. Si el rol `imax_app` no existe, simplemente se omiten los `GRANT`.

Ejemplos de uso:

```sql
-- Cliente 2 solicita reembolso de todos los boletos emitidos de su compra 1
SELECT * FROM solicitar_reembolso(2, 1, NULL, 'Cambio de planes', '127.0.0.1');
-- Administrador (7) la ejecuta
SELECT * FROM resolver_reembolso(7, <id_solicitud>, 'ejecutar', NULL, '127.0.0.1');
-- Fuera de política, con override
SELECT * FROM resolver_reembolso(7, <id_solicitud>, 'ejecutar', 'Cancelación de la función', '127.0.0.1', TRUE);
-- Cortesía: el administrador (7) otorga el asiento 5, categoría Adulto, al cliente 2
SELECT * FROM otorgar_cortesia(7, 1, 5, 2, 1, 'Invitado de prensa', '127.0.0.1');
-- Cambio manual de asiento del boleto 4 al asiento 6 (misma zona)
SELECT * FROM cambiar_asiento_boleto(7, 4, 6, 'Pedido del cliente', '127.0.0.1');
-- Historial del último mes (contador)
SELECT * FROM consultar_auditoria_admin(6, now() - interval '30 days', now());
-- Consulta analítica de la pauta: operaciones críticas del último mes por administrador
SELECT * FROM resumen_auditoria_admin(6);
```

---

## 8. Pendientes (no se declaran cumplidos)

| Pendiente | Responsable | Detalle |
| --- | --- | --- |
| **Interfaz de gestión** (omitida por ahora) | C | (a) Cliente/taquillero: elegir boletos y solicitar reembolso; (b) Administrador: lista de solicitudes con *ejecutar / rechazar / forzar*; (c) Historial administrativo para contador y administrador. La interfaz solo llama a las funciones de este script. |
| Fijar `app.id_usuario`/`app.ip`/`app.motivo` en Flask | A (con C) | Sin esto, la aplicación debe seguir conectándose con la cuenta propietaria; con `imax_app` se rechazará. |
| `revertir_venta` real, inventario, pago y reembolso | B (B-01/B-04) | Hoy no registran el reembolso/pago ni liberan un inventario propio (para C el asiento sí queda libre, porque `asiento_ocupado` excluye boletos anulados). Además, `uq_cd_asiento` solo impide repetir un asiento *dentro de la misma compra*; la unicidad vigente por función/asiento debe resolverla el inventario de B. |
| Unicidad de asiento por función en la venta en línea | B (B-01) | Cortesías y cambios de asiento ya tienen su propio bloqueo, pero la reserva/compra de B debe usar una restricción única vigente por función/asiento (RN-03, RN-05, doble venta). |
| Cierre del issue #17 | C | Solo cuando estén la interfaz y la integración con B-04. |

**Matriz de requisitos (`docs/requisitos.md`):** RN-17, RN-19 y RN-20 pasan a *Verificado en BD; interfaz e integración con B-04 pendientes*. La revisión cruzada de B sigue pendiente aunque las pruebas pasen: ninguna aprobación se presume.

---

## 9. Subir el trabajo a GitHub (paso a paso)

Convención del equipo: issues y PR, sin GitHub Projects; ramas con el código de la tarea; commits con `feat:`/`fix:`/`docs:`/`test:`; revisión cruzada (**B revisa a C**).

1. **Abrir la terminal en la carpeta del repositorio** `BD_IMAX` y actualizar:
   ```bash
   git checkout main
   git pull origin main
   ```
2. **Crear la rama de la tarea:**
   ```bash
   git checkout -b c-03-rbac-reembolsos-auditoria
   ```
3. **Copiar los archivos nuevos** donde están los de C-01/C-02 (si no hay carpeta, usa `sql/` para el `.sql` y `docs/` para el `.md`) y **eliminar los dos archivos equivocados** (`script_c03_eventos_recurrentes.sql`, `documentacion_c03.md`) si ya los habías agregado.
4. **Revisar qué vas a subir:**
   ```bash
   git status
   ```
5. **Agregar y confirmar** (ajusta las rutas a donde los pusiste):
   ```bash
   git add sql/script_c03_rbac_reembolsos_auditoria.sql docs/documentacion_c03_rbac_reembolsos_auditoria.md
   git commit -m "feat: RBAC, reembolsos autorizados y auditoria de cambios criticos (C-03)"
   ```
   Si necesitas quitar los archivos viejos: `git rm <archivo>` y un commit `fix: retirar archivos de otro proyecto`.
6. **Publicar la rama:**
   ```bash
   git push -u origin c-03-rbac-reembolsos-auditoria
   ```
7. **Abrir el Pull Request** en GitHub («Compare & pull request»). En la descripción escribe: qué cambia, que cubre el [issue #17](https://github.com/Mauriart/BD_IMAX/issues/17), el resultado de las pruebas y los pendientes de la sección 8. **Usa «Refs #17», no «Closes #17»**, para que el issue no se cierre solo, porque falta la interfaz. Pide revisión a `keilynsolanotencio-dev` (B).
8. Tras la aprobación, integrar (*Merge*). El issue se cierra únicamente cuando se completen los pendientes.

---

## Anexo A — Script de pruebas reproducible

Ejecutar con `psql -d <tu_base> -q -f pruebas_c03.sql`. Todo termina en `ROLLBACK`, así que no deja datos. Cada línea `NOTICE` indica `OK` o `FALLA`. Usa el escenario del `imax.sql` (usuarios 1-2 clientes, 3 taquillero, 4-5 puerta, 6 contador, 7 administrador; función 1 el 29/10/2026). Requiere el rol `imax_app` y **una base recién cargada** (depende de los estados iniciales de los boletos). Resultado esperado: 94 líneas `OK` y ninguna `FALLA`.

```sql
\set ON_ERROR_STOP off
BEGIN;
CREATE FUNCTION pg_temp.chk(nombre text, ok boolean, detalle text DEFAULT '') RETURNS void LANGUAGE plpgsql AS $$
BEGIN RAISE NOTICE '% | %  %', CASE WHEN ok THEN 'OK   ' ELSE 'FALLA' END, nombre, detalle; END $$;

-- ===== RBAC: matriz de permisos (usuarios: 1,2 cliente; 3 taquillero; 4,5 puerta; 6 contador; 7 admin)
SELECT pg_temp.chk('C03-01 cliente NO configura tarifas', NOT autorizar_accion(1,'configurar_tarifas'));
SELECT pg_temp.chk('C03-01 taquillero NO gestiona catalogo/salas', NOT autorizar_accion(3,'gestionar_catalogo'));
SELECT pg_temp.chk('C03-01 operador NO vende', NOT autorizar_accion(4,'venta_presencial') AND NOT autorizar_accion(4,'reservar_comprar'));
SELECT pg_temp.chk('C03-01 contador NO reprograma', NOT autorizar_accion(6,'gestionar_catalogo'));
SELECT pg_temp.chk('C03-01 admin SI gestiona', autorizar_accion(7,'gestionar_catalogo') AND autorizar_accion(7,'configurar_tarifas'));

-- ===== RBAC en la BD sobre operaciones reales de A (trigger guardia)
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['1','3','4','6'] LOOP
    PERFORM set_config('app.id_usuario', t, true);
    BEGIN INSERT INTO sala(id_cine,nombre) VALUES (1,'Intruso '||t); RAISE NOTICE 'FALLA | usuario % inserto sala', t;
    EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'OK    | C03-02 usuario % rechazado al crear sala', t; END;
    BEGIN UPDATE tarifa SET monto=0 WHERE id_tarifa=1; RAISE NOTICE 'FALLA | usuario % cambio precio', t;
    EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'OK    | C03-02 usuario % rechazado al cambiar precio', t; END;
    BEGIN UPDATE funcion SET inicio=inicio WHERE id_funcion=1; RAISE NOTICE 'FALLA | usuario % reprogramo', t;
    EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'OK    | C03-02 usuario % rechazado al reprogramar', t; END;
  END LOOP; END $$;
SELECT pg_temp.chk('C03-02 precio intacto', (SELECT monto FROM tarifa WHERE id_tarifa=1)=8.00);

-- admin sin motivo -> revierte; con motivo -> audita
SELECT set_config('app.id_usuario','7',true), set_config('app.ip','10.0.0.9',true), set_config('app.motivo','',true);
DO $$ BEGIN UPDATE tarifa SET monto=9 WHERE id_tarifa=1; RAISE NOTICE 'FALLA | admin sin motivo paso';
 EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK    | C03-03 admin sin motivo rechazado'; END $$;
SELECT set_config('app.motivo','Ajuste de precio promocional',true);
UPDATE tarifa SET monto=9 WHERE id_tarifa=1;
SELECT pg_temp.chk('C03-03 audito cambio de precio con actor/rol/ip/motivo',
  EXISTS(SELECT 1 FROM admin_operacion_audit WHERE accion='update_tarifa' AND id_usuario_actor=7 AND rol_al_actuar='administrador' AND ip='10.0.0.9' AND motivo='Ajuste de precio promocional' AND cambios->'antes'->>'monto'='8.00' AND cambios->'despues'->>'monto'='9.00'));
INSERT INTO asiento(id_zona,fila,numero) VALUES (1,'Z',1);
SELECT pg_temp.chk('C03-03 audito distribucion (asiento)', EXISTS(SELECT 1 FROM admin_operacion_audit WHERE accion='insert_asiento'));
UPDATE tarifa SET monto=8 WHERE id_tarifa=1;

-- usuarios: sin escalada
SELECT set_config('app.id_usuario','1',true);
DO $$ BEGIN INSERT INTO usuario(id_rol,nombre,correo,password_hash) VALUES (5,'Falso admin','x@x.test','h'); RAISE NOTICE 'FALLA | cliente creo admin';
 EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'OK    | C03-04 cliente no puede crear admin'; END $$;
DO $$ BEGIN UPDATE usuario SET id_rol=5 WHERE id_usuario=1; RAISE NOTICE 'FALLA | cliente se ascendio';
 EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'OK    | C03-04 cliente no puede cambiar roles'; END $$;
INSERT INTO usuario(id_rol,nombre,correo,password_hash) VALUES (1,'Nuevo cliente','nuevo@x.test','h');
SELECT pg_temp.chk('C03-04 registro de cliente permitido', true);

-- rol de la app sin actor
RESET app.id_usuario; SELECT set_config('app.id_usuario','',true);
GRANT ALL ON sala TO imax_app;
SET ROLE imax_app;
DO $$ BEGIN INSERT INTO sala(id_cine,nombre) VALUES (1,'Sin actor'); RAISE NOTICE 'FALLA | imax_app sin actor inserto';
 EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'OK    | C03-05 imax_app sin actor rechazado'; END $$;
RESET ROLE;

-- ===== Reembolsos
-- solicitar
SELECT pg_temp.chk('C03-06 cliente ajeno rechazado', (SELECT codigo FROM solicitar_reembolso(1,1,NULL,'quiero','127.0.0.1'))='NO_AUTORIZADO');
SELECT pg_temp.chk('C03-06 operador sin permiso', (SELECT codigo FROM solicitar_reembolso(4,1,NULL,'x','127.0.0.1'))='NO_AUTORIZADO');
SELECT pg_temp.chk('C03-06 denegaciones quedaron auditadas', (SELECT count(*) FROM admin_operacion_audit WHERE accion LIKE 'denegado:%')>=2);
SELECT pg_temp.chk('C03-07 boleto usado rechazado', (SELECT codigo FROM solicitar_reembolso(2,1,ARRAY[2],'x','127.0.0.1'))='ESTADO_INVALIDO');
SELECT pg_temp.chk('C03-07 boleto anulado/compra reembolsada', (SELECT codigo FROM solicitar_reembolso(1,2,NULL,'x','127.0.0.1'))='ESTADO_INVALIDO');
SELECT pg_temp.chk('C03-07 boleto de otra compra', (SELECT codigo FROM solicitar_reembolso(2,1,ARRAY[4],'x','127.0.0.1'))='ESTADO_INVALIDO');
SELECT pg_temp.chk('C03-07 motivo vacio / ip mala', (SELECT codigo FROM solicitar_reembolso(2,1,NULL,' ','127.0.0.1'))='DATOS_INVALIDOS' AND (SELECT codigo FROM solicitar_reembolso(2,1,NULL,'x','no-ip'))='DATOS_INVALIDOS');
SELECT pg_temp.chk('C03-07 boletos repetidos', (SELECT codigo FROM solicitar_reembolso(2,1,ARRAY[1,1],'x','127.0.0.1'))='DATOS_INVALIDOS');
SELECT * FROM solicitar_reembolso(2,1,NULL,'Cambio de planes','127.0.0.1') \gset s1_
SELECT pg_temp.chk('C03-08 cliente propio en politica crea solicitud', :'s1_exito'='t' AND :'s1_codigo'='OK', 'id='||:'s1_id_solicitud');
SELECT pg_temp.chk('C03-08 duplicada pendiente', (SELECT codigo FROM solicitar_reembolso(3,1,ARRAY[1],'x','127.0.0.1'))='REFERENCIA_CONFLICTIVA');

-- resolver sin permiso
SELECT pg_temp.chk('C03-09 taquillero no resuelve', (SELECT codigo FROM resolver_reembolso(3,:s1_id_solicitud,'ejecutar',NULL,'127.0.0.1'))='NO_AUTORIZADO');
SELECT pg_temp.chk('C03-09 cliente no resuelve', (SELECT codigo FROM resolver_reembolso(2,:s1_id_solicitud,'ejecutar',NULL,'127.0.0.1'))='NO_AUTORIZADO');
SELECT pg_temp.chk('C03-09 app no puede llamar revertir_venta', NOT has_function_privilege('imax_app','revertir_venta(integer,text)','EXECUTE'));
-- ejecutar ordinario
SELECT * FROM resolver_reembolso(7,:s1_id_solicitud,'ejecutar',NULL,'192.168.1.5') \gset r1_
SELECT pg_temp.chk('C03-10 reembolso ordinario OK', :'r1_exito'='t' AND :r1_monto_devuelto=8.00, 'monto='||:'r1_monto_devuelto');
SELECT pg_temp.chk('C03-10 boleto 1 anulado', (SELECT estado FROM boleto WHERE id_boleto=1)='anulado');
SELECT pg_temp.chk('C03-10 compra 1 parcial (queda el boleto usado)', (SELECT estado FROM compra WHERE id_compra=1)='parcialmente_reembolsada');
SELECT pg_temp.chk('C03-10 solicitud ejecutada', (SELECT estado FROM solicitud_reembolso WHERE id_solicitud_reembolso=:s1_id_solicitud)='ejecutada');
SELECT pg_temp.chk('C03-10 auditoria reembolso_ordinario', EXISTS(SELECT 1 FROM admin_operacion_audit WHERE accion='reembolso_ordinario' AND ip='192.168.1.5' AND id_entidad=:s1_id_solicitud::text));
SELECT pg_temp.chk('C03-10 repetir resolver rechazado', (SELECT codigo FROM resolver_reembolso(7,:s1_id_solicitud,'ejecutar',NULL,'127.0.0.1'))='ESTADO_INVALIDO');
SELECT pg_temp.chk('C03-10 boleto anulado no vuelve a solicitarse', (SELECT codigo FROM solicitar_reembolso(2,1,ARRAY[1],'x','127.0.0.1'))='ESTADO_INVALIDO');

-- fuera de politica: funcion inicia en 1 hora
UPDATE funcion SET inicio=now()+interval '1 hour', fin=now()+interval '3 hours' WHERE id_funcion=1;
SELECT pg_temp.chk('C03-11 cliente fuera de politica rechazado', (SELECT codigo FROM solicitar_reembolso(2,3,NULL,'tarde','127.0.0.1'))='FUERA_DE_POLITICA');
SELECT pg_temp.chk('C03-11 taquillero tambien', (SELECT codigo FROM solicitar_reembolso(3,3,NULL,'tarde','127.0.0.1'))='FUERA_DE_POLITICA');
SELECT * FROM solicitar_reembolso(7,3,NULL,'Cancelacion de funcion por falla tecnica','127.0.0.1') \gset s2_
SELECT pg_temp.chk('C03-11 admin crea solicitud excepcional', :'s2_codigo'='OK');
SELECT pg_temp.chk('C03-12 ejecutar sin override rechazado', (SELECT codigo FROM resolver_reembolso(7,:s2_id_solicitud,'ejecutar',NULL,'127.0.0.1'))='FUERA_DE_POLITICA');
SELECT pg_temp.chk('C03-12 boleto 4 sigue emitido', (SELECT estado FROM boleto WHERE id_boleto=4)='emitido');
SELECT pg_temp.chk('C03-12 override sin motivo rechazado', (SELECT codigo FROM resolver_reembolso(7,:s2_id_solicitud,'ejecutar',' ','127.0.0.1',true))='DATOS_INVALIDOS');
SELECT * FROM resolver_reembolso(7,:s2_id_solicitud,'ejecutar','Cancelacion de funcion por falla tecnica','127.0.0.1',true) \gset r2_
SELECT pg_temp.chk('C03-12 override autorizado ejecuta', :'r2_exito'='t' AND (SELECT estado FROM boleto WHERE id_boleto=4)='anulado' AND (SELECT estado FROM compra WHERE id_compra=3)='reembolsada');
SELECT pg_temp.chk('C03-12 auditado como reembolso_forzado', EXISTS(SELECT 1 FROM admin_operacion_audit WHERE accion='reembolso_forzado' AND (cambios->>'fuera_de_politica')='true' AND motivo LIKE 'Cancelacion%'));

-- boleto usado entre solicitud y resolucion (carrera ingreso/reembolso)
UPDATE funcion SET inicio=now()+interval '5 days', fin=now()+interval '5 days 2 hours' WHERE id_funcion=1;
UPDATE boleto SET estado='emitido', usado_en=NULL WHERE id_boleto=2;
SELECT * FROM solicitar_reembolso(2,1,ARRAY[2],'prueba carrera','127.0.0.1') \gset s3_
UPDATE boleto SET estado='usado', usado_en=now() WHERE id_boleto=2;
SELECT pg_temp.chk('C03-13 boleto usado tras solicitar: no se reembolsa', (SELECT codigo FROM resolver_reembolso(7,:s3_id_solicitud,'ejecutar',NULL,'127.0.0.1'))='ESTADO_INVALIDO');
SELECT pg_temp.chk('C03-13 forzar tampoco revive usado', (SELECT codigo FROM resolver_reembolso(7,:s3_id_solicitud,'ejecutar','x','127.0.0.1',true))='ESTADO_INVALIDO');
SELECT pg_temp.chk('C03-14 rechazar requiere motivo', (SELECT codigo FROM resolver_reembolso(7,:s3_id_solicitud,'rechazar','','127.0.0.1'))='DATOS_INVALIDOS');
SELECT pg_temp.chk('C03-14 rechazar con motivo', (SELECT exito FROM resolver_reembolso(7,:s3_id_solicitud,'rechazar','Boleto ya usado','127.0.0.1')));
SELECT pg_temp.chk('C03-14 solicitud heredada sin boletos no se ejecuta', (SELECT codigo FROM resolver_reembolso(7,3,'ejecutar',NULL,'127.0.0.1'))='DATOS_INVALIDOS');

-- politica
SELECT exito AS ok15 FROM cambiar_politica(7,'reembolso_horas_antes',4,'Ajuste operativo','127.0.0.1') \gset
SELECT pg_temp.chk('C03-15 admin cambia politica y audita', :'ok15'='t' AND (SELECT valor_entero FROM politica_negocio)=4 AND EXISTS(SELECT 1 FROM admin_operacion_audit WHERE accion='configurar_politica'));
SELECT pg_temp.chk('C03-15 contador no cambia politica', (SELECT codigo FROM cambiar_politica(6,'reembolso_horas_antes',0,'x','127.0.0.1'))='NO_AUTORIZADO');

-- historial: consultable e inalterable
SELECT pg_temp.chk('C03-16 contador consulta historial', (SELECT count(*) FROM consultar_auditoria_admin(6))>5);
SELECT pg_temp.chk('C03-16 filtro por accion', (SELECT count(*) FROM consultar_auditoria_admin(7,NULL,NULL,NULL,'reembolso_forzado'))=1);
DO $$ BEGIN PERFORM * FROM consultar_auditoria_admin(1); RAISE NOTICE 'FALLA | cliente leyo auditoria';
 EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'OK    | C03-16 cliente no consulta historial'; END $$;
DO $$ BEGIN UPDATE admin_operacion_audit SET motivo='alterado'; RAISE NOTICE 'FALLA | update auditoria';
 EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'OK    | C03-17 UPDATE auditoria bloqueado'; END $$;
DO $$ BEGIN DELETE FROM admin_operacion_audit; RAISE NOTICE 'FALLA | delete auditoria';
 EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'OK    | C03-17 DELETE auditoria bloqueado'; END $$;
DO $$ BEGIN TRUNCATE admin_operacion_audit; RAISE NOTICE 'FALLA | truncate auditoria';
 EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'OK    | C03-17 TRUNCATE auditoria bloqueado'; END $$;

-- ===== Puerta: el boleto anulado por reembolso es rechazado y queda registrado
UPDATE funcion SET inicio=now()+interval '10 minutes', fin=now()+interval '130 minutes' WHERE id_funcion=1;
UPDATE boleto SET estado='emitido', usado_en=NULL WHERE id_boleto IN (2,4);
UPDATE compra SET estado='pagada' WHERE id_compra=3;
SELECT pg_temp.chk('C03-18 puerta acepta boleto emitido', (SELECT exito FROM validar_y_consumir_ingreso_qr((SELECT token_qr FROM boleto WHERE id_boleto=2),1,5,'P1')));
SELECT pg_temp.chk('C03-18 segundo escaneo: Entrada ya utilizada', (SELECT mensaje FROM validar_y_consumir_ingreso_qr((SELECT token_qr FROM boleto WHERE id_boleto=2),1,5,'P1'))='Entrada ya utilizada');
SELECT * FROM solicitar_reembolso(7,3,NULL,'Falla tecnica','127.0.0.1') \gset s9_
SELECT exito AS ok9 FROM resolver_reembolso(7,:s9_id_solicitud,'ejecutar','Falla tecnica de sala','127.0.0.1',true) \gset
SELECT pg_temp.chk('C03-19 reembolso forzado ejecutado', :'ok9'='t');
SELECT pg_temp.chk('C03-19 puerta rechaza boleto reembolsado', (SELECT mensaje FROM validar_y_consumir_ingreso_qr((SELECT token_qr FROM boleto WHERE id_boleto=4),1,5,'P1')) LIKE 'Boleto anulado%');
SELECT pg_temp.chk('C03-19 intento rechazado registrado en puerta', EXISTS(SELECT 1 FROM acceso_puerta_log WHERE id_boleto=4 AND resultado='rechazado'));
SELECT exito AS ok19 FROM validar_y_consumir_ingreso_qr(gen_random_uuid(),1,5,'P1') \gset
SELECT pg_temp.chk('C03-19 QR inexistente rechazado y registrado', :'ok19'='f' AND EXISTS(SELECT 1 FROM acceso_puerta_log WHERE id_boleto IS NULL));

-- ===== Cortesías, cambio de asiento y resumen de auditoría (C03-21 a C03-26)
UPDATE funcion SET inicio=now()+interval '5 days', fin=now()+interval '5 days 2 hours' WHERE id_funcion=1;
-- asientos libres: 4 (compra 2 reembolsada) y los de la zona VIP
SELECT pg_temp.chk('C03-21 contador/taquillero/cliente no otorgan cortesia',
  (SELECT codigo FROM otorgar_cortesia(6,1,4,2,1,'x','127.0.0.1'))='NO_AUTORIZADO'
  AND (SELECT codigo FROM otorgar_cortesia(3,1,4,2,1,'x','127.0.0.1'))='NO_AUTORIZADO'
  AND (SELECT codigo FROM otorgar_cortesia(1,1,4,2,1,'x','127.0.0.1'))='NO_AUTORIZADO');
SELECT pg_temp.chk('C03-21 intentos denegados auditados', (SELECT count(*) FROM admin_operacion_audit WHERE accion='denegado:otorgar_cortesia')=3);
SELECT pg_temp.chk('C03-21 motivo vacio / ip mala', (SELECT codigo FROM otorgar_cortesia(7,1,4,2,1,' ','127.0.0.1'))='DATOS_INVALIDOS' AND (SELECT codigo FROM otorgar_cortesia(7,1,4,2,1,'x','nada'))='DATOS_INVALIDOS');
SELECT pg_temp.chk('C03-21 asiento ocupado rechazado', (SELECT codigo FROM otorgar_cortesia(7,1,2,2,1,'Invitado','127.0.0.1'))='REFERENCIA_CONFLICTIVA');
SELECT pg_temp.chk('C03-21 beneficiario no cliente rechazado', (SELECT codigo FROM otorgar_cortesia(7,1,4,3,1,'Invitado','127.0.0.1'))='DATOS_INVALIDOS');
SELECT * FROM otorgar_cortesia(7,1,4,2,1,'Invitado de prensa','10.1.1.1') \gset c_
SELECT pg_temp.chk('C03-22 cortesia otorgada', :'c_exito'='t' AND (SELECT total FROM compra WHERE id_compra=:c_id_compra)=0 AND (SELECT estado FROM boleto WHERE id_boleto=:c_id_boleto)='emitido', 'compra='||:'c_id_compra');
SELECT pg_temp.chk('C03-22 asiento queda ocupado', asiento_ocupado(1,4));
SELECT pg_temp.chk('C03-22 cortesia auditada', EXISTS(SELECT 1 FROM admin_operacion_audit WHERE accion='otorgar_cortesia' AND id_usuario_actor=7 AND ip='10.1.1.1' AND motivo='Invitado de prensa' AND (cambios->>'id_boleto')=:'c_id_boleto'));
SELECT pg_temp.chk('C03-22 no se duplica el asiento', (SELECT codigo FROM otorgar_cortesia(7,1,4,2,1,'Otra','127.0.0.1'))='REFERENCIA_CONFLICTIVA');
-- cambio de asiento
SELECT pg_temp.chk('C03-23 taquillero no cambia asiento', (SELECT codigo FROM cambiar_asiento_boleto(3,:c_id_boleto,5,'x','127.0.0.1'))='NO_AUTORIZADO');
SELECT * FROM otorgar_cortesia(7,1,6,2,1,'Segundo invitado','127.0.0.1') \gset d_
SELECT pg_temp.chk('C03-23 asiento ocupado (misma zona)', (SELECT codigo FROM cambiar_asiento_boleto(7,:c_id_boleto,6,'x','127.0.0.1'))='REFERENCIA_CONFLICTIVA');
SELECT pg_temp.chk('C03-23 boleto usado no cambia', (SELECT codigo FROM cambiar_asiento_boleto(7,2,5,'x','127.0.0.1'))='ESTADO_INVALIDO');
SELECT pg_temp.chk('C03-23 mismo asiento', (SELECT codigo FROM cambiar_asiento_boleto(7,:c_id_boleto,4,'x','127.0.0.1'))='DATOS_INVALIDOS');
SELECT pg_temp.chk('C03-23 otra zona exige reprecio (B)', (SELECT codigo FROM cambiar_asiento_boleto(7,:c_id_boleto,1,'x','127.0.0.1'))='ZONA_DISTINTA');
SELECT pg_temp.chk('C03-23 motivo obligatorio', (SELECT codigo FROM cambiar_asiento_boleto(7,:c_id_boleto,5,'','127.0.0.1'))='DATOS_INVALIDOS');
SELECT exito AS ok24 FROM cambiar_asiento_boleto(7,:c_id_boleto,5,'Pedido del cliente','10.1.1.1') \gset
SELECT pg_temp.chk('C03-24 cambio valido', :'ok24'='t' AND (SELECT id_asiento FROM compra_detalle WHERE id_compra=:c_id_compra)=5);
SELECT pg_temp.chk('C03-24 antes/despues auditado', EXISTS(SELECT 1 FROM admin_operacion_audit WHERE accion='cambio_asiento' AND (cambios->'antes'->>'id_asiento')='4' AND (cambios->'despues'->>'id_asiento')='5'));
SELECT pg_temp.chk('C03-24 asiento anterior liberado', NOT asiento_ocupado(1,4) AND asiento_ocupado(1,5));
-- el boleto reembolsado libera su asiento
SELECT * FROM solicitar_reembolso(7,:c_id_compra,NULL,'Anulacion de cortesia','127.0.0.1') \gset s5_
SELECT exito AS ok25 FROM resolver_reembolso(7,:s5_id_solicitud,'ejecutar',NULL,'127.0.0.1') \gset
SELECT pg_temp.chk('C03-25 reembolso de cortesia libera asiento', :'ok25'='t' AND NOT asiento_ocupado(1,5));
-- resumen analitico
SELECT pg_temp.chk('C03-26 contador ve resumen por administrador', (SELECT count(*) FROM resumen_auditoria_admin(6))>0 AND (SELECT bool_and(id_usuario_actor=7) FROM resumen_auditoria_admin(6)));
SELECT pg_temp.chk('C03-26 resumen excluye denegados', (SELECT count(*) FROM resumen_auditoria_admin(6) WHERE accion LIKE 'denegado:%')=0);
DO $$ BEGIN PERFORM * FROM resumen_auditoria_admin(3); RAISE NOTICE 'FALLA | taquillero leyo resumen';
 EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'OK    | C03-26 taquillero no consulta resumen'; END $$;
ROLLBACK;
```

## Anexo B — Prueba de concurrencia C03-20 (dos sesiones)

Preparación (una vez, en una **copia** de la base, porque estos cambios sí se confirman): poner la función 1 a 10 minutos de iniciar y crear una solicitud forzada para la compra 3.

```sql
UPDATE funcion SET inicio = now() + interval '10 minutes', fin = now() + interval '130 minutes' WHERE id_funcion = 1;
SELECT id_solicitud FROM solicitar_reembolso(7, 3, NULL, 'Prueba de carrera', '127.0.0.1');   -- anota el id
SELECT token_qr FROM boleto WHERE id_boleto = 4;                                              -- anota el token
```

**Sesión A** (ejecutar y dejar abierta unos segundos antes del `COMMIT`):

```sql
BEGIN;
SELECT * FROM resolver_reembolso(7, <id_solicitud>, 'ejecutar', 'Carrera', '127.0.0.1', TRUE);
-- esperar ~10 s
COMMIT;
```

**Sesión B** (lanzar mientras A sigue sin hacer `COMMIT`):

```sql
SELECT * FROM validar_y_consumir_ingreso_qr('<token>'::uuid, 1, 5, 'puerta-1');
```

Esperado: B queda esperando; al hacer `COMMIT` A, B responde `Boleto anulado o reembolsado previamente` y `SELECT estado FROM boleto WHERE id_boleto = 4` devuelve `anulado`. (Resultado obtenido en la revisión: coincide.)

## Anexo C — Prueba de concurrencia C03-27 (dos cortesías, mismo asiento)

En una **copia** de la base (estos cambios sí se confirman), con la función 1 en el futuro y el asiento 5 libre:

**Sesión A:**

```sql
BEGIN;
SELECT codigo FROM otorgar_cortesia(7, 1, 5, 2, 1, 'Sesión A', '127.0.0.1');
SELECT pg_sleep(4);
COMMIT;
```

**Sesión B** (lanzar ~1 s después de iniciar A):

```sql
SELECT codigo, mensaje FROM otorgar_cortesia(7, 1, 5, 1, 1, 'Sesión B', '127.0.0.1');
```

Esperado: A devuelve `OK`; B espera el bloqueo y, al confirmarse A, devuelve `REFERENCIA_CONFLICTIVA`. `SELECT count(*) FROM compra_detalle WHERE id_asiento = 5` devuelve 1. (Resultado obtenido en la revisión: coincide.)
