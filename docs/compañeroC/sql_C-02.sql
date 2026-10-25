-- Puerta de C conectada al boleto real de B. El QR solo contiene el UUID.
DROP FUNCTION IF EXISTS validar_y_consumir_ingreso_qr(uuid,integer,integer,varchar);
CREATE OR REPLACE FUNCTION validar_y_consumir_ingreso_qr(p_token_qr uuid,p_id_funcion_solicitada integer,
    p_id_usuario_operador integer,p_dispositivo varchar,p_acreditacion boolean DEFAULT FALSE)
RETURNS TABLE(exito boolean,mensaje text,id_boleto_procesado bigint)
LANGUAGE plpgsql AS $$
DECLARE b boleto%ROWTYPE; f funcion%ROWTYPE; rechazo text; compra_boleto bigint;
        instante timestamptz; categoria_especial boolean;
BEGIN
    PERFORM actor_ventas(p_id_usuario_operador,'validar_ingreso');
    IF btrim(coalesce(p_dispositivo,''))='' THEN RAISE EXCEPTION 'Identifique el dispositivo.' USING ERRCODE='23514'; END IF;
    SELECT * INTO b FROM boleto WHERE token_qr=p_token_qr;
    IF NOT FOUND THEN rechazo:='Codigo QR no registrado.';
    ELSE
        PERFORM coordinar_venta(b.id_funcion);
        PERFORM id_compra FROM compra WHERE id_compra=b.id_compra FOR UPDATE;
        SELECT * INTO b FROM boleto WHERE token_qr=p_token_qr FOR UPDATE;
        SELECT * INTO f FROM funcion WHERE id_funcion=b.id_funcion;
        instante:=clock_timestamp();
        SELECT ce.requiere_acreditacion INTO categoria_especial FROM compra_detalle cd
        JOIN categoria_entrada ce USING(id_categoria_entrada)
        WHERE cd.id_compra=b.id_compra AND cd.id_asiento=b.id_asiento;
        IF b.estado='Usado' THEN rechazo:='Entrada ya utilizada';
        ELSIF b.estado='Anulado' THEN rechazo:='Entrada anulada o reembolsada';
        ELSIF b.estado<>'Emitido' THEN rechazo:='Estado de entrada invalido';
        ELSIF b.id_funcion<>p_id_funcion_solicitada THEN rechazo:='Entrada de otra funcion';
        ELSIF NOT f.activa THEN rechazo:='Funcion inactiva';
        ELSIF instante<f.inicio-INTERVAL '30 minutes' OR instante>f.inicio+INTERVAL '15 minutes' THEN rechazo:='Acceso fuera de horario';
        ELSIF categoria_especial AND NOT p_acreditacion THEN rechazo:='Debe verificar la acreditacion de esta categoria';
        END IF;
    END IF;
    IF rechazo IS NULL THEN
        UPDATE boleto SET estado='Usado',usado_en=clock_timestamp() WHERE id_boleto=b.id_boleto;
    END IF;
    INSERT INTO acceso_puerta_log(id_boleto,id_funcion_solicitada,id_usuario_operador,dispositivo,resultado,motivo)
    VALUES(b.id_boleto,p_id_funcion_solicitada,p_id_usuario_operador,p_dispositivo,
        CASE WHEN rechazo IS NULL THEN 'aceptado' ELSE 'rechazado' END,coalesce(rechazo,'Acceso concedido'));
    RETURN QUERY SELECT rechazo IS NULL,coalesce(rechazo,'Acceso concedido'),b.id_boleto;
END $$;
