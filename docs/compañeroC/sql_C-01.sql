-- C-01: identidad, roles, autorización común, auditoría administrativa,
-- registro de puerta y solicitudes de reembolso.
-- Ejecutar DESPUÉS de relacional_A.sql (y sus ajustes). No toca tablas de A.
-- Mismo estilo que A: SERIAL / INT, restricciones con nombre.
BEGIN;

CREATE TABLE rol (
    id_rol SERIAL PRIMARY KEY,
    nombre VARCHAR(30) NOT NULL UNIQUE
);

CREATE TABLE usuario (
    id_usuario SERIAL PRIMARY KEY,
    id_rol INT NOT NULL,
    nombre VARCHAR(100) NOT NULL,
    correo VARCHAR(150) NOT NULL,
    password_hash TEXT NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_usuario_rol FOREIGN KEY (id_rol) REFERENCES rol(id_rol),
    CONSTRAINT uq_usuario_correo UNIQUE (correo),
    CONSTRAINT ck_usuario_correo_normalizado
        CHECK (correo = lower(btrim(correo)) AND correo <> ''),
    CONSTRAINT ck_usuario_nombre CHECK (btrim(nombre) <> '')
);

-- Matriz de permisos (sección 9 de 00_acuerdos.md): un permiso = una acción.
CREATE TABLE rol_permiso (
    id_rol INT NOT NULL,
    accion VARCHAR(60) NOT NULL,
    PRIMARY KEY (id_rol, accion),
    CONSTRAINT fk_rol_permiso_rol FOREIGN KEY (id_rol) REFERENCES rol(id_rol)
);

-- id_compra e id_boleto pertenecen a B. Las FK se agregan en
-- integracion_C_B.sql cuando existan compra y boleto.
CREATE TABLE solicitud_reembolso (
    id_solicitud_reembolso SERIAL PRIMARY KEY,
    id_compra INT NOT NULL,
    id_usuario_actor INT NOT NULL,
    motivo TEXT NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'pendiente',
    creada_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resuelta_en TIMESTAMPTZ,
    id_usuario_resuelve INT,

    CONSTRAINT fk_solicitud_actor FOREIGN KEY (id_usuario_actor) REFERENCES usuario(id_usuario),
    CONSTRAINT fk_solicitud_resuelve FOREIGN KEY (id_usuario_resuelve) REFERENCES usuario(id_usuario),
    CONSTRAINT ck_solicitud_estado CHECK (estado IN ('pendiente', 'ejecutada', 'rechazada')),
    CONSTRAINT ck_solicitud_motivo CHECK (btrim(motivo) <> ''),
    CONSTRAINT ck_solicitud_resolucion CHECK (
        (estado = 'pendiente' AND resuelta_en IS NULL AND id_usuario_resuelve IS NULL)
        OR (estado <> 'pendiente' AND resuelta_en IS NOT NULL AND id_usuario_resuelve IS NOT NULL)
    )
);

CREATE TABLE solicitud_reembolso_detalle (
    id_solicitud_reembolso INT NOT NULL,
    id_boleto INT NOT NULL,
    PRIMARY KEY (id_solicitud_reembolso, id_boleto),
    CONSTRAINT fk_srd_solicitud FOREIGN KEY (id_solicitud_reembolso)
        REFERENCES solicitud_reembolso(id_solicitud_reembolso)
);

-- Logs: sin FK al boleto/función porque un QR inexistente también se registra.
CREATE TABLE acceso_puerta_log (
    id_acceso_puerta_log SERIAL PRIMARY KEY,
    fecha TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_boleto INT,
    id_funcion_solicitada INT,
    id_usuario_operador INT NOT NULL,
    dispositivo VARCHAR(100) NOT NULL,
    resultado VARCHAR(20) NOT NULL,
    motivo VARCHAR(200),

    CONSTRAINT fk_puerta_operador FOREIGN KEY (id_usuario_operador) REFERENCES usuario(id_usuario),
    CONSTRAINT ck_puerta_resultado CHECK (resultado IN ('aceptado', 'rechazado'))
);

CREATE TABLE admin_operacion_audit (
    id_admin_operacion_audit SERIAL PRIMARY KEY,
    fecha TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_usuario_actor INT NOT NULL,
    rol_al_actuar VARCHAR(30) NOT NULL,
    ip VARCHAR(45) NOT NULL,
    accion VARCHAR(60) NOT NULL,
    entidad VARCHAR(60) NOT NULL,
    id_entidad VARCHAR(60),
    motivo TEXT NOT NULL,
    cambios JSONB,

    CONSTRAINT fk_audit_actor FOREIGN KEY (id_usuario_actor) REFERENCES usuario(id_usuario),
    CONSTRAINT ck_audit_motivo CHECK (btrim(motivo) <> '')
);

-- Los logs no se editan ni se borran desde la aplicación.
CREATE OR REPLACE FUNCTION bloquear_modificacion_log()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Los registros de % no se pueden modificar ni eliminar.', TG_TABLE_NAME
        USING ERRCODE = '42501';
END;
$$;

CREATE TRIGGER trg_puerta_log_inmutable
BEFORE UPDATE OR DELETE ON acceso_puerta_log
FOR EACH ROW EXECUTE FUNCTION bloquear_modificacion_log();

CREATE TRIGGER trg_admin_audit_inmutable
BEFORE UPDATE OR DELETE ON admin_operacion_audit
FOR EACH ROW EXECUTE FUNCTION bloquear_modificacion_log();

-- Mecanismo común de autorización, reutilizable por A y B.
CREATE OR REPLACE FUNCTION autorizar_accion(p_id_usuario INT, p_accion TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM usuario u
        INNER JOIN rol_permiso rp ON rp.id_rol = u.id_rol
        WHERE u.id_usuario = p_id_usuario AND u.activo = TRUE
          AND rp.accion = p_accion
    );
$$;

-- Datos por rol.
INSERT INTO rol (nombre) VALUES
    ('cliente'), ('taquillero'), ('operador_puerta'), ('contador'), ('administrador');

INSERT INTO rol_permiso (id_rol, accion)
SELECT r.id_rol, p.accion
FROM (VALUES
    ('cliente','consultar_cartelera'), ('taquillero','consultar_cartelera'),
    ('operador_puerta','consultar_cartelera'), ('contador','consultar_cartelera'),
    ('administrador','consultar_cartelera'),
    ('administrador','gestionar_catalogo'),
    ('administrador','configurar_tarifas'),
    ('contador','ver_tarifas'), ('administrador','ver_tarifas'),
    ('cliente','reservar_comprar'),
    ('taquillero','venta_presencial'),
    ('cliente','consultar_boletos_propios'),
    ('taquillero','consultar_boletos_venta'),
    ('administrador','consultar_boletos_admin'),
    ('operador_puerta','validar_ingreso'),
    ('cliente','solicitar_reembolso'), ('taquillero','solicitar_reembolso'),
    ('administrador','solicitar_reembolso'),
    ('administrador','resolver_reembolso'),
    ('contador','ver_reportes_financieros'), ('administrador','ver_reportes_financieros'),
    ('contador','ver_auditoria'), ('administrador','ver_auditoria'),
    ('administrador','administrar_usuarios')
) AS p(rol, accion)
INNER JOIN rol r ON r.nombre = p.rol;

-- password_hash de prueba: reemplazar con hashes reales de Werkzeug
-- (generate_password_hash) antes de usar el login de la aplicación.
INSERT INTO usuario (id_rol, nombre, correo, password_hash)
SELECT r.id_rol, u.nombre, u.correo, 'HASH_DE_PRUEBA'
FROM (VALUES
    ('cliente','Cliente Uno','cliente1@imax.test'),
    ('cliente','Cliente Dos','cliente2@imax.test'),
    ('taquillero','Taquillero','taquillero@imax.test'),
    ('operador_puerta','Operador Puerta 1','puerta1@imax.test'),
    ('operador_puerta','Operador Puerta 2','puerta2@imax.test'),
    ('contador','Contador','contador@imax.test'),
    ('administrador','Administrador','admin@imax.test')
) AS u(rol, nombre, correo)
INNER JOIN rol r ON r.nombre = u.rol;

COMMIT;
