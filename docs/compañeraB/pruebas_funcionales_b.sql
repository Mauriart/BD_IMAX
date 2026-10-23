-- Preparar inventario inicial
INSERT INTO inventario_funcion (id_funcion, id_asiento, estado)
SELECT 1, id_asiento, 'disponible' 
FROM asiento 
WHERE id_asiento BETWEEN 1 AND 6
ON CONFLICT (id_funcion, id_asiento) 
DO UPDATE SET estado = 'disponible', id_reserva = NULL, id_boleto = NULL;

-- B-T00: Consultar disponibilidad inicial de la función
BEGIN;
SELECT * FROM consultar_disponibilidad(1);
ROLLBACK;

-- Reservar los asientos 1 y 2
BEGIN;
SELECT reservar_asientos(1, 1, 1, ARRAY[1, 2]);
SELECT * FROM consultar_disponibilidad(1);
ROLLBACK;

--B-T01: No se pueden reservar más de 6 asientos
BEGIN;
SELECT reservar_asientos(1, 1, 1, ARRAY[1, 2, 3, 4, 5, 6, 7]);
ROLLBACK;

--B-T02 Un segundo cliente no puede tomar un asiento ya bloqueado
BEGIN;
SELECT reservar_asientos(1, 1, 1, ARRAY[1]);
SELECT reservar_asientos(1, 1, 1, ARRAY[1]);
ROLLBACK;

--B-T03 Si uno de los asientos falla, ninguno queda reservado
BEGIN;
SELECT reservar_asientos(1, 1, 1, ARRAY[1]);
SELECT reservar_asientos(1, 1, 1, ARRAY[1, 2, 3]);
ROLLBACK;

--B-T04: Una reserva vencida libera su asiento
BEGIN;
SELECT reservar_asientos(1, 1, 1, ARRAY[1]);
UPDATE reserva SET vence_en = now() - interval '1 minute' WHERE estado = 'activa';
SELECT liberar_reservas_vencidas();
-- Verificar que el asiento volvió a estar disponible
SELECT * FROM consultar_disponibilidad(1);
ROLLBACK;

--B-T05: Pago rechazado cancela la compra y libera el inventario
BEGIN;
-- Reservar el asiento 3
SELECT reservar_asientos(1, 1, 1, ARRAY[3]);
-- Procesar pago como Rechazado
SELECT procesar_pago(id_compra, 'Rechazado', 'Tarjeta', 'REF-PAGO-001')
FROM compra ORDER BY id_compra DESC LIMIT 1;
-- Verificar que el asiento 3 se liberó
SELECT * FROM consultar_disponibilidad(1);
ROLLBACK;

--B-T06: Pago aprobado emite boletos correctamente
BEGIN;
-- Reservar el asiento 3
SELECT reservar_asientos(1, 1, 1, ARRAY[3]);
-- Procesar pago aprobado ('Exito')
SELECT procesar_pago(id_compra, 'Exito', 'Tarjeta', 'REF-PAGO-002')
FROM compra ORDER BY id_compra DESC LIMIT 1;
-- Verificar que se crearon los boletos
SELECT * FROM boleto WHERE id_compra = (SELECT id_compra FROM compra ORDER BY id_compra DESC LIMIT 1);
ROLLBACK;


--B-T07: Enviar dos veces el mismo pago no duplica nada
BEGIN; 
SELECT reservar_asientos(1, 1, 1, ARRAY[1]);
SELECT procesar_pago(id_compra, 'Exito', 'Tarjeta', 'REF-DUP-001') 
FROM compra ORDER BY id_compra DESC LIMIT 1; --primer pago
SELECT procesar_pago(id_compra, 'Exito', 'Tarjeta', 'REF-DUP-001') 
FROM compra ORDER BY id_compra DESC LIMIT 1; --pago duplicado
ROLLBACK;

--B-T08: Un pago que llega tarde se rechaza y no genera boletos
BEGIN; 
SELECT reservar_asientos(1, 1, 1, ARRAY[5]);
UPDATE reserva SET vence_en = now() - interval '5 minutes' WHERE estado = 'activa';
SELECT liberar_reservas_vencidas();
-- Intentar procesar el pago de forma tardía (se procesa como rechazado o cancelado)
SELECT procesar_pago(id_compra, 'Rechazado', 'Tarjeta', 'REF-TARDE-001') 
FROM compra ORDER BY id_compra DESC LIMIT 1;
-- Verificar que NO se generaron boletos para esta compra
SELECT * FROM boleto WHERE id_compra = (SELECT id_compra FROM compra ORDER BY id_compra DESC LIMIT 1);
ROLLBACK;

--B-T09: Validar el cálculo automático de totales de compra
BEGIN; 
SELECT reservar_asientos(1, 1, 1, ARRAY[1, 2, 3]);
-- Consultar la compra y su monto total calculado
SELECT id_compra, total, estado, moneda FROM compra ORDER BY id_compra DESC LIMIT 1;
ROLLBACK;

-- B-T10: Cada cliente ve solo sus boletos
BEGIN;
SELECT reservar_asientos(1, 1, 1, ARRAY[1]);
SELECT procesar_pago(id_compra, 'Exito', 'Tarjeta', 'REF-PAGO-003') 
FROM compra ORDER BY id_compra DESC LIMIT 1;
SELECT * FROM consultar_boletos_usuario(1, 1);
ROLLBACK;

-- BT-11: Rembolso y anulación del boleto
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



