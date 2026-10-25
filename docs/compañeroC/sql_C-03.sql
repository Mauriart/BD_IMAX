-- C-03 integrado con las tablas reales de B.
BEGIN;
INSERT INTO rol_permiso(id_rol,accion)
SELECT r.id_rol,p.accion FROM rol r CROSS JOIN
(VALUES('forzar_reembolso'),('configurar_politicas'),('otorgar_cortesia'),('cambiar_asiento')) p(accion)
WHERE r.nombre='administrador' ON CONFLICT DO NOTHING;


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

CREATE OR REPLACE FUNCTION exigir_permiso(
    p_id_usuario integer, p_accion text, p_ip text, p_entidad text, p_id_entidad text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF nullif(current_setting('app.id_usuario',true),'')::integer IS DISTINCT FROM p_id_usuario THEN RETURN FALSE; END IF;
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

CREATE OR REPLACE FUNCTION solicitar_reembolso(
    p_id_usuario_actor integer, p_id_compra bigint, p_ids_boleto bigint[],
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
    v_ids        bigint[];
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

    IF v_estado NOT IN ('Pagada', 'ParcialmenteReembolsada') THEN
        RETURN QUERY SELECT FALSE, 'ESTADO_INVALIDO',
            'La compra está en estado ' || v_estado || ' y no admite reembolso.', NULL::integer; RETURN;
    END IF;

    IF (SELECT total FROM compra WHERE id_compra=p_id_compra)=0 THEN
        RETURN QUERY SELECT FALSE,'DATOS_INVALIDOS','Una cortesia no tiene importe que devolver.',NULL::integer; RETURN;
    END IF;
    IF p_ids_boleto IS NULL OR cardinality(p_ids_boleto) = 0 THEN
        SELECT array_agg(b.id_boleto ORDER BY b.id_boleto) INTO v_ids
        FROM boleto b INNER JOIN compra_detalle cd ON cd.id_compra = b.id_compra AND cd.id_asiento = b.id_asiento
        WHERE cd.id_compra = p_id_compra AND b.estado = 'Emitido';
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
    FROM boleto b INNER JOIN compra_detalle cd ON cd.id_compra = b.id_compra AND cd.id_asiento = b.id_asiento
    WHERE b.id_boleto = ANY (v_ids) AND cd.id_compra = p_id_compra AND b.estado = 'Emitido';
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

CREATE OR REPLACE FUNCTION resolver_reembolso(
    p_id_usuario_admin integer, p_id_solicitud integer, p_decision text,
    p_motivo text, p_ip text, p_forzar boolean DEFAULT FALSE)
RETURNS TABLE (exito boolean, codigo text, mensaje text, monto_devuelto numeric)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_decision text := lower(btrim(coalesce(p_decision, '')));
    v_compra   bigint;
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
    WHERE d.id_solicitud_reembolso = p_id_solicitud AND b.estado = 'Emitido';
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
      AND a.fecha >= coalesce(p_desde, CURRENT_TIMESTAMP - INTERVAL '720 hours')
      AND a.fecha <  coalesce(p_hasta, CURRENT_TIMESTAMP + INTERVAL '1 second')
    GROUP BY a.id_usuario_actor, u.nombre, a.accion
    ORDER BY a.id_usuario_actor, total DESC, a.accion;
END;
$$;

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



-- Las operaciones manuales de C usan el mismo inventario y pagos de B.
CREATE OR REPLACE FUNCTION otorgar_cortesia(p_id_usuario_admin integer,p_id_funcion integer,p_id_asiento integer,
    p_id_cliente integer,p_id_categoria integer,p_motivo text,p_ip text)
RETURNS TABLE(exito boolean,codigo text,mensaje text,id_compra bigint,id_boleto bigint)
LANGUAGE plpgsql AS $$
DECLARE compra_nueva bigint; boleto_nuevo bigint;
BEGIN
    IF normalizar_ip(p_ip) IS NULL OR btrim(coalesce(p_motivo,''))='' THEN
        RETURN QUERY SELECT FALSE,'DATOS_INVALIDOS','IP y motivo son obligatorios.',NULL::bigint,NULL::bigint; RETURN;
    END IF;
    IF NOT exigir_permiso(p_id_usuario_admin,'otorgar_cortesia',p_ip,'funcion',p_id_funcion::text) THEN
        RETURN QUERY SELECT FALSE,'NO_AUTORIZADO','Su rol no puede otorgar cortesias.',NULL::bigint,NULL::bigint; RETURN;
    END IF;
    BEGIN
        compra_nueva:=reservar_asientos(p_id_cliente::bigint,p_id_usuario_admin::bigint,p_id_funcion::bigint,ARRAY[p_id_asiento],p_id_categoria);
        UPDATE compra_detalle SET descuento=precio_base,total_linea=0 WHERE compra_detalle.id_compra=compra_nueva;
        PERFORM calcular_total(compra_nueva);
        PERFORM procesar_pago(compra_nueva,'Exito'::varchar,'Cortesia'::varchar,('CORT-'||compra_nueva)::varchar);
        SELECT b.id_boleto INTO boleto_nuevo FROM boleto b WHERE b.id_compra=compra_nueva;
        PERFORM auditar_accion(p_id_usuario_admin,p_ip,'otorgar_cortesia','compra',compra_nueva::text,p_motivo,
            jsonb_build_object('id_funcion',p_id_funcion,'id_asiento',p_id_asiento,'id_boleto',boleto_nuevo));
    EXCEPTION WHEN raise_exception THEN
        RETURN QUERY SELECT FALSE,'REFERENCIA_CONFLICTIVA',SQLERRM,NULL::bigint,NULL::bigint; RETURN;
    END;
    RETURN QUERY SELECT TRUE,'OK','Cortesia emitida.',compra_nueva,boleto_nuevo;
END $$;

CREATE OR REPLACE FUNCTION cambiar_asiento_boleto(p_id_usuario_admin integer,p_id_boleto bigint,p_id_asiento_nuevo integer,
    p_motivo text,p_ip text)
RETURNS TABLE(exito boolean,codigo text,mensaje text)
LANGUAGE plpgsql AS $$
DECLARE b boleto%ROWTYPE; zona_antes integer; zona_nueva integer; reserva_actual bigint;
BEGIN
    IF normalizar_ip(p_ip) IS NULL OR btrim(coalesce(p_motivo,''))='' THEN
        RETURN QUERY SELECT FALSE,'DATOS_INVALIDOS','IP y motivo son obligatorios.'; RETURN;
    END IF;
    IF NOT exigir_permiso(p_id_usuario_admin,'cambiar_asiento',p_ip,'boleto',p_id_boleto::text) THEN
        RETURN QUERY SELECT FALSE,'NO_AUTORIZADO','Su rol no puede cambiar asientos.'; RETURN;
    END IF;
    SELECT * INTO b FROM boleto WHERE boleto.id_boleto=p_id_boleto;
    IF NOT FOUND THEN RETURN QUERY SELECT FALSE,'NO_ENCONTRADO','El boleto no existe.'; RETURN; END IF;
    PERFORM coordinar_venta(b.id_funcion);
    PERFORM c.id_compra FROM compra c WHERE c.id_compra=b.id_compra FOR UPDATE;
    SELECT * INTO b FROM boleto WHERE boleto.id_boleto=p_id_boleto FOR UPDATE;
    IF b.estado<>'Emitido' OR NOT EXISTS(SELECT 1 FROM funcion WHERE id_funcion=b.id_funcion AND activa AND inicio>clock_timestamp()) THEN
        RETURN QUERY SELECT FALSE,'ESTADO_INVALIDO','Solo se cambia una entrada emitida de una funcion futura.'; RETURN;
    END IF;
    SELECT id_zona INTO zona_antes FROM asiento WHERE id_asiento=b.id_asiento;
    SELECT id_zona INTO zona_nueva FROM asiento WHERE id_asiento=p_id_asiento_nuevo;
    IF zona_antes IS DISTINCT FROM zona_nueva OR b.id_asiento=p_id_asiento_nuevo THEN
        RETURN QUERY SELECT FALSE,'ZONA_DISTINTA','Seleccione otro asiento de la misma zona.'; RETURN;
    END IF;
    PERFORM preparar_inventario(b.id_funcion);
    PERFORM i.id_asiento FROM inventario_funcion i WHERE i.id_funcion=b.id_funcion
      AND i.id_asiento IN (b.id_asiento,p_id_asiento_nuevo) ORDER BY i.id_asiento FOR UPDATE;
    IF NOT EXISTS(SELECT 1 FROM inventario_funcion WHERE id_funcion=b.id_funcion AND id_asiento=p_id_asiento_nuevo AND estado='disponible') THEN
        RETURN QUERY SELECT FALSE,'REFERENCIA_CONFLICTIVA','El asiento nuevo no esta disponible.'; RETURN;
    END IF;
    IF EXISTS(SELECT 1 FROM solicitud_reembolso_detalle d JOIN solicitud_reembolso s USING(id_solicitud_reembolso)
              WHERE d.id_boleto=p_id_boleto AND s.estado='pendiente') THEN
        RETURN QUERY SELECT FALSE,'REFERENCIA_CONFLICTIVA','Resuelva primero la solicitud pendiente.'; RETURN;
    END IF;
    BEGIN
        SELECT id_reserva INTO reserva_actual FROM inventario_funcion WHERE id_funcion=b.id_funcion AND id_asiento=b.id_asiento;
        UPDATE compra_detalle SET id_asiento=p_id_asiento_nuevo WHERE id_compra=b.id_compra AND id_asiento=b.id_asiento;
        UPDATE reserva SET id_asiento=p_id_asiento_nuevo WHERE id_reserva=reserva_actual;
        UPDATE boleto SET id_asiento=p_id_asiento_nuevo WHERE boleto.id_boleto=p_id_boleto;
        UPDATE inventario_funcion SET estado='disponible',id_reserva=NULL,id_boleto=NULL
        WHERE id_funcion=b.id_funcion AND id_asiento=b.id_asiento;
        UPDATE inventario_funcion SET estado='vendido',id_reserva=reserva_actual,id_boleto=b.id_boleto
        WHERE id_funcion=b.id_funcion AND id_asiento=p_id_asiento_nuevo;
        PERFORM auditar_accion(p_id_usuario_admin,p_ip,'cambio_asiento','boleto',p_id_boleto::text,p_motivo,
            jsonb_build_object('antes',b.id_asiento,'despues',p_id_asiento_nuevo));
    EXCEPTION WHEN unique_violation THEN
        RETURN QUERY SELECT FALSE,'REFERENCIA_CONFLICTIVA','La compra ya contiene ese asiento.'; RETURN;
    END;
    RETURN QUERY SELECT TRUE,'OK','Asiento cambiado.';
END $$;
COMMIT;
