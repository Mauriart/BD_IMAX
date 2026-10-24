--
-- PostgreSQL database dump
--

\restrict fPjqaYoVIgqp5jt63EZ2cd88xOG0FrrjWc1bXwbJ2TSsx03UfgLrR1JdHZIjg0y

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

-- Started on 2026-10-24 00:24:32

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 298 (class 1255 OID 18300)
-- Name: asiento_ocupado(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.asiento_ocupado(p_id_funcion integer, p_id_asiento integer, p_excluir_detalle integer DEFAULT NULL::integer) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
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


ALTER FUNCTION public.asiento_ocupado(p_id_funcion integer, p_id_asiento integer, p_excluir_detalle integer) OWNER TO postgres;

--
-- TOC entry 290 (class 1255 OID 18292)
-- Name: auditar_accion(integer, text, text, text, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.auditar_accion(p_id_usuario_actor integer, p_ip text, p_accion text, p_entidad text, p_id_entidad text, p_motivo text, p_cambios jsonb DEFAULT NULL::jsonb) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


ALTER FUNCTION public.auditar_accion(p_id_usuario_actor integer, p_ip text, p_accion text, p_entidad text, p_id_entidad text, p_motivo text, p_cambios jsonb) OWNER TO postgres;

--
-- TOC entry 287 (class 1255 OID 18307)
-- Name: auditar_cambio_critico(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.auditar_cambio_critico() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
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


ALTER FUNCTION public.auditar_cambio_critico() OWNER TO postgres;

--
-- TOC entry 277 (class 1255 OID 18148)
-- Name: autorizar_accion(integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.autorizar_accion(p_id_usuario integer, p_accion text) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT EXISTS (
        SELECT 1
        FROM usuario u
        INNER JOIN rol_permiso rp ON rp.id_rol = u.id_rol
        WHERE u.id_usuario = p_id_usuario AND u.activo = TRUE
          AND rp.accion = p_accion
    );
$$;


ALTER FUNCTION public.autorizar_accion(p_id_usuario integer, p_accion text) OWNER TO postgres;

--
-- TOC entry 267 (class 1255 OID 18145)
-- Name: bloquear_modificacion_log(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.bloquear_modificacion_log() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'Los registros de % no se pueden modificar ni eliminar.', TG_TABLE_NAME
        USING ERRCODE = '42501';
END;
$$;


ALTER FUNCTION public.bloquear_modificacion_log() OWNER TO postgres;

--
-- TOC entry 268 (class 1255 OID 18150)
-- Name: bloquear_truncate_log(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.bloquear_truncate_log() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'Los registros de % no se pueden vaciar.', TG_TABLE_NAME
        USING ERRCODE = '42501';
END;
$$;


ALTER FUNCTION public.bloquear_truncate_log() OWNER TO postgres;

--
-- TOC entry 296 (class 1255 OID 18303)
-- Name: cambiar_asiento_boleto(integer, integer, integer, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.cambiar_asiento_boleto(p_id_usuario_admin integer, p_id_boleto integer, p_id_asiento_nuevo integer, p_motivo text, p_ip text) RETURNS TABLE(exito boolean, codigo text, mensaje text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


ALTER FUNCTION public.cambiar_asiento_boleto(p_id_usuario_admin integer, p_id_boleto integer, p_id_asiento_nuevo integer, p_motivo text, p_ip text) OWNER TO postgres;

--
-- TOC entry 5401 (class 0 OID 0)
-- Dependencies: 296
-- Name: FUNCTION cambiar_asiento_boleto(p_id_usuario_admin integer, p_id_boleto integer, p_id_asiento_nuevo integer, p_motivo text, p_ip text); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.cambiar_asiento_boleto(p_id_usuario_admin integer, p_id_boleto integer, p_id_asiento_nuevo integer, p_motivo text, p_ip text) IS 'C-03: cambio manual de asiento dentro de la misma zona; audita antes/después.';


--
-- TOC entry 294 (class 1255 OID 18299)
-- Name: cambiar_politica(integer, text, integer, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.cambiar_politica(p_id_usuario integer, p_clave text, p_valor integer, p_motivo text, p_ip text) RETURNS TABLE(exito boolean, codigo text, mensaje text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


ALTER FUNCTION public.cambiar_politica(p_id_usuario integer, p_clave text, p_valor integer, p_motivo text, p_ip text) OWNER TO postgres;

--
-- TOC entry 269 (class 1255 OID 18290)
-- Name: normalizar_ip(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.normalizar_ip(p_ip text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    RETURN host(btrim(p_ip)::inet);
EXCEPTION WHEN others THEN
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.normalizar_ip(p_ip text) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 255 (class 1259 OID 18122)
-- Name: admin_operacion_audit; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.admin_operacion_audit (
    id_admin_operacion_audit integer NOT NULL,
    fecha timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    id_usuario_actor integer NOT NULL,
    rol_al_actuar character varying(30) NOT NULL,
    ip character varying(45) NOT NULL,
    accion character varying(60) NOT NULL,
    entidad character varying(60) NOT NULL,
    id_entidad character varying(60),
    motivo text NOT NULL,
    cambios jsonb,
    CONSTRAINT ck_audit_ip CHECK ((public.normalizar_ip((ip)::text) IS NOT NULL)),
    CONSTRAINT ck_audit_motivo CHECK ((btrim(motivo) <> ''::text))
);


ALTER TABLE public.admin_operacion_audit OWNER TO postgres;

--
-- TOC entry 5405 (class 0 OID 0)
-- Dependencies: 255
-- Name: TABLE admin_operacion_audit; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.admin_operacion_audit IS 'C-05 / RN-20 categoría 4 (administración). Solo INSERT, escrita por auditar_accion/triggers. Inmutable por trigger y privilegios. Retención mínima 60 meses desde el evento.';


--
-- TOC entry 295 (class 1255 OID 18305)
-- Name: consultar_auditoria_admin(integer, timestamp with time zone, timestamp with time zone, integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.consultar_auditoria_admin(p_id_usuario integer, p_desde timestamp with time zone DEFAULT NULL::timestamp with time zone, p_hasta timestamp with time zone DEFAULT NULL::timestamp with time zone, p_id_actor integer DEFAULT NULL::integer, p_accion text DEFAULT NULL::text) RETURNS SETOF public.admin_operacion_audit
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


ALTER FUNCTION public.consultar_auditoria_admin(p_id_usuario integer, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_id_actor integer, p_accion text) OWNER TO postgres;

--
-- TOC entry 291 (class 1255 OID 18293)
-- Name: exigir_permiso(integer, text, text, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.exigir_permiso(p_id_usuario integer, p_accion text, p_ip text, p_entidad text, p_id_entidad text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


ALTER FUNCTION public.exigir_permiso(p_id_usuario integer, p_accion text, p_ip text, p_entidad text, p_id_entidad text) OWNER TO postgres;

--
-- TOC entry 288 (class 1255 OID 18308)
-- Name: guardia_alta_usuario(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.guardia_alta_usuario() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
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


ALTER FUNCTION public.guardia_alta_usuario() OWNER TO postgres;

--
-- TOC entry 286 (class 1255 OID 18306)
-- Name: guardia_rbac(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.guardia_rbac() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
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


ALTER FUNCTION public.guardia_rbac() OWNER TO postgres;

--
-- TOC entry 271 (class 1255 OID 18301)
-- Name: otorgar_cortesia(integer, integer, integer, integer, integer, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.otorgar_cortesia(p_id_usuario_admin integer, p_id_funcion integer, p_id_asiento integer, p_id_cliente integer, p_id_categoria integer, p_motivo text, p_ip text) RETURNS TABLE(exito boolean, codigo text, mensaje text, id_compra integer, id_boleto integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


ALTER FUNCTION public.otorgar_cortesia(p_id_usuario_admin integer, p_id_funcion integer, p_id_asiento integer, p_id_cliente integer, p_id_categoria integer, p_motivo text, p_ip text) OWNER TO postgres;

--
-- TOC entry 5409 (class 0 OID 0)
-- Dependencies: 271
-- Name: FUNCTION otorgar_cortesia(p_id_usuario_admin integer, p_id_funcion integer, p_id_asiento integer, p_id_cliente integer, p_id_categoria integer, p_motivo text, p_ip text); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.otorgar_cortesia(p_id_usuario_admin integer, p_id_funcion integer, p_id_asiento integer, p_id_cliente integer, p_id_categoria integer, p_motivo text, p_ip text) IS 'C-03: cortesía (total 0) otorgada por administrador; emite boleto y audita con motivo.';


--
-- TOC entry 270 (class 1255 OID 18291)
-- Name: politica_entero(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.politica_entero(p_clave text) RETURNS integer
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'pg_temp'
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


ALTER FUNCTION public.politica_entero(p_clave text) OWNER TO postgres;

--
-- TOC entry 264 (class 1255 OID 18003)
-- Name: proteger_sala_con_tarifas(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.proteger_sala_con_tarifas() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.id_sala IS DISTINCT FROM OLD.id_sala THEN
        IF TG_TABLE_NAME = 'funcion' THEN
            IF EXISTS (SELECT 1 FROM tarifa WHERE id_funcion = OLD.id_funcion) THEN
                RAISE EXCEPTION 'No se puede cambiar la sala de una función con tarifas.'
                    USING ERRCODE = '23514';
            END IF;
        ELSE
            IF EXISTS (SELECT 1 FROM tarifa WHERE id_zona = OLD.id_zona) THEN
                RAISE EXCEPTION 'No se puede cambiar la sala de una zona con tarifas.'
                    USING ERRCODE = '23514';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.proteger_sala_con_tarifas() OWNER TO postgres;

--
-- TOC entry 293 (class 1255 OID 18297)
-- Name: resolver_reembolso(integer, integer, text, text, text, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.resolver_reembolso(p_id_usuario_admin integer, p_id_solicitud integer, p_decision text, p_motivo text, p_ip text, p_forzar boolean DEFAULT false) RETURNS TABLE(exito boolean, codigo text, mensaje text, monto_devuelto numeric)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


ALTER FUNCTION public.resolver_reembolso(p_id_usuario_admin integer, p_id_solicitud integer, p_decision text, p_motivo text, p_ip text, p_forzar boolean) OWNER TO postgres;

--
-- TOC entry 5412 (class 0 OID 0)
-- Dependencies: 293
-- Name: FUNCTION resolver_reembolso(p_id_usuario_admin integer, p_id_solicitud integer, p_decision text, p_motivo text, p_ip text, p_forzar boolean); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.resolver_reembolso(p_id_usuario_admin integer, p_id_solicitud integer, p_decision text, p_motivo text, p_ip text, p_forzar boolean) IS 'C-03: ejecuta o rechaza una solicitud; invoca revertir_venta (B-04); audita.';


--
-- TOC entry 297 (class 1255 OID 18304)
-- Name: resumen_auditoria_admin(integer, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.resumen_auditoria_admin(p_id_usuario integer, p_desde timestamp with time zone DEFAULT NULL::timestamp with time zone, p_hasta timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS TABLE(id_usuario_actor integer, nombre_actor text, accion text, total bigint, ultima_vez timestamp with time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


ALTER FUNCTION public.resumen_auditoria_admin(p_id_usuario integer, p_desde timestamp with time zone, p_hasta timestamp with time zone) OWNER TO postgres;

--
-- TOC entry 5414 (class 0 OID 0)
-- Dependencies: 297
-- Name: FUNCTION resumen_auditoria_admin(p_id_usuario integer, p_desde timestamp with time zone, p_hasta timestamp with time zone); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.resumen_auditoria_admin(p_id_usuario integer, p_desde timestamp with time zone, p_hasta timestamp with time zone) IS 'C-03: consulta analítica de operaciones críticas por administrador (último mes por omisión).';


--
-- TOC entry 289 (class 1255 OID 18296)
-- Name: revertir_venta(integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.revertir_venta(p_id_solicitud_reembolso integer, p_referencia text) RETURNS TABLE(monto_reembolsado numeric, boletos_anulados integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
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
        $$;


ALTER FUNCTION public.revertir_venta(p_id_solicitud_reembolso integer, p_referencia text) OWNER TO postgres;

--
-- TOC entry 292 (class 1255 OID 18294)
-- Name: solicitar_reembolso(integer, integer, integer[], text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.solicitar_reembolso(p_id_usuario_actor integer, p_id_compra integer, p_ids_boleto integer[], p_motivo text, p_ip text) RETURNS TABLE(exito boolean, codigo text, mensaje text, id_solicitud integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


ALTER FUNCTION public.solicitar_reembolso(p_id_usuario_actor integer, p_id_compra integer, p_ids_boleto integer[], p_motivo text, p_ip text) OWNER TO postgres;

--
-- TOC entry 5417 (class 0 OID 0)
-- Dependencies: 292
-- Name: FUNCTION solicitar_reembolso(p_id_usuario_actor integer, p_id_compra integer, p_ids_boleto integer[], p_motivo text, p_ip text); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.solicitar_reembolso(p_id_usuario_actor integer, p_id_compra integer, p_ids_boleto integer[], p_motivo text, p_ip text) IS 'C-03: solicita reembolso validando rol, propiedad, estado de boletos y política.';


--
-- TOC entry 272 (class 1255 OID 18271)
-- Name: validar_boleto_de_solicitud(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validar_boleto_de_solicitud() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    compra_solicitud INT;
    compra_boleto INT;
BEGIN
    SELECT id_compra INTO compra_solicitud
    FROM solicitud_reembolso WHERE id_solicitud_reembolso = NEW.id_solicitud_reembolso FOR SHARE;
    SELECT cd.id_compra INTO compra_boleto
    FROM boleto b INNER JOIN compra_detalle cd ON cd.id_compra_detalle = b.id_compra_detalle
    WHERE b.id_boleto = NEW.id_boleto;
    -- Las referencias inexistentes las rechazan las FK.
    IF compra_solicitud IS NOT NULL AND compra_boleto IS NOT NULL
       AND compra_solicitud <> compra_boleto THEN
        RAISE EXCEPTION 'El boleto no pertenece a la compra de la solicitud de reembolso.'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.validar_boleto_de_solicitud() OWNER TO postgres;

--
-- TOC entry 265 (class 1255 OID 18006)
-- Name: validar_horario_funcion(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validar_horario_funcion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.activa = FALSE THEN
        RETURN NEW;
    END IF;

    -- Serializar la programación de una misma sala.
    PERFORM id_sala FROM sala WHERE id_sala = NEW.id_sala FOR UPDATE;

    IF EXISTS (
        SELECT 1 FROM funcion
        WHERE id_sala = NEW.id_sala
          AND activa = TRUE
          AND id_funcion <> NEW.id_funcion
          AND NEW.inicio < fin + INTERVAL '15 minutes'
          AND NEW.fin + INTERVAL '15 minutes' > inicio
    ) THEN
        RAISE EXCEPTION 'El horario se cruza con otra función o con su tiempo de limpieza.';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.validar_horario_funcion() OWNER TO postgres;

--
-- TOC entry 266 (class 1255 OID 18008)
-- Name: validar_vigencia_tarifa(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validar_vigencia_tarifa() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- El mismo bloqueo coordina altas simultáneas de tarifas de una función.
    -- En una actualización se bloquean origen y destino en orden de ID.
    IF TG_OP = 'UPDATE' THEN
        PERFORM id_funcion FROM funcion
        WHERE id_funcion IN (OLD.id_funcion, NEW.id_funcion)
        ORDER BY id_funcion FOR UPDATE;
    ELSE
        PERFORM id_funcion FROM funcion WHERE id_funcion = NEW.id_funcion FOR UPDATE;
    END IF;

    IF EXISTS (
        SELECT 1 FROM tarifa
        WHERE id_funcion = NEW.id_funcion AND id_zona = NEW.id_zona
          AND id_categoria_entrada = NEW.id_categoria_entrada
          AND id_tarifa <> NEW.id_tarifa
          AND NEW.vigente_desde < vigente_hasta AND NEW.vigente_hasta > vigente_desde
    ) THEN
        RAISE EXCEPTION 'Ya existe una tarifa para esa función, zona y categoría durante esa vigencia.'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.validar_vigencia_tarifa() OWNER TO postgres;

--
-- TOC entry 284 (class 1255 OID 18273)
-- Name: validar_y_consumir_ingreso_qr(uuid, integer, integer, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validar_y_consumir_ingreso_qr(p_token_qr uuid, p_id_funcion_solicitada integer, p_id_usuario_operador integer, p_dispositivo character varying) RETURNS TABLE(exito boolean, mensaje text, id_boleto_procesado integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


ALTER FUNCTION public.validar_y_consumir_ingreso_qr(p_token_qr uuid, p_id_funcion_solicitada integer, p_id_usuario_operador integer, p_dispositivo character varying) OWNER TO postgres;

--
-- TOC entry 263 (class 1255 OID 18001)
-- Name: validar_zona_tarifa(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validar_zona_tarifa() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    sala_funcion INT;
    sala_zona INT;
BEGIN
    -- Mantener estables ambas referencias hasta terminar la transacción.
    SELECT id_sala INTO sala_funcion
    FROM funcion WHERE id_funcion = NEW.id_funcion FOR SHARE;

    SELECT id_sala INTO sala_zona
    FROM zona WHERE id_zona = NEW.id_zona FOR SHARE;

    -- Las referencias inexistentes las rechazan las FK ya definidas.
    IF sala_funcion IS NOT NULL AND sala_zona IS NOT NULL
       AND sala_funcion <> sala_zona THEN
        RAISE EXCEPTION 'La zona de la tarifa debe pertenecer a la sala de la función.'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.validar_zona_tarifa() OWNER TO postgres;

--
-- TOC entry 253 (class 1259 OID 18103)
-- Name: acceso_puerta_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.acceso_puerta_log (
    id_acceso_puerta_log integer NOT NULL,
    fecha timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    id_boleto integer,
    id_funcion_solicitada integer,
    id_usuario_operador integer NOT NULL,
    dispositivo character varying(100) NOT NULL,
    resultado character varying(20) NOT NULL,
    motivo character varying(200),
    CONSTRAINT ck_puerta_dispositivo CHECK ((btrim((dispositivo)::text) <> ''::text)),
    CONSTRAINT ck_puerta_motivo_rechazo CHECK ((((resultado)::text = 'aceptado'::text) OR (btrim((COALESCE(motivo, ''::character varying))::text) <> ''::text))),
    CONSTRAINT ck_puerta_resultado CHECK (((resultado)::text = ANY ((ARRAY['aceptado'::character varying, 'rechazado'::character varying])::text[])))
);


ALTER TABLE public.acceso_puerta_log OWNER TO postgres;

--
-- TOC entry 5420 (class 0 OID 0)
-- Dependencies: 253
-- Name: TABLE acceso_puerta_log; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.acceso_puerta_log IS 'C-05 / RN-20 categoría 3 (puerta). Solo INSERT. Inmutable por trigger y privilegios. Retención mínima 60 meses desde el evento; los meses > 6 se exportan a archivo WORM. Se elimina únicamente por DROP de partición ya vencida (ver documentación C-05 §4).';


--
-- TOC entry 252 (class 1259 OID 18102)
-- Name: acceso_puerta_log_id_acceso_puerta_log_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.acceso_puerta_log_id_acceso_puerta_log_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.acceso_puerta_log_id_acceso_puerta_log_seq OWNER TO postgres;

--
-- TOC entry 5422 (class 0 OID 0)
-- Dependencies: 252
-- Name: acceso_puerta_log_id_acceso_puerta_log_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.acceso_puerta_log_id_acceso_puerta_log_seq OWNED BY public.acceso_puerta_log.id_acceso_puerta_log;


--
-- TOC entry 254 (class 1259 OID 18121)
-- Name: admin_operacion_audit_id_admin_operacion_audit_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.admin_operacion_audit_id_admin_operacion_audit_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.admin_operacion_audit_id_admin_operacion_audit_seq OWNER TO postgres;

--
-- TOC entry 5424 (class 0 OID 0)
-- Dependencies: 254
-- Name: admin_operacion_audit_id_admin_operacion_audit_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.admin_operacion_audit_id_admin_operacion_audit_seq OWNED BY public.admin_operacion_audit.id_admin_operacion_audit;


--
-- TOC entry 234 (class 1259 OID 17843)
-- Name: asiento; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.asiento (
    id_asiento integer NOT NULL,
    id_zona integer NOT NULL,
    fila character varying(10) NOT NULL,
    numero integer NOT NULL,
    CONSTRAINT asiento_numero_check CHECK ((numero > 0))
);


ALTER TABLE public.asiento OWNER TO postgres;

--
-- TOC entry 233 (class 1259 OID 17842)
-- Name: asiento_id_asiento_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.asiento_id_asiento_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.asiento_id_asiento_seq OWNER TO postgres;

--
-- TOC entry 5426 (class 0 OID 0)
-- Dependencies: 233
-- Name: asiento_id_asiento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.asiento_id_asiento_seq OWNED BY public.asiento.id_asiento;


--
-- TOC entry 261 (class 1259 OID 18236)
-- Name: boleto; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.boleto (
    id_boleto integer NOT NULL,
    id_compra_detalle integer NOT NULL,
    token_qr uuid DEFAULT gen_random_uuid() NOT NULL,
    estado character varying(20) DEFAULT 'emitido'::character varying NOT NULL,
    emitido_en timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    usado_en timestamp with time zone,
    CONSTRAINT ck_boleto_estado CHECK (((estado)::text = ANY ((ARRAY['emitido'::character varying, 'usado'::character varying, 'anulado'::character varying])::text[]))),
    CONSTRAINT ck_boleto_usado CHECK ((((estado)::text = 'usado'::text) = (usado_en IS NOT NULL)))
);


ALTER TABLE public.boleto OWNER TO postgres;

--
-- TOC entry 260 (class 1259 OID 18235)
-- Name: boleto_id_boleto_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.boleto_id_boleto_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.boleto_id_boleto_seq OWNER TO postgres;

--
-- TOC entry 5427 (class 0 OID 0)
-- Dependencies: 260
-- Name: boleto_id_boleto_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.boleto_id_boleto_seq OWNED BY public.boleto.id_boleto;


--
-- TOC entry 226 (class 1259 OID 17778)
-- Name: categoria_entrada; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.categoria_entrada (
    id_categoria_entrada integer NOT NULL,
    nombre character varying(50) NOT NULL,
    requiere_acreditacion boolean DEFAULT false NOT NULL
);


ALTER TABLE public.categoria_entrada OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 17777)
-- Name: categoria_entrada_id_categoria_entrada_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.categoria_entrada_id_categoria_entrada_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.categoria_entrada_id_categoria_entrada_seq OWNER TO postgres;

--
-- TOC entry 5428 (class 0 OID 0)
-- Dependencies: 225
-- Name: categoria_entrada_id_categoria_entrada_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.categoria_entrada_id_categoria_entrada_seq OWNED BY public.categoria_entrada.id_categoria_entrada;


--
-- TOC entry 220 (class 1259 OID 17738)
-- Name: cine; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cine (
    id_cine integer NOT NULL,
    nombre character varying(100) NOT NULL,
    ubicacion text NOT NULL,
    zona_horaria character varying(100) NOT NULL
);


ALTER TABLE public.cine OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 17737)
-- Name: cine_id_cine_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.cine_id_cine_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cine_id_cine_seq OWNER TO postgres;

--
-- TOC entry 5429 (class 0 OID 0)
-- Dependencies: 219
-- Name: cine_id_cine_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.cine_id_cine_seq OWNED BY public.cine.id_cine;


--
-- TOC entry 257 (class 1259 OID 18155)
-- Name: compra; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.compra (
    id_compra integer NOT NULL,
    id_usuario_cliente integer NOT NULL,
    id_usuario_actor integer NOT NULL,
    id_funcion integer NOT NULL,
    estado character varying(30) NOT NULL,
    total numeric(12,2) NOT NULL,
    moneda character varying(3) DEFAULT 'USD'::character varying NOT NULL,
    creada_en timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_compra_estado CHECK (((estado)::text = ANY ((ARRAY['pendiente'::character varying, 'pagada'::character varying, 'cancelada'::character varying, 'expirada'::character varying, 'parcialmente_reembolsada'::character varying, 'reembolsada'::character varying])::text[]))),
    CONSTRAINT ck_compra_moneda CHECK (((moneda)::text = 'USD'::text)),
    CONSTRAINT ck_compra_total CHECK ((total >= (0)::numeric))
);


ALTER TABLE public.compra OWNER TO postgres;

--
-- TOC entry 259 (class 1259 OID 18190)
-- Name: compra_detalle; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.compra_detalle (
    id_compra_detalle integer NOT NULL,
    id_compra integer NOT NULL,
    id_asiento integer NOT NULL,
    id_categoria_entrada integer NOT NULL,
    id_tarifa integer NOT NULL,
    id_promocion integer,
    precio_base numeric(12,2) NOT NULL,
    descuento numeric(12,2) DEFAULT 0 NOT NULL,
    cargo_servicio numeric(12,2) DEFAULT 0 NOT NULL,
    total_linea numeric(12,2) NOT NULL,
    CONSTRAINT ck_cd_montos CHECK (((precio_base >= (0)::numeric) AND (descuento >= (0)::numeric) AND (cargo_servicio >= (0)::numeric) AND (total_linea = ((precio_base - descuento) + cargo_servicio))))
);


ALTER TABLE public.compra_detalle OWNER TO postgres;

--
-- TOC entry 258 (class 1259 OID 18189)
-- Name: compra_detalle_id_compra_detalle_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.compra_detalle_id_compra_detalle_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.compra_detalle_id_compra_detalle_seq OWNER TO postgres;

--
-- TOC entry 5430 (class 0 OID 0)
-- Dependencies: 258
-- Name: compra_detalle_id_compra_detalle_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.compra_detalle_id_compra_detalle_seq OWNED BY public.compra_detalle.id_compra_detalle;


--
-- TOC entry 256 (class 1259 OID 18154)
-- Name: compra_id_compra_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.compra_id_compra_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.compra_id_compra_seq OWNER TO postgres;

--
-- TOC entry 5431 (class 0 OID 0)
-- Dependencies: 256
-- Name: compra_id_compra_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.compra_id_compra_seq OWNED BY public.compra.id_compra;


--
-- TOC entry 236 (class 1259 OID 17862)
-- Name: funcion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.funcion (
    id_funcion integer NOT NULL,
    id_pelicula integer NOT NULL,
    id_sala integer NOT NULL,
    inicio timestamp with time zone NOT NULL,
    fin timestamp with time zone NOT NULL,
    activa boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_funcion_horario CHECK ((fin > inicio))
);


ALTER TABLE public.funcion OWNER TO postgres;

--
-- TOC entry 235 (class 1259 OID 17861)
-- Name: funcion_id_funcion_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.funcion_id_funcion_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.funcion_id_funcion_seq OWNER TO postgres;

--
-- TOC entry 5432 (class 0 OID 0)
-- Dependencies: 235
-- Name: funcion_id_funcion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.funcion_id_funcion_seq OWNED BY public.funcion.id_funcion;


--
-- TOC entry 240 (class 1259 OID 17937)
-- Name: funcion_promocion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.funcion_promocion (
    id_funcion integer NOT NULL,
    id_promocion integer NOT NULL
);


ALTER TABLE public.funcion_promocion OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 17767)
-- Name: genero; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.genero (
    id_genero integer NOT NULL,
    nombre character varying(50) NOT NULL
);


ALTER TABLE public.genero OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 17766)
-- Name: genero_id_genero_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.genero_id_genero_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.genero_id_genero_seq OWNER TO postgres;

--
-- TOC entry 5433 (class 0 OID 0)
-- Dependencies: 223
-- Name: genero_id_genero_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.genero_id_genero_seq OWNED BY public.genero.id_genero;


--
-- TOC entry 222 (class 1259 OID 17751)
-- Name: pelicula; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pelicula (
    id_pelicula integer NOT NULL,
    titulo character varying(200) NOT NULL,
    sinopsis text NOT NULL,
    clasificacion character varying(30) NOT NULL,
    duracion_min integer NOT NULL,
    poster_url text NOT NULL,
    CONSTRAINT pelicula_duracion_min_check CHECK ((duracion_min > 0))
);


ALTER TABLE public.pelicula OWNER TO postgres;

--
-- TOC entry 239 (class 1259 OID 17920)
-- Name: pelicula_genero; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pelicula_genero (
    id_pelicula integer NOT NULL,
    id_genero integer NOT NULL
);


ALTER TABLE public.pelicula_genero OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 17750)
-- Name: pelicula_id_pelicula_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.pelicula_id_pelicula_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.pelicula_id_pelicula_seq OWNER TO postgres;

--
-- TOC entry 5434 (class 0 OID 0)
-- Dependencies: 221
-- Name: pelicula_id_pelicula_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.pelicula_id_pelicula_seq OWNED BY public.pelicula.id_pelicula;


--
-- TOC entry 262 (class 1259 OID 18277)
-- Name: politica_negocio; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.politica_negocio (
    clave character varying(60) NOT NULL,
    valor_entero integer NOT NULL,
    descripcion text NOT NULL,
    actualizada_en timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT politica_negocio_valor_entero_check CHECK ((valor_entero >= 0))
);


ALTER TABLE public.politica_negocio OWNER TO postgres;

--
-- TOC entry 5435 (class 0 OID 0)
-- Dependencies: 262
-- Name: TABLE politica_negocio; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.politica_negocio IS 'Políticas numéricas centralizadas; se modifican solo con cambiar_politica (auditado).';


--
-- TOC entry 228 (class 1259 OID 17791)
-- Name: promocion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.promocion (
    id_promocion integer NOT NULL,
    nombre character varying(100) NOT NULL,
    tipo character varying(30) NOT NULL,
    condicion text NOT NULL,
    vigente_desde timestamp with time zone NOT NULL,
    vigente_hasta timestamp with time zone NOT NULL,
    activa boolean DEFAULT true NOT NULL,
    CONSTRAINT ck_promocion_vigencia CHECK ((vigente_hasta > vigente_desde))
);


ALTER TABLE public.promocion OWNER TO postgres;

--
-- TOC entry 243 (class 1259 OID 17984)
-- Name: promocion_categoria; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.promocion_categoria (
    id_promocion integer NOT NULL,
    id_categoria_entrada integer NOT NULL
);


ALTER TABLE public.promocion_categoria OWNER TO postgres;

--
-- TOC entry 241 (class 1259 OID 17954)
-- Name: promocion_dia; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.promocion_dia (
    id_promocion integer NOT NULL,
    dia_semana integer NOT NULL,
    CONSTRAINT promocion_dia_dia_semana_check CHECK (((dia_semana >= 1) AND (dia_semana <= 7)))
);


ALTER TABLE public.promocion_dia OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 17790)
-- Name: promocion_id_promocion_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.promocion_id_promocion_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.promocion_id_promocion_seq OWNER TO postgres;

--
-- TOC entry 5437 (class 0 OID 0)
-- Dependencies: 227
-- Name: promocion_id_promocion_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.promocion_id_promocion_seq OWNED BY public.promocion.id_promocion;


--
-- TOC entry 242 (class 1259 OID 17967)
-- Name: promocion_zona; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.promocion_zona (
    id_promocion integer NOT NULL,
    id_zona integer NOT NULL
);


ALTER TABLE public.promocion_zona OWNER TO postgres;

--
-- TOC entry 245 (class 1259 OID 18011)
-- Name: rol; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.rol (
    id_rol integer NOT NULL,
    nombre character varying(30) NOT NULL
);


ALTER TABLE public.rol OWNER TO postgres;

--
-- TOC entry 244 (class 1259 OID 18010)
-- Name: rol_id_rol_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.rol_id_rol_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rol_id_rol_seq OWNER TO postgres;

--
-- TOC entry 5439 (class 0 OID 0)
-- Dependencies: 244
-- Name: rol_id_rol_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.rol_id_rol_seq OWNED BY public.rol.id_rol;


--
-- TOC entry 248 (class 1259 OID 18048)
-- Name: rol_permiso; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.rol_permiso (
    id_rol integer NOT NULL,
    accion character varying(60) NOT NULL
);


ALTER TABLE public.rol_permiso OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 17809)
-- Name: sala; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sala (
    id_sala integer NOT NULL,
    id_cine integer NOT NULL,
    nombre character varying(100) NOT NULL
);


ALTER TABLE public.sala OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 17808)
-- Name: sala_id_sala_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.sala_id_sala_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sala_id_sala_seq OWNER TO postgres;

--
-- TOC entry 5441 (class 0 OID 0)
-- Dependencies: 229
-- Name: sala_id_sala_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.sala_id_sala_seq OWNED BY public.sala.id_sala;


--
-- TOC entry 250 (class 1259 OID 18061)
-- Name: solicitud_reembolso; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.solicitud_reembolso (
    id_solicitud_reembolso integer NOT NULL,
    id_compra integer NOT NULL,
    id_usuario_actor integer NOT NULL,
    motivo text NOT NULL,
    estado character varying(20) DEFAULT 'pendiente'::character varying NOT NULL,
    creada_en timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    resuelta_en timestamp with time zone,
    id_usuario_resuelve integer,
    CONSTRAINT ck_solicitud_estado CHECK (((estado)::text = ANY ((ARRAY['pendiente'::character varying, 'ejecutada'::character varying, 'rechazada'::character varying])::text[]))),
    CONSTRAINT ck_solicitud_motivo CHECK ((btrim(motivo) <> ''::text)),
    CONSTRAINT ck_solicitud_resolucion CHECK (((((estado)::text = 'pendiente'::text) AND (resuelta_en IS NULL) AND (id_usuario_resuelve IS NULL)) OR (((estado)::text <> 'pendiente'::text) AND (resuelta_en IS NOT NULL) AND (id_usuario_resuelve IS NOT NULL))))
);


ALTER TABLE public.solicitud_reembolso OWNER TO postgres;

--
-- TOC entry 251 (class 1259 OID 18090)
-- Name: solicitud_reembolso_detalle; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.solicitud_reembolso_detalle (
    id_solicitud_reembolso integer NOT NULL,
    id_boleto integer NOT NULL
);


ALTER TABLE public.solicitud_reembolso_detalle OWNER TO postgres;

--
-- TOC entry 249 (class 1259 OID 18060)
-- Name: solicitud_reembolso_id_solicitud_reembolso_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.solicitud_reembolso_id_solicitud_reembolso_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.solicitud_reembolso_id_solicitud_reembolso_seq OWNER TO postgres;

--
-- TOC entry 5444 (class 0 OID 0)
-- Dependencies: 249
-- Name: solicitud_reembolso_id_solicitud_reembolso_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.solicitud_reembolso_id_solicitud_reembolso_seq OWNED BY public.solicitud_reembolso.id_solicitud_reembolso;


--
-- TOC entry 238 (class 1259 OID 17887)
-- Name: tarifa; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tarifa (
    id_tarifa integer NOT NULL,
    id_funcion integer NOT NULL,
    id_zona integer NOT NULL,
    id_categoria_entrada integer NOT NULL,
    monto numeric(12,2) NOT NULL,
    moneda character varying(3) DEFAULT 'USD'::character varying NOT NULL,
    vigente_desde timestamp with time zone NOT NULL,
    vigente_hasta timestamp with time zone NOT NULL,
    CONSTRAINT ck_tarifa_moneda CHECK (((moneda)::text = 'USD'::text)),
    CONSTRAINT ck_tarifa_monto CHECK ((monto >= (0)::numeric)),
    CONSTRAINT ck_tarifa_vigencia CHECK ((vigente_hasta > vigente_desde))
);


ALTER TABLE public.tarifa OWNER TO postgres;

--
-- TOC entry 237 (class 1259 OID 17886)
-- Name: tarifa_id_tarifa_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tarifa_id_tarifa_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tarifa_id_tarifa_seq OWNER TO postgres;

--
-- TOC entry 5446 (class 0 OID 0)
-- Dependencies: 237
-- Name: tarifa_id_tarifa_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tarifa_id_tarifa_seq OWNED BY public.tarifa.id_tarifa;


--
-- TOC entry 247 (class 1259 OID 18022)
-- Name: usuario; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.usuario (
    id_usuario integer NOT NULL,
    id_rol integer NOT NULL,
    nombre character varying(100) NOT NULL,
    correo character varying(150) NOT NULL,
    password_hash text NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT ck_usuario_correo_normalizado CHECK ((((correo)::text = lower(btrim((correo)::text))) AND ((correo)::text <> ''::text))),
    CONSTRAINT ck_usuario_nombre CHECK ((btrim((nombre)::text) <> ''::text))
);


ALTER TABLE public.usuario OWNER TO postgres;

--
-- TOC entry 246 (class 1259 OID 18021)
-- Name: usuario_id_usuario_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.usuario_id_usuario_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.usuario_id_usuario_seq OWNER TO postgres;

--
-- TOC entry 5448 (class 0 OID 0)
-- Dependencies: 246
-- Name: usuario_id_usuario_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.usuario_id_usuario_seq OWNED BY public.usuario.id_usuario;


--
-- TOC entry 232 (class 1259 OID 17826)
-- Name: zona; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.zona (
    id_zona integer NOT NULL,
    id_sala integer NOT NULL,
    nombre character varying(50) NOT NULL
);


ALTER TABLE public.zona OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 17825)
-- Name: zona_id_zona_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.zona_id_zona_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.zona_id_zona_seq OWNER TO postgres;

--
-- TOC entry 5450 (class 0 OID 0)
-- Dependencies: 231
-- Name: zona_id_zona_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.zona_id_zona_seq OWNED BY public.zona.id_zona;


--
-- TOC entry 5019 (class 2604 OID 18106)
-- Name: acceso_puerta_log id_acceso_puerta_log; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.acceso_puerta_log ALTER COLUMN id_acceso_puerta_log SET DEFAULT nextval('public.acceso_puerta_log_id_acceso_puerta_log_seq'::regclass);


--
-- TOC entry 5021 (class 2604 OID 18125)
-- Name: admin_operacion_audit id_admin_operacion_audit; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.admin_operacion_audit ALTER COLUMN id_admin_operacion_audit SET DEFAULT nextval('public.admin_operacion_audit_id_admin_operacion_audit_seq'::regclass);


--
-- TOC entry 5007 (class 2604 OID 17846)
-- Name: asiento id_asiento; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.asiento ALTER COLUMN id_asiento SET DEFAULT nextval('public.asiento_id_asiento_seq'::regclass);


--
-- TOC entry 5029 (class 2604 OID 18239)
-- Name: boleto id_boleto; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.boleto ALTER COLUMN id_boleto SET DEFAULT nextval('public.boleto_id_boleto_seq'::regclass);


--
-- TOC entry 5001 (class 2604 OID 17781)
-- Name: categoria_entrada id_categoria_entrada; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categoria_entrada ALTER COLUMN id_categoria_entrada SET DEFAULT nextval('public.categoria_entrada_id_categoria_entrada_seq'::regclass);


--
-- TOC entry 4998 (class 2604 OID 17741)
-- Name: cine id_cine; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cine ALTER COLUMN id_cine SET DEFAULT nextval('public.cine_id_cine_seq'::regclass);


--
-- TOC entry 5023 (class 2604 OID 18158)
-- Name: compra id_compra; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.compra ALTER COLUMN id_compra SET DEFAULT nextval('public.compra_id_compra_seq'::regclass);


--
-- TOC entry 5026 (class 2604 OID 18193)
-- Name: compra_detalle id_compra_detalle; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.compra_detalle ALTER COLUMN id_compra_detalle SET DEFAULT nextval('public.compra_detalle_id_compra_detalle_seq'::regclass);


--
-- TOC entry 5008 (class 2604 OID 17865)
-- Name: funcion id_funcion; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.funcion ALTER COLUMN id_funcion SET DEFAULT nextval('public.funcion_id_funcion_seq'::regclass);


--
-- TOC entry 5000 (class 2604 OID 17770)
-- Name: genero id_genero; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.genero ALTER COLUMN id_genero SET DEFAULT nextval('public.genero_id_genero_seq'::regclass);


--
-- TOC entry 4999 (class 2604 OID 17754)
-- Name: pelicula id_pelicula; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pelicula ALTER COLUMN id_pelicula SET DEFAULT nextval('public.pelicula_id_pelicula_seq'::regclass);


--
-- TOC entry 5003 (class 2604 OID 17794)
-- Name: promocion id_promocion; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promocion ALTER COLUMN id_promocion SET DEFAULT nextval('public.promocion_id_promocion_seq'::regclass);


--
-- TOC entry 5012 (class 2604 OID 18014)
-- Name: rol id_rol; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rol ALTER COLUMN id_rol SET DEFAULT nextval('public.rol_id_rol_seq'::regclass);


--
-- TOC entry 5005 (class 2604 OID 17812)
-- Name: sala id_sala; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sala ALTER COLUMN id_sala SET DEFAULT nextval('public.sala_id_sala_seq'::regclass);


--
-- TOC entry 5016 (class 2604 OID 18064)
-- Name: solicitud_reembolso id_solicitud_reembolso; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.solicitud_reembolso ALTER COLUMN id_solicitud_reembolso SET DEFAULT nextval('public.solicitud_reembolso_id_solicitud_reembolso_seq'::regclass);


--
-- TOC entry 5010 (class 2604 OID 17890)
-- Name: tarifa id_tarifa; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tarifa ALTER COLUMN id_tarifa SET DEFAULT nextval('public.tarifa_id_tarifa_seq'::regclass);


--
-- TOC entry 5013 (class 2604 OID 18025)
-- Name: usuario id_usuario; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuario ALTER COLUMN id_usuario SET DEFAULT nextval('public.usuario_id_usuario_seq'::regclass);


--
-- TOC entry 5006 (class 2604 OID 17829)
-- Name: zona id_zona; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.zona ALTER COLUMN id_zona SET DEFAULT nextval('public.zona_id_zona_seq'::regclass);


--
-- TOC entry 5383 (class 0 OID 18103)
-- Dependencies: 253
-- Data for Name: acceso_puerta_log; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.acceso_puerta_log (id_acceso_puerta_log, fecha, id_boleto, id_funcion_solicitada, id_usuario_operador, dispositivo, resultado, motivo) FROM stdin;
\.


--
-- TOC entry 5385 (class 0 OID 18122)
-- Dependencies: 255
-- Data for Name: admin_operacion_audit; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.admin_operacion_audit (id_admin_operacion_audit, fecha, id_usuario_actor, rol_al_actuar, ip, accion, entidad, id_entidad, motivo, cambios) FROM stdin;
2	2026-10-22 23:17:02.262048-06	7	administrador	127.0.0.1	prueba	rol	\N	ensayo	\N
\.


--
-- TOC entry 5364 (class 0 OID 17843)
-- Dependencies: 234
-- Data for Name: asiento; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.asiento (id_asiento, id_zona, fila, numero) FROM stdin;
1	1	A	1
2	1	A	2
3	1	A	3
4	2	B	1
5	2	B	2
6	2	B	3
\.


--
-- TOC entry 5391 (class 0 OID 18236)
-- Dependencies: 261
-- Data for Name: boleto; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.boleto (id_boleto, id_compra_detalle, token_qr, estado, emitido_en, usado_en) FROM stdin;
1	1	4a44fb0a-6aa6-40a3-8210-5c752cf8511c	emitido	2026-10-23 14:33:20.370266-06	\N
2	2	ab5a5dd0-1ec1-4f75-ba0f-30981dae5e29	usado	2026-10-23 14:33:20.370266-06	2026-10-23 14:33:20.370266-06
3	3	9d69b490-8e15-43ff-8925-6d219150dfb8	anulado	2026-10-23 14:33:20.370266-06	\N
4	4	33e460b6-9617-4d80-b8d1-73ed74f6ab70	emitido	2026-10-23 14:33:20.370266-06	\N
\.


--
-- TOC entry 5356 (class 0 OID 17778)
-- Dependencies: 226
-- Data for Name: categoria_entrada; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.categoria_entrada (id_categoria_entrada, nombre, requiere_acreditacion) FROM stdin;
1	Adulto	f
2	Niño	t
3	Estudiante	t
4	Tercera edad	t
\.


--
-- TOC entry 5350 (class 0 OID 17738)
-- Dependencies: 220
-- Data for Name: cine; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cine (id_cine, nombre, ubicacion, zona_horaria) FROM stdin;
1	IMAX Central	San José, Costa Rica	America/Costa_Rica
\.


--
-- TOC entry 5387 (class 0 OID 18155)
-- Dependencies: 257
-- Data for Name: compra; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.compra (id_compra, id_usuario_cliente, id_usuario_actor, id_funcion, estado, total, moneda, creada_en) FROM stdin;
1	2	2	1	pagada	13.00	USD	2026-10-23 14:33:20.370266-06
2	1	3	1	reembolsada	12.00	USD	2026-10-23 14:33:20.370266-06
3	2	2	1	pagada	8.00	USD	2026-10-23 14:33:20.370266-06
\.


--
-- TOC entry 5389 (class 0 OID 18190)
-- Dependencies: 259
-- Data for Name: compra_detalle; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.compra_detalle (id_compra_detalle, id_compra, id_asiento, id_categoria_entrada, id_tarifa, id_promocion, precio_base, descuento, cargo_servicio, total_linea) FROM stdin;
1	1	1	1	1	\N	8.00	0.00	0.00	8.00
2	1	2	2	2	\N	5.00	0.00	0.00	5.00
3	2	4	1	3	\N	12.00	0.00	0.00	12.00
4	3	3	1	1	\N	8.00	0.00	0.00	8.00
\.


--
-- TOC entry 5366 (class 0 OID 17862)
-- Dependencies: 236
-- Data for Name: funcion; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.funcion (id_funcion, id_pelicula, id_sala, inicio, fin, activa) FROM stdin;
1	1	1	2026-10-29 18:00:00-06	2026-10-29 20:00:00-06	t
\.


--
-- TOC entry 5370 (class 0 OID 17937)
-- Dependencies: 240
-- Data for Name: funcion_promocion; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.funcion_promocion (id_funcion, id_promocion) FROM stdin;
1	1
\.


--
-- TOC entry 5354 (class 0 OID 17767)
-- Dependencies: 224
-- Data for Name: genero; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.genero (id_genero, nombre) FROM stdin;
1	Ciencia ficción
2	Aventura
\.


--
-- TOC entry 5352 (class 0 OID 17751)
-- Dependencies: 222
-- Data for Name: pelicula; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.pelicula (id_pelicula, titulo, sinopsis, clasificacion, duracion_min, poster_url) FROM stdin;
1	Horizonte estelar	Una tripulación explora un planeta desconocido.	Todo público	120	/static/img/horizonte_estelar.png
\.


--
-- TOC entry 5369 (class 0 OID 17920)
-- Dependencies: 239
-- Data for Name: pelicula_genero; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.pelicula_genero (id_pelicula, id_genero) FROM stdin;
1	1
1	2
\.


--
-- TOC entry 5392 (class 0 OID 18277)
-- Dependencies: 262
-- Data for Name: politica_negocio; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.politica_negocio (clave, valor_entero, descripcion, actualizada_en) FROM stdin;
reembolso_horas_antes	2	Horas mínimas antes del inicio de la función para solicitar y ejecutar un reembolso ordinario (inclusive).	2026-10-23 20:34:38.433063-06
\.


--
-- TOC entry 5358 (class 0 OID 17791)
-- Dependencies: 228
-- Data for Name: promocion; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.promocion (id_promocion, nombre, tipo, condicion, vigente_desde, vigente_hasta, activa) FROM stdin;
1	Pareja General	2x1	Dos entradas de adulto en zona General de la misma función.	2026-10-21 00:00:00-06	2026-10-29 18:00:00-06	t
\.


--
-- TOC entry 5373 (class 0 OID 17984)
-- Dependencies: 243
-- Data for Name: promocion_categoria; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.promocion_categoria (id_promocion, id_categoria_entrada) FROM stdin;
1	1
\.


--
-- TOC entry 5371 (class 0 OID 17954)
-- Dependencies: 241
-- Data for Name: promocion_dia; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.promocion_dia (id_promocion, dia_semana) FROM stdin;
1	1
1	2
1	3
1	4
1	5
1	6
1	7
\.


--
-- TOC entry 5372 (class 0 OID 17967)
-- Dependencies: 242
-- Data for Name: promocion_zona; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.promocion_zona (id_promocion, id_zona) FROM stdin;
1	1
\.


--
-- TOC entry 5375 (class 0 OID 18011)
-- Dependencies: 245
-- Data for Name: rol; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.rol (id_rol, nombre) FROM stdin;
1	cliente
2	taquillero
3	operador_puerta
4	contador
5	administrador
\.


--
-- TOC entry 5378 (class 0 OID 18048)
-- Dependencies: 248
-- Data for Name: rol_permiso; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.rol_permiso (id_rol, accion) FROM stdin;
1	solicitar_reembolso
1	consultar_boletos_propios
1	reservar_comprar
1	consultar_cartelera
2	solicitar_reembolso
2	consultar_boletos_venta
2	venta_presencial
2	consultar_cartelera
3	validar_ingreso
3	consultar_cartelera
4	ver_auditoria
4	ver_reportes_financieros
4	ver_tarifas
4	consultar_cartelera
5	administrar_usuarios
5	ver_auditoria
5	ver_reportes_financieros
5	resolver_reembolso
5	solicitar_reembolso
5	consultar_boletos_admin
5	ver_tarifas
5	configurar_tarifas
5	gestionar_catalogo
5	consultar_cartelera
5	forzar_reembolso
5	configurar_politicas
5	otorgar_cortesia
5	cambiar_asiento
\.


--
-- TOC entry 5360 (class 0 OID 17809)
-- Dependencies: 230
-- Data for Name: sala; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.sala (id_sala, id_cine, nombre) FROM stdin;
1	1	Sala 1
\.


--
-- TOC entry 5380 (class 0 OID 18061)
-- Dependencies: 250
-- Data for Name: solicitud_reembolso; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.solicitud_reembolso (id_solicitud_reembolso, id_compra, id_usuario_actor, motivo, estado, creada_en, resuelta_en, id_usuario_resuelve) FROM stdin;
3	1	1	Cambio de planes	pendiente	2026-10-22 23:21:35.708303-06	\N	\N
\.


--
-- TOC entry 5381 (class 0 OID 18090)
-- Dependencies: 251
-- Data for Name: solicitud_reembolso_detalle; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.solicitud_reembolso_detalle (id_solicitud_reembolso, id_boleto) FROM stdin;
\.


--
-- TOC entry 5368 (class 0 OID 17887)
-- Dependencies: 238
-- Data for Name: tarifa; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tarifa (id_tarifa, id_funcion, id_zona, id_categoria_entrada, monto, moneda, vigente_desde, vigente_hasta) FROM stdin;
1	1	1	1	8.00	USD	2026-10-21 00:00:00-06	2026-10-29 18:00:00-06
2	1	1	2	5.00	USD	2026-10-21 00:00:00-06	2026-10-29 18:00:00-06
3	1	1	3	6.00	USD	2026-10-21 00:00:00-06	2026-10-29 18:00:00-06
4	1	1	4	5.00	USD	2026-10-21 00:00:00-06	2026-10-29 18:00:00-06
5	1	2	1	12.00	USD	2026-10-21 00:00:00-06	2026-10-29 18:00:00-06
6	1	2	2	9.00	USD	2026-10-21 00:00:00-06	2026-10-29 18:00:00-06
7	1	2	3	10.00	USD	2026-10-21 00:00:00-06	2026-10-29 18:00:00-06
8	1	2	4	9.00	USD	2026-10-21 00:00:00-06	2026-10-29 18:00:00-06
\.


--
-- TOC entry 5377 (class 0 OID 18022)
-- Dependencies: 247
-- Data for Name: usuario; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.usuario (id_usuario, id_rol, nombre, correo, password_hash, activo, creado_en) FROM stdin;
1	1	Cliente Dos	cliente2@imax.test	HASH_DE_PRUEBA	t	2026-10-22 23:03:04.634204-06
2	1	Cliente Uno	cliente1@imax.test	HASH_DE_PRUEBA	t	2026-10-22 23:03:04.634204-06
3	2	Taquillero	taquillero@imax.test	HASH_DE_PRUEBA	t	2026-10-22 23:03:04.634204-06
4	3	Operador Puerta 2	puerta2@imax.test	HASH_DE_PRUEBA	t	2026-10-22 23:03:04.634204-06
5	3	Operador Puerta 1	puerta1@imax.test	HASH_DE_PRUEBA	t	2026-10-22 23:03:04.634204-06
6	4	Contador	contador@imax.test	HASH_DE_PRUEBA	t	2026-10-22 23:03:04.634204-06
7	5	Administrador	admin@imax.test	HASH_DE_PRUEBA	t	2026-10-22 23:03:04.634204-06
\.


--
-- TOC entry 5362 (class 0 OID 17826)
-- Dependencies: 232
-- Data for Name: zona; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.zona (id_zona, id_sala, nombre) FROM stdin;
1	1	General
2	1	VIP
\.


--
-- TOC entry 5451 (class 0 OID 0)
-- Dependencies: 252
-- Name: acceso_puerta_log_id_acceso_puerta_log_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.acceso_puerta_log_id_acceso_puerta_log_seq', 1, true);


--
-- TOC entry 5452 (class 0 OID 0)
-- Dependencies: 254
-- Name: admin_operacion_audit_id_admin_operacion_audit_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.admin_operacion_audit_id_admin_operacion_audit_seq', 3, true);


--
-- TOC entry 5453 (class 0 OID 0)
-- Dependencies: 233
-- Name: asiento_id_asiento_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.asiento_id_asiento_seq', 6, true);


--
-- TOC entry 5454 (class 0 OID 0)
-- Dependencies: 260
-- Name: boleto_id_boleto_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.boleto_id_boleto_seq', 4, true);


--
-- TOC entry 5455 (class 0 OID 0)
-- Dependencies: 225
-- Name: categoria_entrada_id_categoria_entrada_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.categoria_entrada_id_categoria_entrada_seq', 4, true);


--
-- TOC entry 5456 (class 0 OID 0)
-- Dependencies: 219
-- Name: cine_id_cine_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cine_id_cine_seq', 1, true);


--
-- TOC entry 5457 (class 0 OID 0)
-- Dependencies: 258
-- Name: compra_detalle_id_compra_detalle_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.compra_detalle_id_compra_detalle_seq', 4, true);


--
-- TOC entry 5458 (class 0 OID 0)
-- Dependencies: 256
-- Name: compra_id_compra_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.compra_id_compra_seq', 3, true);


--
-- TOC entry 5459 (class 0 OID 0)
-- Dependencies: 235
-- Name: funcion_id_funcion_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.funcion_id_funcion_seq', 1, true);


--
-- TOC entry 5460 (class 0 OID 0)
-- Dependencies: 223
-- Name: genero_id_genero_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.genero_id_genero_seq', 2, true);


--
-- TOC entry 5461 (class 0 OID 0)
-- Dependencies: 221
-- Name: pelicula_id_pelicula_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.pelicula_id_pelicula_seq', 1, true);


--
-- TOC entry 5462 (class 0 OID 0)
-- Dependencies: 227
-- Name: promocion_id_promocion_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.promocion_id_promocion_seq', 1, true);


--
-- TOC entry 5463 (class 0 OID 0)
-- Dependencies: 244
-- Name: rol_id_rol_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.rol_id_rol_seq', 5, true);


--
-- TOC entry 5464 (class 0 OID 0)
-- Dependencies: 229
-- Name: sala_id_sala_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.sala_id_sala_seq', 1, true);


--
-- TOC entry 5465 (class 0 OID 0)
-- Dependencies: 249
-- Name: solicitud_reembolso_id_solicitud_reembolso_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.solicitud_reembolso_id_solicitud_reembolso_seq', 3, true);


--
-- TOC entry 5466 (class 0 OID 0)
-- Dependencies: 237
-- Name: tarifa_id_tarifa_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tarifa_id_tarifa_seq', 8, true);


--
-- TOC entry 5467 (class 0 OID 0)
-- Dependencies: 246
-- Name: usuario_id_usuario_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.usuario_id_usuario_seq', 13, true);


--
-- TOC entry 5468 (class 0 OID 0)
-- Dependencies: 231
-- Name: zona_id_zona_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.zona_id_zona_seq', 2, true);


--
-- TOC entry 5114 (class 2606 OID 18115)
-- Name: acceso_puerta_log acceso_puerta_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.acceso_puerta_log
    ADD CONSTRAINT acceso_puerta_log_pkey PRIMARY KEY (id_acceso_puerta_log);


--
-- TOC entry 5116 (class 2606 OID 18139)
-- Name: admin_operacion_audit admin_operacion_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.admin_operacion_audit
    ADD CONSTRAINT admin_operacion_audit_pkey PRIMARY KEY (id_admin_operacion_audit);


--
-- TOC entry 5082 (class 2606 OID 17853)
-- Name: asiento asiento_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.asiento
    ADD CONSTRAINT asiento_pkey PRIMARY KEY (id_asiento);


--
-- TOC entry 5124 (class 2606 OID 18251)
-- Name: boleto boleto_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.boleto
    ADD CONSTRAINT boleto_pkey PRIMARY KEY (id_boleto);


--
-- TOC entry 5068 (class 2606 OID 17789)
-- Name: categoria_entrada categoria_entrada_nombre_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categoria_entrada
    ADD CONSTRAINT categoria_entrada_nombre_key UNIQUE (nombre);


--
-- TOC entry 5070 (class 2606 OID 17787)
-- Name: categoria_entrada categoria_entrada_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categoria_entrada
    ADD CONSTRAINT categoria_entrada_pkey PRIMARY KEY (id_categoria_entrada);


--
-- TOC entry 5060 (class 2606 OID 17749)
-- Name: cine cine_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cine
    ADD CONSTRAINT cine_pkey PRIMARY KEY (id_cine);


--
-- TOC entry 5120 (class 2606 OID 18207)
-- Name: compra_detalle compra_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.compra_detalle
    ADD CONSTRAINT compra_detalle_pkey PRIMARY KEY (id_compra_detalle);


--
-- TOC entry 5118 (class 2606 OID 18173)
-- Name: compra compra_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.compra
    ADD CONSTRAINT compra_pkey PRIMARY KEY (id_compra);


--
-- TOC entry 5086 (class 2606 OID 17875)
-- Name: funcion funcion_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.funcion
    ADD CONSTRAINT funcion_pkey PRIMARY KEY (id_funcion);


--
-- TOC entry 5092 (class 2606 OID 17943)
-- Name: funcion_promocion funcion_promocion_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.funcion_promocion
    ADD CONSTRAINT funcion_promocion_pkey PRIMARY KEY (id_funcion, id_promocion);


--
-- TOC entry 5064 (class 2606 OID 17776)
-- Name: genero genero_nombre_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.genero
    ADD CONSTRAINT genero_nombre_key UNIQUE (nombre);


--
-- TOC entry 5066 (class 2606 OID 17774)
-- Name: genero genero_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.genero
    ADD CONSTRAINT genero_pkey PRIMARY KEY (id_genero);


--
-- TOC entry 5090 (class 2606 OID 17926)
-- Name: pelicula_genero pelicula_genero_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pelicula_genero
    ADD CONSTRAINT pelicula_genero_pkey PRIMARY KEY (id_pelicula, id_genero);


--
-- TOC entry 5062 (class 2606 OID 17765)
-- Name: pelicula pelicula_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pelicula
    ADD CONSTRAINT pelicula_pkey PRIMARY KEY (id_pelicula);


--
-- TOC entry 5130 (class 2606 OID 18289)
-- Name: politica_negocio politica_negocio_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.politica_negocio
    ADD CONSTRAINT politica_negocio_pkey PRIMARY KEY (clave);


--
-- TOC entry 5098 (class 2606 OID 17990)
-- Name: promocion_categoria promocion_categoria_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promocion_categoria
    ADD CONSTRAINT promocion_categoria_pkey PRIMARY KEY (id_promocion, id_categoria_entrada);


--
-- TOC entry 5094 (class 2606 OID 17961)
-- Name: promocion_dia promocion_dia_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promocion_dia
    ADD CONSTRAINT promocion_dia_pkey PRIMARY KEY (id_promocion, dia_semana);


--
-- TOC entry 5072 (class 2606 OID 17807)
-- Name: promocion promocion_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promocion
    ADD CONSTRAINT promocion_pkey PRIMARY KEY (id_promocion);


--
-- TOC entry 5096 (class 2606 OID 17973)
-- Name: promocion_zona promocion_zona_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promocion_zona
    ADD CONSTRAINT promocion_zona_pkey PRIMARY KEY (id_promocion, id_zona);


--
-- TOC entry 5100 (class 2606 OID 18020)
-- Name: rol rol_nombre_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rol
    ADD CONSTRAINT rol_nombre_key UNIQUE (nombre);


--
-- TOC entry 5108 (class 2606 OID 18054)
-- Name: rol_permiso rol_permiso_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rol_permiso
    ADD CONSTRAINT rol_permiso_pkey PRIMARY KEY (id_rol, accion);


--
-- TOC entry 5102 (class 2606 OID 18018)
-- Name: rol rol_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rol
    ADD CONSTRAINT rol_pkey PRIMARY KEY (id_rol);


--
-- TOC entry 5074 (class 2606 OID 17817)
-- Name: sala sala_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sala
    ADD CONSTRAINT sala_pkey PRIMARY KEY (id_sala);


--
-- TOC entry 5112 (class 2606 OID 18096)
-- Name: solicitud_reembolso_detalle solicitud_reembolso_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.solicitud_reembolso_detalle
    ADD CONSTRAINT solicitud_reembolso_detalle_pkey PRIMARY KEY (id_solicitud_reembolso, id_boleto);


--
-- TOC entry 5110 (class 2606 OID 18079)
-- Name: solicitud_reembolso solicitud_reembolso_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.solicitud_reembolso
    ADD CONSTRAINT solicitud_reembolso_pkey PRIMARY KEY (id_solicitud_reembolso);


--
-- TOC entry 5088 (class 2606 OID 17904)
-- Name: tarifa tarifa_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tarifa
    ADD CONSTRAINT tarifa_pkey PRIMARY KEY (id_tarifa);


--
-- TOC entry 5084 (class 2606 OID 17855)
-- Name: asiento uq_asiento_ubicacion; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.asiento
    ADD CONSTRAINT uq_asiento_ubicacion UNIQUE (id_zona, fila, numero);


--
-- TOC entry 5126 (class 2606 OID 18255)
-- Name: boleto uq_boleto_detalle; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.boleto
    ADD CONSTRAINT uq_boleto_detalle UNIQUE (id_compra_detalle);


--
-- TOC entry 5128 (class 2606 OID 18253)
-- Name: boleto uq_boleto_token; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.boleto
    ADD CONSTRAINT uq_boleto_token UNIQUE (token_qr);


--
-- TOC entry 5122 (class 2606 OID 18209)
-- Name: compra_detalle uq_cd_asiento; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.compra_detalle
    ADD CONSTRAINT uq_cd_asiento UNIQUE (id_compra, id_asiento);


--
-- TOC entry 5076 (class 2606 OID 17819)
-- Name: sala uq_sala_nombre; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sala
    ADD CONSTRAINT uq_sala_nombre UNIQUE (id_cine, nombre);


--
-- TOC entry 5104 (class 2606 OID 18042)
-- Name: usuario uq_usuario_correo; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT uq_usuario_correo UNIQUE (correo);


--
-- TOC entry 5078 (class 2606 OID 17836)
-- Name: zona uq_zona_nombre; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.zona
    ADD CONSTRAINT uq_zona_nombre UNIQUE (id_sala, nombre);


--
-- TOC entry 5106 (class 2606 OID 18040)
-- Name: usuario usuario_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_pkey PRIMARY KEY (id_usuario);


--
-- TOC entry 5080 (class 2606 OID 17834)
-- Name: zona zona_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.zona
    ADD CONSTRAINT zona_pkey PRIMARY KEY (id_zona);


--
-- TOC entry 5200 (class 2620 OID 18147)
-- Name: admin_operacion_audit trg_admin_audit_inmutable; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_admin_audit_inmutable BEFORE DELETE OR UPDATE ON public.admin_operacion_audit FOR EACH ROW EXECUTE FUNCTION public.bloquear_modificacion_log();


--
-- TOC entry 5201 (class 2620 OID 18152)
-- Name: admin_operacion_audit trg_admin_audit_sin_truncate; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_admin_audit_sin_truncate BEFORE TRUNCATE ON public.admin_operacion_audit FOR EACH STATEMENT EXECUTE FUNCTION public.bloquear_truncate_log();


--
-- TOC entry 5179 (class 2620 OID 18326)
-- Name: asiento trg_auditar_cambio; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auditar_cambio AFTER INSERT OR DELETE OR UPDATE ON public.asiento FOR EACH ROW EXECUTE FUNCTION public.auditar_cambio_critico('id_asiento');


--
-- TOC entry 5170 (class 2620 OID 18330)
-- Name: categoria_entrada trg_auditar_cambio; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auditar_cambio AFTER INSERT OR DELETE OR UPDATE ON public.categoria_entrada FOR EACH ROW EXECUTE FUNCTION public.auditar_cambio_critico('id_categoria_entrada');


--
-- TOC entry 5181 (class 2620 OID 18327)
-- Name: funcion trg_auditar_cambio; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auditar_cambio AFTER INSERT OR DELETE OR UPDATE ON public.funcion FOR EACH ROW EXECUTE FUNCTION public.auditar_cambio_critico('id_funcion');


--
-- TOC entry 5172 (class 2620 OID 18329)
-- Name: promocion trg_auditar_cambio; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auditar_cambio AFTER INSERT OR DELETE OR UPDATE ON public.promocion FOR EACH ROW EXECUTE FUNCTION public.auditar_cambio_critico('id_promocion');


--
-- TOC entry 5174 (class 2620 OID 18324)
-- Name: sala trg_auditar_cambio; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auditar_cambio AFTER INSERT OR DELETE OR UPDATE ON public.sala FOR EACH ROW EXECUTE FUNCTION public.auditar_cambio_critico('id_sala');


--
-- TOC entry 5185 (class 2620 OID 18328)
-- Name: tarifa trg_auditar_cambio; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auditar_cambio AFTER INSERT OR DELETE OR UPDATE ON public.tarifa FOR EACH ROW EXECUTE FUNCTION public.auditar_cambio_critico('id_tarifa');


--
-- TOC entry 5194 (class 2620 OID 18332)
-- Name: usuario trg_auditar_cambio; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auditar_cambio AFTER DELETE OR UPDATE OF id_rol, activo ON public.usuario FOR EACH ROW EXECUTE FUNCTION public.auditar_cambio_critico('id_usuario');


--
-- TOC entry 5176 (class 2620 OID 18325)
-- Name: zona trg_auditar_cambio; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_auditar_cambio AFTER INSERT OR DELETE OR UPDATE ON public.zona FOR EACH ROW EXECUTE FUNCTION public.auditar_cambio_critico('id_zona');


--
-- TOC entry 5195 (class 2620 OID 18333)
-- Name: usuario trg_guardia_alta_usuario; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guardia_alta_usuario BEFORE INSERT ON public.usuario FOR EACH ROW EXECUTE FUNCTION public.guardia_alta_usuario();


--
-- TOC entry 5180 (class 2620 OID 18315)
-- Name: asiento trg_guardia_rbac; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guardia_rbac BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.asiento FOR EACH STATEMENT EXECUTE FUNCTION public.guardia_rbac('gestionar_catalogo');


--
-- TOC entry 5171 (class 2620 OID 18323)
-- Name: categoria_entrada trg_guardia_rbac; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guardia_rbac BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.categoria_entrada FOR EACH STATEMENT EXECUTE FUNCTION public.guardia_rbac('configurar_tarifas');


--
-- TOC entry 5167 (class 2620 OID 18312)
-- Name: cine trg_guardia_rbac; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guardia_rbac BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.cine FOR EACH STATEMENT EXECUTE FUNCTION public.guardia_rbac('gestionar_catalogo');


--
-- TOC entry 5182 (class 2620 OID 18316)
-- Name: funcion trg_guardia_rbac; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guardia_rbac BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.funcion FOR EACH STATEMENT EXECUTE FUNCTION public.guardia_rbac('gestionar_catalogo');


--
-- TOC entry 5190 (class 2620 OID 18322)
-- Name: funcion_promocion trg_guardia_rbac; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guardia_rbac BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.funcion_promocion FOR EACH STATEMENT EXECUTE FUNCTION public.guardia_rbac('configurar_tarifas');


--
-- TOC entry 5169 (class 2620 OID 18310)
-- Name: genero trg_guardia_rbac; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guardia_rbac BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.genero FOR EACH STATEMENT EXECUTE FUNCTION public.guardia_rbac('gestionar_catalogo');


--
-- TOC entry 5168 (class 2620 OID 18309)
-- Name: pelicula trg_guardia_rbac; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guardia_rbac BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.pelicula FOR EACH STATEMENT EXECUTE FUNCTION public.guardia_rbac('gestionar_catalogo');


--
-- TOC entry 5189 (class 2620 OID 18311)
-- Name: pelicula_genero trg_guardia_rbac; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guardia_rbac BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.pelicula_genero FOR EACH STATEMENT EXECUTE FUNCTION public.guardia_rbac('gestionar_catalogo');


--
-- TOC entry 5173 (class 2620 OID 18318)
-- Name: promocion trg_guardia_rbac; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guardia_rbac BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.promocion FOR EACH STATEMENT EXECUTE FUNCTION public.guardia_rbac('configurar_tarifas');


--
-- TOC entry 5193 (class 2620 OID 18321)
-- Name: promocion_categoria trg_guardia_rbac; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guardia_rbac BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.promocion_categoria FOR EACH STATEMENT EXECUTE FUNCTION public.guardia_rbac('configurar_tarifas');


--
-- TOC entry 5191 (class 2620 OID 18319)
-- Name: promocion_dia trg_guardia_rbac; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guardia_rbac BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.promocion_dia FOR EACH STATEMENT EXECUTE FUNCTION public.guardia_rbac('configurar_tarifas');


--
-- TOC entry 5192 (class 2620 OID 18320)
-- Name: promocion_zona trg_guardia_rbac; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guardia_rbac BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.promocion_zona FOR EACH STATEMENT EXECUTE FUNCTION public.guardia_rbac('configurar_tarifas');


--
-- TOC entry 5175 (class 2620 OID 18313)
-- Name: sala trg_guardia_rbac; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guardia_rbac BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.sala FOR EACH STATEMENT EXECUTE FUNCTION public.guardia_rbac('gestionar_catalogo');


--
-- TOC entry 5186 (class 2620 OID 18317)
-- Name: tarifa trg_guardia_rbac; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guardia_rbac BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.tarifa FOR EACH STATEMENT EXECUTE FUNCTION public.guardia_rbac('configurar_tarifas');


--
-- TOC entry 5196 (class 2620 OID 18331)
-- Name: usuario trg_guardia_rbac; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guardia_rbac BEFORE DELETE OR UPDATE OF id_rol, activo OR TRUNCATE ON public.usuario FOR EACH STATEMENT EXECUTE FUNCTION public.guardia_rbac('administrar_usuarios');


--
-- TOC entry 5177 (class 2620 OID 18314)
-- Name: zona trg_guardia_rbac; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_guardia_rbac BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.zona FOR EACH STATEMENT EXECUTE FUNCTION public.guardia_rbac('gestionar_catalogo');


--
-- TOC entry 5183 (class 2620 OID 18004)
-- Name: funcion trg_proteger_sala_funcion; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_proteger_sala_funcion BEFORE UPDATE OF id_sala ON public.funcion FOR EACH ROW EXECUTE FUNCTION public.proteger_sala_con_tarifas();


--
-- TOC entry 5178 (class 2620 OID 18005)
-- Name: zona trg_proteger_sala_zona; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_proteger_sala_zona BEFORE UPDATE OF id_sala ON public.zona FOR EACH ROW EXECUTE FUNCTION public.proteger_sala_con_tarifas();


--
-- TOC entry 5198 (class 2620 OID 18146)
-- Name: acceso_puerta_log trg_puerta_log_inmutable; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_puerta_log_inmutable BEFORE DELETE OR UPDATE ON public.acceso_puerta_log FOR EACH ROW EXECUTE FUNCTION public.bloquear_modificacion_log();


--
-- TOC entry 5199 (class 2620 OID 18151)
-- Name: acceso_puerta_log trg_puerta_log_sin_truncate; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_puerta_log_sin_truncate BEFORE TRUNCATE ON public.acceso_puerta_log FOR EACH STATEMENT EXECUTE FUNCTION public.bloquear_truncate_log();


--
-- TOC entry 5197 (class 2620 OID 18272)
-- Name: solicitud_reembolso_detalle trg_validar_boleto_solicitud; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_boleto_solicitud BEFORE INSERT OR UPDATE ON public.solicitud_reembolso_detalle FOR EACH ROW EXECUTE FUNCTION public.validar_boleto_de_solicitud();


--
-- TOC entry 5184 (class 2620 OID 18007)
-- Name: funcion trg_validar_horario_funcion; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_horario_funcion BEFORE INSERT OR UPDATE OF id_sala, inicio, fin, activa ON public.funcion FOR EACH ROW EXECUTE FUNCTION public.validar_horario_funcion();


--
-- TOC entry 5187 (class 2620 OID 18009)
-- Name: tarifa trg_validar_vigencia_tarifa; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_vigencia_tarifa BEFORE INSERT OR UPDATE ON public.tarifa FOR EACH ROW EXECUTE FUNCTION public.validar_vigencia_tarifa();


--
-- TOC entry 5188 (class 2620 OID 18002)
-- Name: tarifa trg_validar_zona_tarifa; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_validar_zona_tarifa BEFORE INSERT OR UPDATE OF id_funcion, id_zona ON public.tarifa FOR EACH ROW EXECUTE FUNCTION public.validar_zona_tarifa();


--
-- TOC entry 5133 (class 2606 OID 17856)
-- Name: asiento fk_asiento_zona; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.asiento
    ADD CONSTRAINT fk_asiento_zona FOREIGN KEY (id_zona) REFERENCES public.zona(id_zona);


--
-- TOC entry 5157 (class 2606 OID 18140)
-- Name: admin_operacion_audit fk_audit_actor; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.admin_operacion_audit
    ADD CONSTRAINT fk_audit_actor FOREIGN KEY (id_usuario_actor) REFERENCES public.usuario(id_usuario);


--
-- TOC entry 5166 (class 2606 OID 18256)
-- Name: boleto fk_boleto_detalle; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.boleto
    ADD CONSTRAINT fk_boleto_detalle FOREIGN KEY (id_compra_detalle) REFERENCES public.compra_detalle(id_compra_detalle);


--
-- TOC entry 5161 (class 2606 OID 18215)
-- Name: compra_detalle fk_cd_asiento; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.compra_detalle
    ADD CONSTRAINT fk_cd_asiento FOREIGN KEY (id_asiento) REFERENCES public.asiento(id_asiento);


--
-- TOC entry 5162 (class 2606 OID 18220)
-- Name: compra_detalle fk_cd_categoria; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.compra_detalle
    ADD CONSTRAINT fk_cd_categoria FOREIGN KEY (id_categoria_entrada) REFERENCES public.categoria_entrada(id_categoria_entrada);


--
-- TOC entry 5163 (class 2606 OID 18210)
-- Name: compra_detalle fk_cd_compra; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.compra_detalle
    ADD CONSTRAINT fk_cd_compra FOREIGN KEY (id_compra) REFERENCES public.compra(id_compra);


--
-- TOC entry 5164 (class 2606 OID 18230)
-- Name: compra_detalle fk_cd_promocion; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.compra_detalle
    ADD CONSTRAINT fk_cd_promocion FOREIGN KEY (id_promocion) REFERENCES public.promocion(id_promocion);


--
-- TOC entry 5165 (class 2606 OID 18225)
-- Name: compra_detalle fk_cd_tarifa; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.compra_detalle
    ADD CONSTRAINT fk_cd_tarifa FOREIGN KEY (id_tarifa) REFERENCES public.tarifa(id_tarifa);


--
-- TOC entry 5158 (class 2606 OID 18179)
-- Name: compra fk_compra_actor; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.compra
    ADD CONSTRAINT fk_compra_actor FOREIGN KEY (id_usuario_actor) REFERENCES public.usuario(id_usuario);


--
-- TOC entry 5159 (class 2606 OID 18174)
-- Name: compra fk_compra_cliente; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.compra
    ADD CONSTRAINT fk_compra_cliente FOREIGN KEY (id_usuario_cliente) REFERENCES public.usuario(id_usuario);


--
-- TOC entry 5160 (class 2606 OID 18184)
-- Name: compra fk_compra_funcion; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.compra
    ADD CONSTRAINT fk_compra_funcion FOREIGN KEY (id_funcion) REFERENCES public.funcion(id_funcion);


--
-- TOC entry 5134 (class 2606 OID 17876)
-- Name: funcion fk_funcion_pelicula; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.funcion
    ADD CONSTRAINT fk_funcion_pelicula FOREIGN KEY (id_pelicula) REFERENCES public.pelicula(id_pelicula);


--
-- TOC entry 5141 (class 2606 OID 17944)
-- Name: funcion_promocion fk_funcion_promocion_funcion; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.funcion_promocion
    ADD CONSTRAINT fk_funcion_promocion_funcion FOREIGN KEY (id_funcion) REFERENCES public.funcion(id_funcion);


--
-- TOC entry 5142 (class 2606 OID 17949)
-- Name: funcion_promocion fk_funcion_promocion_promocion; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.funcion_promocion
    ADD CONSTRAINT fk_funcion_promocion_promocion FOREIGN KEY (id_promocion) REFERENCES public.promocion(id_promocion);


--
-- TOC entry 5135 (class 2606 OID 17881)
-- Name: funcion fk_funcion_sala; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.funcion
    ADD CONSTRAINT fk_funcion_sala FOREIGN KEY (id_sala) REFERENCES public.sala(id_sala);


--
-- TOC entry 5139 (class 2606 OID 17932)
-- Name: pelicula_genero fk_pelicula_genero_genero; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pelicula_genero
    ADD CONSTRAINT fk_pelicula_genero_genero FOREIGN KEY (id_genero) REFERENCES public.genero(id_genero);


--
-- TOC entry 5140 (class 2606 OID 17927)
-- Name: pelicula_genero fk_pelicula_genero_pelicula; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pelicula_genero
    ADD CONSTRAINT fk_pelicula_genero_pelicula FOREIGN KEY (id_pelicula) REFERENCES public.pelicula(id_pelicula);


--
-- TOC entry 5146 (class 2606 OID 17996)
-- Name: promocion_categoria fk_promocion_categoria_categoria; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promocion_categoria
    ADD CONSTRAINT fk_promocion_categoria_categoria FOREIGN KEY (id_categoria_entrada) REFERENCES public.categoria_entrada(id_categoria_entrada);


--
-- TOC entry 5147 (class 2606 OID 17991)
-- Name: promocion_categoria fk_promocion_categoria_promocion; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promocion_categoria
    ADD CONSTRAINT fk_promocion_categoria_promocion FOREIGN KEY (id_promocion) REFERENCES public.promocion(id_promocion);


--
-- TOC entry 5143 (class 2606 OID 17962)
-- Name: promocion_dia fk_promocion_dia_promocion; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promocion_dia
    ADD CONSTRAINT fk_promocion_dia_promocion FOREIGN KEY (id_promocion) REFERENCES public.promocion(id_promocion);


--
-- TOC entry 5144 (class 2606 OID 17974)
-- Name: promocion_zona fk_promocion_zona_promocion; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promocion_zona
    ADD CONSTRAINT fk_promocion_zona_promocion FOREIGN KEY (id_promocion) REFERENCES public.promocion(id_promocion);


--
-- TOC entry 5145 (class 2606 OID 17979)
-- Name: promocion_zona fk_promocion_zona_zona; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promocion_zona
    ADD CONSTRAINT fk_promocion_zona_zona FOREIGN KEY (id_zona) REFERENCES public.zona(id_zona);


--
-- TOC entry 5155 (class 2606 OID 18340)
-- Name: acceso_puerta_log fk_puerta_boleto; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.acceso_puerta_log
    ADD CONSTRAINT fk_puerta_boleto FOREIGN KEY (id_boleto) REFERENCES public.boleto(id_boleto);


--
-- TOC entry 5156 (class 2606 OID 18116)
-- Name: acceso_puerta_log fk_puerta_operador; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.acceso_puerta_log
    ADD CONSTRAINT fk_puerta_operador FOREIGN KEY (id_usuario_operador) REFERENCES public.usuario(id_usuario);


--
-- TOC entry 5149 (class 2606 OID 18055)
-- Name: rol_permiso fk_rol_permiso_rol; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rol_permiso
    ADD CONSTRAINT fk_rol_permiso_rol FOREIGN KEY (id_rol) REFERENCES public.rol(id_rol);


--
-- TOC entry 5131 (class 2606 OID 17820)
-- Name: sala fk_sala_cine; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sala
    ADD CONSTRAINT fk_sala_cine FOREIGN KEY (id_cine) REFERENCES public.cine(id_cine);


--
-- TOC entry 5150 (class 2606 OID 18080)
-- Name: solicitud_reembolso fk_solicitud_actor; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.solicitud_reembolso
    ADD CONSTRAINT fk_solicitud_actor FOREIGN KEY (id_usuario_actor) REFERENCES public.usuario(id_usuario);


--
-- TOC entry 5151 (class 2606 OID 18261)
-- Name: solicitud_reembolso fk_solicitud_compra; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.solicitud_reembolso
    ADD CONSTRAINT fk_solicitud_compra FOREIGN KEY (id_compra) REFERENCES public.compra(id_compra);


--
-- TOC entry 5152 (class 2606 OID 18085)
-- Name: solicitud_reembolso fk_solicitud_resuelve; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.solicitud_reembolso
    ADD CONSTRAINT fk_solicitud_resuelve FOREIGN KEY (id_usuario_resuelve) REFERENCES public.usuario(id_usuario);


--
-- TOC entry 5153 (class 2606 OID 18266)
-- Name: solicitud_reembolso_detalle fk_srd_boleto; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.solicitud_reembolso_detalle
    ADD CONSTRAINT fk_srd_boleto FOREIGN KEY (id_boleto) REFERENCES public.boleto(id_boleto);


--
-- TOC entry 5154 (class 2606 OID 18097)
-- Name: solicitud_reembolso_detalle fk_srd_solicitud; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.solicitud_reembolso_detalle
    ADD CONSTRAINT fk_srd_solicitud FOREIGN KEY (id_solicitud_reembolso) REFERENCES public.solicitud_reembolso(id_solicitud_reembolso);


--
-- TOC entry 5136 (class 2606 OID 17915)
-- Name: tarifa fk_tarifa_categoria; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tarifa
    ADD CONSTRAINT fk_tarifa_categoria FOREIGN KEY (id_categoria_entrada) REFERENCES public.categoria_entrada(id_categoria_entrada);


--
-- TOC entry 5137 (class 2606 OID 17905)
-- Name: tarifa fk_tarifa_funcion; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tarifa
    ADD CONSTRAINT fk_tarifa_funcion FOREIGN KEY (id_funcion) REFERENCES public.funcion(id_funcion);


--
-- TOC entry 5138 (class 2606 OID 17910)
-- Name: tarifa fk_tarifa_zona; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tarifa
    ADD CONSTRAINT fk_tarifa_zona FOREIGN KEY (id_zona) REFERENCES public.zona(id_zona);


--
-- TOC entry 5148 (class 2606 OID 18043)
-- Name: usuario fk_usuario_rol; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT fk_usuario_rol FOREIGN KEY (id_rol) REFERENCES public.rol(id_rol);


--
-- TOC entry 5132 (class 2606 OID 17837)
-- Name: zona fk_zona_sala; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.zona
    ADD CONSTRAINT fk_zona_sala FOREIGN KEY (id_sala) REFERENCES public.sala(id_sala);


--
-- TOC entry 5398 (class 0 OID 0)
-- Dependencies: 298
-- Name: FUNCTION asiento_ocupado(p_id_funcion integer, p_id_asiento integer, p_excluir_detalle integer); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.asiento_ocupado(p_id_funcion integer, p_id_asiento integer, p_excluir_detalle integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.asiento_ocupado(p_id_funcion integer, p_id_asiento integer, p_excluir_detalle integer) TO imax_app;


--
-- TOC entry 5399 (class 0 OID 0)
-- Dependencies: 290
-- Name: FUNCTION auditar_accion(p_id_usuario_actor integer, p_ip text, p_accion text, p_entidad text, p_id_entidad text, p_motivo text, p_cambios jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.auditar_accion(p_id_usuario_actor integer, p_ip text, p_accion text, p_entidad text, p_id_entidad text, p_motivo text, p_cambios jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.auditar_accion(p_id_usuario_actor integer, p_ip text, p_accion text, p_entidad text, p_id_entidad text, p_motivo text, p_cambios jsonb) TO imax_app;


--
-- TOC entry 5400 (class 0 OID 0)
-- Dependencies: 277
-- Name: FUNCTION autorizar_accion(p_id_usuario integer, p_accion text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.autorizar_accion(p_id_usuario integer, p_accion text) TO imax_app;


--
-- TOC entry 5402 (class 0 OID 0)
-- Dependencies: 296
-- Name: FUNCTION cambiar_asiento_boleto(p_id_usuario_admin integer, p_id_boleto integer, p_id_asiento_nuevo integer, p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.cambiar_asiento_boleto(p_id_usuario_admin integer, p_id_boleto integer, p_id_asiento_nuevo integer, p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cambiar_asiento_boleto(p_id_usuario_admin integer, p_id_boleto integer, p_id_asiento_nuevo integer, p_motivo text, p_ip text) TO imax_app;


--
-- TOC entry 5403 (class 0 OID 0)
-- Dependencies: 294
-- Name: FUNCTION cambiar_politica(p_id_usuario integer, p_clave text, p_valor integer, p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.cambiar_politica(p_id_usuario integer, p_clave text, p_valor integer, p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cambiar_politica(p_id_usuario integer, p_clave text, p_valor integer, p_motivo text, p_ip text) TO imax_app;


--
-- TOC entry 5404 (class 0 OID 0)
-- Dependencies: 269
-- Name: FUNCTION normalizar_ip(p_ip text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.normalizar_ip(p_ip text) TO imax_app;


--
-- TOC entry 5406 (class 0 OID 0)
-- Dependencies: 255
-- Name: TABLE admin_operacion_audit; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE public.admin_operacion_audit TO imax_app;


--
-- TOC entry 5407 (class 0 OID 0)
-- Dependencies: 295
-- Name: FUNCTION consultar_auditoria_admin(p_id_usuario integer, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_id_actor integer, p_accion text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.consultar_auditoria_admin(p_id_usuario integer, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_id_actor integer, p_accion text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.consultar_auditoria_admin(p_id_usuario integer, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_id_actor integer, p_accion text) TO imax_app;


--
-- TOC entry 5408 (class 0 OID 0)
-- Dependencies: 291
-- Name: FUNCTION exigir_permiso(p_id_usuario integer, p_accion text, p_ip text, p_entidad text, p_id_entidad text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.exigir_permiso(p_id_usuario integer, p_accion text, p_ip text, p_entidad text, p_id_entidad text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.exigir_permiso(p_id_usuario integer, p_accion text, p_ip text, p_entidad text, p_id_entidad text) TO imax_app;


--
-- TOC entry 5410 (class 0 OID 0)
-- Dependencies: 271
-- Name: FUNCTION otorgar_cortesia(p_id_usuario_admin integer, p_id_funcion integer, p_id_asiento integer, p_id_cliente integer, p_id_categoria integer, p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.otorgar_cortesia(p_id_usuario_admin integer, p_id_funcion integer, p_id_asiento integer, p_id_cliente integer, p_id_categoria integer, p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.otorgar_cortesia(p_id_usuario_admin integer, p_id_funcion integer, p_id_asiento integer, p_id_cliente integer, p_id_categoria integer, p_motivo text, p_ip text) TO imax_app;


--
-- TOC entry 5411 (class 0 OID 0)
-- Dependencies: 270
-- Name: FUNCTION politica_entero(p_clave text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.politica_entero(p_clave text) TO imax_app;


--
-- TOC entry 5413 (class 0 OID 0)
-- Dependencies: 293
-- Name: FUNCTION resolver_reembolso(p_id_usuario_admin integer, p_id_solicitud integer, p_decision text, p_motivo text, p_ip text, p_forzar boolean); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.resolver_reembolso(p_id_usuario_admin integer, p_id_solicitud integer, p_decision text, p_motivo text, p_ip text, p_forzar boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.resolver_reembolso(p_id_usuario_admin integer, p_id_solicitud integer, p_decision text, p_motivo text, p_ip text, p_forzar boolean) TO imax_app;


--
-- TOC entry 5415 (class 0 OID 0)
-- Dependencies: 297
-- Name: FUNCTION resumen_auditoria_admin(p_id_usuario integer, p_desde timestamp with time zone, p_hasta timestamp with time zone); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.resumen_auditoria_admin(p_id_usuario integer, p_desde timestamp with time zone, p_hasta timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.resumen_auditoria_admin(p_id_usuario integer, p_desde timestamp with time zone, p_hasta timestamp with time zone) TO imax_app;


--
-- TOC entry 5416 (class 0 OID 0)
-- Dependencies: 289
-- Name: FUNCTION revertir_venta(p_id_solicitud_reembolso integer, p_referencia text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.revertir_venta(p_id_solicitud_reembolso integer, p_referencia text) FROM PUBLIC;


--
-- TOC entry 5418 (class 0 OID 0)
-- Dependencies: 292
-- Name: FUNCTION solicitar_reembolso(p_id_usuario_actor integer, p_id_compra integer, p_ids_boleto integer[], p_motivo text, p_ip text); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.solicitar_reembolso(p_id_usuario_actor integer, p_id_compra integer, p_ids_boleto integer[], p_motivo text, p_ip text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.solicitar_reembolso(p_id_usuario_actor integer, p_id_compra integer, p_ids_boleto integer[], p_motivo text, p_ip text) TO imax_app;


--
-- TOC entry 5419 (class 0 OID 0)
-- Dependencies: 284
-- Name: FUNCTION validar_y_consumir_ingreso_qr(p_token_qr uuid, p_id_funcion_solicitada integer, p_id_usuario_operador integer, p_dispositivo character varying); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.validar_y_consumir_ingreso_qr(p_token_qr uuid, p_id_funcion_solicitada integer, p_id_usuario_operador integer, p_dispositivo character varying) TO imax_app;


--
-- TOC entry 5421 (class 0 OID 0)
-- Dependencies: 253
-- Name: TABLE acceso_puerta_log; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE public.acceso_puerta_log TO imax_app;


--
-- TOC entry 5423 (class 0 OID 0)
-- Dependencies: 252
-- Name: SEQUENCE acceso_puerta_log_id_acceso_puerta_log_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT USAGE ON SEQUENCE public.acceso_puerta_log_id_acceso_puerta_log_seq TO imax_app;


--
-- TOC entry 5425 (class 0 OID 0)
-- Dependencies: 254
-- Name: SEQUENCE admin_operacion_audit_id_admin_operacion_audit_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT USAGE ON SEQUENCE public.admin_operacion_audit_id_admin_operacion_audit_seq TO imax_app;


--
-- TOC entry 5436 (class 0 OID 0)
-- Dependencies: 262
-- Name: TABLE politica_negocio; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.politica_negocio TO imax_app;


--
-- TOC entry 5438 (class 0 OID 0)
-- Dependencies: 245
-- Name: TABLE rol; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.rol TO imax_app;


--
-- TOC entry 5440 (class 0 OID 0)
-- Dependencies: 248
-- Name: TABLE rol_permiso; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.rol_permiso TO imax_app;


--
-- TOC entry 5442 (class 0 OID 0)
-- Dependencies: 250
-- Name: TABLE solicitud_reembolso; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.solicitud_reembolso TO imax_app;


--
-- TOC entry 5443 (class 0 OID 0)
-- Dependencies: 251
-- Name: TABLE solicitud_reembolso_detalle; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE public.solicitud_reembolso_detalle TO imax_app;


--
-- TOC entry 5445 (class 0 OID 0)
-- Dependencies: 249
-- Name: SEQUENCE solicitud_reembolso_id_solicitud_reembolso_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT USAGE ON SEQUENCE public.solicitud_reembolso_id_solicitud_reembolso_seq TO imax_app;


--
-- TOC entry 5447 (class 0 OID 0)
-- Dependencies: 247
-- Name: TABLE usuario; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.usuario TO imax_app;


--
-- TOC entry 5449 (class 0 OID 0)
-- Dependencies: 246
-- Name: SEQUENCE usuario_id_usuario_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT USAGE ON SEQUENCE public.usuario_id_usuario_seq TO imax_app;


-- Completed on 2026-10-24 00:24:32

--
-- PostgreSQL database dump complete
--

\unrestrict fPjqaYoVIgqp5jt63EZ2cd88xOG0FrrjWc1bXwbJ2TSsx03UfgLrR1JdHZIjg0y

