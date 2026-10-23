-- Libera automáticamente las reservas que ya pasaron su tiempo de expiración
CREATE OR REPLACE FUNCTION liberar_reservas_vencidas()
RETURNS VOID AS $$
BEGIN
    -- Marcar como expiradas las reservas activas cuyo tiempo de vencimiento ya pasó
    UPDATE reserva
    SET estado = 'expirada'
    WHERE estado = 'activa' AND vence_en < clock_timestamp();

    -- Actualizar el inventario a 'disponible' donde la reserva haya expirado
    UPDATE inventario_funcion inv
    SET estado = 'disponible', id_reserva = NULL
    FROM reserva r
    WHERE inv.id_funcion = r.id_funcion 
      AND inv.id_asiento = r.id_asiento 
      AND r.estado = 'expirada'
      AND inv.estado = 'bloqueado';
      
    -- Actualizar el estado de la compra a 'Expirada' si todas sus reservas expiraron
    UPDATE compra c
    SET estado = 'Expirada'
    WHERE estado = 'Pendiente' 
      AND NOT EXISTS (
          SELECT 1 FROM reserva r 
          WHERE r.id_compra = c.id_compra AND r.estado = 'activa'
      );
END;
$$ LANGUAGE plpgsql;

-- Permite visualizar el mapa de asientos con sus estados (disponible, bloqueado, vendido)
CREATE OR REPLACE FUNCTION consultar_disponibilidad(p_id_funcion BIGINT)
RETURNS TABLE (
    asiento_id INT,
    estado_actual VARCHAR,
    reserva_id BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT inv.id_asiento, inv.estado, inv.id_reserva
    FROM inventario_funcion inv
    WHERE inv.id_funcion = p_id_funcion
    ORDER BY inv.id_asiento;
END;
$$ LANGUAGE plpgsql;

-- Reserva múltiples asientos de forma atómica evitando estados parciales inconsistentes y aplicando límite de entradas
CREATE OR REPLACE FUNCTION reservar_asientos(
    p_id_usuario_cliente BIGINT, 
    p_id_usuario_actor BIGINT, 
    p_id_funcion BIGINT, 
    p_asientos INT[]
)
RETURNS BIGINT AS $$
DECLARE
    v_id_compra BIGINT;
    v_asiento INT;
    v_id_reserva BIGINT;
    v_limite_entradas INT := 6;
BEGIN
    -- Validar que se seleccionaron asientos
    IF array_length(p_asientos, 1) IS NULL OR array_length(p_asientos, 1) = 0 THEN
        RAISE EXCEPTION 'Debe seleccionar al menos un asiento para reservar.';
    END IF;

    -- Validar restricción de límite de entradas
    IF array_length(p_asientos, 1) > v_limite_entradas THEN
        RAISE EXCEPTION 'No puede seleccionar más de % entradas por compra.', v_limite_entradas;
    END IF;

    -- Crear la cabecera de la compra en estado 'Pendiente'
    INSERT INTO compra (id_usuario_cliente, id_usuario_actor, id_funcion, estado, total)
    VALUES (p_id_usuario_cliente, p_id_usuario_actor, p_id_funcion, 'Pendiente', 0)
    RETURNING id_compra INTO v_id_compra;

    -- Recorrer cada asiento solicitado de manera segura
    FOREACH v_asiento IN ARRAY p_asientos
    LOOP
        -- Verificar disponibilidad estricta en el inventario
        PERFORM 1 FROM inventario_funcion 
        WHERE id_funcion = p_id_funcion AND id_asiento = v_asiento AND estado = 'disponible';
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'El asiento con ID % no se encuentra disponible. Operación cancelada.', v_asiento;
        END IF;

        -- Registrar la reserva temporal
        INSERT INTO reserva (id_compra, id_funcion, id_asiento, estado, vence_en, precio_unitario)
        VALUES (v_id_compra, p_id_funcion, v_asiento, 'activa', now() + interval '2 minutes', 7.50)
        RETURNING id_reserva INTO v_id_reserva;

        -- Registrar el detalle de la compra
        INSERT INTO compra_detalle (id_compra, id_asiento, id_categoria_entrada, id_tarifa, precio_base, total_linea)
        VALUES (v_id_compra, v_asiento, 1, 1, 7.50, 0.00, 7.50);

        -- Actualizar el inventario a estado 'bloqueado' vinculando la reserva
        UPDATE inventario_funcion
        SET estado = 'bloqueado', id_reserva = v_id_reserva
        WHERE id_funcion = p_id_funcion AND id_asiento = v_asiento;
    END LOOP;

    -- Calcular y actualizar el monto total inicial de la compra
    PERFORM calcular_total(v_id_compra);

    RETURN v_id_compra;
END;
$$ LANGUAGE plpgsql;

-- Suma los totales de cada línea (que ya consideran precio menos descuento)
CREATE OR REPLACE FUNCTION calcular_total(p_id_compra BIGINT)
RETURNS NUMERIC AS $$
DECLARE
    v_total NUMERIC(10,2);
BEGIN
    -- Suma los totales de cada línea
    SELECT COALESCE(SUM(total_linea), 0) INTO v_total
    FROM compra_detalle
    WHERE id_compra = p_id_compra;

    -- Actualizar el campo total final en la tabla compra
    UPDATE compra
    SET total = v_total
    WHERE id_compra = p_id_compra;

    RETURN v_total;
END;
$$ LANGUAGE plpgsql;

-- Procesa el pago, cambia estados a pagado o vendido y genera los boletos correspondientes
CREATE OR REPLACE FUNCTION procesar_pago(
    p_id_compra BIGINT, 
    p_resultado VARCHAR, 
    p_metodo VARCHAR, 
    p_referencia VARCHAR
)
RETURNS VOID AS $$
DECLARE
    v_monto NUMERIC(10,2);
    v_estado_pago VARCHAR(12);
    v_id_pago BIGINT;
    r_asiento RECORD;
BEGIN
    -- Obtener el monto total de la compra
    SELECT total INTO v_monto FROM compra WHERE id_compra = p_id_compra;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La compra con ID % no existe.', p_id_compra;
    END IF;

    -- Evaluar resultado del pago
    IF p_resultado = 'Exito' OR p_resultado = 'Aprobado' THEN
        v_estado_pago := 'Aprobado';
    ELSE
        v_estado_pago := 'Rechazado';
    END IF;

    -- Registrar el pago en la tabla pago
    INSERT INTO pago (id_compra, estado, metodo, referencia, monto)
    VALUES (p_id_compra, v_estado_pago, p_metodo, p_referencia, v_monto)
    RETURNING id_pago INTO v_id_pago;

    -- Registrar la transacción en el log
    INSERT INTO transaccion_log (id_compra, id_pago, resultado, evento, estado_anterior, estado_nuevo, monto, moneda)
    VALUES (p_id_compra, v_id_pago, p_resultado, 'Procesar Pago', 'Pendiente', v_estado_pago, v_monto, 'USD');

    -- Acciones si el pago fue aprobado exitosamente
    IF v_estado_pago = 'Aprobado' THEN
        UPDATE compra SET estado = 'Pagada' WHERE id_compra = p_id_compra;
        UPDATE reserva SET estado = 'confirmada' WHERE id_compra = p_id_compra;

        -- Generar boletos y actualizar inventario a 'vendido' para cada asiento de la compra
        FOR r_asiento IN 
            SELECT cd.id_funcion, cd.id_asiento 
            FROM compra_detalle cd 
            JOIN compra c ON cd.id_compra = c.id_compra 
            WHERE c.id_compra = p_id_compra
        LOOP
            INSERT INTO boleto (id_compra, id_funcion, id_asiento, estado)
            VALUES (p_id_compra, r_asiento.id_funcion, r_asiento.id_asiento, 'Emitido');
            
            UPDATE inventario_funcion
            SET estado = 'vendido', 
                id_boleto = (SELECT MAX(id_boleto) FROM boleto WHERE id_compra = p_id_compra AND id_asiento = r_asiento.id_asiento)
            WHERE id_funcion = r_asiento.id_funcion AND id_asiento = r_asiento.id_asiento;
        END LOOP;
    ELSE
        -- Si el pago es rechazado, se cancela la compra
        UPDATE compra SET estado = 'Cancelada' WHERE id_compra = p_id_compra;
        
        -- Se marcan las reservas como liberadas
		UPDATE reserva SET estado = 'liberada' WHERE id_compra = p_id_compra;

        -- Se devuelve el inventario a estado 'disponible'
        UPDATE inventario_funcion inv
        SET estado = 'disponible', id_reserva = NULL
        FROM compra_detalle cd
        WHERE inv.id_funcion = (SELECT id_funcion FROM compra WHERE id_compra = p_id_compra)
          AND inv.id_asiento = cd.id_asiento
          AND cd.id_compra = p_id_compra;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Consulta los boletos adquiridos por un cliente específico
CREATE OR REPLACE FUNCTION consultar_boletos_usuario(
    p_id_usuario_cliente BIGINT, 
    p_id_usuario_actor BIGINT
)
RETURNS TABLE (
    boleto_id BIGINT,
    compra_id BIGINT,
    funcion_id BIGINT,
    asiento_id INT,
    estado_boleto VARCHAR,
    qr_token UUID
) AS $$
BEGIN
    RETURN QUERY
    SELECT b.id_boleto, b.id_compra, b.id_funcion, b.id_asiento::INT, b.estado, b.token_qr
    FROM boleto b
    JOIN compra c ON b.id_compra = c.id_compra
    WHERE c.id_usuario_cliente = p_id_usuario_cliente;
END;
$$ LANGUAGE plpgsql;

-- Revierte una venta/compra pagada, anula boletos y libera el inventario de asientos
CREATE OR REPLACE FUNCTION revertir_venta(
    p_id_compra BIGINT, 
    p_id_usuario_actor BIGINT, 
    p_motivo VARCHAR
)
RETURNS VOID AS $$
BEGIN
    -- Actualizar estado de la compra a Reembolsada
    UPDATE compra
    SET estado = 'Reembolsada'
    WHERE id_compra = p_id_compra;

    -- Anular los boletos asociados
    UPDATE boleto
    SET estado = 'Anulado'
    WHERE id_compra = p_id_compra;

    -- Liberar el inventario de la función
    UPDATE inventario_funcion inv
    SET estado = 'disponible', id_reserva = NULL, id_boleto = NULL
    FROM compra_detalle cd
    WHERE inv.id_funcion = (SELECT id_funcion FROM compra WHERE id_compra = p_id_compra)
      AND inv.id_asiento = cd.id_asiento
      AND cd.id_compra = p_id_compra;

    -- Actualizar estado de la reserva
    UPDATE reserva
    SET estado = 'liberada'
    WHERE id_compra = p_id_compra;

    -- Registrar la acción en el log de transacciones[cite: 1]
    INSERT INTO transaccion_log (id_compra, id_usuario_actor, resultado, evento, estado_anterior, estado_nuevo, detalle)
    VALUES (p_id_compra, p_id_usuario_actor, 'Exito', 'Revertir Venta', 'Pagada', 'Reembolsada', p_motivo);
END;
$$ LANGUAGE plpgsql;
