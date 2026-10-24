# Documentación técnica C-05 — Logs, auditoría e inalterabilidad, y dimensionamiento a 5 años

**Issue:** [C-05 · #19](https://github.com/Mauriart/BD_IMAX/issues/19) · **Bloque:** C · **Versión:** 1.1 · **Fecha:** 2026-10-23
**Requisitos de referencia:** RN-20, volúmenes de la licitación, fases DBLC 1 y 2.
**Archivos de esta entrega:**

| Archivo | Uso |
| --- | --- |
| `documentacion_tecnica_c_05.md` | Este documento. |
| `c05_logs_endurecimiento.sql` | Script nuevo e idempotente: privilegios mínimos y restricciones de campos obligatorios. |
| `c05_verificacion_logs.sql` | 15 casos de rechazo/aceptación; termina en `ROLLBACK`, no deja filas. |
| `c05_dimensionamiento.sql` | Tabla de cálculo reproducible (supuestos S-01…S-24 editables). |
| `consultas_sql_c_05.sql` | Cuatro consultas de control sobre los logs (reemplaza el `.md` anterior, que contenía SQL). |

---

## 1. Alcance y qué se entrega

El issue pide: (1) logs `acceso_puerta_log` y `admin_operacion_audit` separados de los de B; (2) registrar escaneos aceptados/rechazados y cambios administrativos con campos obligatorios; (3) dimensionar con 1 500 salas, 500 títulos y 15 millones de boletos mensuales; (4) calcular GB/TB mensuales y a 60 meses por categoría declarando tamaños, eventos, fallos, crecimiento, índices, réplicas y backups.

Hilo conductor: **programación → reserva → pago → boleto QR → ingreso → trazabilidad**. Cada etapa deja huella en uno de los cuatro logs (§2).

**Límites que conviene leer primero**

- Las tablas `acceso_puerta_log` y `admin_operacion_audit` **ya existen** en `imax.sql`; aquí no se repite su `CREATE TABLE`. Se endurecen con un script nuevo, como piden los acuerdos §4.
- `transaccion_log` y `asiento_auditoria_log` (logs de B) **no existen todavía** en `imax.sql`. Su tamaño en §5 se calcula con un DDL provisional tomado de los acuerdos §5 y queda marcado como provisional hasta que B-05 lo entregue.
- Los tamaños por fila se **midieron en PostgreSQL 16.15** con 300 000 filas sintéticas por tabla (el proyecto apunta a 17.x/18.x; ver §9). La compresión del archivo, la compresión de backups y el multiplicador de WAL son **supuestos no medidos**.
- Nada de esto es evidencia de capacidad global: el prototipo no demuestra 8 millones de usuarios ni 50 000 TPS.

---

## 2. Las cuatro categorías de logs

La consigna menciona «tres categorías» y luego enumera cuatro. Se cubren las cuatro, una tabla por dominio, sin mezclar logs masivos con la bitácora administrativa (nota de arquitectura de la consigna).

| # | Categoría (RN-20) | Tabla | Dueño | Estado en `imax.sql` | Qué registra |
| --- | --- | --- | --- | --- | --- |
| L1 | Financiero / ciclo de pago | `transaccion_log` | B | **Pendiente (B-05)** | Intentos de pago, resultado, monto, emisión de boletos, reembolsos. |
| L2 | Bloqueos de asientos / inventario | `asiento_auditoria_log` | B | **Pendiente (B-05)** | Bloqueo, expiración, venta, liberación y colisiones por función + asiento. |
| L3 | Acceso en puerta | `acceso_puerta_log` | C | Existe | Cada escaneo QR: fecha, boleto (NULL si el QR no existe), función solicitada, operador, dispositivo, resultado, motivo. |
| L4 | Operaciones administrativas | `admin_operacion_audit` | C | Existe | Cortesías, cambios de asiento, reembolsos, políticas, cambios de catálogo/precios/roles, intentos denegados: actor, rol, IP, acción, entidad, motivo, antes/después. |

> **Corrección respecto a la versión anterior:** el borrador tomaba `compra`/`boleto` como «log de transacciones» y añadía una cuarta categoría «Seguridad y sistema» que no figura en la consigna. Las tablas `compra`/`boleto` son datos operativos (se dimensionan aparte, bloque D1); los logs de inventario (L2) faltaban. Los logs de aplicación/WAF/autenticación se tratan como observabilidad con retención corta y **no** forman parte de RN-20.

### 2.1 Campos obligatorios y restricciones (C)

| Tabla | Obligatorios (`NOT NULL`) | Restricciones |
| --- | --- | --- |
| `acceso_puerta_log` | `id`, `fecha`, `id_usuario_operador`, `dispositivo`, `resultado` | `ck_puerta_resultado` (aceptado/rechazado); FK a operador. **Nuevas:** `ck_puerta_motivo_rechazo` (todo rechazo lleva motivo), `ck_puerta_dispositivo` (no vacío), `fk_puerta_boleto` (si hay `id_boleto`, el boleto existe). |
| `admin_operacion_audit` | `id`, `fecha`, `id_usuario_actor`, `rol_al_actuar`, `ip`, `accion`, `entidad`, `motivo` | `ck_audit_motivo` (motivo no vacío); FK a actor. **Nueva:** `ck_audit_ip` (IP válida mediante `normalizar_ip`). |

Decisiones deliberadas: `id_boleto` sigue siendo `NULL` para «QR inexistente» (acuerdos §5). `id_funcion_solicitada` queda **sin FK** para que un intento con función mal digitada quede registrado en lugar de abortar la transacción.

### 2.2 Quién escribe en los logs

| Evento | Función / trigger | Log |
| --- | --- | --- |
| Escaneo aceptado o rechazado | `validar_y_consumir_ingreso_qr` | L3 |
| Cortesía, cambio de asiento, cambio de política, reembolso ordinario/forzado/rechazado | `otorgar_cortesia`, `cambiar_asiento_boleto`, `cambiar_politica`, `resolver_reembolso` → `auditar_accion` | L4 |
| Alta/edición/borrado de catálogo, tarifas, promociones, categorías, usuarios | trigger `auditar_cambio_critico` | L4 |
| Intento sin permiso | `exigir_permiso` → acción `denegado:<permiso>` | L4 |

Motivos de rechazo de puerta realmente emitidos por la función (texto libre; se tipifican en las consultas con los códigos de los acuerdos §10): *Código QR no registrado…* → `QR_INEXISTENTE`; *Entrada ya utilizada* → `ENTRADA_YA_UTILIZADA`; *Boleto anulado o reembolsado…* → `BOLETO_ANULADO`; *El boleto corresponde a otra función…* → `FUNCION_INCORRECTA`; *Ingreso muy temprano… / fuera de horario…* → `FUERA_DE_HORARIO`.

---

## 3. Verificación ejecutada

`c05_logs_endurecimiento.sql` se aplicó dos veces seguidas sin error (idempotente) sobre una copia de `imax.sql`, y `c05_verificacion_logs.sql` dio **15 de 15 casos OK**:

| Casos | Esperado | Resultado |
| --- | --- | --- |
| 1–4 | `UPDATE`/`DELETE` en ambos logs → `42501` | OK |
| 5–6 | `TRUNCATE` en ambos logs → `42501` | OK |
| 7–9 | resultado inválido y rechazo sin motivo → `23514`; escaneo sin operador → `23502` | OK |
| 10–11 | FK a boleto inexistente → `23503`; QR inexistente con `id_boleto NULL` → permitido | OK |
| 12–15 | auditoría con motivo vacío / IP inválida → `23514`; actor inexistente → `23503`; `auditar_accion` sin motivo → `23514` | OK |

Las cuatro consultas de §6 también se ejecutaron sobre datos sintéticos y devolvieron lo esperado. **Entorno:** PostgreSQL 16.15 (Ubuntu 24.04); al volcado se le quitaron las líneas exclusivas de 17+ (`\restrict`, `transaction_timeout`). Hay que repetir ambos scripts en la versión que use el equipo y guardar la salida en `evidencias/c/` (esta ejecución no la sustituye).

---

## 4. Inalterabilidad y retención (RN-20)

### 4.1 Qué garantiza hoy el prototipo

1. Triggers `BEFORE UPDATE OR DELETE` (`bloquear_modificacion_log`) y `BEFORE TRUNCATE` (`bloquear_truncate_log`) en ambos logs, con `42501`.
2. Privilegios mínimos: `imax_app` solo tiene `SELECT, INSERT`; el script revoca explícitamente `UPDATE, DELETE, TRUNCATE` y quita todo a `PUBLIC`.
3. Las escrituras de L4 pasan por funciones `SECURITY DEFINER` (`auditar_accion`) con motivo obligatorio; si falta el motivo, falla y revierte el cambio completo.
4. Los éxitos se confirman junto con el cambio de negocio; un rechazo de puerta queda registrado como `rechazado`.

### 4.2 Límite que la versión anterior ocultaba

El borrador afirmaba que los logs no se pueden alterar «ni siquiera con privilegios de superusuario». **Eso es falso.** El propietario o un superusuario puede `ALTER TABLE … DISABLE TRIGGER`, `DROP TABLE` o modificar el catálogo. Los acuerdos §11 ya advierten que *una tabla local no prueba inalterabilidad a cinco años*. Lo que se puede afirmar es: la **cuenta de aplicación** no puede alterar los logs, y cualquier intento por vía SQL normal queda rechazado.

### 4.3 Propuesta para la operación real (no implementada)

| Medida | Propósito |
| --- | --- |
| Exportación mensual al cerrar cada partición a almacenamiento **inmutable** (S3 Object Lock en modo *compliance* / Azure immutable blob) con retención ≥ 60 meses | Conserva evidencia aunque alguien con privilegios altere la BD. |
| Manifiesto por archivo con SHA-256 y conteo de filas, guardado en otra cuenta/región | Permite demostrar que una muestra histórica no fue alterada. |
| Cuenta propietaria de las tablas distinta de la de despliegue; nadie usa el rol propietario en operación diaria; alerta ante `DISABLE TRIGGER`/`DROP` | Reduce y detecta el bypass. |
| Acceso de lectura a auditoría solo para contador y administrador (ya modelado) | Separación de funciones. |

### 4.4 Retención y particionamiento

- **Mínimo 60 meses desde la fecha del evento** para las cuatro categorías.
- Diseño físico propuesto: partición mensual por `fecha` (la consigna recomienda particionar por fecha). En una tabla particionada la PK debe incluir la columna de partición: `PRIMARY KEY (id, fecha)`.
- Calientes: últimos **6 meses** en PostgreSQL. Al cerrar el mes se exporta a archivo inmutable; pasado el mes 6 se hace `DETACH PARTITION` tras verificar el manifiesto. El archivo mantiene los 60 meses.
- Como `DELETE` está bloqueado, la única baja permitida es `DROP` de una partición **cuyo límite superior sea anterior a hoy − 60 meses**, ejecutada por un procedimiento controlado y auditado.
- **Hallazgo comprobado:** el trigger `BEFORE TRUNCATE` del padre **no** se dispara si se hace `TRUNCATE` directamente sobre una partición. Hay que crear también `trg_*_sin_truncate` y el trigger de inmutabilidad en **cada** partición (o quitar `TRUNCATE` a todo rol excepto al propietario).

```sql
-- Esquema propuesto (probado en PG 16); no aplicar sobre la BD actual sin acordarlo con el equipo.
CREATE TABLE acceso_puerta_log_p (
  id_acceso_puerta_log bigint GENERATED ALWAYS AS IDENTITY,
  fecha timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  id_boleto integer, id_funcion_solicitada integer, id_usuario_operador integer NOT NULL,
  dispositivo varchar(100) NOT NULL, resultado varchar(20) NOT NULL, motivo varchar(200),
  PRIMARY KEY (id_acceso_puerta_log, fecha),
  CONSTRAINT ck_puerta_resultado CHECK (resultado IN ('aceptado','rechazado'))
) PARTITION BY RANGE (fecha);
CREATE TABLE acceso_puerta_log_2026_10 PARTITION OF acceso_puerta_log_p
  FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2026-11-01 00:00:00+00');
-- Repetir en CADA partición: trigger de inmutabilidad y BEFORE TRUNCATE.
```

---

## 5. Dimensionamiento a 60 meses

Se aplica la fórmula de los acuerdos: `almacenamiento por copia = datos + índices + espacio operativo`; `total = copias operativas + respaldos + WAL + archivo histórico`. Todo se reproduce con `c05_dimensionamiento.sql`.

### 5.1 Base de la consigna

| Dato | Valor | Nota |
| --- | --- | --- |
| Salas / títulos | 1 500 / 500 | Los 500 son títulos activos; las **funciones** son 500 diarias = 15 000 al mes (30 días). |
| Boletos | 15 000 000 / mes | `15 M × 60 = 900 000 000` boletos en cinco años, **sin crecimiento**. |
| Pico | 50 000 TPS × 600 s = 30 000 000 operaciones | Ventana de diez minutos, **no** tasa mensual (§5.6). |

Los logs se estiman **aparte** de los 900 M de boletos: un boleto genera varios eventos y no todos los eventos son de boletos vendidos.

### 5.2 Supuestos declarados (versión 1.0)

| ID | Supuesto | Valor | Origen |
| --- | --- | --- | --- |
| S-03 | Boletos por compra | 2,5 | Equipo (tope RN-04 = 6) |
| S-04 | Reservas que terminan pagadas | 60 % | Equipo |
| S-05 | De las no pagadas, las que expiran (el resto: pago rechazado) | 75 % | Equipo |
| S-06 | Colisiones sobre bloqueos (intentos sobre asiento ya tomado) | 10 % | Equipo |
| S-07 | Boletos que nunca se escanean (no-show) | 5 % | Equipo |
| S-08 | Rechazos de puerta sobre aceptados (2.º escaneo, función/horario, QR inválido) | 10 % | Equipo |
| S-09 | Boletos reembolsados | 3 % | Equipo |
| S-11/12 | 12 tarifas por función (3 zonas × 4 categorías); 35 000 eventos admin «otros»/mes | — | Equipo |
| S-14 | Meses calientes en PostgreSQL | 6 | Equipo |
| S-15 | Crecimiento anual (escenario B) | 10 % | Ejemplo de la consigna |
| S-16 | Espacio operativo (bloat, fillfactor, libre) | ×1,25 | Equipo |
| S-17/19 | Réplicas calientes / copias de archivo | 2 / 2 | Equipo (región + DR) |
| S-18 | Compresión del archivo (Parquet) | 4:1 | **No medido** |
| S-20/21/22 | Compresión de backup / fulls retenidos / multiplicador WAL | 2:1 / 5 / ×2,5 | **No medidos** |

Eventos mensuales derivados (escenario sin crecimiento):

| Concepto | Valor/mes |
| --- | --- |
| Compras pagadas | 6 000 000 |
| Reservas (= filas de `compra` y `reserva`) | 10 000 000 |
| Asientos bloqueados (vendidos + no convertidos) | 25 000 000 |
| Intentos de pago (aprobados + rechazados) | 7 000 000 |
| Escaneos en puerta (95 % de 15 M + 10 % de rechazos) | 15 675 000 |
| Eventos administrativos | 435 500 |

Origen de los eventos administrativos: 15 000 funciones × 1,5 (alta + ediciones) + 15 000 × 12 tarifas × 1,1 + 180 000 solicitudes de reembolso resueltas + 35 000 otros. Cada alta de tarifa o función genera una fila de auditoría por el trigger `auditar_cambio_critico`; esto explica por qué el supuesto previo de 200 000 estaba subestimado.

### 5.3 Tamaño por fila (medido, PG 16.15, 300 000 filas, bytes)

| Tabla | Heap/fila | Índices/fila | Observación |
| --- | --- | --- | --- |
| `acceso_puerta_log` (L3) | 119 | 80 | 3 btree parciales + BRIN en `fecha` (propuestos para C-07) |
| `admin_operacion_audit` (L4) | 376 | 100 | `cambios` jsonb pesa más en altas de tarifa/función |
| `transaccion_log` (L1) | 135 | 46 | DDL provisional |
| `asiento_auditoria_log` (L2) | 126 | 55 | DDL provisional |
| `compra` / `compra_detalle` / `boleto` | 77 / 76 / 69 | 76 / 52 / 85 | Existen; el UUID aleatorio de `boleto` encarece su índice |
| `pago` / `reserva` / `reserva_detalle` / `inventario_funcion` | 117 / 69 / 45 / 61 | 95 / 45 / 32 / 23 | DDL provisional |

El 40 % genérico de índices del borrador se reemplazó por estos tamaños medidos. Las cargas sintéticas son secuenciales; en producción los índices se fragmentan más, lo cual cubre el factor ×1,25 (S-16).

### 5.4 Resultado por categoría (GiB; GiB = 2³⁰ bytes)

| Categoría | Eventos/mes | Datos/mes | Índices/mes | **60 m sin crecimiento** (datos + índices) | **60 m con +10 %/año** |
| --- | --- | --- | --- | --- | --- |
| L1 Financiero | 29 360 000 | 3,69 | 1,26 | 297,0 | 362,6 |
| L2 Inventario | 52 950 000 | 6,21 | 2,71 | 535,5 | 653,9 |
| L3 Puerta | 15 675 000 | 1,74 | 1,17 | 174,3 | 212,8 |
| L4 Administración | 435 500 | 0,15 | 0,04 | 11,6 | 14,1 |
| **Total de los 4 logs** | **98 420 500** | **11,79** | **5,18** | **1 018,4 (≈ 0,99 TiB)** | **1 243,4 (≈ 1,21 TiB)** |
| D1 Operativo histórico (compra, detalle, boleto, pago, reserva, reserva_detalle) | — | — | — | 647,6 | 790,7 |
| D2 `inventario_funcion` (solo operación activa) | 21 428 571 | 1,22 | 0,46 | 100,6 | 122,8 |

El escenario con crecimiento equivale a 1 098,9 M de boletos en 60 meses (15 M × 12 × (1 + 1,1 + 1,21 + 1,331 + 1,4641)).

### 5.5 Operación activa vs archivo, réplicas y backups (mes 60, GiB)

| Bloque / escenario | Primario NVMe (6 m × 1,25) | 2 réplicas calientes | Archivo frío (comprimido, 2 copias) | Backups 30 d (fulls + incrementales + WAL) | **Total** |
| --- | --- | --- | --- | --- | --- |
| 4 logs · sin crecimiento | 127,3 | 254,6 | 353,8 | 347,9 | **1 083,7 (1,06 TiB)** |
| 4 logs · +10 %/año | 186,4 | 372,8 | 432,0 | 509,4 | **1 500,6 (1,47 TiB)** |
| Datos operativos · sin crecimiento | 93,5 | 187,0 | 177,1 | 255,6 | 713,3 (0,70 TiB) |
| Datos operativos · +10 %/año | 136,9 | 273,8 | 216,3 | 374,3 | 1 001,3 (0,98 TiB) |
| **Todo · sin crecimiento** | 220,8 | 441,6 | 530,9 | 603,6 | **1,75 TiB** |
| **Todo · +10 %/año** | 323,3 | 646,6 | 648,3 | 883,7 | **2,44 TiB** |

Lectura: el archivo almacena solo datos (sin índices) y contiene los 60 meses; los primeros 6 meses están, además, en caliente. Réplica, backup y archivo cumplen funciones distintas (acuerdos §11): la réplica sirve para continuar el servicio, el backup para volver a un estado anterior, el archivo para conservar y consultar historia.

> La consigna da como ejemplo «45 TB acumulados» en su tabla de costos, sin derivación. Nuestro cálculo da 1,75–2,44 TiB entre logs y datos operativos. Esa diferencia debe discutirse con A en A-06 (el ejemplo es referencial, no una cotización), pero A debe usar esta tabla como base y no el ejemplo.

### 5.6 Ventana pico: 50 000 TPS × 600 s

Es una **cota para dimensionar IOPS y WAL, no un volumen que se suma al mes**. Si cada operación fuera una escritura de log de ~185 B (datos + índices): 8,8 MiB/s, ≈ 22 MiB/s de WAL con el multiplicador S-22, y 5,2 GiB en los diez minutos. Es una cota muy conservadora: los 50 000 TPS incluyen lecturas, y el volumen de 15 M boletos al mes limita las ventas confirmadas (30 M operaciones serían ya el 30,5 % de todos los eventos de log del mes). Tampoco es un TPS equivalente a «compras»: la consulta Q3 de §6 cuenta compras, no transacciones.

### 5.7 Contrato de entrega a A (A-06)

A debe tomar de `c05_dimensionamiento.sql` **versión 1.0**: R5 (totales por escenario) y R4 (desglose caliente/archivo/réplicas/backups). Cualquier cambio de supuestos sube la versión y se comunica a A. Hasta que B entregue el DDL real de L1, L2, `pago`, `reserva` e `inventario_funcion`, esas filas son provisionales y A debe marcar la estimación como «pendiente de conciliar».

---

## 6. Consultas de control

Archivo `consultas_sql_c_05.sql`. Usan ventana de 720 h, corte único e intervalos `[desde, hasta)` (acuerdos §4). **No sustituyen los reportes de C-04**; Q2 coincide con el reporte de auditoría de la consigna.

| Consulta | Qué responde | Correcciones frente a la versión anterior |
| --- | --- | --- |
| Q1 Rechazos reiterados en puerta | Operador/función con ≥ 3 rechazos en 720 h, con tipo de rechazo normalizado | Ventana de 720 h; tipifica motivos (antes `DISTINCT` sobre texto con IDs y horas). |
| Q2a/Q2b Auditoría por administrador | Cortesías, reembolsos (ordinarios/forzados), cambios de asiento, políticas, cambios de catálogo/precios/roles y denegados, **agrupados por ID de administrador**, último mes; Q2b trae el detalle | Antes: 7 días, sin agrupar, solo 4 acciones; omitía los eventos de trigger y los reembolsos ordinarios. |
| Q3 Ritmo de compras por minuto | Compras creadas/cobradas/pendientes/no concretadas y bruto cobrado, 2 h | Antes sumaba el total de **todas** las compras (incluidas canceladas) y se rotulaba como TPS. Ahora filtra cobradas y aclara que no mide TPS. |
| Q4 Efectividad de ingreso por sala | % aceptados/rechazados del **día local** de cada cine | Antes `CURRENT_DATE` (zona de la sesión); ahora la zona IANA del cine. El encabezado del `.sql` anterior decía «ingresos» (dinero) y era efectividad de acceso. |

Con la base de ensayo, Q2b muestra la fila `prueba / ensayo` del 22-oct (ver §9, punto 2).

---

## 7. Cumplimiento del issue #19

| Criterio | Estado | Evidencia y reserva |
| --- | --- | --- |
| Cuatro categorías de logs | **Cumplido en diseño y cálculo.** | §2. L1 y L2 dependen del DDL de B (B-05); no existen aún en `imax.sql`. |
| Crear `acceso_puerta_log` y `admin_operacion_audit` separados de los de B | **Cumplido** | Ya en `imax.sql`; endurecidos con `c05_logs_endurecimiento.sql`. |
| Registrar escaneos y cambios con campos obligatorios | **Cumplido** | §2.1; 15 casos OK (§3). Pendiente repetir en PG 17/18 y guardar evidencia en el repo. |
| Tabla reproducible, activa vs archivo | **Cumplido** | `c05_dimensionamiento.sql`; §5.4–5.5. |
| Base sin crecimiento: 900 M boletos; logs aparte | **Cumplido** | §5.1 y escenario A; escenario B separado. |
| 50 000 TPS × 600 s como ventana pico | **Cumplido** | §5.6. |
| Tamaños, eventos, fallos, crecimiento, índices, réplicas y backups declarados | **Cumplido con reservas** | Supuestos S-xx; compresión, backup y WAL no medidos (S-18, S-20, S-22). |
| A recibe supuestos/versiones | **Cumplido** | §5.7, versión 1.0. Falta conciliar con B. |
| Retención e inalterabilidad documentadas | **Cumplido, con límite explícito** | §4. La inalterabilidad fuerte requiere archivo inmutable (propuesta, no implementada). |

---

## 8. Reproducir

```bash
psql -d imax -v ON_ERROR_STOP=1 -f sql/c05_logs_endurecimiento.sql
psql -d imax -f sql/c05_verificacion_logs.sql     # esperado: 15 filas OK; termina en ROLLBACK
psql -d imax -f sql/c05_dimensionamiento.sql      # tablas R1–R7
psql -d imax -f sql/consultas_sql_c_05.sql        # solo lectura
```

---

## 9. Observaciones y decisiones pendientes para el equipo

1. **Logs de B ausentes.** `transaccion_log` y `asiento_auditoria_log` no están en `imax.sql`. Sus identificadores deben ser `BIGINT`: ≈ 53 M eventos/mes × 60 ≈ 3 200 M, por encima del máximo de `INTEGER` (2 147 M). Para los logs de C basta `INTEGER`: puerta ≈ 940 M (≈ 1 150 M con crecimiento) y administración ≈ 26 M. Los acuerdos §4 piden `BIGINT` en general, pero A-01 se entregó con `SERIAL`; esa decisión es de Mauriart.
2. **Datos de ensayo en la auditoría.** `admin_operacion_audit` contiene una fila `prueba / ensayo` (id 2; la secuencia ya va en 3). Por diseño no se puede borrar: reinstalar la base antes de la demostración, o los reportes la mostrarán.
3. **Ventana de `resumen_auditoria_admin` (C-03).** La función usa `INTERVAL '1 month'` por omisión; los acuerdos fijan 720 h. Cambio de una línea en C-03; las consultas de esta entrega ya usan 720 h.
4. **Motivos de puerta en texto libre.** No hay columna de código; la tipificación se hace con `ILIKE`. Una columna `codigo_motivo` sería más robusta (cambio a C-02, no incluido).
5. **Índices.** Se proponen (comentados al final del script) pero no se crean: pertenecen a C-07 y su `EXPLAIN ANALYZE` «antes» no debe contaminarse.
6. **Versión de PostgreSQL.** Los acuerdos fijan 17.x, pero el volcado dice «Dumped from database version 18.6» y `factibilidad.md` enlaza la documentación 18. Conviene fijar una y registrar la revisión usada en las pruebas.
7. **FK de `id_funcion_solicitada`** omitida a propósito (§2.1); si el equipo prefiere integridad estricta, se añade y el intento con función inexistente pasará a ser un error.

## 10. Registro de correcciones a la versión anterior

| Problema encontrado | Corrección |
| --- | --- |
| Categorías erróneas (`compra`/`boleto` como log; «Seguridad y sistema» inventada; faltaba inventario) | Las cuatro de RN-20 (§2). |
| «Inalterable ni con superusuario» | Retirado; límites y propuesta WORM (§4). |
| Cifra de 617 GB «históricos» sin coincidir con 551,81 GB − 55,2 GB; índices incluidos en lo archivado | Recalculado: archivo solo con datos y compresión declarada (§5.5). |
| Sin crecimiento, réplicas, backups ni fallos cuantificados; 40 % de índices sin base | Supuestos S-xx, tamaños medidos, dos escenarios (§5). |
| Tabla de motivos de puerta no coincidía con los textos reales de la función | Textos reales y códigos de acuerdos §10 (§2.2). |
| Q2 con 7 días y sin agrupar; Q3 sumaba compras no cobradas y se presentaba como TPS; Q4 con `CURRENT_DATE` | §6. |
| Todos los criterios como «✅ Cumplido» sin evidencia | Estados con reservas y evidencia (§7). |
| SQL guardado en archivo `.md` | `consultas_sql_c_05.sql`. |
