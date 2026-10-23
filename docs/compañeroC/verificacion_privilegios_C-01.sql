-- Verifica privilegios mínimos y protección de logs. Ejecutar con una cuenta
-- propietaria después de privilegios_C.sql. Todo termina con ROLLBACK.
BEGIN;

DO $$
DECLARE
    v_admin INT := (SELECT id_usuario FROM usuario WHERE correo = 'admin@imax.test');
BEGIN
    -- TRUNCATE bloqueado incluso para el propietario.
    BEGIN
        TRUNCATE admin_operacion_audit;
        RAISE EXCEPTION 'ERROR: se permitió vaciar la auditoría.';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK: TRUNCATE de auditoría rechazado.';
    END;
    BEGIN
        TRUNCATE acceso_puerta_log;
        RAISE EXCEPTION 'ERROR: se permitió vaciar el registro de puerta.';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK: TRUNCATE del registro de puerta rechazado.';
    END;

    -- La cuenta de la aplicación solo puede agregar a los logs.
    SET LOCAL ROLE imax_app;
    INSERT INTO admin_operacion_audit (id_usuario_actor, rol_al_actuar, ip, accion, entidad, motivo)
    VALUES (v_admin, 'administrador', '127.0.0.1', 'prueba', 'rol', 'ensayo');
    BEGIN
        DELETE FROM admin_operacion_audit;
        RAISE EXCEPTION 'ERROR: la aplicación pudo borrar la auditoría.';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK: la aplicación no puede borrar la auditoría.';
    END;
    BEGIN
        UPDATE acceso_puerta_log SET resultado = 'aceptado';
        RAISE EXCEPTION 'ERROR: la aplicación pudo modificar el registro de puerta.';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK: la aplicación no puede modificar el registro de puerta.';
    END;
    BEGIN
        INSERT INTO rol_permiso (id_rol, accion) VALUES (1, 'gestionar_catalogo');
        RAISE EXCEPTION 'ERROR: la aplicación pudo cambiar la matriz de permisos.';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK: la aplicación no puede cambiar la matriz de permisos.';
    END;
    BEGIN
        DELETE FROM usuario WHERE id_usuario = v_admin;
        RAISE EXCEPTION 'ERROR: la aplicación pudo borrar un usuario.';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK: la aplicación no puede borrar usuarios.';
    END;
    IF NOT autorizar_accion(v_admin, 'gestionar_catalogo') THEN
        RAISE EXCEPTION 'ERROR: la aplicación debe poder invocar autorizar_accion.';
    END IF;
    RAISE NOTICE 'OK: la aplicación puede invocar autorizar_accion.';
    RESET ROLE;

    IF (SELECT rolsuper FROM pg_roles WHERE rolname = 'imax_app') THEN
        RAISE EXCEPTION 'ERROR: imax_app es superusuario.';
    END IF;
    RAISE NOTICE 'OK: imax_app no es superusuario.';
END;
$$;

ROLLBACK;
