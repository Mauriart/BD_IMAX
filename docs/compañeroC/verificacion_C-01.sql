-- Verificación de C-01 sobre los datos de ejemplo, sin dejarlos modificados.
-- Ejecutar después de instalacion_completa_A.sql y relacional_C.sql.
-- En psql usar ON_ERROR_STOP=1. En DBeaver, ejecutar el script completo (Alt+X).
-- Cada rechazo se comprueba en un bloque EXCEPTION; todo termina con ROLLBACK.
BEGIN;

DO $$
BEGIN
    -- 22 tablas (15 de A y 7 de C); si se instaló el fixture de B habrá 3 más.
    IF (SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema = 'public' AND table_type = 'BASE TABLE') < 22 THEN
        RAISE EXCEPTION 'Se esperaban al menos 22 tablas en public.';
    END IF;
    IF (SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name IN ('rol','usuario','rol_permiso',
            'solicitud_reembolso','solicitud_reembolso_detalle','acceso_puerta_log',
            'admin_operacion_audit')) <> 7 THEN
        RAISE EXCEPTION 'Faltan tablas de C.';
    END IF;
    IF (SELECT COUNT(*) FROM rol) <> 5 THEN
        RAISE EXCEPTION 'Se esperaban 5 roles.';
    END IF;
    IF (SELECT COUNT(*) FROM usuario) < 7 THEN
        RAISE EXCEPTION 'Se esperaban al menos 7 usuarios.';
    END IF;
    IF (SELECT COUNT(*) FROM rol_permiso) <> 24 THEN
        RAISE EXCEPTION 'Se esperaban 24 permisos.';
    END IF;
    RAISE NOTICE 'OK: tablas de A y C, 5 roles, usuarios y 24 permisos.';
END;
$$;

DO $$
DECLARE
    v_admin INT := (SELECT id_usuario FROM usuario WHERE correo = 'admin@imax.test');
    v_cliente INT := (SELECT id_usuario FROM usuario WHERE correo = 'cliente1@imax.test');
    v_contador INT := (SELECT id_usuario FROM usuario WHERE correo = 'contador@imax.test');
    v_puerta INT := (SELECT id_usuario FROM usuario WHERE correo = 'puerta1@imax.test');
BEGIN
    IF NOT autorizar_accion(v_admin, 'gestionar_catalogo') THEN
        RAISE EXCEPTION 'ERROR: el administrador debe gestionar el catálogo.';
    END IF;
    IF autorizar_accion(v_cliente, 'gestionar_catalogo') THEN
        RAISE EXCEPTION 'ERROR: el cliente no debe gestionar el catálogo.';
    END IF;
    IF NOT autorizar_accion(v_contador, 'ver_auditoria') THEN
        RAISE EXCEPTION 'ERROR: el contador debe ver la auditoría.';
    END IF;
    IF NOT autorizar_accion(v_puerta, 'validar_ingreso') THEN
        RAISE EXCEPTION 'ERROR: el operador debe validar ingresos.';
    END IF;
    IF autorizar_accion(v_puerta, 'resolver_reembolso') THEN
        RAISE EXCEPTION 'ERROR: el operador no debe resolver reembolsos.';
    END IF;
    IF autorizar_accion(-1, 'consultar_cartelera') THEN
        RAISE EXCEPTION 'ERROR: un usuario inexistente no debe tener permisos.';
    END IF;
    IF autorizar_accion(v_admin, 'accion_inexistente') THEN
        RAISE EXCEPTION 'ERROR: una acción desconocida no debe autorizarse.';
    END IF;
    RAISE NOTICE 'OK: autorizar_accion responde según la matriz de roles.';

    -- Un usuario inactivo pierde sus permisos (se revierte con el ROLLBACK final).
    UPDATE usuario SET activo = FALSE WHERE id_usuario = v_admin;
    IF autorizar_accion(v_admin, 'gestionar_catalogo') THEN
        RAISE EXCEPTION 'ERROR: un usuario inactivo no debe tener permisos.';
    END IF;
    UPDATE usuario SET activo = TRUE WHERE id_usuario = v_admin;
    RAISE NOTICE 'OK: un usuario inactivo no obtiene permisos.';
END;
$$;

DO $$
DECLARE
    v_admin INT := (SELECT id_usuario FROM usuario WHERE correo = 'admin@imax.test');
    v_cliente INT := (SELECT id_usuario FROM usuario WHERE correo = 'cliente1@imax.test');
    v_puerta INT := (SELECT id_usuario FROM usuario WHERE correo = 'puerta1@imax.test');
BEGIN
    BEGIN
        INSERT INTO usuario (id_rol, nombre, correo, password_hash)
        VALUES (1, 'Repetido', 'cliente1@imax.test', 'x');
        RAISE EXCEPTION 'ERROR: se aceptó un correo repetido.';
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE 'OK: correo repetido rechazado.';
    END;
    BEGIN
        INSERT INTO usuario (id_rol, nombre, correo, password_hash)
        VALUES (1, 'Mayúsculas', 'CLIENTE9@IMAX.TEST', 'x');
        RAISE EXCEPTION 'ERROR: se aceptó un correo sin normalizar.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: correo sin normalizar rechazado.';
    END;
    BEGIN
        INSERT INTO usuario (id_rol, nombre, correo, password_hash)
        VALUES (-999, 'Sin rol', 'sinrol@imax.test', 'x');
        RAISE EXCEPTION 'ERROR: se aceptó un rol inexistente.';
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE NOTICE 'OK: rol inexistente rechazado.';
    END;
    BEGIN
        INSERT INTO admin_operacion_audit (id_usuario_actor, rol_al_actuar, ip, accion, entidad, motivo)
        VALUES (v_admin, 'administrador', '127.0.0.1', 'prueba', 'rol', ' ');
        RAISE EXCEPTION 'ERROR: se aceptó un motivo vacío.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: motivo vacío de auditoría rechazado.';
    END;

    -- Fila válida; se revierte al final, por lo que no deja residuos.
    INSERT INTO admin_operacion_audit (id_usuario_actor, rol_al_actuar, ip, accion, entidad, motivo)
    VALUES (v_admin, 'administrador', '127.0.0.1', 'prueba', 'rol', 'ensayo');
    BEGIN
        UPDATE admin_operacion_audit SET motivo = 'cambio';
        RAISE EXCEPTION 'ERROR: se permitió modificar la auditoría.';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK: modificación de auditoría rechazada.';
    END;
    BEGIN
        DELETE FROM admin_operacion_audit;
        RAISE EXCEPTION 'ERROR: se permitió borrar la auditoría.';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK: borrado de auditoría rechazado.';
    END;

    BEGIN
        INSERT INTO solicitud_reembolso (id_compra, id_usuario_actor, motivo, estado)
        VALUES (1, v_cliente, 'prueba', 'inventado');
        RAISE EXCEPTION 'ERROR: se aceptó un estado inválido.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: estado de solicitud inválido rechazado.';
    END;
    BEGIN
        INSERT INTO solicitud_reembolso (id_compra, id_usuario_actor, motivo, estado, resuelta_en)
        VALUES (1, v_cliente, 'prueba', 'ejecutada', now());
        RAISE EXCEPTION 'ERROR: se aceptó una solicitud resuelta sin resolutor.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: solicitud resuelta sin resolutor rechazada.';
    END;
    BEGIN
        INSERT INTO solicitud_reembolso (id_compra, id_usuario_actor, motivo, estado, resuelta_en, id_usuario_resuelve)
        VALUES (1, v_cliente, 'prueba', 'pendiente', now(), v_admin);
        RAISE EXCEPTION 'ERROR: se aceptó una solicitud pendiente con resolución.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: solicitud pendiente con resolución rechazada.';
    END;
    BEGIN
        INSERT INTO solicitud_reembolso (id_compra, id_usuario_actor, motivo)
        VALUES (1, v_cliente, ' ');
        RAISE EXCEPTION 'ERROR: se aceptó un motivo vacío en la solicitud.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: motivo vacío de solicitud rechazado.';
    END;
    INSERT INTO solicitud_reembolso (id_compra, id_usuario_actor, motivo)
    VALUES (1, v_cliente, 'Cambio de planes');
    RAISE NOTICE 'OK: solicitud pendiente válida aceptada.';

    BEGIN
        INSERT INTO acceso_puerta_log (id_usuario_operador, dispositivo, resultado)
        VALUES (v_puerta, 'lector-1', 'quizas');
        RAISE EXCEPTION 'ERROR: se aceptó un resultado de puerta inválido.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: resultado de puerta inválido rechazado.';
    END;
    -- Un QR inexistente se registra sin boleto ni función.
    INSERT INTO acceso_puerta_log (id_usuario_operador, dispositivo, resultado, motivo)
    VALUES (v_puerta, 'lector-1', 'rechazado', 'QR inexistente');
    BEGIN
        UPDATE acceso_puerta_log SET resultado = 'aceptado';
        RAISE EXCEPTION 'ERROR: se permitió modificar el registro de puerta.';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK: modificación del registro de puerta rechazada.';
    END;
END;
$$;

ROLLBACK;
