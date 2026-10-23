# Diccionario de Datos — Módulo B: Ventas, Inventario y Boletos

**Módulo:** Ventas y Procesamiento Financiero (Bloque B)  
**Propietaria:** Keilyn  
**Estado:** B-01 Completado  

---

## 1. Propósito del Módulo
Este módulo gestiona la creación de órdenes de compra, el inventario temporal de asientos por función, el procesamiento simulado de pagos, la emisión de boletos digitales con código QR y la auditoría inalterable de transacciones e inventario.

---

## 2. Diccionario de Tablas

### 2.1 Tabla `compra`
Guarda las órdenes principales iniciadas por los clientes para una función específica.

| Columna | Tipo | Nulo | Por defecto | PK/FK | Restricciones | Propósito / Regla que protege |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id_compra` | `BIGINT` | No | `GENERATED ALWAYS` | PK | — | Identificador único de la compra. |
| `id_usuario` | `BIGINT` | No | — | FK | `REFERENCES usuario` | Cliente que realiza la compra. |
| `id_funcion` | `BIGINT` | No | — | FK | `REFERENCES funcion` | Función de cine a la que corresponde. |
| `id_promocion` | `BIGINT` | Sí | `NULL` | FK | `REFERENCES promocion` | Promoción aplicada (ej. 2x1) si aplica. |
| `estado` | `VARCHAR(15)` | No | `'pendiente'` | — | `CHECK (estado IN (...))` | Estado de la compra (pendiente, pagada, cancelada, expirada, reembolsada). |
| `subtotal` | `NUMERIC(10,2)`| No | `0` | — | `CHECK (subtotal >= 0)` | Suma de tarifas de los asientos. |
| `descuento` | `NUMERIC(10,2)`| No | `0` | — | `CHECK (descuento >= 0)` | Monto descontado por promociones. |
| `total` | `NUMERIC(10,2)`| No | `0` | — | `CHECK (total >= 0)` | Monto final a cobrar en la pasarela. |
| `moneda` | `CHAR(3)` | No | `'USD'` | — | — | Moneda de la transacción (USD). |
| `creada_en` | `TIMESTAMPTZ` | No | `now()` | — | — | Estampa de tiempo exacta de la orden. |

---

### 2.2 Tabla `reserva_asiento`
Representa el inventario por función. Registra el bloqueo temporal de un asiento para una función específica.

| Columna | Tipo | Nulo | Por defecto | PK/FK | Restricciones | Propósito / Regla que protege |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id_reserva` | `BIGINT` | No | `GENERATED ALWAYS` | PK | — | Identificador único de la reserva. |
| `id_compra` | `BIGINT` | No | — | FK | `REFERENCES compra` | Orden de compra asociada. |
| `id_funcion` | `BIGINT` | No | — | FK | `REFERENCES funcion` | Función específica a reservar. |
| `id_asiento` | `BIGINT` | No | — | FK | `REFERENCES asiento` | Asiento físico seleccionado. |
| `estado` | `VARCHAR(12)` | No | `'activa'` | — | `CHECK (estado IN (...))` | Estado del bloqueo (activa, confirmada, expirada, liberada). |
| `categoria` | `VARCHAR(20)` | No | `'adulto'` | — | — | Perfil de tarifa (adulto, nino, estudiante). |
| `precio_unitario`|`NUMERIC(10,2)`| Sí| `NULL` | — | `CHECK (precio >= 0)` | Precio fijado al cotizar (foto histórica). |
| `creada_en` | `TIMESTAMPTZ` | No | `now()` | — | — | Fecha y hora de inicio del bloqueo. |
| `vence_en` | `TIMESTAMPTZ` | No | — | — | — | Vencimiento del bloqueo (2 minutos / RN-05). |

* **Índice de seguridad contra doble venta:** `uq_ocupacion_vigente` (`UNIQUE` en `id_funcion, id_asiento` con filtro `WHERE estado IN ('activa','confirmada')`).

---

### 2.3 Tabla `pago`
Registra cada intento de pago simulado enviado a la pasarela.

| Columna | Tipo | Nulo | Por defecto | PK/FK | Restricciones | Propósito / Regla que protege |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id_pago` | `BIGINT` | No | `GENERATED ALWAYS` | PK | — | Identificador único del pago. |
| `id_compra` | `BIGINT` | No | — | FK | `REFERENCES compra` | Compra asociada al pago. |
| `estado` | `VARCHAR(12)` | No | — | — | `CHECK (estado IN (...))` | Resultado (pendiente, aprobado, rechazado, reembolsado). |
| `metodo` | `VARCHAR(20)` | No | — | — | — | Método de pago simulado (tarjeta, transferencia). |
| `referencia` | `VARCHAR(60)` | No | — | — | `UNIQUE` | Código de referencia para garantizar idempotencia. |
| `monto` | `NUMERIC(10,2)`| No | — | — | `CHECK (monto >= 0)` | Monto cobrado en la transacción. |
| `moneda` | `CHAR(3)` | No | `'USD'` | — | — | Moneda del pago (USD). |
| `creado_en` | `TIMESTAMPTZ` | No | `now()` | — | — | Momento del intento de pago. |

---

### 2.4 Tabla `boleto`
Entradas digitales emitidas únicamente tras la aprobación exitosa del pago (RN-11).

| Columna | Tipo | Nulo | Por defecto | PK/FK | Restricciones | Propósito / Regla que protege |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `id_boleto` | `BIGINT` | No | `GENERATED ALWAYS` | PK | — | Identificador interno del boleto. |
| `id_compra` | `BIGINT` | No | — | FK | `REFERENCES compra` | Compra que dio origen al boleto. |
| `id_funcion` | `BIGINT` | No | — | FK | `REFERENCES funcion` | Función válida para el ingreso. |
| `id_asiento` | `BIGINT` | No | — | FK | `REFERENCES asiento` | Asiento asignado. |
| `token_qr` | `UUID` | No | `gen_random_uuid()`| — | `UNIQUE` | Código UUID seguro contenido en el QR (RN-12). |
| `estado` | `VARCHAR(10)` | No | `'emitido'` | — | `CHECK (estado IN (...))` | Estado del boleto (emitido, usado, anulado). |
| `emitido_en` | `TIMESTAMPTZ` | No | `now()` | — | — | Estampa de tiempo de emisión. |
| `usado_en` | `TIMESTAMPTZ` | Sí | `NULL` | — | — | Estampa de tiempo registrada al escanear en puerta. |

---

## 3. Justificación de Normalización y Diseño Técnico

1. **Cumplimiento de la 3ª Forma Normal (3FN):**
   * Todas las tablas cuentan con claves primarias simples de tipo `BIGINT GENERATED ALWAYS AS IDENTITY`.
   * En `reserva_asiento`, la combinación `(id_funcion, id_asiento)` representa una clave candidata únicamente mientras el bloqueo esté vigente, por lo que se implementa mediante un índice único parcial y no como una restricción física rígida para no bloquear el historial [2].

2. **Preservación de Precios Históricos (Desnormalización Controlada):**
   * El campo `precio_unitario` se almacena explícitamente en `reserva_asiento` en el momento de la cotización [2]. Esto garantiza que si la Persona A modifica las tarifas generales del catálogo en el futuro, el precio de los boletos ya reservados o pagados se mantenga intacto e inalterable [2].

3. **Garantía Física contra Doble Venta:**
   * Mediante el índice único parcial `uq_ocupacion_vigente`, la base de datos rechaza de forma atómica a nivel de motor (sin depender de la pantalla) cualquier intento de insertar una segunda reserva activa o confirmada para el mismo asiento y función [2, 6, 7].