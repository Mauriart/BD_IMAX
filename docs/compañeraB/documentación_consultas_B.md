# Documentación y Pruebas del Sistema de Reserva y Ventas

**Módulo:** Ventas, Inventario por Función, Pagos y Boletos (Bloque B)\
**Propietaria:** Keilyn

---

## **1. Propósito del Documento**

Este documento contiene la explicación detallada, la función, la sintaxis SQL empleada y el resultado obtenido para cada una de las 11 pruebas/consultas realizadas en el sistema de gestión de inventario, reservas y compras.

## 1. B-T00: Consultar disponibilidad inicial y prueba de reserva básica

### ¿Qué es y para qué funciona?

Esta prueba verifica la consulta del estado de disponibilidad de los asientos de una función específica (Función ID: 1) y evalúa el comportamiento del sistema al realizar una reserva válida de 2 asientos (`ARRAY[1, 2]`).

### Código SQL

```
-- Consultar disponibilidad inicial
BEGIN;
SELECT * FROM consultar_disponibilidad(1);
ROLLBACK;

-- Reservar los asientos 1 y 2 y verificar cambio de estado
BEGIN;
SELECT reservar_asientos(1, 1, 1, ARRAY[1, 2]);
SELECT * FROM consultar_disponibilidad(1);
ROLLBACK;

```

### Resultado que manda

* **Disponibilidad Inicial:** Devuelve la lista de los asientos del 1 al 6, todos con el estado `'disponible'` y `reserva_id` como `NULL`.

* **Tras la Reserva:** Los asientos 1 y 2 pasan al estado `'bloqueado'` y se les asigna un identificador de reserva activa (`reserva_id`), mientras que los asientos del 3 al 6 permanecen en `'disponible'`.

## 2. B-T01: Validación de límite máximo de asientos por reserva

### ¿Qué es y para qué funciona?

Esta consulta evalúa la regla de negocio que prohíbe a un usuario seleccionar más de 6 entradas en un solo proceso de compra. Se intenta realizar una reserva solicitando 7 asientos (`ARRAY[1, 2, 3, 4, 5, 6, 7]`).

### Código SQL

```
BEGIN;
SELECT reservar_asientos(1, 1, 1, ARRAY[1, 2, 3, 4, 5, 6, 7]);
ROLLBACK;

```

### Resultado que manda

La función de la base de datos detiene la ejecución mediante un error de excepción controlado (`RAISE`):

* **Mensaje de Error:** `ERROR: No puede seleccionar más de 6 entradas por compra.`

* **Estado SQL:** `P0001` (Excepción lanzada por función PL/pgSQL).

## 3. B-T02: Bloqueo de asientos ya reservados por otro cliente

### ¿Qué es y para qué funciona?

Comprueba el mecanismo de concurrencia y control de disponibilidad impidiendo que un cliente reserve un asiento que ya ha sido bloqueado previamente por otro usuario.

### Código SQL

```
BEGIN;
SELECT reservar_asientos(1, 1, 1, ARRAY[1]); -- Primer cliente bloquea asiento 1
SELECT reservar_asientos(1, 1, 1, ARRAY[1]); -- Segundo cliente intenta tomar el mismo asiento
ROLLBACK;

```

### Resultado que manda

La segunda llamada a la función falla inmediatamente al detectar que el asiento ya no se encuentra libre:

* **Mensaje de Error:** `ERROR: El asiento con ID 1 no se encuentra disponible. Operación cancelada.`

* **Estado SQL:** `P0001`

## 4. B-T03: Atomicidad de la reserva (Principio de "Todo o Nada")

### ¿Qué es y para qué funciona?

Valida que si una solicitud de reserva contempla múltiples asientos y al menos uno de ellos falla (por estar ocupado), **ninguno** de los asientos solicitados de la lista quede bloqueado, manteniendo la integridad del proceso.

### Código SQL

```
BEGIN;
SELECT reservar_asientos(1, 1, 1, ARRAY[1]);        -- Asiento 1 queda bloqueado
SELECT reservar_asientos(1, 1, 1, ARRAY[1, 2, 3]); -- Intento de reservar 1, 2 y 3
ROLLBACK;

```

### Resultado que manda

* **Mensaje de Error:** `ERROR: El asiento con ID 1 no se encuentra disponible. Operación cancelada.`

* **Efecto:** La segunda transacción falla por completo, evitando que los asientos 2 y 3 queden bloqueados indebidamente.

## 5. B-T04: Expiración automática de reservas vencidas

### ¿Qué es y para qué funciona?

Evalúa la lógica de liberación de inventario cuando una reserva excede su tiempo de vigencia. Se fuerza el vencimiento cambiando la columna `vence_en` y se ejecuta la rutina de limpieza.

### Código SQL

```
BEGIN;
SELECT reservar_asientos(1, 1, 1, ARRAY[1]);
UPDATE reserva SET vence_en = now() - interval '1 minute' WHERE estado = 'activa';
SELECT liberar_reservas_vencidas();

-- Verificar que el asiento volvió a estar disponible
SELECT * FROM consultar_disponibilidad(1);
ROLLBACK;

```

### Resultado que manda

* `liberar_reservas_vencidas()` cambia el estado de la reserva expirada.

* Al consultar nuevamente la disponibilidad, el asiento 1 retorna al estado `'disponible'` con `reserva_id` en `NULL`.

## 6. B-T05: Cancelación de compra y liberación por pago rechazado

### ¿Qué es y para qué funciona?

Verifica que cuando una pasarela de pago responde con un estado rechazado (`'Rechazado'`), el sistema anula el proceso de compra y libera los asientos asociados para que otros usuarios puedan adquirirlos.

### Código SQL

```
BEGIN;
SELECT reservar_asientos(1, 1, 1, ARRAY[3]);

SELECT procesar_pago(id_compra, 'Rechazado', 'Tarjeta', 'REF-PAGO-001')
FROM compra ORDER BY id_compra DESC LIMIT 1;

SELECT * FROM consultar_disponibilidad(1);
ROLLBACK;

```

### Resultado que manda

* La función `procesar_pago` registra el estado como rechazado.

* La consulta final de disponibilidad confirma que el asiento 3 queda nuevamente libre (`'disponible'`).

## 7. B-T06: Emisión exitosa de boletos tras pago aprobado

### ¿Qué es y para qué funciona?

Verifica el flujo completo exitoso de una transacción: tras completar el pago (`'Exito'`), el sistema emite automáticamente los boletos correspondientes con sus tokens/códigos QR y marcas de tiempo.

### Código SQL

```
BEGIN;
SELECT reservar_asientos(1, 1, 1, ARRAY[3]);

SELECT procesar_pago(id_compra, 'Exito', 'Tarjeta', 'REF-PAGO-002')
FROM compra ORDER BY id_compra DESC LIMIT 1;

SELECT * FROM boleto WHERE id_compra = (SELECT id_compra FROM compra ORDER BY id_compra DESC LIMIT 1);
ROLLBACK;

```

### Resultado que manda

Devuelve el registro del nuevo boleto en la tabla `boleto` mostrando:

* **id_boleto:** Generado automáticamente.

* **id_asiento:** 3.

* **token_qr:** Identificador UUID asignado.

* **estado:** `'Emitido'`.

* **emitido_en:** Fecha y hora exacta del procesamiento.

## 8. B-T07: Control de pagos duplicados (Idempotencia)

### ¿Qué es y para qué funciona?

Asegura que el sistema prevenga el doble cobro o procesamiento repetido de una misma transacción utilizando referencias de pago únicas (`referencia`).

### Código SQL

```
BEGIN;
SELECT reservar_asientos(1, 1, 1, ARRAY[1]);

SELECT procesar_pago(id_compra, 'Exito', 'Tarjeta', 'REF-DUP-001')
FROM compra ORDER BY id_compra DESC LIMIT 1; -- Primer pago

SELECT procesar_pago(id_compra, 'Exito', 'Tarjeta', 'REF-DUP-001')
FROM compra ORDER BY id_compra DESC LIMIT 1; -- Pago duplicado
ROLLBACK;

```

### Resultado que manda

El motor de base de datos bloquea el segundo intento al violar la restricción de unicidad:

* **Mensaje de Error:** `ERROR: duplicate key value violates unique constraint "pago_referencia_key"`

* **Detalle:** `Key (referencia)=(REF-DUP-001) already exists.`

* **Estado SQL:** `23505` (Violación de restricción única).

## 9. B-T08: Rechazo de pago extemporáneo (Pago Tardío)

### ¿Qué es y para qué funciona?

Evalúa la regla que impide la emisión de boletos si un pago se aprueba o procesa después de que la reserva asociada haya sido liberada por vencimiento.

### Código SQL

```
BEGIN;
SELECT reservar_asientos(1, 1, 1, ARRAY[5]);
UPDATE reserva SET vence_en = now() - interval '5 minutes' WHERE estado = 'activa';
SELECT liberar_reservas_vencidas();

SELECT procesar_pago(id_compra, 'Rechazado', 'Tarjeta', 'REF-TARDE-001')
FROM compra ORDER BY id_compra DESC LIMIT 1;

SELECT * FROM boleto WHERE id_compra = (SELECT id_compra FROM compra ORDER BY id_compra DESC LIMIT 1);
ROLLBACK;

```

### Resultado que manda

* La consulta a la tabla `boleto` retorna **0 filas** (vacía), confirmando que no se generó ningún boleto para una compra vencida/rechazada.

## 10. B-T09: Cálculo automático del monto total de compra

### ¿Qué es y para qué funciona?

Verifica que al realizar una reserva de múltiples entradas, la base de datos calcule de manera automática y exacta el monto total a pagar según el precio de cada asiento.

### Código SQL

```
BEGIN;
SELECT reservar_asientos(1, 1, 1, ARRAY[1, 2, 3]);

SELECT id_compra, total, estado, moneda FROM compra ORDER BY id_compra DESC LIMIT 1;
ROLLBACK;

```

### Resultado que manda

Devuelve la información de la compra creada:

* **total:** `22.50` (Monto acumulado calculado).

* **estado:** `'Pendiente'`.

* **moneda:** `'USD'`.

## 11. B-T10: Consulta de boletos por usuario (Privacidad y Aislamiento)

### ¿Qué es y para qué funciona?

Garantiza que la función de consulta de boletos filtre correctamente los resultados para que cada cliente únicamente tenga acceso a visualizar sus propias entradas compradas.

### Código SQL

```
BEGIN;
SELECT reservar_asientos(1, 1, 1, ARRAY[1]);

SELECT procesar_pago(id_compra, 'Exito', 'Tarjeta', 'REF-PAGO-003')
FROM compra ORDER BY id_compra DESC LIMIT 1;

SELECT * FROM consultar_boletos_usuario(1, 1); -- (id_usuario, id_funcion)
ROLLBACK;

```

### Resultado que manda

Devuelve una fila correspondiente al boleto comprado por el usuario especificado:

* **boleto_id:** ID generado.

* **asiento_id:** 1.

* **qr_token:** UUID del código QR.

* **estado_boleto:** `'Emitido'`.

## 12. B-T11: Reembolso, anulación de boletos y liberación de inventario

### ¿Qué es y para qué funciona?

Prueba la funcionalidad de reversión de compra (`revertir_venta`). Evalúa que se anulen los boletos previamente emitidos y que los asientos involucrados retornen automáticamente al inventario de disponibles.

### Código SQL

```
BEGIN;
SELECT reservar_asientos(1, 1, 1, ARRAY[2]);

SELECT procesar_pago(id_compra, 'Exito', 'Tarjeta', 'REF-PAGO-004')
FROM compra ORDER BY id_compra DESC LIMIT 1;

-- Revertir la venta usando la última compra registrada
SELECT revertir_venta(id_compra, 1, 'Prueba de reembolso por solicitud')
FROM compra ORDER BY id_compra DESC LIMIT 1;

-- Verificar disponibilidad e inventario liberado
SELECT * FROM consultar_disponibilidad(1);
ROLLBACK;

```

### Resultado que manda

* La función de reversión procesa la solicitud con el motivo indicado.

* Al consultar la disponibilidad final, el asiento 2 se muestra libre nuevamente con el estado `'disponible'`.
