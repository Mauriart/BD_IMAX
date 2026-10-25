# Diccionario de Datos — Módulo B: Ventas, Inventario, Pagos y Reembolsos

**Módulo:** Ventas, Inventario por Función y Procesamiento Financiero (Bloque B)
**Propietaria:** Keilyn
**Basado en:** Acuerdos del equipo`00_acuerdos.md`
**Estado:** B-01 Completado con arquitectura extendida

---

## 1. Propósito del Módulo
Este módulo gestiona el ciclo completo de comercialización de entradas de cine:
- Creación de órdenes de compra con cliente y actor de taquilla/sistema.
- Desglose detallado por línea de compra (`compra_detalle`) conservando tarifas y descuentos históricos.
- Control en tiempo real del inventario por función (`inventario_funcion`) y bloqueos temporales (`reserva`).
- Procesamiento simulado de pagos y emisión de boletos con código QR único (`UUID`).
- Registro y ejecución de devoluciones simuladas parciales o totales (`reembolso` y `reembolso_detalle`).
- Bitácoras inalterables a nivel de base de datos (`transaccion_log` y `asiento_auditoria_log`).

---

## 2. Diccionario de Tablas

### 2.1 Tabla `compra`
Registra la orden principal de venta iniciada por un cliente o procesada por un operador/taquillero.

| Columna | Tipo | Nulo | Por defecto | PK/FK | Restricciones | Propósito / Regla que protege |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id_compra` | `BIGINT` | No | `GENERATED ALWAYS` | PK | — | Identificador único de la orden de compra. |
| `id_usuario_cliente` | `BIGINT` | No | — | FK | `REFERENCES usuario` | Cliente titular de la compra. |
| `id_usuario_actor` | `BIGINT` | No | — | FK | `REFERENCES usuario` | Usuario/operador que ejecuta la transacción. |
| `id_funcion` | `BIGINT` | No | — | FK | `REFERENCES funcion` | Función específica a la que aplica la compra. |
| `estado` | `VARCHAR(15)` | No | `'Pendiente'` | — | `CHECK (estado IN ('Pendiente','Pagada','Cancelada','Expirada','Reembolsada'))` | Estado del ciclo de vida de la orden. |
| `total` | `NUMERIC(10,2)`| No | `0` | — | `CHECK (total >= 0)` | Monto total acumulado de la compra. |
| `moneda` | `CHAR(3)` | No | `'USD'` | — | — | Moneda de la transacción (USD / Acuerdos 00). |
| `creada_en` | `TIMESTAMPTZ` | No | `now()` | — | — | Estampa de tiempo exacta de la orden. |

---

### 2.2 Tabla `compra_detalle`
Almacena el desglose por línea de cada entrada adquirida, fijando precios y promociones al momento de cotizar.

| Columna | Tipo | Nulo | Por defecto | PK/FK | Restricciones | Propósito / Regla que protege |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id_compra_detalle` | `BIGINT` | No | `GENERATED ALWAYS` | PK | — | Identificador único de la línea de detalle. |
| `id_compra` | `BIGINT` | No | — | FK | `REFERENCES compra` | Compra a la que pertenece esta entrada. |
| `id_asiento` | `INT` | No | — | FK | `REFERENCES asiento` | Asiento físico seleccionado. |
| `id_categoria_entrada`| `INT` | No | — | FK | `REFERENCES categoria_entrada`| Categoría aplicada (adulto, niño, estudiante, etc.). |
| `id_tarifa` | `INT` | No | — | FK | `REFERENCES tarifa` | Tarifa de catálogo utilizada como base. |
| `id_promocion` | `BIGINT` | Sí | `NULL` | FK | `REFERENCES promocion` | Promoción aplicada (ej. 2x1) si aplica. |
| `precio_base` | `NUMERIC(10,2)`| No | `0` | — | `CHECK (precio_base >= 0)` | Precio original de la tarifa sin descuento. |
| `descuento` | `NUMERIC(10,2)`| No | `0` | — | `CHECK (descuento >= 0)` | Descuento asignado a este asiento. |
| `cargo_servicio` | `NUMERIC(10,2)`| No | `0` | — | — | Cargo adicional por servicio (USD 0.00 inicial). |
| `total_linea` | `NUMERIC(10,2)`| No | — | — | — | Total neto por asiento (`precio_base - descuento + cargo`). |

---

### 2.3 Tabla `reserva`
Registra el bloqueo temporal de inventario asignado a una compra mientras se completa el pago.

| Columna | Tipo | Nulo | Por defecto | PK/FK | Restricciones | Propósito / Regla que protege |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id_reserva` | `BIGINT` | No | `GENERATED ALWAYS` | PK | — | Identificador único del registro de reserva. |
| `id_compra` | `BIGINT` | No | — | FK | `REFERENCES compra` | Compra asociada al bloqueo. |
| `id_funcion` | `BIGINT` | No | — | FK | `REFERENCES funcion` | Función reservada. |
| `id_asiento` | `BIGINT` | No | — | FK | `REFERENCES asiento` | Asiento reservado. |
| `estado` | `VARCHAR(12)` | No | `'activa'` | — | `CHECK (estado IN ('activa','confirmada','expirada','liberada'))` | Estado del bloqueo temporal. |
| `categoria` | `VARCHAR(20)` | No | `'adulto'` | — | — | Categoría de la entrada. |
| `precio_unitario`| `NUMERIC(10,2)`| Sí | `NULL` | — | `CHECK (precio_unitario >= 0)` | Cotización congelada por asiento. |
| `creada_en` | `TIMESTAMPTZ` | No | `now()` | — | — | Instante de inicio de la reserva. |
| `vence_en` | `TIMESTAMPTZ` | No | — | — | — | Vencimiento estricto de 120 segundos (RN-05). |

* **Índice de seguridad contra doble bloqueo:** `uq_ocupacion_vigente` (`UNIQUE` en `id_funcion, id_asiento` con filtro `WHERE estado IN ('Activa', 'Confirmada')`).

---

### 2.4 Tabla `inventario_funcion`
Representa la matriz de ocupación física en tiempo real para cada asiento de cada función.

| Columna | Tipo | Nulo | Por defecto | PK/FK | Restricciones | Propósito / Regla que protege |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id_funcion` | `INT` | No | — | PK, FK | `REFERENCES funcion` | Parte de la clave primaria compuesta. |
| `id_asiento` | `INT` | No | — | PK, FK | `REFERENCES asiento` | Parte de la clave primaria compuesta. |
| `estado` | `VARCHAR(20)` | No | `'disponible'` | — | `CHECK (estado IN ('disponible','bloqueado','vendido'))` | Estado actual del asiento en el mapa. |
| `id_reserva` | `BIGINT` | Sí | `NULL` | FK | `REFERENCES reserva` | Reserva activa si el estado es `'bloqueado'`. |
| `id_boleto` | `BIGINT` | Sí | `NULL` | FK, UNIQUE| `REFERENCES boleto` | Boleto asociado si el estado es `'vendido'`. |

* **Restricción de Integridad Físico-Lógica (`ck_inventario_ocupante`):**
  - Si está `'disponible'`, `id_reserva` e `id_boleto` DEBEN ser `NULL`.
  - Si está `'bloqueado'`, `id_reserva` DEBE existir e `id_boleto` DEBE ser `NULL`.
  - Si está `'vendido'`, ambos `id_reserva` e `id_boleto` DEBEN existir.

---

### 2.5 Tabla `pago`
Registra las transacciones financieras enviadas a la pasarela simulada.

| Columna | Tipo | Nulo | Por defecto | PK/FK | Restricciones | Propósito / Regla que protege |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id_pago` | `BIGINT` | No | `GENERATED ALWAYS` | PK | — | Identificador del cobro. |
| `id_compra` | `BIGINT` | No | — | FK | `REFERENCES compra` | Orden de compra cobrada. |
| `estado` | `VARCHAR(12)` | No | — | — | `CHECK (estado IN ('Pendiente','Aprobado','Rechazado','Reembolsado'))` | Resultado del intento de pago. |
| `metodo` | `VARCHAR(20)` | No | — | — | — | Tarjeta, transferencia, efectivo, etc. |
| `referencia` | `VARCHAR(60)` | No | — | — | `UNIQUE` | Código de referencia para garantizar idempotencia. |
| `monto` | `NUMERIC(10,2)`| No | — | — | `CHECK (monto >= 0)` | Importe total cobrado. |
| `moneda` | `CHAR(3)` | No | `'USD'` | — | — | Moneda (USD). |
| `creado_en` | `TIMESTAMPTZ` | No | `now()` | — | — | Instante de la transacción. |

---

### 2.6 Tabla `boleto`
Entradas digitales individuales emitidas tras la aprobación del pago.

| Columna | Tipo | Nulo | Por defecto | PK/FK | Restricciones | Propósito / Regla que protege |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id_boleto` | `BIGINT` | No | `GENERATED ALWAYS` | PK | — | Identificador interno del boleto. |
| `id_compra` | `BIGINT` | No | — | FK | `REFERENCES compra` | Compra asociada. |
| `id_funcion` | `BIGINT` | No | — | FK | `REFERENCES funcion` | Función autorizada. |
| `id_asiento` | `BIGINT` | No | — | FK | `REFERENCES asiento` | Asiento asignado. |
| `token_qr` | `UUID` | No | `gen_random_uuid()`| — | `UNIQUE` | Token único para lectura de QR en puerta (RN-12). |
| `estado` | `VARCHAR(10)` | No | `'Emitido'` | — | `CHECK (estado IN ('Emitido','Usado','Anulado'))` | Estado del boleto individual. |
| `emitido_en` | `TIMESTAMPTZ` | No | `now()` | — | — | Instante de emisión. |
| `usado_en` | `TIMESTAMPTZ` | Sí | `NULL` | — | — | Registro de hora al escanear en puerta. |

* **Índice de seguridad contra doble emisión vigente:** `uq_boleto_vigente` (`UNIQUE` en `id_funcion, id_asiento` con filtro `WHERE estado IN ('Emitido','Usado')`).

---

### 2.7 Tabla `reembolso`
Encabezado financiero que certifica la devolución simulada de dinero.

| Columna | Tipo | Nulo | Por defecto | PK/FK | Restricciones | Propósito / Regla que protege |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id_reembolso` | `BIGINT` | No | `GENERATED ALWAYS` | PK | — | Identificador del reembolso. |
| `id_solicitud_reembolso`| `BIGINT` | No | — | FK, UNIQUE| `REFERENCES solicitud_reembolso`| Solicitud aprobada por la Persona C. |
| `id_pago` | `BIGINT` | No | — | FK | `REFERENCES pago` | Pago original sobre el que se hace la devolución. |
| `referencia` | `VARCHAR(80)` | No | — | — | `UNIQUE` | Código de transacción de la devolución. |
| `monto` | `NUMERIC(12,2)`| No | — | — | `CHECK (monto > 0)` | Monto devuelto. |
| `moneda` | `VARCHAR(3)`| No | `'USD'` | — | — | Moneda (USD). |
| `creado_en` | `TIMESTAMPTZ` | No | `now()` | — | — | Fecha y hora del reembolso. |

---

### 2.8 Tabla `reembolso_detalle`
Relaciona cada reembolso con los boletos específicos que fueron anulados.

| Columna | Tipo | Nulo | Por defecto | PK/FK | Restricciones | Propósito / Regla que protege |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id_reembolso` | `BIGINT` | No | — | PK, FK | `REFERENCES reembolso` | Parte de la clave primaria compuesta. |
| `id_boleto` | `BIGINT` | No | — | PK, FK, UNIQUE| `REFERENCES boleto` | Boleto anulado. Evita devolver 2 veces el mismo boleto. |
| `monto` | `NUMERIC(12,2)`| No | — | — | `CHECK (monto > 0)` | Importe individual devuelto por este boleto. |

---

### 2.9 Tabla `transaccion_log`
Bitácora de eventos financieros y cambios de estado en transacciones.

| Columna | Tipo | Nulo | Por defecto | PK/FK | Restricciones | Propósito / Regla que protege |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id_trasaccion_log`| `BIGINT` | No | `GENERATED ALWAYS` | PK | — | Identificador de la bitácora. |
| `creado_en` | `TIMESTAMPTZ` | No | `now()` | — | — | Instante del evento registrado. |
| `id_compra` | `BIGINT` | Sí | `NULL` | — | — | Compra involucrada (opcional). |
| `id_pago` | `BIGINT` | Sí | `NULL` | — | — | Pago involucrado (opcional). |
| `id_usuario_actor` | `BIGINT` | Sí | `NULL` | — | — | Usuario/operador que generó el evento. |
| `resultado` | `VARCHAR(10)` | No | — | — | `CHECK (resultado IN ('Exito','Rechazo','Fallo'))` | Resultado del proceso registrado. |
| `evento` | `VARCHAR(40)` | No | — | — | — | Nombre del evento (ej. `'PAGO_APROBADO'`). |
| `estado_anterior` | `VARCHAR(15)` | Sí | `NULL` | — | — | Estado previo del recurso. |
| `estado_nuevo` | `VARCHAR(15)` | Sí | `NULL` | — | — | Nuevo estado asignado. |
| `monto` | `NUMERIC(10,2)`| Sí | `NULL` | — | — | Importe involucrado si aplica. |
| `moneda` | `CHAR(3)` | Sí | `NULL` | — | — | Moneda. |
| `detalle` | `TEXT` | Sí | `NULL` | — | — | Información técnica o motivo. |

* **Protección de Inalterabilidad:** Protegida mediante el Trigger `trg_tlog_inmutable` que impide operaciones de `UPDATE` o `DELETE`.

---

### 2.10 Tabla `asiento_auditoria_log`
Bitácora de cambios de estado e inventario en los asientos de las funciones.

| Columna | Tipo | Nulo | Por defecto | PK/FK | Restricciones | Propósito / Regla que protege |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id_asiento_auditoria_log`| `BIGINT` | No | `GENERATED ALWAYS` | PK | — | Identificador del registro de auditoría. |
| `creado_en` | `TIMESTAMPTZ` | No | `now()` | — | — | Instante exacto del cambio. |
| `id_funcion` | `BIGINT` | No | — | — | — | Función afectada. |
| `id_asiento` | `BIGINT` | No | — | — | — | Asiento afectado. |
| `id_compra` | `BIGINT` | Sí | `NULL` | — | — | Compra asociada si aplica. |
| `id_usuario_actor` | `BIGINT` | Sí | `NULL` | — | — | Usuario que causó el cambio. |
| `evento` | `VARCHAR(40)` | No | — | — | — | Nombre de la acción (ej. `'BLOQUEO_ASIENTO'`). |
| `estado_anterior` | `VARCHAR(15)` | Sí | `NULL` | — | — | Estado anterior en inventario. |
| `estado_nuevo` | `VARCHAR(15)` | Sí | `NULL` | — | — | Nuevo estado asignado. |
| `detalle` | `TEXT` | Sí | `NULL` | — | — | Motivo o contexto adicional. |

* **Protección de Inalterabilidad:** Protegida mediante el Trigger `trg_alog_inmutable` que impide operaciones de `UPDATE` o `DELETE`.

---

## 3. Justificación de Normalización y Decisiones Técnicas

1. **Separación de Inventario y Reservas Históricas:**
   * La tabla `inventario_funcion` mantiene el estado **actual y en tiempo real** de cada asiento (`disponible`, `bloqueado`, `vendido`), actuando como un semáforo de alta velocidad.
   * La tabla `reserva` y las tablas de log conservan la **trazabilidad histórica permanente**, garantizando que aunque una reserva expire o se libere, el registro quede guardado para auditoría.

2. **Detalle de Compra e Instantánea de Precios (`compra_detalle`):**
   * Se almacena `precio_base`, `descuento` y `cargo_servicio` por cada línea individual. Esto cumple con la norma de **3ª Forma Normal (3FN)** al desacoplar las tarifas cambiantes del catálogo general de la Persona A del precio real cobrado históricamente en cada venta.

3. **Reembolsos Parciales y Granularidad por Boleto:**
   * La relación entre `reembolso` y `reembolso_detalle` permite devolver uno o varios boletos de una misma compra sin necesidad de anular la orden completa. La restricción `UNIQUE` en `reembolso_detalle(id_boleto)` evita técnicamente que un mismo boleto sea reembolsado más de una vez.

4. **Triggers e Inalterabilidad a 5 Años:**
   * La inalterabilidad exigida en el proyecto para los logs se resuelve a nivel de motor de BD mediante los triggers `trg_tlog_inmutable` y `trg_alog_inmutable`, garantizando la máxima seguridad sin depender de la aplicación web.
