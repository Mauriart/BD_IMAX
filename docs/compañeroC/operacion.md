# Riesgos, continuidad y operación — Bloque C (C-06)

Responsable: **IanDavid1406 (C)** · Issue: **C-06 / #21** · Versión 1.1 · 24 de octubre de 2026

Integra el dimensionamiento y los logs de **C-05 / #19** (documentación v1.1, `c05_dimensionamiento.sql` v1.0). Donde C-05 y la versión 1.0 de este documento diferían, prevalece C-05 y el cambio se registra en §13.

Fases DBLC cubiertas: **Fase 1** (análisis de riesgos) y **Fase 5** (operación y mantenimiento). Reglas relacionadas: RN-09, RN-10, RN-14, RN-17, RN-19, RN-20 y las políticas de los [acuerdos](00_acuerdos.md).

## 0. Cómo leer este documento

Este documento propone una operación **global**. El prototipo local solo aporta evidencia parcial de integridad, auditoría e inalterabilidad. Para evitar confusiones:

| Etiqueta | Significado |
| --- | --- |
| **[OBJ]** | Objetivo de la propuesta global. No está medido ni contratado. |
| **[LOCAL]** | Comportamiento comprobado en el prototipo con `imax.sql` y el script `sql/c06_verificacion_continuidad.sql`. |
| **[PEND]** | Depende de otro módulo (B/A), del dimensionamiento de C-05 o de un simulacro aún no ejecutado. |

Los valores RPO ≤ 5 s, RTO < 5 min y SLA 99,99 % son los de la consigna y los acuerdos (§1). Son metas que la arquitectura debe justificar, no cifras ya medidas. Los costos pertenecen a A-06. Los volúmenes y tamaños provienen de C-05 (§7.3); aquí no se inventan cifras nuevas. Los supuestos de C-05 que **no están medidos** (compresión del archivo, compresión de backup, multiplicador de WAL) se marcan donde se usan.

## 1. Arquitectura de referencia (resumen coherente con A)

Se toma como base [factibilidad.md](factibilidad.md) §4:

- Cada **celda regional** tiene un PostgreSQL primario, una réplica en otra zona de la misma región, balanceador, pool de conexiones, caché de catálogo, cola de tareas y monitoreo.
- Cada función pertenece a una región, que es la única que confirma sus reservas, ventas e ingresos (§4.1 de A).
- Los respaldos y el WAL se guardan **separados** del primario, en otra región y otra cuenta/suscripción.
- El histórico y la auditoría se exportan a almacenamiento protegido contra alteración (WORM).
- Se añade un **testigo de quórum** en una tercera ubicación para decidir promociones sin riesgo de dos primarios (§R-10).

## 2. Matriz única de riesgos y mitigación

Formato obligatorio de la consigna. Probabilidad: Baja/Media/Alta. Impacto: Bajo/Medio/Crítico. RTO/RPO son objetivos **[OBJ]**.

| ID Riesgo | Descripción del riesgo | Probabilidad | Impacto | Estrategia de mitigación / Plan de respaldo (DRP) | RTO / RPO objetivo |
| --- | --- | --- | --- | --- | --- |
| R-01 | Caída de la instancia primaria de BD durante un estreno. | Media | Crítico | Réplica síncrona en otra zona con conmutación automática (Patroni o servicio administrado), aislamiento del primario anterior (*fencing*) y reconexión del pool. Alertas al detectar la falla. | RTO < 5 min (meta de diseño ≈ 1-2 min) / RPO ≈ 0 |
| R-02 | Pérdida de una zona o región completa de la celda. | Baja | Crítico | Réplica asíncrona en otra región con retraso monitoreado; promoción decidida por quórum con testigo; DNS/balanceo global redirige. Procedimiento manual de respaldo aprobado por el responsable de guardia. | RTO < 5 min con promoción automática; fallback documentado ≤ 15 min / RPO ≤ 5 s (acotado por el retraso medido) |
| R-03 | Falla de la red o del proveedor de internet (sede o cine). | Alta | Medio | Varios enlaces y proveedores en sedes críticas y puertas, respaldo celular, balanceo multizona, CDN para archivos públicos. No se escribe en BD por rutas no autorizadas. | RTO < 5 min / RPO 0 (no se confirmó escritura) |
| R-04 | Caída, lentitud o respuesta tardía de la pasarela de pago. | Alta | Crítico | Tiempos de espera y *circuit breaker*; referencia de idempotencia única por pago (existe en el diseño de B); proveedor secundario; conciliación posterior de pagos pendientes. El rechazo cancela la compra y libera asientos (RN-10). Una confirmación tardía no reactiva asientos liberados (acuerdos §6). | RTO < 5 min (cambio de proveedor) / RPO 0 (referencia registrada antes de llamar) |
| R-05 | Doble venta del mismo asiento de una función por pérdida de consistencia del inventario. | Media | Crítico | Unicidad física de la ocupación vigente `(id_funcion, id_asiento)`; transacciones atómicas; bloqueos en orden de ID; prueba automatizada de 50 solicitudes; consulta periódica de conciliación (V09c del script). **[PEND]**: ver hallazgo H-2. | RTO < 5 min (detección y bloqueo de la función) / RPO 0 |
| R-06 | Borrado o corrupción lógica por error humano o migración defectuosa. | Media | Crítico | Recuperación a un instante (PITR) hacia una instancia temporal; extracción de las filas afectadas y reconciliación; privilegios mínimos; migraciones revisadas y probadas en copia. | RTO ≤ 60 min / RPO ≈ 0 hasta el instante previo al error (WAL continuo) |
| R-07 | Ataque de denegación de servicio (DDoS) en el estreno. | Alta | Crítico | CDN y WAF con límites por origen/usuario; sala de espera antes de la compra; autoescalado limitado; el pool protege a la BD. Los límites se prueban para no bloquear redes compartidas. | RTO < 5 min (mitigación automática) / RPO 0 |
| R-08 | Acaparamiento de asientos por bots o intentos de reventa. | Alta | Medio | Límite de 6 asientos por compra (RN-04), cuenta autenticada, límite de tasa, captcha ante comportamiento anómalo, bloqueo de 120 s sin renovación. | RTO n/a / RPO n/a |
| R-09 | Saturación de BD por una función muy demandada (conexiones, esperas, *deadlocks*). | Alta | Crítico | Pool con límite, sala de espera, orden de bloqueo uniforme, `lock_timeout` y `statement_timeout`, reintento limitado, caché solo para lectura de catálogo. | RTO < 5 min / RPO 0 |
| R-10 | Retraso de réplica o *split-brain* (dos primarios aceptando ventas). | Baja | Crítico | Quórum con testigo; *fencing* antes de promover; las lecturas críticas (reserva, pago, ingreso) van al primario; alerta si el retraso supera 2 s; si no se asegura quién manda, se suspenden las ventas. | RTO < 5 min / RPO ≤ 5 s |
| R-11 | QR duplicado o falla de los dispositivos de puerta. | Media | Medio | Consumo condicional `emitido → usado` (RN-14); token UUID; registro de cada intento en `acceso_puerta_log`; protocolo de incidencias con autorización del administrador y registro posterior. | RTO < 5 min / RPO 0 |
| R-12 | Abuso de privilegios o escalamiento de rol por personal interno. | Media | Crítico | Permisos validados en BD (`autorizar_accion`, `guardia_rbac`); acciones críticas con actor, rol, IP y motivo; separación de funciones; revisión periódica de usuarios y roles. | RTO n/a / RPO 0 (auditoría transaccional) |
| R-13 | Alteración o pérdida de las bitácoras de auditoría. | Baja | Crítico | Triggers de inmutabilidad y bloqueo de TRUNCATE; cuenta de aplicación con solo SELECT/INSERT; cuenta propietaria de las tablas distinta de la de despliegue y alerta ante DDL sobre los logs (`DISABLE TRIGGER`, `DROP`), porque un propietario o superusuario sí puede eludir los triggers; exportación mensual a WORM con retención ≥ 60 meses; manifiesto SHA-256 con conteo de filas en otra cuenta/región. | RTO ≤ 4 h (consulta del archivo) / RPO ≤ 5 s en BD; ≤ 1 h en archivo |
| R-14 | Exposición de datos de tarjeta o fuga de secretos. | Baja | Crítico | No recibir ni guardar PAN/CVV (RN-09); pasarela externa certificada; secretos fuera de Git y en gestor de secretos; TLS; escaneo del repositorio; rotación de credenciales. | RTO ≤ 1 h (revocar y rotar) / RPO n/a |
| R-15 | Respaldo corrupto, incompleto o inaccesible. | Media | Crítico | Restauración automática semanal a instancia efímera con comprobaciones; copias en dos regiones y cuentas; cifrado con claves respaldadas; simulacro trimestral. Un respaldo no probado no cuenta. | RTO ≤ 4 h (reconstrucción total desde archivo) / RPO ≤ 1 min (WAL transmitido) |
| R-16 | Cola de tareas atrasada o pérdida de avisos. | Media | Medio | Registro de la tarea pendiente en la misma transacción del cambio (*outbox*); reintentos idempotentes; alerta por antigüedad de la cola. | RTO ≤ 15 min / RPO 0 |
| R-17 | Despliegue o migración de esquema fallida. | Media | Crítico | Scripts SQL numerados; ensayo en copia con volumen representativo; despliegue gradual con reversión; prohibido desplegar durante estrenos (congelamiento). | RTO < 5 min (revertir aplicación) / RPO 0 |
| R-18 | Incumplimiento de privacidad o filtración de datos personales. | Baja | Crítico | Minimización y cifrado; acceso por rol; anonimización al solicitar supresión (ver §9); procedimiento de notificación de incidentes. | RTO n/a / RPO n/a; notificación según la norma aplicable |
| R-19 | Crecimiento sin control del almacenamiento, ausencia de particiones o agotamiento de identificadores. | Media | Medio | Particiones mensuales creadas con antelación; alertas al 70 % y 85 % de capacidad; exportación y eliminación de particiones solo después de la retención; identificadores `BIGINT` en los logs de B (≈ 3.200 M de eventos en 60 meses superan el máximo de `INTEGER`, C-05 §9.1). | RTO ≤ 1 h / RPO 0 |
| R-20 | Errores de reloj o zona horaria (afectan bloqueo de 120 s y tolerancia de puerta). | Baja | Medio | Usar siempre la hora de la BD (`CURRENT_TIMESTAMP`, `timestamptz`) y NTP monitoreado; zona IANA por cine para fechas locales. | RTO n/a / RPO 0 |
| R-21 | Error de configuración de precios o políticas. | Media | Medio | Vigencias sin traslape (A); cambios de política solo con `cambiar_politica` auditada; cotización de la reserva congelada. | RTO ≤ 15 min / RPO 0 |

## 3. Seguimiento de la matriz

Complementa la matriz sin alterar su formato obligatorio.

| ID | Regla / fuente | Propietario | Indicador o alerta | Evidencia |
| --- | --- | --- | --- | --- |
| R-01 | SLA, RTO | C con A | Latencia del primario, estado de réplica | **[PEND]** simulacro S-01 |
| R-02 | RTO/RPO | C con A | Retraso de réplica regional (alerta > 2 s) | **[PEND]** simulacro S-04 |
| R-03 | SLA | A | Disponibilidad por enlace | **[PEND]** |
| R-04 | RN-09, RN-10 | B | Pagos pendientes > tiempo máximo | **[PEND]** B-03 |
| R-05 | RN-03/05 | B | Resultado de V09c = 0; prueba de 50 solicitudes | **[PEND]** B-06 (H-2) |
| R-06 | Fase 5 | C | Prueba de PITR | **[PEND]** S-03 |
| R-07 | Fase 1 | A | Solicitudes bloqueadas por WAF | **[PEND]** |
| R-08 | RN-04 | B | Compras por usuario/origen | **[PEND]** |
| R-09 | Pico 50.000 TPS | B con A | Esperas por bloqueo, conexiones usadas | **[PEND]** prueba de carga |
| R-10 | RPO | C | Retraso de réplica, estado del testigo | **[PEND]** S-04 |
| R-11 | RN-14/15/16 | C | Rechazos de puerta por motivo | **[LOCAL]** función `validar_y_consumir_ingreso_qr` con registro de intentos |
| R-12 | RN-17/20 | C | Acciones denegadas (`denegado:*`) | **[LOCAL]** V03 y V04; matriz de roles en `rol_permiso` |
| R-13 | RN-20 | C | Verificación de triggers y privilegios; DDL sobre logs | **[LOCAL]** V03, V04, V11 y los 15 casos de `c05_verificacion_logs.sql` (OK en PG 16.15); alerta de DDL **[PEND]** |
| R-14 | RN-09 | B con C | Columnas sensibles | **[LOCAL]** V06 y V07 |
| R-15 | Fase 5 | C | Resultado de restauración automática | **[PEND]** S-02; procedimiento local en §11 |
| R-16 | Operación | B | Edad de la cola | **[PEND]** |
| R-17 | Fase 4/5 | Todos | Fallos de despliegue | **[PEND]** |
| R-18 | Privacidad | C | Solicitudes y accesos a datos personales | **[PEND]** |
| R-19 | RN-20 | C | Capacidad usada, particiones creadas | **[LOCAL]** cálculo C-05 §5; alertas y particiones **[PEND]** |
| R-20 | RN-05/16 | Todos | Desfase NTP | **[LOCAL]** diseño con `timestamptz` |
| R-21 | RN-07 | A con C | Cambios de política | **[LOCAL]** `cambiar_politica` auditada |

## 4. Qué ocurre en cada escenario de falla

| Falla | Qué ocurre | Qué se conserva | Responsable |
| --- | --- | --- | --- |
| Una copia de la aplicación | El balanceador la retira; el resto atiende. | Todo; las operaciones confirmadas están en BD. | Plataforma |
| Primario de BD | Conmutación a la réplica síncrona de la misma región; el primario anterior queda aislado. Las operaciones en vuelo sin `COMMIT` se rechazan y el cliente reintenta con la misma referencia. | Todo lo confirmado (RPO ≈ 0). | Administración de BD |
| Réplica | Se reconstruye desde el primario; sin ella el primario puede suspender ventas si exige confirmación síncrona. | Todo. | Administración de BD |
| Zona completa | Igual que el primario si la réplica estaba en otra zona. | Todo lo confirmado. | Administración de BD |
| Región completa | Promoción de la réplica asíncrona de otra región por quórum. Las ventas confirmadas que no llegaron se detectan comparando con la pasarela. | Todo hasta el retraso medido (≤ 5 s objetivo). | Plataforma y finanzas |
| Pasarela de pago | Las compras quedan `pendiente`; vencen a los 120 s y liberan asientos; se activa el proveedor secundario. | Referencias de pago; sin duplicar cobros. | Finanzas |
| Cola o caché | La venta sigue; los avisos se reenvían desde la tabla *outbox*; el catálogo se lee de BD con mayor latencia. | Todo. | Plataforma |
| Enlace de un cine | La puerta usa el enlace de respaldo. Sin conexión no se admite por QR: procede el protocolo de incidencias autorizado. | Los registros posteriores se asientan con su motivo. | Operación de sala |
| Almacenamiento de respaldos | Se usa la copia de la otra región; se reconstruye la perdida. | Las dos copias no se pierden a la vez salvo desastre múltiple. | Administración de BD |
| Borrado accidental | PITR a instancia temporal y reinserción controlada. | Lo anterior al error. | Administración de BD |

## 5. RPO, RTO y SLA: objetivos y justificación

### 5.1 Clases de datos

| Clase | Contenido | RPO | RTO |
| --- | --- | --- | --- |
| 0 — Críticos | Inventario, compras, pagos, boletos, estado de QR | ≤ 5 s (ideal 0) | < 5 min |
| 1 — Puerta y autorización | Validación de ingreso, usuarios, roles | ≤ 5 s | < 5 min |
| 2 — Catálogo | Cartelera, tarifas | ≤ 5 min | ≤ 15 min (se sirve de caché) |
| 3 — Analítica | Reportes y dashboard | ≤ 1 h | ≤ 4 h |
| 4 — Archivo | Auditoría histórica en WORM | ≤ 1 h | ≤ 4 h para consulta |

Los objetivos de la consigna se aplican a las clases 0 y 1.

### 5.2 Presupuesto de indisponibilidad del SLA 99,99 %

| Periodo | Indisponibilidad permitida |
| --- | --- |
| Año (365 d) | 52,56 min |
| Mes (30 d) | 4,32 min |
| Semana | 60,48 s |

Un RTO de 5 min ya consume más que el presupuesto mensual. Por eso:

1. La meta de diseño de las conmutaciones es de **1-2 min**, no 5; el valor 5 es el límite.
2. Las actualizaciones se hacen sin parada (rolling) y las migraciones en línea.
3. El SLA se define sobre la **plataforma propia**; la pasarela externa y los proveedores se tratan como dependencias con su propio SLA. El SLA compuesto es el producto de los SLA de las dependencias en serie, por lo que se usan alternativas (R-04).
4. Incidentes que consuman el presupuesto se registran y justifican cambios de diseño.

### 5.3 Por qué la propuesta puede cumplir RPO ≤ 5 s

La frecuencia de respaldo **no** es la prueba del RPO: una copia diaria permitiría perder hasta un día. El RPO se cumple con tres mecanismos encadenados:

1. **Réplica síncrona de quórum dentro de la región** (`synchronous_commit` con `synchronous_standby_names = 'ANY 1 (...)'`): una transacción solo se confirma cuando al menos una réplica guardó el WAL. Ante la caída del primario no se pierden transacciones confirmadas (RPO ≈ 0).
2. **Réplica asíncrona entre regiones** con retraso monitoreado: la pérdida máxima ante un desastre regional es el retraso del momento. Con alerta a 2 s y objetivo ≤ 5 s se cumple mientras el enlace lo permita. La replicación síncrona entre regiones queda descartada para ventas por su latencia, salvo que las pruebas demuestren lo contrario.
3. **Transmisión continua de WAL al archivo** (por ejemplo `pg_receivewal` en modo síncrono, o el servicio administrado): permite PITR y reconstrucción. Con solo `archive_command` el límite sería `archive_timeout`, que por sí solo no garantiza 5 s.

En el caso financiero, la **conciliación con la pasarela** actúa como red adicional: un pago aprobado cuyo registro se perdiera se recupera por su referencia de idempotencia.

### 5.4 Por qué puede cumplir RTO < 5 min

El tiempo de recuperación se compone así (valores de diseño **[OBJ]**, a medir en simulacros):

| Componente | Orden esperado |
| --- | --- |
| Detección (vencimiento del *lease* del líder, ej. 30 s) | ≈ 30 s |
| *Fencing* y promoción | 10-30 s |
| Redirección del pool y reconexión de la aplicación | 10-30 s |
| Verificación mínima (consulta de humo) | 10-20 s |
| **Total esperado** | **≈ 1-2 min** (límite 5 min) |

No se presenta como medido. Se acepta la meta solo si los simulacros S-01 y S-04 lo confirman; si no, se ajusta el diseño o se declara la limitación.

### 5.5 Capacidad de replicación frente al pico (datos de C-05 §5.6)

C-05 estima, como **cota conservadora**, que si las 50.000 operaciones/s fueran escrituras de log (~185 B con índices) habría ≈ 8,8 MiB/s de datos y ≈ 22 MiB/s de WAL (multiplicador S-22 = 2,5, **no medido**). Implicaciones para el RPO:

| Concepto | Valor | Lectura |
| --- | --- | --- |
| WAL pico (cota, solo logs) | ≈ 22 MiB/s ≈ 176 Mbit/s | El enlace entre regiones debe superarlo con margen, además del WAL de las tablas operativas, que C-05 no incluye en esta cota. |
| WAL en la ventana de 600 s | ≈ 13.200 MiB ≈ 12,9 GiB | Si el enlace es insuficiente, el retraso crece durante el pico y **el RPO ≤ 5 s se pierde**. |
| Comparación con el legado | 50 Mbps ≈ 6 MiB/s | El enlace residencial cubriría menos de un tercio de esa cota: confirma el rechazo de la red legada. |

Consecuencias: (1) el enlace entre regiones se dimensiona con la cota y se mide en la prueba de carga; (2) la alerta de retraso (> 2 s) debe activar la sala de espera para reducir escritura; (3) si no se garantiza el enlace, la replicación entre regiones se declara con RPO mayor y no se afirma ≤ 5 s. La cota no es medición: los 50.000 TPS incluyen lecturas y no se suman al volumen mensual.

## 6. Réplica, backup y archivo histórico

| Mecanismo | Para qué sirve | Frecuencia / modo | No protege contra |
| --- | --- | --- | --- |
| **Réplica** | Continuar el servicio ante falla de hardware, zona o región. | Continua (síncrona en la región, asíncrona entre regiones). | Borrado accidental o corrupción: también se replican. |
| **Backup + WAL** | Volver a un estado anterior (PITR) o reconstruir todo. | Ver §7. | Pérdida de la propia copia si no se verifica o no está separada. |
| **Archivo histórico/auditoría (WORM)** | Conservar y consultar evidencia 60 meses sin alteración. | Exportación periódica de particiones vencidas del periodo caliente. | Restaurar el servicio completo: no contiene todo el estado operativo. |

## 7. Respaldo y recuperación

### 7.1 Frecuencia y retención propuesta

| Tipo | Frecuencia | Retención | Ubicación | Uso |
| --- | --- | --- | --- | --- |
| WAL continuo | Transmisión continua | 30 días | Región secundaria, otra cuenta | PITR y RPO bajo |
| Respaldo base completo | Semanal | 5 completos (4 semanales + 1) | Región secundaria | Punto de partida de PITR |
| Respaldo incremental | Diario | 30 días | Región secundaria | Reduce el tiempo de restauración (PostgreSQL 17 admite incrementales con `pg_basebackup`) |
| Volcado lógico (`pg_dump`) de esquema y catálogos | Diario | 30 días | Región secundaria | Portabilidad y revisión; **no** da PITR |
| Archivo de auditoría/financiero (WORM) | Mensual, al cerrar cada partición | ≥ 60 meses desde el evento | Almacenamiento inmutable, 2 copias | Evidencia fiscal y de seguridad |

Los valores de retención (30 días, 5 completos) son los supuestos S-21 y de backup de C-05, para que el costo de A-06 sea coherente. La versión 1.0 de este documento proponía además 8 semanas de completos y 12 respaldos mensuales; se retiran porque C-05 no los dimensiona y el archivo WORM ya conserva la historia de 60 meses. Si el equipo los quiere, se suman a C-05 y A-06.

**Respuesta a «¿frecuencia de respaldo aceptable?»:** semanal completo + diario incremental + WAL continuo. El RPO lo da el WAL/réplica, no el calendario. Los tamaños se calculan con la fórmula de §7.3 usando C-05.

### 7.2 Verificación

1. **Automática semanal (S-02):** restaurar el último base + WAL a una instancia efímera, arrancar, ejecutar `sql/c06_verificacion_continuidad.sql`, comparar conteos y destruir la instancia. Resultado guardado en `evidencias/c/c06/`.
2. **Simulacro trimestral de recuperación total (S-03):** PITR a un instante elegido y reconstrucción desde archivo; se mide RTO y pérdida real.
3. **Simulacro semestral de falla de primario y región (S-01, S-04):** se mide el tiempo hasta la primera venta exitosa y se comprueba que solo un primario confirma ventas.
4. **Cada resultado se compara con los objetivos** y, si no se cumplen, se abre una acción correctiva.

### 7.3 Almacenamiento (valores de C-05, mes 60)

Fuente: C-05 §5.5, escenario A (sin crecimiento) y B (+10 %/año). GiB = 2³⁰ bytes. Incluye los cuatro logs más los datos operativos; las filas de B (L1, L2, `pago`, `reserva`, `reserva_detalle`, `inventario_funcion`) son **provisionales**.

| Componente | A sin crecimiento | B +10 %/año |
| --- | --- | --- |
| Primario NVMe (6 meses calientes × 1,25) | 220,8 GiB | 323,3 GiB |
| 2 réplicas calientes | 441,6 GiB | 646,6 GiB |
| Archivo frío comprimido, 2 copias (supuesto 4:1 **no medido**) | 530,9 GiB | 648,3 GiB |
| Backups 30 días (fulls + incrementales + WAL; supuestos 2:1 y ×2,5 **no medidos**) | 603,6 GiB | 883,7 GiB |
| **Total** | **≈ 1,75 TiB** | **≈ 2,44 TiB** |

Solo los cuatro logs de RN-20: **1.083,7 GiB (≈ 1,06 TiB)** sin crecimiento y **1.500,6 GiB (≈ 1,47 TiB)** con crecimiento.

Puntos que C-06 aporta a la conciliación con A-06:

1. **Copias de backup.** C-05 cuenta el backup **una vez**. Este documento exige que la copia esté en otra región y cuenta (R-15). Una segunda copia añadiría 603,6 GiB (A) o 883,7 GiB (B), llevando el total a ≈ 2,34 TiB o ≈ 3,31 TiB. **Decisión pendiente del equipo:** aceptar una sola copia (con el archivo WORM de 2 copias como segunda línea) o costear la segunda.
2. **Alcance por celda.** C-05 dimensiona el total global como si fuera una instancia. Con celdas regionales (A §4.1) cada primario guarda una fracción; el reparto por región se define con A y no cambia el total.
3. **Ejemplo de 45 TB de la consigna.** C-05 §5.5 ya advierte que es referencial; A-06 debe usar la tabla de C-05.
4. **Tiempo de restauración.** Con un rendimiento efectivo **supuesto** de 200 MiB/s, restaurar el primario (220,8–323,3 GiB) toma ≈ 19–28 min, más la reproducción de WAL. Eso es compatible con el RTO ≤ 4 h de R-15, pero debe **medirse** en S-03.

### 7.4 Procedimiento de recuperación

1. Detectar y declarar el incidente (alerta o reporte); asignar responsable.
2. Decidir el tipo: falla de componente, región o corrupción lógica.
3. Falla de componente: conmutar por *failover*; comprobar que el anterior quedó aislado; **no** reabrir ventas hasta tener un único primario.
4. Corrupción lógica: restaurar a instancia temporal en el instante previo al error, extraer lo afectado y reaplicarlo bajo transacción.
5. Revisar integridad (V09), pagos pendientes frente a la pasarela, boletos usados contra acceso registrado.
6. Reanudar ventas gradualmente; registrar tiempos y pérdida en el informe del incidente.

## 8. Retención y trazabilidad de logs (5 años)

| Categoría | Tabla | Propietario | Estado en `imax.sql` |
| --- | --- | --- | --- |
| Financiera | `transaccion_log` | B | **[PEND]** no existe (B-05) |
| Inventario | `asiento_auditoria_log` | B | **[PEND]** no existe (B-05) |
| Puerta | `acceso_puerta_log` | C | **[LOCAL]** existe, inmutable |
| Administración | `admin_operacion_audit` | C | **[LOCAL]** existe, inmutable |

La consigna menciona tres categorías y enumera cuatro; se cubren las cuatro.

### 8.1 Inalterabilidad

**[LOCAL]** En el script de verificación se comprueba: triggers `BEFORE UPDATE/DELETE` y `BEFORE TRUNCATE` en las dos tablas de C; la cuenta `imax_app` tiene solo `SELECT, INSERT`; el contenido no incluye `password_hash`, `token_qr` completo ni CVV.

**Límite explícito (C-05 §4.2):** no se puede afirmar que los logs sean inalterables «ni con superusuario». El propietario de la tabla o un superusuario puede ejecutar `ALTER TABLE ... DISABLE TRIGGER`, `DROP TABLE` o modificar el catálogo. Lo comprobable es que la **cuenta de aplicación** no puede alterarlos y que cualquier intento por SQL normal se rechaza con `42501`.

**[OBJ]** Una tabla local **no** demuestra inalterabilidad a cinco años. Se propone:

1. Periodo caliente en BD (≈ 6 meses, alineado con el comentario de `acceso_puerta_log`).
2. Exportación mensual de cada partición vencida a almacenamiento WORM con modo de retención (por ejemplo S3 Object Lock en modo *compliance* o inmutabilidad temporal en Azure Blob; **verificar condiciones en la fecha de compra**).
3. Manifiesto por archivo con SHA-256 y conteo de filas, guardado en otra cuenta o región; la verificación periódica recalcula y compara una muestra histórica.
4. Eliminación solo por vencimiento del periodo (partición cuyo límite superior sea anterior a hoy − 60 meses) mediante un procedimiento controlado y auditado; nunca por DELETE.
5. Cuenta propietaria de las tablas distinta de la de despliegue, sin uso en la operación diaria, y alerta ante DDL sobre los logs.

### 8.2 Particionamiento (propuesta para tablas nuevas)

Las tablas existentes en `imax.sql` no están particionadas. Para B-05 y para una futura versión de las de C se propone partición por rango mensual de `fecha`:

```sql
-- Propuesta de referencia; no se instala en esta entrega.
CREATE TABLE transaccion_log (
    id_transaccion_log bigint GENERATED ALWAYS AS IDENTITY,
    fecha timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    /* resto de columnas */
    PRIMARY KEY (id_transaccion_log, fecha)   -- la PK debe incluir la clave de partición
) PARTITION BY RANGE (fecha);
```

La restricción única/PK debe incluir la clave de partición y las FK hacia una tabla particionada requieren revisión. Hay que crear las particiones con antelación (R-19).

**Hallazgo de C-05 §4.4 (comprobado en PG 16):** el trigger `BEFORE TRUNCATE` del padre **no** se dispara si se ejecuta `TRUNCATE` directamente sobre una partición. Por eso el trigger de inmutabilidad y el de TRUNCATE deben crearse en **cada** partición, o retirarse `TRUNCATE` a todo rol salvo el propietario. El script de verificación (V12) detecta particiones sin ellos. Para `acceso_puerta_log`, C-05 ya contiene el esquema particionado propuesto; no está aplicado en `imax.sql`.

## 9. Privacidad y seguridad de datos

### 9.1 Clasificación

| Dato | Clasificación | Medida |
| --- | --- | --- |
| `usuario.nombre`, `correo` | Personal | Acceso por rol, cifrado en reposo y tránsito |
| `usuario.password_hash` | Secreto | Hash fuerte; excluido de los logs (los triggers lo quitan con `- 'password_hash'`) |
| `boleto.token_qr` | Credencial de acceso | Solo el propietario lo consulta; no se guarda completo en logs |
| IP en `admin_operacion_audit` | Personal (empleados) | Acceso solo de lectura para roles autorizados; justificada por trazabilidad |
| PAN/CVV | Prohibido | Nunca se reciben ni almacenan (RN-09) |

### 9.2 Retención frente a supresión de datos personales

La retención de auditoría es una **obligación del caso académico** (y, en la práctica, normativa fiscal/seguridad según la jurisdicción). En normativas como el RGPD el derecho de supresión admite excepciones por obligación legal (art. 17.3.b); para Costa Rica aplica la Ley 8968. Esta propuesta **no es asesoría legal**; debe confirmarse por jurisdicción antes de operar.

Enfoque propuesto: los logs referencian `id_usuario`, no datos personales. Ante una solicitud de supresión, se **anonimiza** el usuario conservando su ID y la historia:

```sql
-- Propuesta, no instalada. Cumple los CHECK existentes de usuario.
UPDATE usuario
   SET nombre = 'Usuario anonimizado',
       correo = 'anonimo-' || id_usuario || '@anonimizado.invalid',
       password_hash = 'ANONIMIZADO'
 WHERE id_usuario = :id;
```

Los respaldos caducan a los 30 días y la anonimización se reaplica tras una restauración. La operación debe registrarse en `admin_operacion_audit`.

### 9.3 Seguridad operativa

- Permisos y propiedad se validan en BD (`autorizar_accion`, `guardia_rbac`, `exigir_permiso`); ocultar botones no basta.
- La cuenta de aplicación (`imax_app`) no es superusuaria ni puede alterar logs.
- Secretos fuera de Git; revisión del repositorio antes de publicarlo.
- Acceso a respaldos y WORM separado de la cuenta de aplicación; cifrado con claves respaldadas.

## 10. Operación y mantenimiento

### 10.1 Monitoreo y alertas

| Métrica | Umbral inicial | Acción |
| --- | --- | --- |
| Retraso de réplica | > 2 s alerta; > 5 s crítico | Investigar; si persiste, restringir ventas |
| Edad del último WAL archivado | > 60 s | Revisar transmisión |
| Último respaldo verificado | > 8 días | Ejecutar S-02 |
| Conexiones usadas del pool | > 80 % | Activar sala de espera |
| Esperas por bloqueo / *deadlocks* | Aumento sostenido | Revisar orden de bloqueo |
| Pagos pendientes | > tiempo máximo | Conciliar con pasarela |
| Edad de la cola | > 5 min | Escalar trabajadores |
| Capacidad de disco | 70 % / 85 % | Crear particiones / ampliar |
| Intentos `denegado:*` | Pico inusual | Revisar actor y origen |
| DDL sobre las tablas de log (`DISABLE TRIGGER`, `DROP`, `ALTER`) | Cualquier evento | Alerta inmediata a seguridad |

Cada alerta tiene responsable y procedimiento.

### 10.2 Mantenimiento rutinario

| Frecuencia | Tarea |
| --- | --- |
| Diaria | Revisar alertas, respaldos y estado de réplicas |
| Semanal | Restauración automática (S-02); `ANALYZE` y revisión de planes críticos |
| Mensual | Crear particiones, exportar a WORM, revisar roles de usuarios, parches de seguridad |
| Trimestral | Simulacro S-03; revisión de la matriz de riesgos |
| Semestral | Simulacros S-01 y S-04 |
| Anual | Revisión de retención, privacidad y costos |

### 10.3 Gestión de cambios

Scripts SQL numerados; ensayo en copia con el volumen representativo; revisión cruzada (A revisa B, B revisa C, C revisa A); plan de reversión antes de aplicar; congelamiento durante estrenos; registro de cada cambio.

### 10.4 Funciones operativas

Descritas en [factibilidad.md](factibilidad.md) §7: administración de BD, plataforma y red, seguridad y auditoría, taquilla y puerta, soporte y finanzas. C define las políticas de seguridad, auditoría y continuidad; no implica personal ya contratado.

## 11. Evidencia local y hallazgos

### 11.1 Cómo reproducir

1. Restaurar `imax.sql` en una base vacía. El volcado fue generado con `pg_dump 18.6` e incluye `\restrict`: usar un `psql` actualizado o eliminar esas dos líneas si el cliente no las reconoce.
2. Ejecutar `sql/c06_verificacion_continuidad.sql`. Todos los controles devuelven `OK`, `REVISAR`, `INFORMATIVO` o `PENDIENTE`.
3. Guardar la salida en `evidencias/c/c06/`.

Restauración lógica básica del prototipo:

```bash
createdb imax_restore
psql -d imax_restore -v ON_ERROR_STOP=1 -f imax.sql
psql -d imax_restore -f sql/c06_verificacion_continuidad.sql
```

Un volcado lógico demuestra que existe una copia **reproducible**, no un RPO ni un RTO.

### 11.1.1 Evidencia heredada de C-05

| Evidencia | Resultado | Límite |
| --- | --- | --- |
| `c05_logs_endurecimiento.sql` (idempotente, aplicado dos veces) | Sin error | Ejecutado en PG 16.15; las restricciones `ck_puerta_*`, `fk_puerta_boleto` y `ck_audit_ip` ya constan en `imax.sql` |
| `c05_verificacion_logs.sql` | 15 de 15 casos OK (UPDATE/DELETE/TRUNCATE rechazados con `42501`, dominios y FK) | PG 16.15 sin líneas exclusivas de 17+; **repetir en la versión final del equipo** y guardar la salida en `evidencias/c/` |
| `c05_dimensionamiento.sql` | Tablas R1–R7 reproducibles | Tamaños por fila medidos en PG 16.15 con 300.000 filas sintéticas; S-18, S-20 y S-22 no medidos |

Orden sugerido para la evidencia de C-06: aplicar C-05 → `c05_verificacion_logs.sql` → `c06_verificacion_continuidad.sql`.

### 11.2 Hallazgos sobre `imax.sql` (a resolver)

| ID | Hallazgo | Impacto | Responsable |
| --- | --- | --- | --- |
| H-1 | Los acuerdos fijan PostgreSQL 17.x y el volcado proviene de 18.6. | Compatibilidad entre los tres equipos. | Todos |
| H-2 | La única unicidad en `compra_detalle` es `(id_compra, id_asiento)`; no hay restricción física de ocupación vigente por `(id_funcion, id_asiento)` ni tabla `inventario_funcion`. La protección actual depende de `asiento_ocupado` y de bloqueos en funciones. | R-05: la doble venta no queda impedida por restricción. | B |
| H-3 | No existen `transaccion_log` ni `asiento_auditoria_log`. | Faltan 2 de las 4 categorías de log. | B (B-05) |
| H-4 | `acceso_puerta_log` y `admin_operacion_audit` no están particionadas en `imax.sql`, aunque el comentario de la primera presupone DROP de partición. C-05 §4.4 propone el esquema, sin aplicar. | Ciclo de retención de 60 meses no implementado; `TRUNCATE` sobre una partición evade el trigger del padre. | C |
| H-5 | Datos sintéticos incoherentes: la solicitud de reembolso 3 no tiene detalle (el ejecutor la rechazaría); el boleto 2 está `usado` sin registro de puerta; `admin_operacion_audit` contiene una fila de prueba y no se puede borrar. | Pruebas de reporte y auditoría. Reinstalar la base antes de la demostración (C-05 §9.2). | C |
| H-6 | Los logs de B usarían `BIGINT` (≈ 3.200 M de eventos en 60 meses); los de C caben en `INTEGER` (puerta ≈ 940 M, ≈ 1.150 M con crecimiento), pero A-01 usó `SERIAL`. | Riesgo R-19 de agotar identificadores; la decisión es de Mauriart (C-05 §9.1). | B y A |
| H-7 | La verificación de C-05 se ejecutó en PG 16.15, no en 17/18. | La evidencia debe repetirse en la versión que se fije (ver H-1). | C |
| H-8 | C-05 cuenta el backup una sola vez; C-06 exige otra región/cuenta. | Diferencia de 603,6–883,7 GiB para A-06 (ver §7.3). | A y C |

## 12. Trazabilidad con el issue C-06

| Criterio del issue | Dónde se cumple | Estado |
| --- | --- | --- |
| Matriz única: riesgo, probabilidad, impacto, mitigación/DRP, RTO/RPO | §2 | Cubierto |
| Caída de BD, red, pasarela, doble venta, pérdida de datos y DDoS | R-01, R-03, R-04, R-05, R-06, R-07 | Cubierto |
| Justificar RPO ≤ 5 s, RTO < 5 min y SLA 99,99 % | §5 | Cubierto como propuesta; medición **[PEND]** |
| Frecuencia de backup, conservación, restauración/verificación, privacidad y logs a cinco años | §7, §8, §9 | Cubierto; tamaños de C-05 v1.1 (§7.3), con supuestos no medidos |
| Coherencia con la arquitectura de A | §1 y §4 | Cubierto |
| Se distinguen réplica, backup y archivo histórico | §6 | Cubierto |
| Backup no usado como prueba de RPO; mecanismo explicado | §5.3 | Cubierto |
| Objetivos globales distintos de la evidencia local; fuentes y limitaciones | §0, §11 y §13 | Cubierto |

## 13. Fuentes y limitaciones

- [PostgreSQL: archivado continuo y PITR](https://www.postgresql.org/docs/18/continuous-archiving.html)
- [PostgreSQL: réplica de espera y replicación síncrona](https://www.postgresql.org/docs/18/warm-standby.html)
- [PostgreSQL: particionamiento](https://www.postgresql.org/docs/18/ddl-partitioning.html)
- [PCI SSC: CVV no debe conservarse tras la autorización](https://www.pcisecuritystandards.org/faqs/1319/)
- Documentación de los proveedores para WORM e inmutabilidad (consultar la versión vigente antes de decidir).
- Consigna: «Proyecto II – Diseño desde Cero de una BD», Fases 1 y 5.

**Limitaciones.** (1) No se ejecutó ningún simulacro; los tiempos de §5.4 son de diseño. (2) Los tamaños provienen de C-05 v1.1: la compresión del archivo, la compresión de backup y el multiplicador de WAL (S-18, S-20, S-22) no están medidos, y las tablas de B (L1, L2, `pago`, `reserva`, `inventario_funcion`) son provisionales hasta B-05. (3) No se evaluó la normativa legal por país. (4) Se desconoce la configuración de los proveedores de nube elegidos en A-06. (5) El prototipo local no valida la escala global.

## Anexo — Plantilla de registro de simulacro

| Campo | Contenido |
| --- | --- |
| ID del simulacro | S-01 a S-04 |
| Fecha y entorno | |
| Escenario | Falla de primario / respaldo / PITR / región |
| Carga durante la prueba | Ventas por segundo y tipo |
| Instante de la falla | |
| Instante de la primera venta exitosa | |
| RTO medido | |
| Transacciones confirmadas perdidas (RPO real) | |
| ¿Un solo primario confirmó ventas? | Sí / No |
| Resultado de `c06_verificacion_continuidad.sql` | |
| Desviaciones y acciones | |
| Responsable | |

## Cambios de la versión 1.1 respecto a la 1.0

| Cambio | Motivo |
| --- | --- |
| Retención de backups alineada con C-05: 30 días y 5 completos; se retiran 8 semanas y 12 respaldos mensuales. | Coherencia de costo con A-06. |
| §7.3 reemplaza la fórmula por los valores de C-05 §5.5 y registra la diferencia por la copia de backup en otra región. | Datos entregados por C-05. |
| Nueva §5.5: capacidad de replicación frente al pico, con la cota de WAL de C-05 §5.6. | El RPO depende del enlace entre regiones. |
| §8.1 y R-13: se reconoce que un propietario o superusuario puede eludir los triggers; se añaden propietario separado y alerta de DDL. | Corrección heredada de C-05 §4.2. |
| §8.2: trigger de inmutabilidad y de TRUNCATE por partición. | Hallazgo de C-05 §4.4. |
| R-19 incluye agotamiento de identificadores; hallazgos H-6 a H-8. | C-05 §9. |
