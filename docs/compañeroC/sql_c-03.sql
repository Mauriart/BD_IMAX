-- =============================================================================
-- PROYECTO II - BD IMAX  |  Bloque C  |  Issue C-03 (#17)
-- "Aplicar RBAC, reembolsos autorizados y auditoría de cambios críticos"
-- Requisitos: RN-17 (privilegios mínimos), RN-19 (reembolsos), RN-20 (auditoría)
-- Motor: PostgreSQL. Script INCREMENTAL: se ejecuta sobre la BD que ya tiene
--        imax.sql (tablas de A, B-parcial y C-01/C-02). No borra datos ni tablas.
-- Es repetible (idempotente): puede ejecutarse más de una vez.
-- Incluye: RBAC en BD, reembolsos (solicitar/resolver/forzar), políticas, cortesías,
-- cambio manual de asiento, historial y resumen de auditoría administrativa.
-- Ejecutar con:  psql -v ON_ERROR_STOP=1 -d <base> -f script_c03_rbac_reembolsos_auditoria.sql
-- =============================================================================
BEGIN;

-- -----------------------------------------------------------------------------
-- 0. CORRECCIÓN Y ENDURECIMIENTO DE FUNCIONES YA EXISTENTES (C-01 / C-02)
--  a) validar_y_consumir_ingreso_qr declaraba v_motivo_rechazo como VARCHAR(200)
--     pero la función devuelve TEXT: toda ruta de RECHAZO lanzaba error
--     ("structure of query does not match function result type") y, al
--     revertirse la transacción, el intento rechazado NO quedaba en
--     acceso_puerta_log. Se corrige el tipo (resto del cuerpo sin cambios).
--  b) Ambas funciones SECURITY DEFINER / de autorización fijan search_path para
--     que nadie pueda "tapar" objetos de public con otros propios.
-- -----------------------------------------------------------------------------
ALTER FUNCTION public.autorizar_accion(integer, text)
    SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.validar_y_consumir_ingreso_qr(p_token_qr uuid, p_id_funcion_solicitada integer, p_id_usuario_operador integer, p_dispositivo character varying) RETURNS TABLE(exito boolean, mensaje text, id_boleto_procesado integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path = public, pg_temp
    AS $$
DECLARE
    v_id_boleto INT;
    v_estado_boleto VARCHAR(20);
    v_id_funcion_real INT;
    v_inicio_funcion TIMESTAMPTZ;
    v_fin_funcion TIMESTAMPTZ;
    v_ahora TIMESTAMPTZ := CURRENT_TIMESTAMP;
    v_motivo_rechazo TEXT;   -- CORREGIDO C-03: era VARCHAR(200) y rompía RETURN QUERY (tipo text)
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
            v_ahora, NULL, p_id_funcion_solicitada, p_id_usuario_operador, p_dispositivo, 'rechazado', left(v_motivo_rechazo, 200)
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
            v_ahora, v_id_boleto, p_id_funcion_solicitada, p_id_usuario_operador, p_dispositivo, 'rechazado', left(v_motivo_rechazo, 200)
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
            v_ahora, v_id_boleto, p_id_funcion_solicitada, p_id_usuario_operador, p_dispositivo, 'rechazado', left(v_motivo_rechazo, 200)
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
            v_ahora, v_id_boleto, p_id_funcion_solicitada, p_id_usuario_operador, p_dispositivo, 'rechazado', left(v_motivo_rechazo, 200)
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

-- -----------------------------------------------------------------------------
-- 1. NUEVOS PERMISOS DE LA MATRIZ DE ROLES (solo administrador)
-- -----------------------------------------------------------------------------
INSERT INTO rol_permiso (id_rol, accion)
SELECT r.id_rol, p.accion
FROM rol r
CROSS JOIN (VALUES ('forzar_reembolso'), ('configurar_politicas'),
                   ('otorgar_cortesia'), ('cambiar_asiento')) AS p(accion)
WHERE r.nombre = 'administrador'
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------------
-- 2. POLÍTICAS CENTRALIZADAS (acuerdos, sección 6)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS politica_negocio (
    clave          VARCHAR(60) PRIMARY KEY,
    valor_entero   INTEGER     NOT NULL CHECK (valor_entero >= 0),
    descripcion    TEXT        NOT NULL,
    actualizada_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO politica_negocio (clave, valor_entero, descripcion)
VALUES ('reembolso_horas_antes', 2,
        'Horas mínimas antes del inicio de la función para solicitar y ejecutar un reembolso ordinario (inclusive).')
ON CONFLICT (clave) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 3. FUNCIONES AUXILIARES
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION normalizar_ip(p_ip text)
RETURNS text
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    RETURN host(btrim(p_ip)::inet);
EXCEPTION WHEN others THEN
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION politica_entero(p_clave text)
RETURNS integer
LANGUAGE plpgsql STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v integer;
BEGIN
    SELECT valor_entero INTO v FROM politica_negocio WHERE clave = p_clave;
    IF v IS NULL THEN
        RAISE EXCEPTION 'La política % no está definida.', p_clave USING ERRCODE = '55000';
    END IF;
    RETURN v;
END;
$$;

-- Registro de auditoría administrativa. El rol se toma SIEMPRE de la BD,
-- nunca de un parámetro, para que no pueda falsificarse.
CREATE OR REPLACE FUNCTION auditar_accion(
    p_id_usuario_actor integer, p_ip text, p_accion text, p_entidad text,
    p_id_entidad text, p_motivo text, p_cambios jsonb DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rol varchar(30);
    v_ip  text := normalizar_ip(p_ip);
    v_id  integer;
BEGIN
    SELECT r.nombre INTO v_rol
    FROM usuario u INNER JOIN rol r ON r.id_rol = u.id_rol
    WHERE u.id_usuario = p_id_usuario_actor;
    IF v_rol IS NULL THEN
        RAISE EXCEPTION 'El actor % no existe.', p_id_usuario_actor USING ERRCODE = '23503';
    END IF;
    IF v_ip IS NULL THEN
        RAISE EXCEPTION 'La dirección IP del actor es inválida.' USING ERRCODE = '22023';
    END IF;
    IF btrim(coalesce(p_motivo, '')) = '' THEN
        RAISE EXCEPTION 'El motivo es obligatorio para auditar la acción.' USING ERRCODE = '23514';
    END IF;
    INSERT INTO admin_operacion_audit
        (id_usuario_actor, rol_al_actuar, ip, accion, entidad, id_entidad, motivo, cambios)
    VALUES (p_id_usuario_actor, v_rol, v_ip, p_accion, p_entidad, p_id_entidad, p_motivo, p_cambios)
    RETURNING id_admin_operacion_audit INTO v_id;
    RETURN v_id;
END;
$$;

-- Comprueba el permiso; si se deniega, deja constancia del intento en la
-- auditoría (el llamador devuelve un resultado, no lanza error, para que el
-- registro se confirme).
CREATE OR REPLACE FUNCTION exigir_permiso(
    p_id_usuario integer, p_accion text, p_ip text, p_entidad text, p_id_entidad text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF autorizar_accion(p_id_usuario, p_accion) THEN
        RETURN TRUE;
    END IF;
    IF EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario)
       AND normalizar_ip(p_ip) IS NOT NULL THEN
        PERFORM auditar_accion(p_id_usuario, p_ip, left('denegado:' || p_accion, 60),
                               p_entidad, p_id_entidad,
                               'Intento denegado: el rol no posee el permiso ' || p_accion, NULL);
    END IF;
    RETURN FALSE;
END;
$$;

-- -----------------------------------------------------------------------------
-- 4. SOLICITUD DE REEMBOLSO / CANCELACIÓN (RN-19)  -  gestión por C
-- Reglas: permiso solicitar_reembolso; el cliente solo su propia compra;
-- solo boletos 'emitido' (nunca usados ni anulados); política de horas antes
-- del inicio (ordinaria). Fuera de política solo la crea quien tenga el
-- permiso forzar_reembolso (administrador); los demás reciben FUERA_DE_POLITICA.
-- p_ids_boleto NULL o vacío = todos los boletos emitidos de la compra.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION solicitar_reembolso(
    p_id_usuario_actor integer, p_id_compra integer, p_ids_boleto integer[],
    p_motivo text, p_ip text)
RETURNS TABLE (exito boolean, codigo text, mensaje text, id_solicitud integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rol        text;
    v_cliente    integer;
    v_estado     text;
    v_inicio     timestamptz;
    v_ids        integer[];
    v_n          integer;
    v_horas      integer;
    v_fuera      boolean;
    v_id         integer;
BEGIN
    IF normalizar_ip(p_ip) IS NULL THEN
        RETURN QUERY SELECT FALSE, 'DATOS_INVALIDOS', 'La dirección IP es inválida.', NULL::integer; RETURN;
    END IF;
    IF btrim(coalesce(p_motivo, '')) = '' THEN
        RETURN QUERY SELECT FALSE, 'DATOS_INVALIDOS', 'El motivo es obligatorio.', NULL::integer; RETURN;
    END IF;
    IF NOT exigir_permiso(p_id_usuario_actor, 'solicitar_reembolso', p_ip, 'compra', p_id_compra::text) THEN
        RETURN QUERY SELECT FALSE, 'NO_AUTORIZADO', 'Su rol no puede solicitar reembolsos.', NULL::integer; RETURN;
    END IF;

    SELECT r.nombre INTO v_rol
    FROM usuario u INNER JOIN rol r ON r.id_rol = u.id_rol
    WHERE u.id_usuario = p_id_usuario_actor;

    SELECT c.id_usuario_cliente, c.estado, f.inicio
      INTO v_cliente, v_estado, v_inicio
    FROM compra c INNER JOIN funcion f ON f.id_funcion = c.id_funcion
    WHERE c.id_compra = p_id_compra
    FOR UPDATE OF c;
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'NO_ENCONTRADO', 'La compra no existe.', NULL::integer; RETURN;
    END IF;

    -- Propiedad: el cliente solo opera sobre sus compras (taquillero y administrador
    -- actúan en nombre de un cliente identificado).
    IF v_rol = 'cliente' AND v_cliente <> p_id_usuario_actor THEN
        PERFORM auditar_accion(p_id_usuario_actor, p_ip, 'denegado:compra_ajena', 'compra',
                               p_id_compra::text, 'Intento de reembolso sobre una compra de otro cliente', NULL);
        RETURN QUERY SELECT FALSE, 'NO_AUTORIZADO', 'La compra no pertenece al usuario.', NULL::integer; RETURN;
    END IF;

    IF v_estado NOT IN ('pagada', 'parcialmente_reembolsada') THEN
        RETURN QUERY SELECT FALSE, 'ESTADO_INVALIDO',
            'La compra está en estado ' || v_estado || ' y no admite reembolso.', NULL::integer; RETURN;
    END IF;

    IF p_ids_boleto IS NULL OR cardinality(p_ids_boleto) = 0 THEN
        SELECT array_agg(b.id_boleto ORDER BY b.id_boleto) INTO v_ids
        FROM boleto b INNER JOIN compra_detalle cd ON cd.id_compra_detalle = b.id_compra_detalle
        WHERE cd.id_compra = p_id_compra AND b.estado = 'emitido';
    ELSE
        v_ids := p_ids_boleto;
    END IF;
    IF v_ids IS NULL OR cardinality(v_ids) = 0 THEN
        RETURN QUERY SELECT FALSE, 'ESTADO_INVALIDO', 'No hay boletos emitidos que reembolsar.', NULL::integer; RETURN;
    END IF;
    IF array_position(v_ids, NULL) IS NOT NULL
       OR (SELECT count(DISTINCT x) FROM unnest(v_ids) AS x) <> cardinality(v_ids) THEN
        RETURN QUERY SELECT FALSE, 'DATOS_INVALIDOS', 'La lista de boletos tiene valores nulos o repetidos.', NULL::integer; RETURN;
    END IF;

    -- Bloquea los boletos en orden de ID (mismo orden que ingreso y reversión).
    PERFORM 1 FROM boleto b WHERE b.id_boleto = ANY (v_ids) ORDER BY b.id_boleto FOR UPDATE;
    SELECT count(*) INTO v_n
    FROM boleto b INNER JOIN compra_detalle cd ON cd.id_compra_detalle = b.id_compra_detalle
    WHERE b.id_boleto = ANY (v_ids) AND cd.id_compra = p_id_compra AND b.estado = 'emitido';
    IF v_n <> cardinality(v_ids) THEN
        RETURN QUERY SELECT FALSE, 'ESTADO_INVALIDO',
            'Algún boleto no pertenece a la compra o no está emitido (usado o anulado).', NULL::integer; RETURN;
    END IF;

    IF EXISTS (SELECT 1 FROM solicitud_reembolso s
               INNER JOIN solicitud_reembolso_detalle d ON d.id_solicitud_reembolso = s.id_solicitud_reembolso
               WHERE s.estado = 'pendiente' AND d.id_boleto = ANY (v_ids)) THEN
        RETURN QUERY SELECT FALSE, 'REFERENCIA_CONFLICTIVA',
            'Ya existe una solicitud pendiente para alguno de esos boletos.', NULL::integer; RETURN;
    END IF;

    v_horas := politica_entero('reembolso_horas_antes');
    v_fuera := CURRENT_TIMESTAMP > v_inicio - make_interval(hours => v_horas);
    IF v_fuera AND NOT autorizar_accion(p_id_usuario_actor, 'forzar_reembolso') THEN
        RETURN QUERY SELECT FALSE, 'FUERA_DE_POLITICA',
            'El reembolso ordinario solo procede hasta ' || v_horas || ' horas antes de la función.', NULL::integer; RETURN;
    END IF;

    INSERT INTO solicitud_reembolso (id_compra, id_usuario_actor, motivo)
    VALUES (p_id_compra, p_id_usuario_actor, btrim(p_motivo))
    RETURNING id_solicitud_reembolso INTO v_id;
    INSERT INTO solicitud_reembolso_detalle (id_solicitud_reembolso, id_boleto)
    SELECT v_id, x FROM unnest(v_ids) AS x;

    RETURN QUERY SELECT TRUE, 'OK', 'Solicitud registrada y pendiente de resolución.', v_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- 5. REVERSIÓN DE VENTA (contrato de B-04)  -  EJECUTA B, AUTORIZA C
-- C nunca modifica boletos/compras por su cuenta: invoca esta operación.
-- IMPORTANTE: es una IMPLEMENTACIÓN PROVISIONAL del contrato acordado
--   revertir_venta(p_id_solicitud_reembolso integer, p_referencia text)
--   -> (monto_reembolsado numeric, boletos_anulados integer)
-- Solo se crea si B todavía no publicó la suya; si ya existe, no se toca.
-- Pendiente de B: liberar inventario_funcion (vendido -> disponible) y registrar
-- reembolso/pago cuando existan esas tablas.
-- -----------------------------------------------------------------------------
DO $do$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc p INNER JOIN pg_namespace n ON n.oid = p.pronamespace
                   WHERE n.nspname = 'public' AND p.proname = 'revertir_venta') THEN
        EXECUTE $f$
        CREATE FUNCTION public.revertir_venta(p_id_solicitud_reembolso integer, p_referencia text)
        RETURNS TABLE (monto_reembolsado numeric, boletos_anulados integer)
        LANGUAGE plpgsql SECURITY DEFINER
        SET search_path = public, pg_temp
        AS $b$
        DECLARE
            v_compra integer; v_total integer; v_n integer; v_monto numeric(12,2); v_restantes integer;
        BEGIN
            SELECT s.id_compra INTO v_compra FROM solicitud_reembolso s
            WHERE s.id_solicitud_reembolso = p_id_solicitud_reembolso AND s.estado = 'pendiente'
            FOR UPDATE;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'La solicitud no existe o ya fue resuelta.' USING ERRCODE = '55000';
            END IF;
            PERFORM 1 FROM boleto b INNER JOIN solicitud_reembolso_detalle d ON d.id_boleto = b.id_boleto
            WHERE d.id_solicitud_reembolso = p_id_solicitud_reembolso ORDER BY b.id_boleto FOR UPDATE OF b;
            SELECT count(*), count(*) FILTER (WHERE b.estado = 'emitido'),
                   coalesce(sum(cd.total_linea), 0)
              INTO v_total, v_n, v_monto
            FROM solicitud_reembolso_detalle d
            INNER JOIN boleto b ON b.id_boleto = d.id_boleto
            INNER JOIN compra_detalle cd ON cd.id_compra_detalle = b.id_compra_detalle
            WHERE d.id_solicitud_reembolso = p_id_solicitud_reembolso;
            IF v_total = 0 OR v_n <> v_total THEN
                RAISE EXCEPTION 'Algún boleto de la solicitud ya no está emitido.' USING ERRCODE = '55000';
            END IF;
            UPDATE boleto SET estado = 'anulado'
            WHERE estado = 'emitido' AND id_boleto IN
                  (SELECT d.id_boleto FROM solicitud_reembolso_detalle d
                   WHERE d.id_solicitud_reembolso = p_id_solicitud_reembolso);
            SELECT count(*) INTO v_restantes
            FROM boleto b INNER JOIN compra_detalle cd ON cd.id_compra_detalle = b.id_compra_detalle
            WHERE cd.id_compra = v_compra AND b.estado <> 'anulado';
            UPDATE compra SET estado = CASE WHEN v_restantes = 0 THEN 'reembolsada'
                                            ELSE 'parcialmente_reembolsada' END
            WHERE id_compra = v_compra;
            RETURN QUERY SELECT v_monto, v_n;
        END;
        $b$
        $f$;
    END IF;
END
$do$;

-- -----------------------------------------------------------------------------
-- 6. RESOLUCIÓN DE REEMBOLSO (solo administrador)  -  RN-19 / RN-20
-- p_decision: 'ejecutar' | 'rechazar'.
-- Fuera de política solo se ejecuta con p_forzar = TRUE, permiso forzar_reembolso
-- y motivo escrito (override autorizado y auditado). Nunca revive boletos
-- usados o anulados. Todo ocurre en una sola transacción.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION resolver_reembolso(
    p_id_usuario_admin integer, p_id_solicitud integer, p_decision text,
    p_motivo text, p_ip text, p_forzar boolean DEFAULT FALSE)
RETURNS TABLE (exito boolean, codigo text, mensaje text, monto_devuelto numeric)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_decision text := lower(btrim(coalesce(p_decision, '')));
    v_compra   integer;
    v_estado   text;
    v_inicio   timestamptz;
    v_total    integer;
    v_n        integer;
    v_horas    integer;
    v_fuera    boolean;
    v_motivo   text;
    v_monto    numeric;
    v_anulados integer;
BEGIN
    IF v_decision NOT IN ('ejecutar', 'rechazar') THEN
        RETURN QUERY SELECT FALSE, 'DATOS_INVALIDOS', 'La decisión debe ser ejecutar o rechazar.', NULL::numeric; RETURN;
    END IF;
    IF normalizar_ip(p_ip) IS NULL THEN
        RETURN QUERY SELECT FALSE, 'DATOS_INVALIDOS', 'La dirección IP es inválida.', NULL::numeric; RETURN;
    END IF;
    IF NOT exigir_permiso(p_id_usuario_admin, 'resolver_reembolso', p_ip,
                          'solicitud_reembolso', p_id_solicitud::text) THEN
        RETURN QUERY SELECT FALSE, 'NO_AUTORIZADO', 'Su rol no puede resolver reembolsos.', NULL::numeric; RETURN;
    END IF;
    IF p_forzar AND NOT exigir_permiso(p_id_usuario_admin, 'forzar_reembolso', p_ip,
                                       'solicitud_reembolso', p_id_solicitud::text) THEN
        RETURN QUERY SELECT FALSE, 'NO_AUTORIZADO', 'Su rol no puede forzar reembolsos.', NULL::numeric; RETURN;
    END IF;

    SELECT s.id_compra, s.estado INTO v_compra, v_estado
    FROM solicitud_reembolso s WHERE s.id_solicitud_reembolso = p_id_solicitud FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'NO_ENCONTRADO', 'La solicitud no existe.', NULL::numeric; RETURN;
    END IF;
    IF v_estado <> 'pendiente' THEN
        RETURN QUERY SELECT FALSE, 'ESTADO_INVALIDO', 'La solicitud ya fue ' || v_estado || '.', NULL::numeric; RETURN;
    END IF;

    SELECT f.inicio INTO v_inicio
    FROM compra c INNER JOIN funcion f ON f.id_funcion = c.id_funcion
    WHERE c.id_compra = v_compra FOR UPDATE OF c;

    IF v_decision = 'rechazar' THEN
        IF btrim(coalesce(p_motivo, '')) = '' THEN
            RETURN QUERY SELECT FALSE, 'DATOS_INVALIDOS', 'El rechazo requiere un motivo.', NULL::numeric; RETURN;
        END IF;
        UPDATE solicitud_reembolso
           SET estado = 'rechazada', resuelta_en = CURRENT_TIMESTAMP, id_usuario_resuelve = p_id_usuario_admin
         WHERE id_solicitud_reembolso = p_id_solicitud;
        PERFORM auditar_accion(p_id_usuario_admin, p_ip, 'rechazar_reembolso', 'solicitud_reembolso',
                               p_id_solicitud::text, btrim(p_motivo),
                               jsonb_build_object('id_compra', v_compra));
        RETURN QUERY SELECT TRUE, 'OK', 'Solicitud rechazada.', 0::numeric; RETURN;
    END IF;

    -- Ejecutar
    SELECT count(*) INTO v_total FROM solicitud_reembolso_detalle d
    WHERE d.id_solicitud_reembolso = p_id_solicitud;
    IF v_total = 0 THEN
        RETURN QUERY SELECT FALSE, 'DATOS_INVALIDOS', 'La solicitud no tiene boletos asociados.', NULL::numeric; RETURN;
    END IF;

    PERFORM 1 FROM boleto b INNER JOIN solicitud_reembolso_detalle d ON d.id_boleto = b.id_boleto
    WHERE d.id_solicitud_reembolso = p_id_solicitud ORDER BY b.id_boleto FOR UPDATE OF b;
    SELECT count(*) INTO v_n FROM boleto b INNER JOIN solicitud_reembolso_detalle d ON d.id_boleto = b.id_boleto
    WHERE d.id_solicitud_reembolso = p_id_solicitud AND b.estado = 'emitido';
    IF v_n <> v_total THEN
        RETURN QUERY SELECT FALSE, 'ESTADO_INVALIDO',
            'Algún boleto ya fue usado o anulado; no puede reembolsarse.', NULL::numeric; RETURN;
    END IF;

    v_horas := politica_entero('reembolso_horas_antes');
    v_fuera := CURRENT_TIMESTAMP > v_inicio - make_interval(hours => v_horas);
    IF v_fuera AND NOT p_forzar THEN
        RETURN QUERY SELECT FALSE, 'FUERA_DE_POLITICA',
            'Fuera de política (' || v_horas || ' h antes). Solo procede con override autorizado (p_forzar) y motivo.',
            NULL::numeric; RETURN;
    END IF;
    IF v_fuera AND btrim(coalesce(p_motivo, '')) = '' THEN
        RETURN QUERY SELECT FALSE, 'DATOS_INVALIDOS', 'El reembolso forzado requiere un motivo documentado.', NULL::numeric; RETURN;
    END IF;
    v_motivo := coalesce(nullif(btrim(p_motivo), ''), 'Reembolso ordinario conforme a la política vigente');

    -- B ejecuta la reversión (anulación del boleto, estado de compra, liberación).
    SELECT rv.monto_reembolsado, rv.boletos_anulados INTO v_monto, v_anulados
    FROM public.revertir_venta(p_id_solicitud, 'RB-' || p_id_solicitud) AS rv;

    UPDATE solicitud_reembolso
       SET estado = 'ejecutada', resuelta_en = CURRENT_TIMESTAMP, id_usuario_resuelve = p_id_usuario_admin
     WHERE id_solicitud_reembolso = p_id_solicitud;

    PERFORM auditar_accion(
        p_id_usuario_admin, p_ip,
        CASE WHEN v_fuera THEN 'reembolso_forzado' ELSE 'reembolso_ordinario' END,
        'solicitud_reembolso', p_id_solicitud::text, v_motivo,
        jsonb_build_object('id_compra', v_compra, 'boletos_anulados', v_anulados,
                           'monto', v_monto, 'fuera_de_politica', v_fuera,
                           'horas_politica', v_horas));
    RETURN QUERY SELECT TRUE, 'OK', 'Reembolso ejecutado.', v_monto;
END;
$$;

-- -----------------------------------------------------------------------------
-- 7. CONFIGURACIÓN CRÍTICA AUDITADA: cambio de políticas
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION cambiar_politica(
    p_id_usuario integer, p_clave text, p_valor integer, p_motivo text, p_ip text)
RETURNS TABLE (exito boolean, codigo text, mensaje text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_anterior integer;
BEGIN
    IF normalizar_ip(p_ip) IS NULL OR btrim(coalesce(p_motivo, '')) = '' OR p_valor IS NULL OR p_valor < 0 THEN
        RETURN QUERY SELECT FALSE, 'DATOS_INVALIDOS', 'IP, motivo y valor (>= 0) son obligatorios.'; RETURN;
    END IF;
    IF NOT exigir_permiso(p_id_usuario, 'configurar_politicas', p_ip, 'politica_negocio', p_clave) THEN
        RETURN QUERY SELECT FALSE, 'NO_AUTORIZADO', 'Su rol no puede configurar políticas.'; RETURN;
    END IF;
    SELECT valor_entero INTO v_anterior FROM politica_negocio WHERE clave = p_clave FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'NO_ENCONTRADO', 'La política no existe.'; RETURN;
    END IF;
    UPDATE politica_negocio SET valor_entero = p_valor, actualizada_en = CURRENT_TIMESTAMP WHERE clave = p_clave;
    PERFORM auditar_accion(p_id_usuario, p_ip, 'configurar_politica', 'politica_negocio', p_clave, btrim(p_motivo),
                           jsonb_build_object('anterior', v_anterior, 'nuevo', p_valor));
    RETURN QUERY SELECT TRUE, 'OK', 'Política actualizada.';
END;
$$;

-- -----------------------------------------------------------------------------
-- 7-bis. CORTESÍAS Y CAMBIOS MANUALES DE ASIENTO (RN-20, tarea 4 del issue)
-- Solo administrador (permisos otorgar_cortesia / cambiar_asiento). Cada operación
-- se ejecuta y se audita en la MISMA transacción: si la auditoría falla, la
-- operación se revierte. Mientras B no publique inventario_funcion (B-01), la
-- disponibilidad del asiento se calcula con asiento_ocupado() sobre
-- compra/compra_detalle/boleto y la exclusión entre operaciones simultáneas se
-- garantiza con un bloqueo asesor por (función, asiento). Cuando exista el
-- inventario de B, estas funciones deben delegar en él (misma firma).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION asiento_ocupado(p_id_funcion integer, p_id_asiento integer,
                                           p_excluir_detalle integer DEFAULT NULL)
RETURNS boolean
LANGUAGE sql STABLE
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM compra_detalle cd
        INNER JOIN compra c ON c.id_compra = cd.id_compra
        WHERE c.id_funcion = p_id_funcion
          AND cd.id_asiento = p_id_asiento
          AND c.estado IN ('pendiente', 'pagada', 'parcialmente_reembolsada')
          AND cd.id_compra_detalle IS DISTINCT FROM p_excluir_detalle
          AND NOT EXISTS (SELECT 1 FROM boleto b
                          WHERE b.id_compra_detalle = cd.id_compra_detalle AND b.estado = 'anulado')
    );
$$;

CREATE OR REPLACE FUNCTION otorgar_cortesia(
    p_id_usuario_admin integer, p_id_funcion integer, p_id_asiento integer,
    p_id_cliente integer, p_id_categoria integer, p_motivo text, p_ip text)
RETURNS TABLE (exito boolean, codigo text, mensaje text, id_compra integer, id_boleto integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_inicio  timestamptz;
    v_activa  boolean;
    v_sala    integer;
    v_zona    integer;
    v_tarifa  integer;
    v_monto   numeric(12,2);
    v_compra  integer;
    v_detalle integer;
    v_boleto  integer;
BEGIN
    IF normalizar_ip(p_ip) IS NULL OR btrim(coalesce(p_motivo, '')) = '' THEN
        RETURN QUERY SELECT FALSE, 'DATOS_INVALIDOS', 'IP válida y motivo son obligatorios.', NULL::integer, NULL::integer; RETURN;
    END IF;
    IF NOT exigir_permiso(p_id_usuario_admin, 'otorgar_cortesia', p_ip, 'funcion', p_id_funcion::text) THEN
        RETURN QUERY SELECT FALSE, 'NO_AUTORIZADO', 'Su rol no puede otorgar cortesías.', NULL::integer, NULL::integer; RETURN;
    END IF;

    SELECT f.inicio, f.activa, f.id_sala INTO v_inicio, v_activa, v_sala
    FROM funcion f WHERE f.id_funcion = p_id_funcion;
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'NO_ENCONTRADO', 'La función no existe.', NULL::integer, NULL::integer; RETURN;
    END IF;
    IF NOT v_activa OR v_inicio <= CURRENT_TIMESTAMP THEN
        RETURN QUERY SELECT FALSE, 'ESTADO_INVALIDO', 'La función no está activa o ya inició.', NULL::integer, NULL::integer; RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM usuario u INNER JOIN rol r ON r.id_rol = u.id_rol
                   WHERE u.id_usuario = p_id_cliente AND r.nombre = 'cliente' AND u.activo) THEN
        RETURN QUERY SELECT FALSE, 'DATOS_INVALIDOS', 'El beneficiario debe ser un cliente activo.', NULL::integer, NULL::integer; RETURN;
    END IF;

    SELECT a.id_zona INTO v_zona
    FROM asiento a INNER JOIN zona z ON z.id_zona = a.id_zona
    WHERE a.id_asiento = p_id_asiento AND z.id_sala = v_sala;
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'DATOS_INVALIDOS', 'El asiento no pertenece a la sala de la función.', NULL::integer, NULL::integer; RETURN;
    END IF;

    SELECT t.id_tarifa, t.monto INTO v_tarifa, v_monto
    FROM tarifa t
    WHERE t.id_funcion = p_id_funcion AND t.id_zona = v_zona AND t.id_categoria_entrada = p_id_categoria
    ORDER BY t.vigente_desde DESC LIMIT 1;
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'NO_ENCONTRADO', 'No existe tarifa para esa función, zona y categoría.', NULL::integer, NULL::integer; RETURN;
    END IF;

    PERFORM pg_advisory_xact_lock(p_id_funcion, p_id_asiento);
    IF asiento_ocupado(p_id_funcion, p_id_asiento) THEN
        RETURN QUERY SELECT FALSE, 'REFERENCIA_CONFLICTIVA', 'El asiento ya está reservado o vendido.', NULL::integer, NULL::integer; RETURN;
    END IF;

    INSERT INTO compra (id_usuario_cliente, id_usuario_actor, id_funcion, estado, total)
    VALUES (p_id_cliente, p_id_usuario_admin, p_id_funcion, 'pagada', 0)
    RETURNING compra.id_compra INTO v_compra;
    INSERT INTO compra_detalle (id_compra, id_asiento, id_categoria_entrada, id_tarifa,
                                precio_base, descuento, cargo_servicio, total_linea)
    VALUES (v_compra, p_id_asiento, p_id_categoria, v_tarifa, v_monto, v_monto, 0, 0)
    RETURNING compra_detalle.id_compra_detalle INTO v_detalle;
    INSERT INTO boleto (id_compra_detalle) VALUES (v_detalle)
    RETURNING boleto.id_boleto INTO v_boleto;

    PERFORM auditar_accion(p_id_usuario_admin, p_ip, 'otorgar_cortesia', 'compra', v_compra::text, btrim(p_motivo),
                           jsonb_build_object('id_funcion', p_id_funcion, 'id_asiento', p_id_asiento,
                                              'id_cliente', p_id_cliente, 'id_boleto', v_boleto,
                                              'valor_cortesia', v_monto));
    RETURN QUERY SELECT TRUE, 'OK', 'Cortesía otorgada y boleto emitido.', v_compra, v_boleto;
END;
$$;

CREATE OR REPLACE FUNCTION cambiar_asiento_boleto(
    p_id_usuario_admin integer, p_id_boleto integer, p_id_asiento_nuevo integer,
    p_motivo text, p_ip text)
RETURNS TABLE (exito boolean, codigo text, mensaje text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_estado  text;
    v_detalle integer;
    v_antes   integer;
    v_funcion integer;
    v_inicio  timestamptz;
    v_sala    integer;
    v_zona_a  integer;
    v_zona_n  integer;
BEGIN
    IF normalizar_ip(p_ip) IS NULL OR btrim(coalesce(p_motivo, '')) = '' THEN
        RETURN QUERY SELECT FALSE, 'DATOS_INVALIDOS', 'IP válida y motivo son obligatorios.'; RETURN;
    END IF;
    IF NOT exigir_permiso(p_id_usuario_admin, 'cambiar_asiento', p_ip, 'boleto', p_id_boleto::text) THEN
        RETURN QUERY SELECT FALSE, 'NO_AUTORIZADO', 'Su rol no puede cambiar asientos.'; RETURN;
    END IF;

    -- Mismo orden de bloqueo que ingreso y reembolso: primero el boleto.
    SELECT b.estado, cd.id_compra_detalle, cd.id_asiento, c.id_funcion, f.inicio, f.id_sala, a.id_zona
      INTO v_estado, v_detalle, v_antes, v_funcion, v_inicio, v_sala, v_zona_a
    FROM boleto b
    INNER JOIN compra_detalle cd ON cd.id_compra_detalle = b.id_compra_detalle
    INNER JOIN compra c ON c.id_compra = cd.id_compra
    INNER JOIN funcion f ON f.id_funcion = c.id_funcion
    INNER JOIN asiento a ON a.id_asiento = cd.id_asiento
    WHERE b.id_boleto = p_id_boleto
    FOR UPDATE OF b;
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'NO_ENCONTRADO', 'El boleto no existe.'; RETURN;
    END IF;
    IF v_estado <> 'emitido' THEN
        RETURN QUERY SELECT FALSE, 'ESTADO_INVALIDO', 'Solo se cambia el asiento de boletos emitidos (no usados ni anulados).'; RETURN;
    END IF;
    IF v_inicio <= CURRENT_TIMESTAMP THEN
        RETURN QUERY SELECT FALSE, 'ESTADO_INVALIDO', 'La función ya inició.'; RETURN;
    END IF;
    IF p_id_asiento_nuevo = v_antes THEN
        RETURN QUERY SELECT FALSE, 'DATOS_INVALIDOS', 'El asiento nuevo es el mismo que el actual.'; RETURN;
    END IF;

    SELECT a.id_zona INTO v_zona_n
    FROM asiento a INNER JOIN zona z ON z.id_zona = a.id_zona
    WHERE a.id_asiento = p_id_asiento_nuevo AND z.id_sala = v_sala;
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'DATOS_INVALIDOS', 'El asiento nuevo no pertenece a la sala de la función.'; RETURN;
    END IF;
    IF v_zona_n <> v_zona_a THEN
        RETURN QUERY SELECT FALSE, 'ZONA_DISTINTA',
            'Cambiar de zona implica recalcular precio (responsabilidad de B); solo se permite dentro de la misma zona.'; RETURN;
    END IF;

    PERFORM pg_advisory_xact_lock(v_funcion, p_id_asiento_nuevo);
    IF asiento_ocupado(v_funcion, p_id_asiento_nuevo, v_detalle) THEN
        RETURN QUERY SELECT FALSE, 'REFERENCIA_CONFLICTIVA', 'El asiento nuevo ya está reservado o vendido.'; RETURN;
    END IF;

    BEGIN
        UPDATE compra_detalle SET id_asiento = p_id_asiento_nuevo WHERE id_compra_detalle = v_detalle;
    EXCEPTION WHEN unique_violation THEN
        RETURN QUERY SELECT FALSE, 'REFERENCIA_CONFLICTIVA', 'La compra ya tiene registrado ese asiento.'; RETURN;
    END;

    PERFORM auditar_accion(p_id_usuario_admin, p_ip, 'cambio_asiento', 'boleto', p_id_boleto::text, btrim(p_motivo),
                           jsonb_build_object('id_funcion', v_funcion,
                                              'antes',   jsonb_build_object('id_asiento', v_antes),
                                              'despues', jsonb_build_object('id_asiento', p_id_asiento_nuevo)));
    RETURN QUERY SELECT TRUE, 'OK', 'Asiento cambiado.';
END;
$$;

-- Consulta analítica "Auditoría de Operaciones Críticas": acciones manuales de los
-- administradores en un intervalo (por omisión, el último mes), agrupadas por
-- ID de administrador y tipo de acción. Excluye los intentos denegados.
CREATE OR REPLACE FUNCTION resumen_auditoria_admin(
    p_id_usuario integer, p_desde timestamptz DEFAULT NULL, p_hasta timestamptz DEFAULT NULL)
RETURNS TABLE (id_usuario_actor integer, nombre_actor text, accion text, total bigint, ultima_vez timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT autorizar_accion(p_id_usuario, 'ver_auditoria') THEN
        RAISE EXCEPTION 'El usuario no posee permiso para consultar la auditoría.' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT a.id_usuario_actor, u.nombre::text, a.accion::text, count(*), max(a.fecha)
    FROM admin_operacion_audit a
    INNER JOIN usuario u ON u.id_usuario = a.id_usuario_actor
    WHERE a.rol_al_actuar = 'administrador'
      AND a.accion NOT LIKE 'denegado:%'
      AND a.fecha >= coalesce(p_desde, CURRENT_TIMESTAMP - INTERVAL '1 month')
      AND a.fecha <  coalesce(p_hasta, CURRENT_TIMESTAMP + INTERVAL '1 second')
    GROUP BY a.id_usuario_actor, u.nombre, a.accion
    ORDER BY a.id_usuario_actor, total DESC, a.accion;
END;
$$;

-- -----------------------------------------------------------------------------
-- 8. HISTORIAL ADMINISTRATIVO CONSULTABLE (permiso ver_auditoria: contador y
--    administrador). Intervalo [desde, hasta).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION consultar_auditoria_admin(
    p_id_usuario integer, p_desde timestamptz DEFAULT NULL, p_hasta timestamptz DEFAULT NULL,
    p_id_actor integer DEFAULT NULL, p_accion text DEFAULT NULL)
RETURNS SETOF admin_operacion_audit
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT autorizar_accion(p_id_usuario, 'ver_auditoria') THEN
        RAISE EXCEPTION 'El usuario no posee permiso para consultar la auditoría.' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT a.* FROM admin_operacion_audit a
    WHERE (p_desde IS NULL OR a.fecha >= p_desde)
      AND (p_hasta IS NULL OR a.fecha <  p_hasta)
      AND (p_id_actor IS NULL OR a.id_usuario_actor = p_id_actor)
      AND (p_accion IS NULL OR a.accion = p_accion)
    ORDER BY a.fecha DESC, a.id_admin_operacion_audit DESC;
END;
$$;

-- -----------------------------------------------------------------------------
-- 9. RBAC EN LA BD SOBRE LAS OPERACIONES REALES DE A (RN-17)
-- La aplicación, al abrir la transacción, fija el actor autenticado:
--     SELECT set_config('app.id_usuario', '<id de la sesión>', true);
--     SELECT set_config('app.ip',         '<IP del cliente>',   true);
--     SELECT set_config('app.motivo',     '<motivo del cambio>', true);
-- Reglas:
--  * Con actor: se exige el permiso de la matriz; sin él, la operación falla (42501).
--  * Sin actor y conectado como imax_app (rol de la aplicación): se rechaza.
--  * Sin actor y con otra cuenta (migraciones/administración de BD): se permite.
-- Ocultar un botón NO es la protección: esta es la protección.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION guardia_rbac()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_txt   text := nullif(btrim(coalesce(current_setting('app.id_usuario', true), '')), '');
    v_actor integer;
BEGIN
    IF v_txt IS NULL THEN
        IF current_user = 'imax_app' THEN
            RAISE EXCEPTION 'Operación sin usuario autenticado (app.id_usuario).' USING ERRCODE = '42501';
        END IF;
        RETURN NULL;
    END IF;
    BEGIN
        v_actor := v_txt::integer;
    EXCEPTION WHEN others THEN
        RAISE EXCEPTION 'app.id_usuario inválido.' USING ERRCODE = '42501';
    END;
    IF NOT autorizar_accion(v_actor, TG_ARGV[0]) THEN
        RAISE EXCEPTION 'El usuario % no tiene el permiso % para modificar %.', v_actor, TG_ARGV[0], TG_TABLE_NAME
            USING ERRCODE = '42501';
    END IF;
    RETURN NULL;
END;
$$;

-- Auditoría automática de cambios críticos (programación, distribución, precios).
CREATE OR REPLACE FUNCTION auditar_cambio_critico()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_txt     text := nullif(btrim(coalesce(current_setting('app.id_usuario', true), '')), '');
    v_cambios jsonb;
    v_id      text;
BEGIN
    IF v_txt IS NULL THEN
        RETURN NULL;   -- sin actor: ya lo rechazó guardia_rbac si venía de la aplicación
    END IF;
    IF TG_OP = 'INSERT' THEN
        v_cambios := jsonb_build_object('despues', to_jsonb(NEW) - 'password_hash');
        v_id := to_jsonb(NEW) ->> TG_ARGV[0];
    ELSIF TG_OP = 'UPDATE' THEN
        v_cambios := jsonb_build_object('antes', to_jsonb(OLD) - 'password_hash',
                                        'despues', to_jsonb(NEW) - 'password_hash');
        v_id := to_jsonb(NEW) ->> TG_ARGV[0];
    ELSE
        v_cambios := jsonb_build_object('antes', to_jsonb(OLD) - 'password_hash');
        v_id := to_jsonb(OLD) ->> TG_ARGV[0];
    END IF;
    -- Si falta el motivo, auditar_accion falla y el cambio completo se revierte.
    PERFORM auditar_accion(v_txt::integer, current_setting('app.ip', true),
                           left(lower(TG_OP) || '_' || TG_TABLE_NAME, 60), TG_TABLE_NAME, v_id,
                           current_setting('app.motivo', true), v_cambios);
    RETURN NULL;
END;
$$;

-- Evita escalada de privilegios en el alta de usuarios: la aplicación solo puede
-- registrar clientes; crear personal exige administrar_usuarios y queda auditado.
CREATE OR REPLACE FUNCTION guardia_alta_usuario()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_txt  text := nullif(btrim(coalesce(current_setting('app.id_usuario', true), '')), '');
    v_cliente integer;
BEGIN
    SELECT id_rol INTO v_cliente FROM rol WHERE nombre = 'cliente';
    IF NEW.id_rol = v_cliente THEN
        RETURN NEW;
    END IF;
    IF v_txt IS NULL THEN
        IF current_user = 'imax_app' THEN
            RAISE EXCEPTION 'Solo un administrador autenticado puede crear usuarios con rol distinto de cliente.'
                USING ERRCODE = '42501';
        END IF;
        RETURN NEW;
    END IF;
    IF NOT autorizar_accion(v_txt::integer, 'administrar_usuarios') THEN
        RAISE EXCEPTION 'El usuario % no puede administrar usuarios.', v_txt USING ERRCODE = '42501';
    END IF;
    PERFORM auditar_accion(v_txt::integer, current_setting('app.ip', true), 'insert_usuario', 'usuario',
                           NEW.id_usuario::text, current_setting('app.motivo', true),
                           jsonb_build_object('despues', to_jsonb(NEW) - 'password_hash'));
    RETURN NEW;
END;
$$;

DO $$
DECLARE
    r record;
BEGIN
    -- Guardia de permisos (statement-level: cubre INSERT, UPDATE, DELETE y TRUNCATE).
    FOR r IN SELECT * FROM (VALUES
        ('pelicula','gestionar_catalogo'), ('genero','gestionar_catalogo'),
        ('pelicula_genero','gestionar_catalogo'), ('cine','gestionar_catalogo'),
        ('sala','gestionar_catalogo'), ('zona','gestionar_catalogo'),
        ('asiento','gestionar_catalogo'), ('funcion','gestionar_catalogo'),
        ('tarifa','configurar_tarifas'), ('promocion','configurar_tarifas'),
        ('promocion_dia','configurar_tarifas'), ('promocion_zona','configurar_tarifas'),
        ('promocion_categoria','configurar_tarifas'), ('funcion_promocion','configurar_tarifas'),
        ('categoria_entrada','configurar_tarifas')
    ) AS t(tabla, permiso) LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_guardia_rbac ON public.%I', r.tabla);
        EXECUTE format('CREATE TRIGGER trg_guardia_rbac BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE '
                       'ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION public.guardia_rbac(%L)',
                       r.tabla, r.permiso);
    END LOOP;

    -- Auditoría de cambios críticos (fila a fila).
    FOR r IN SELECT * FROM (VALUES
        ('sala','id_sala'), ('zona','id_zona'), ('asiento','id_asiento'), ('funcion','id_funcion'),
        ('tarifa','id_tarifa'), ('promocion','id_promocion'),
        ('categoria_entrada','id_categoria_entrada')
    ) AS t(tabla, pk) LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_auditar_cambio ON public.%I', r.tabla);
        EXECUTE format('CREATE TRIGGER trg_auditar_cambio AFTER INSERT OR UPDATE OR DELETE '
                       'ON public.%I FOR EACH ROW EXECUTE FUNCTION public.auditar_cambio_critico(%L)',
                       r.tabla, r.pk);
    END LOOP;
END;
$$;

-- Usuarios: cambios de rol/estado y bajas.
DROP TRIGGER IF EXISTS trg_guardia_rbac ON usuario;
CREATE TRIGGER trg_guardia_rbac BEFORE UPDATE OF id_rol, activo OR DELETE OR TRUNCATE ON usuario
FOR EACH STATEMENT EXECUTE FUNCTION guardia_rbac('administrar_usuarios');
DROP TRIGGER IF EXISTS trg_auditar_cambio ON usuario;
CREATE TRIGGER trg_auditar_cambio AFTER UPDATE OF id_rol, activo OR DELETE ON usuario
FOR EACH ROW EXECUTE FUNCTION auditar_cambio_critico('id_usuario');
DROP TRIGGER IF EXISTS trg_guardia_alta_usuario ON usuario;
CREATE TRIGGER trg_guardia_alta_usuario BEFORE INSERT ON usuario
FOR EACH ROW EXECUTE FUNCTION guardia_alta_usuario();

-- -----------------------------------------------------------------------------
-- 10. PRIVILEGIOS: las funciones SECURITY DEFINER no quedan abiertas a PUBLIC
--     y la reversión de venta solo la invoca la gestión de C (no la aplicación).
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION auditar_accion(integer, text, text, text, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION exigir_permiso(integer, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION solicitar_reembolso(integer, integer, integer[], text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION resolver_reembolso(integer, integer, text, text, text, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION cambiar_politica(integer, text, integer, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION consultar_auditoria_admin(integer, timestamptz, timestamptz, integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION revertir_venta(integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION otorgar_cortesia(integer, integer, integer, integer, integer, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION cambiar_asiento_boleto(integer, integer, integer, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION resumen_auditoria_admin(integer, timestamptz, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION asiento_ocupado(integer, integer, integer) FROM PUBLIC;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'imax_app') THEN
        REVOKE ALL ON FUNCTION revertir_venta(integer, text) FROM imax_app;
        GRANT EXECUTE ON FUNCTION auditar_accion(integer, text, text, text, text, text, jsonb) TO imax_app;
        GRANT EXECUTE ON FUNCTION exigir_permiso(integer, text, text, text, text) TO imax_app;
        GRANT EXECUTE ON FUNCTION solicitar_reembolso(integer, integer, integer[], text, text) TO imax_app;
        GRANT EXECUTE ON FUNCTION resolver_reembolso(integer, integer, text, text, text, boolean) TO imax_app;
        GRANT EXECUTE ON FUNCTION cambiar_politica(integer, text, integer, text, text) TO imax_app;
        GRANT EXECUTE ON FUNCTION consultar_auditoria_admin(integer, timestamptz, timestamptz, integer, text) TO imax_app;
        GRANT EXECUTE ON FUNCTION normalizar_ip(text) TO imax_app;
        GRANT EXECUTE ON FUNCTION politica_entero(text) TO imax_app;
        GRANT SELECT ON politica_negocio TO imax_app;
        GRANT EXECUTE ON FUNCTION otorgar_cortesia(integer, integer, integer, integer, integer, text, text) TO imax_app;
        GRANT EXECUTE ON FUNCTION cambiar_asiento_boleto(integer, integer, integer, text, text) TO imax_app;
        GRANT EXECUTE ON FUNCTION resumen_auditoria_admin(integer, timestamptz, timestamptz) TO imax_app;
        GRANT EXECUTE ON FUNCTION asiento_ocupado(integer, integer, integer) TO imax_app;
    END IF;
END;
$$;

COMMENT ON TABLE politica_negocio IS 'Políticas numéricas centralizadas; se modifican solo con cambiar_politica (auditado).';
COMMENT ON FUNCTION solicitar_reembolso(integer, integer, integer[], text, text) IS 'C-03: solicita reembolso validando rol, propiedad, estado de boletos y política.';
COMMENT ON FUNCTION otorgar_cortesia(integer, integer, integer, integer, integer, text, text) IS 'C-03: cortesía (total 0) otorgada por administrador; emite boleto y audita con motivo.';
COMMENT ON FUNCTION cambiar_asiento_boleto(integer, integer, integer, text, text) IS 'C-03: cambio manual de asiento dentro de la misma zona; audita antes/después.';
COMMENT ON FUNCTION resumen_auditoria_admin(integer, timestamptz, timestamptz) IS 'C-03: consulta analítica de operaciones críticas por administrador (último mes por omisión).';
COMMENT ON FUNCTION resolver_reembolso(integer, integer, text, text, text, boolean) IS 'C-03: ejecuta o rechaza una solicitud; invoca revertir_venta (B-04); audita.';

-- -----------------------------------------------------------------------------
-- 11. AVISO DE DATOS HEREDADOS (solo informativo; no modifica nada)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_sin_detalle integer;
    v_ajenas      integer;
BEGIN
    SELECT count(*) INTO v_sin_detalle FROM solicitud_reembolso s
    WHERE s.estado = 'pendiente'
      AND NOT EXISTS (SELECT 1 FROM solicitud_reembolso_detalle d
                      WHERE d.id_solicitud_reembolso = s.id_solicitud_reembolso);
    SELECT count(*) INTO v_ajenas FROM solicitud_reembolso s
    INNER JOIN compra c ON c.id_compra = s.id_compra
    INNER JOIN usuario u ON u.id_usuario = s.id_usuario_actor
    INNER JOIN rol r ON r.id_rol = u.id_rol
    WHERE r.nombre = 'cliente' AND c.id_usuario_cliente <> s.id_usuario_actor;
    IF v_sin_detalle > 0 OR v_ajenas > 0 THEN
        RAISE NOTICE 'Datos de prueba heredados: % solicitud(es) pendiente(s) sin boletos y % de cliente sobre compra ajena. resolver_reembolso las rechazará/ignorará; conviene rechazarlas o depurarlas.',
            v_sin_detalle, v_ajenas;
    END IF;
END;
$$;

COMMIT;