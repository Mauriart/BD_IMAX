-- MÓDULO C-02: CONTROL DE ACCESO Y PUERTA (Check-in con Código QR)
-- Autor: Integrante C (Ian David Fernández Aguilar)
-- Issue: C-02 (#16)
-- Reglas de Negocio atendidas: RN-14, RN-15, RN-16

-- -----------------------------------------------------------------------------
-- FUNCIÓN PRINCIPAL: validar_y_consumir_ingreso_qr
-- -----------------------------------------------------------------------------
-- Esta función procesa la validación del código QR en los tótems o dispositivos
-- de puerta de forma atómica.
-- 
-- Parámetros:
--   p_token_qr             : El token UUID contenido en el código QR del cliente.
--   p_id_funcion_solicitada: La función a la que el cliente intenta ingresar físicamente.
--   p_id_usuario_operador  : ID del operador de sala o sistema de puerta autenticado.
--   p_dispositivo          : Identificador del tótem o dispositivo de lectura (ej. 'Totem_Puerta_1').
--
-- Retorna:
--   TABLE(exito BOOLEAN, mensaje TEXT, id_boleto INT)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validar_y_consumir_ingreso_qr(
    p_token_qr UUID,
    p_id_funcion_solicitada INT,
    p_id_usuario_operador INT,
    p_dispositivo VARCHAR(100)
)
RETURNS TABLE (
    exito BOOLEAN,
    mensaje TEXT,
    id_boleto_procesado INT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_id_boleto INT;
    v_estado_boleto VARCHAR(20);
    v_id_funcion_real INT;
    v_inicio_funcion TIMESTAMPTZ;
    v_fin_funcion TIMESTAMPTZ;
    v_ahora TIMESTAMPTZ := CURRENT_TIMESTAMP;
    v_motivo_rechazo VARCHAR(200);
BEGIN
    -- 1. Verificar si el operador tiene permisos de validar ingreso (RBAC - RN-17)
    IF NOT public.autorizar_accion(p_id_usuario_operador, 'validar_ingreso') THEN
        RAISE EXCEPTION 'El usuario operador no posee permisos para validar accesos en puerta.'
            USING ERRCODE = '42501';
    END IF;

    -- 2. Buscar el boleto mediante su token QR.
    -- Aplicamos FOR UPDATE sobre el boleto para evitar que dos lecturas simultáneas
    -- procesen el mismo boleto al mismo milisegundo (prevención de concurrencia).
    SELECT 
        b.id_boleto, 
        b.estado, 
        c.id_funcion, 
        f.inicio, 
        f.fin
    INTO 
        v_id_boleto, 
        v_estado_boleto, 
        v_id_funcion_real, 
        v_inicio_funcion, 
        v_fin_funcion
    FROM public.boleto b
    INNER JOIN public.compra_detalle cd ON b.id_compra_detalle = cd.id_compra_detalle
    INNER JOIN public.compra c ON cd.id_compra = c.id_compra
    INNER JOIN public.funcion f ON c.id_funcion = f.id_funcion
    WHERE b.token_qr = p_token_qr
    FOR UPDATE OF b;

    -- 3. VALIDACIÓN 1: ¿Existe el boleto?
    IF v_id_boleto IS NULL THEN
        v_motivo_rechazo := 'Código QR no registrado o inexistente en el sistema';
        
        -- Guardar intento fallido en el log
        INSERT INTO public.acceso_puerta_log (
            fecha, id_boleto, id_funcion_solicitada, id_usuario_operador, dispositivo, resultado, motivo
        ) VALUES (
            v_ahora, NULL, p_id_funcion_solicitada, p_id_usuario_operador, p_dispositivo, 'rechazado', v_motivo_rechazo
        );

        RETURN QUERY SELECT FALSE, v_motivo_rechazo, NULL::INT;
        RETURN;
    END IF;

    -- 4. VALIDACIÓN 2: Estado del boleto (RN-14 y Reembolsos)
    IF v_estado_boleto = 'usado' THEN
        v_motivo_rechazo := 'Entrada ya utilizada';
    ELSIF v_estado_boleto = 'anulado' THEN
        v_motivo_rechazo := 'Boleto anulado o reembolsado previamente';
    ELSIF v_estado_boleto <> 'emitido' THEN
        v_motivo_rechazo := 'El estado del boleto no permite el ingreso (' || v_estado_boleto || ')';
    END IF;

    IF v_motivo_rechazo IS NOT NULL THEN
        INSERT INTO public.acceso_puerta_log (
            fecha, id_boleto, id_funcion_solicitada, id_usuario_operador, dispositivo, resultado, motivo
        ) VALUES (
            v_ahora, v_id_boleto, p_id_funcion_solicitada, p_id_usuario_operador, p_dispositivo, 'rechazado', v_motivo_rechazo
        );

        RETURN QUERY SELECT FALSE, v_motivo_rechazo, v_id_boleto;
        RETURN;
    END IF;

    -- 5. VALIDACIÓN 3: Verificación de Función y Horario (RN-15)
    IF v_id_funcion_real <> p_id_funcion_solicitada THEN
        v_motivo_rechazo := 'El boleto corresponde a otra función (Función ID ' || v_id_funcion_real || ')';
        
        INSERT INTO public.acceso_puerta_log (
            fecha, id_boleto, id_funcion_solicitada, id_usuario_operador, dispositivo, resultado, motivo
        ) VALUES (
            v_ahora, v_id_boleto, p_id_funcion_solicitada, p_id_usuario_operador, p_dispositivo, 'rechazado', v_motivo_rechazo
        );

        RETURN QUERY SELECT FALSE, v_motivo_rechazo, v_id_boleto;
        RETURN;
    END IF;

    -- 6. VALIDACIÓN 4: Tolerancia de Ingreso en Puerta (RN-16)
    -- Permitido desde 30 minutos antes de iniciar la función hasta 15 minutos después de iniciada.
    IF v_ahora < (v_inicio_funcion - INTERVAL '30 minutes') THEN
        v_motivo_rechazo := 'Ingreso muy temprano. Acceso permitido a partir de: ' || (v_inicio_funcion - INTERVAL '30 minutes');
    ELSIF v_ahora > (v_inicio_funcion + INTERVAL '15 minutes') THEN
        v_motivo_rechazo := 'Ingreso fuera de horario. La ventana de tolerancia (15 min) ha expirado';
    END IF;

    IF v_motivo_rechazo IS NOT NULL THEN
        INSERT INTO public.acceso_puerta_log (
            fecha, id_boleto, id_funcion_solicitada, id_usuario_operador, dispositivo, resultado, motivo
        ) VALUES (
            v_ahora, v_id_boleto, p_id_funcion_solicitada, p_id_usuario_operador, p_dispositivo, 'rechazado', v_motivo_rechazo
        );

        RETURN QUERY SELECT FALSE, v_motivo_rechazo, v_id_boleto;
        RETURN;
    END IF;

    -- 7. CONSUMO ATÓMICO DEL BOLETO (RN-14)
    -- Si llegó hasta aquí, todas las comprobaciones fueron exitosas.
    UPDATE public.boleto
    SET 
        estado = 'usado',
        usado_en = v_ahora
    WHERE id_boleto = v_id_boleto;

    -- 8. REGISTRO DE ACCESO EXITOSO EN BITÁCORA DE PUERTA
    INSERT INTO public.acceso_puerta_log (
        fecha, id_boleto, id_funcion_solicitada, id_usuario_operador, dispositivo, resultado, motivo
    ) VALUES (
        v_ahora, v_id_boleto, p_id_funcion_solicitada, p_id_usuario_operador, p_dispositivo, 'aceptado', 'Acceso concedido exitosamente'
    );

    RETURN QUERY SELECT TRUE, 'Acceso concedido exitosamente'::TEXT, v_id_boleto;
END;
$$;

ALTER FUNCTION public.validar_y_consumir_ingreso_qr(UUID, INT, INT, VARCHAR) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.validar_y_consumir_ingreso_qr(UUID, INT, INT, VARCHAR) TO imax_app;