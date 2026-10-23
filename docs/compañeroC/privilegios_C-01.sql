-- Privilegios mínimos de la cuenta de la aplicación y protección de los logs.
-- Ejecutar después de relacional_C.sql con una cuenta propietaria/administradora.
-- Se puede reejecutar. Cubre solo las tablas de C: los privilegios sobre las tablas
-- de A y B los define cada bloque. La cuenta de la aplicación no es superusuario.
BEGIN;

-- Protección contra TRUNCATE de los logs (el trigger por fila no la cubre).
CREATE OR REPLACE FUNCTION bloquear_truncate_log()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Los registros de % no se pueden vaciar.', TG_TABLE_NAME
        USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS trg_puerta_log_sin_truncate ON acceso_puerta_log;
CREATE TRIGGER trg_puerta_log_sin_truncate
BEFORE TRUNCATE ON acceso_puerta_log
FOR EACH STATEMENT EXECUTE FUNCTION bloquear_truncate_log();

DROP TRIGGER IF EXISTS trg_admin_audit_sin_truncate ON admin_operacion_audit;
CREATE TRIGGER trg_admin_audit_sin_truncate
BEFORE TRUNCATE ON admin_operacion_audit
FOR EACH STATEMENT EXECUTE FUNCTION bloquear_truncate_log();

-- Rol técnico de la aplicación. Sin LOGIN: se le asigna a la cuenta real con
-- GRANT imax_app TO <cuenta>. No es superusuario ni crea bases ni roles.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'imax_app') THEN
        CREATE ROLE imax_app NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
    END IF;
END;
$$;

REVOKE ALL ON rol, usuario, rol_permiso, solicitud_reembolso, solicitud_reembolso_detalle,
              acceso_puerta_log, admin_operacion_audit FROM imax_app;

-- Matriz de permisos: la aplicación la consulta, no la cambia.
GRANT SELECT ON rol, rol_permiso TO imax_app;

-- Usuarios: altas y cambios (por el administrador desde la aplicación); sin borrado.
GRANT SELECT, INSERT, UPDATE ON usuario TO imax_app;

-- Solicitudes: crear y resolver; sin borrado.
GRANT SELECT, INSERT, UPDATE ON solicitud_reembolso TO imax_app;
GRANT SELECT, INSERT ON solicitud_reembolso_detalle TO imax_app;

-- Logs: solo agregar y consultar. Sin UPDATE, DELETE ni TRUNCATE.
GRANT SELECT, INSERT ON acceso_puerta_log, admin_operacion_audit TO imax_app;

GRANT USAGE ON SEQUENCE usuario_id_usuario_seq, solicitud_reembolso_id_solicitud_reembolso_seq,
                        acceso_puerta_log_id_acceso_puerta_log_seq,
                        admin_operacion_audit_id_admin_operacion_audit_seq TO imax_app;

GRANT EXECUTE ON FUNCTION autorizar_accion(INT, TEXT) TO imax_app;

COMMIT;
