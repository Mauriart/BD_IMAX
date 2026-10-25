> Version de trabajo anterior. La aplicacion, SQL y evidencia de la integracion actual se describen en [integracion/guia.md](../integracion/guia.md). Los resultados historicos de este archivo no sustituyen las pruebas sobre las tablas reales de B.

# Pruebas del bloque C — C-07 (issue de pruebas de acceso, permisos, reportes y rendimiento)

Responsable: **bloque C** (asignación personal pendiente). Revisión cruzada: **B revisa C**.
Requisitos: RN-14 a RN-17, RN-19, RN-20; fase DBLC 4.

> **Estado de este documento:** las columnas *Obtenido*, *Evidencia* y *Estado* están **vacías a propósito**.
> Los scripts se entregan, pero no se han ejecutado contra su base. No registre un resultado que no haya observado.

## 1. Línea base (volcado `imax.sql`)

| Elemento | Estado |
| --- | --- |
| Boletos | 1 `emitido`, 2 `usado`, 3 `anulado`, 4 `emitido` |
| Función | Solo la 1: sala 1, 29/10/2026 18:00–20:00 (-06) |
| Sala 1 | 6 asientos: General (1-3), VIP (4-6) |
| Usuarios | 1-2 clientes · 3 taquillero · 4-5 operadores · 6 contador · 7 administrador |
| Logs | `acceso_puerta_log` vacío; `admin_operacion_audit` con 1 fila (actor 7, `prueba`) |
| Índices | Solo PK/UNIQUE |
| Ausentes | `pago`, `reserva`, `inventario_funcion`, `reembolso`, `transaccion_log`, `asiento_auditoria_log` |

## 2. Entorno

| Dato | Valor (completar) |
| --- | --- |
| PostgreSQL (`SELECT version()`) | |
| Python / psycopg / pytest | |
| SO · CPU · RAM · disco | |
| `shared_buffers`, `work_mem`, `effective_cache_size` | |
| Fecha y responsable | |

Bases (todas clonadas de `imax_c07_base`, que nunca se modifica): `imax_c07_puerta`, `imax_c07_rep`, `imax_c07_perf`.
Los logs son inmutables, por eso **no se limpian**: se recrea la base con `reset_entorno.sh`.

## 3. Cómo ejecutar

```bash
export PGPASSWORD=...  C07_APP_PASSWORD=...            # nunca en Git
tests/operacion/reset_entorno.sh base                  # restaura imax.sql (psql 18.x por \restrict)
tests/operacion/reset_entorno.sh puerta
pytest tests/operacion -v --junitxml=evidencias/c/junit.xml
python tests/operacion/concurrencia_qr.py --n 50 --escenario ok --indice 3 --salida evidencias/c/PC-15

tests/operacion/reset_entorno.sh rep
psql -d imax_c07_rep -f sql/perf/c07_verificar_reportes.sql | tee evidencias/c/REP/salida.txt

tests/operacion/reset_entorno.sh perf
python tests/operacion/medir_explain.py --fase antes
psql -d imax_c07_perf -f sql/20_indices_c07.sql
python tests/operacion/medir_explain.py --fase despues
```

Variables opcionales: `C07_DSN_ADMIN`, `C07_DSN_APP`, `C07_DSN_PERF`.
Cada ejecución de pytest consume boletos: **repita `reset_entorno.sh puerta` antes de volver a ejecutarlo**.

## 4. Fixtures

`sql/perf/c07_fixture_puerta.sql` crea 7 escenarios (sala + función relativa a `now()` + compra del cliente 2 con 4 boletos emitidos):

| Escenario | Inicio de la función | Uso |
| --- | --- | --- |
| `ok` | +10 min | idx0 PC-02/03 · idx1 PC-04/11/12/13 · idx2 PC-14 · idx3 PC-15 |
| `temprano` | +45 min | PC-05 |
| `borde_temprano` | +29 min | PC-06 |
| `borde_tarde` | −14 min | idx0 PC-07 · idx1 PC-16 |
| `vencida` | −16 min | PC-08 |
| `politica` | +90 min | PC-04 (otra función), PC-31, PC-32 |
| `lejana` | +2 días | idx0 PC-27/33/34/38 · idx1 PC-28/29/39/40 · idx2+3 PC-36/37 |

Los márgenes son de ±1 min porque `validar_y_consumir_ingreso_qr` usa `CURRENT_TIMESTAMP` y no admite un reloj inyectado.
Los casos que dependen de la línea base (PC-09, PC-10, PC-30, PC-35) usan los boletos 2 y 3, la compra 2 y la solicitud 3.

## 5. Casos

### 5.1 Acceso en puerta (`test_puerta.py`)

| ID | Req. | Caso | Esperado | Obtenido | Evidencia | Estado |
| --- | --- | --- | --- | --- | --- | --- |
| PC-01 | RN-14 | UUID inexistente | `exito=false`; log `rechazado` con `id_boleto` NULL | | | |
| PC-02 | RN-14 | Escaneo válido | `exito=true`; boleto `usado` con `usado_en`; log `aceptado` | | | |
| PC-03 | RN-14 | Segundo escaneo | "Entrada ya utilizada"; log `rechazado` con `id_boleto` | | | |
| PC-04 | RN-15 | Otra función | Rechazo "otra función"; boleto sigue `emitido` | | | |
| PC-05 | RN-16 | Inicio en 45 min | Rechazo "muy temprano" | | | |
| PC-06 | RN-16 | Inicio en 29 min | Aceptado | | | |
| PC-07 | RN-16 | Inicio hace 14 min | Aceptado | | | |
| PC-08 | RN-16 | Inicio hace 16 min | Rechazo "fuera de horario" | | | |
| PC-09 | RN-19 | Boleto 3 (anulado) | Rechazo "anulado o reembolsado" | | | |
| PC-10 | RN-14 | Boleto 2 (usado) con función 1 fuera de horario | "Entrada ya utilizada" (el estado se evalúa antes que el horario) | | | |
| PC-11 | RN-17 | Cliente, taquillero, contador y admin escanean | 42501; el boleto no se consume | | | |
| PC-12 | RN-17 | Operador con `activo=false` | 42501 | | | |
| PC-13 | RN-20 | `dispositivo=''` | `CheckViolation`; la función revierte y el boleto sigue `emitido` | | | |
| PC-14 | RN-14 | 2 escaneos simultáneos | 1 éxito, 1 "Entrada ya utilizada", 0 errores | | | |
| PC-15 | RN-14 | 50 escaneos simultáneos | 1 éxito, 49 rechazos esperados, 0 errores; log: 1 `aceptado` y 49 `rechazado` | | | |
| PC-16 | RN-14/19 | Ingreso vs. reembolso forzado | Gana exactamente uno; estado final `usado` o `anulado`, sin mezcla | | | |
| PC-17 | RN-20 | UPDATE/DELETE/TRUNCATE en `acceso_puerta_log` (postgres e imax_app) | 42501 | | | |

### 5.2 Permisos y auditoría (`test_permisos_rbac.py`)

| ID | Req. | Caso | Esperado | Obtenido | Evidencia | Estado |
| --- | --- | --- | --- | --- | --- | --- |
| PC-20 | RN-17 | `autorizar_accion` por rol vs. `00_acuerdos.md` §9 | Cero diferencias (o documentadas) | | | |
| PC-21 | RN-17 | DML en `tarifa`/`pelicula`/`funcion` con actor cliente, taquillero, operador, contador | 42501 | | | |
| PC-22 | RN-20 | Mismo DML con admin y motivo | Éxito; auditoría con `antes`/`despues`, sin `password_hash` | | | |
| PC-23 | RN-20 | Admin sin motivo | Cambio revertido (23514) | | | |
| PC-24 | RN-17 | `imax_app` sin actor | 42501 (ver hallazgo 5) | | | |
| PC-25 | RN-17 | Alta de usuario: cliente / sin actor / taquillero / admin con motivo | OK / 42501 / 42501 / OK con auditoría | | | |
| PC-26 | RN-20 | `cambiar_politica` | OK auditado · `NO_AUTORIZADO` auditado · `DATOS_INVALIDOS` · `NO_ENCONTRADO` | | | |
| PC-41 | RN-20 | UPDATE/DELETE/TRUNCATE en `admin_operacion_audit` | 42501 | | | |

### 5.3 Reembolsos, cortesías y asientos (`test_reembolsos.py`)

| ID | Req. | Caso | Esperado | Obtenido | Evidencia | Estado |
| --- | --- | --- | --- | --- | --- | --- |
| PC-27 | RN-19 | Cliente solicita su propia compra (≥ 2 h) | `OK`, solicitud pendiente | | | |
| PC-28 | RN-17 | Cliente 1 sobre compra del cliente 2 | `NO_AUTORIZADO` + `denegado:compra_ajena` | | | |
| PC-29 | RN-17 | Operador / contador solicitan | `NO_AUTORIZADO` + `denegado:solicitar_reembolso` | | | |
| PC-30 | RN-19 | Boleto usado, compra reembolsada, boleto de otra compra | `ESTADO_INVALIDO` ×3 | | | |
| PC-31 | RN-19 | Cliente a < 2 h | `FUERA_DE_POLITICA` | | | |
| PC-32 | RN-19/20 | Admin: sin forzar, luego forzado con motivo | `FUERA_DE_POLITICA`; luego `OK`, `reembolso_forzado`, `fuera_de_politica=true` | | | |
| PC-33 | RN-19 | Admin ejecuta solicitud ordinaria | Monto 8,00; boleto `anulado`; compra `parcialmente_reembolsada`; `reembolso_ordinario` | | | |
| PC-34 | RN-19 | Repetir la resolución | `ESTADO_INVALIDO` | | | |
| PC-35 | RN-19 | Solicitud 3 (sin detalle) | `DATOS_INVALIDOS` | | | |
| PC-36 | RN-17 | Rechazar sin motivo; resolver como taquillero | `DATOS_INVALIDOS`; `NO_AUTORIZADO` | | | |
| PC-37 | RN-19 | Reembolso parcial de 2 de 4 boletos | Monto 16,00 = suma de `total_linea`; los otros boletos siguen `emitido` | | | |
| PC-38 | RN-20 | Reventa del asiento liberado; cortesía en asiento ocupado | Boleto y token nuevos, anterior intacto; `REFERENCIA_CONFLICTIVA` | | | |
| PC-39 | RN-20 | `cambiar_asiento_boleto` | `DATOS_INVALIDOS`, `ZONA_DISTINTA`, `REFERENCIA_CONFLICTIVA`, `OK` + auditoría | | | |
| PC-40 | RN-17 | Taquillero: cortesía y cambio de asiento | `NO_AUTORIZADO` + `denegado:` | | | |
| PC-42 | RN-20 | IP inválida | `DATOS_INVALIDOS` | | | |

### 5.4 Reportes (`sql/perf/c07_verificar_reportes.sql`, sobre `imax_c07_rep`)

| Reporte | Esperado (ASSERT) | Obtenido | Estado |
| --- | --- | --- | --- |
| 1 · función 1 | 6 vendibles, 3 boletos no anulados, **50,00 %**; bruto 33,00; devuelto 12,00; **neto 21,00** | | |
| 1b · función sin ventas | Aparece con 0 boletos, 0,00 % y 0,00 | | |
| 2 · top 5 (168 h) | Rep P2 (5), Rep P3 (4), Rep P4 (4), Horizonte estelar (3), Rep P5 (2). Rep P6 queda fuera; Rep P7 (solo boletos > 168 h) y el anulado de P2 no cuentan | | |
| 3 · métodos de pago | **BLOQUEADO**: falta la tabla `pago` (B-01 #6, B-03 #10) | n/a | Bloqueado |
| 4 · auditoría crítica | `resumen_auditoria_admin(7)`: (7, Administrador, `prueba`, 1); contador permitido; cliente 42501 | | |

Intervalos `[desde, hasta)` con un mismo instante de corte. El reporte 1 usa `compra_detalle` como sustituto de "pagos aprobados − devoluciones"; al existir `pago` el neto debe seguir siendo 21,00.

### 5.5 EXPLAIN ANALYZE antes/después (`medir_explain.py`, sobre `imax_c07_perf`)

Dataset: 20 películas, 20.000 funciones, 400.000 compras, 800.000 boletos, 500.000 filas de puerta, 100.000 de auditoría. Carga determinista con triggers desactivados solo durante la inserción masiva.

| Consulta | Índice candidato | Mediana antes (ms) | Mediana después (ms) | Nodos antes → después | Conclusión |
| --- | --- | --- | --- | --- | --- |
| Q1 ocupación/recaudación por función | `compra(id_funcion)` | | | | |
| Q2 top 5, 168 h | `boleto(emitido_en) INCLUDE (...)`, `funcion(id_pelicula)` | | | | |
| Q4 auditoría por administrador | `admin_operacion_audit(fecha, id_usuario_actor)` parcial | | | | |
| Q5 historial de puerta por función | `acceso_puerta_log(id_funcion_solicitada, fecha)` | | | | |
| Q6 historial de puerta por boleto | `acceso_puerta_log(id_boleto)` | | | | |
| Q7 disponibilidad por función | `compra(id_funcion)` | | | | |

Reglas: se adopta un índice solo si el plan lo usa y mejora; no se fuerza ningún plan (`enable_seqscan` no se toca). Si el optimizador mantiene Seq Scan porque la consulta lee gran parte de la tabla, se explica con la selectividad y el volumen. La búsqueda por `token_qr` ya usa `uq_boleto_token` y se documenta como línea base, no como mejora. Q7 se repetirá con `inventario_funcion` cuando B lo entregue.

## 6. Hallazgos a confirmar al ejecutar

1. El volcado es PostgreSQL 18.6; los acuerdos fijan 17.x.
2. `resumen_auditoria_admin` usa `INTERVAL '1 month'`; los acuerdos §4 fijan 720 h.
3. Las denegaciones de `guardia_rbac` hacen rollback y probablemente no quedan auditadas (acuerdos §8.10).
4. Una excepción por permiso en `validar_y_consumir_ingreso_qr` no deja registro en `acceso_puerta_log`.
5. `imax_app` no tiene DML sobre las tablas de A/B; PC-21/22/23 corren como `postgres` con `app.id_usuario` y PC-24 prueba solo el rechazo por privilegios.
6. La solicitud 3 de la línea base es inconsistente (sin detalle y pedida por un cliente distinto al dueño de la compra).
7. Los saltos en secuencias pueden venir de rollbacks; no prueban borrado.
8. Un superusuario puede desactivar los triggers de inmutabilidad: límite a documentar y argumento para el archivo WORM de C-05.
9. `revertir_venta` es una versión reducida, sin `pago` ni `reembolso`: pendiente de integrar con B.
10. La función 1 de la línea base ocurre el 29/10; pasada esa fecha PC-27 y similares dejarían de servir con ella (por eso se usa el escenario `lejana`).

## 7. Trazabilidad

| Requisito | Casos |
| --- | --- |
| RN-14 | PC-01 a PC-03, PC-10, PC-14 a PC-16 |
| RN-15 | PC-04 |
| RN-16 | PC-05 a PC-08 |
| RN-17 | PC-11, PC-12, PC-20 a PC-25, PC-28, PC-29, PC-36, PC-40 |
| RN-19 | PC-09, PC-16, PC-27 a PC-37 |
| RN-20 | PC-13, PC-17, PC-22, PC-23, PC-26, PC-32, PC-38 a PC-42 |
| Reportes (C-04) | §5.4 |
| DBLC 4 / rendimiento | §5.5 |

## 8. Criterios de aceptación

- [ ] Cada PC-xx registra esperado, obtenido, evidencia reproducible y entorno.
- [ ] Un escaneo simultáneo consume la entrada una sola vez (PC-14, PC-15) y el estado final se comprueba en SQL.
- [ ] La matriz de permisos coincide con `00_acuerdos.md` §9, o las diferencias están documentadas.
- [ ] Los cuatro reportes se verifican con resultados conocidos (el 3 puede quedar bloqueado, con motivo y dependencia).
- [ ] Planes, tiempos, SQL, índices, conteo de filas y entorno están en Git.
- [ ] El uso de índices está justificado sin inventar resultados; revisión cruzada (B) completa.
