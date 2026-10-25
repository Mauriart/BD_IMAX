-- Instalacion completa en una base vacia. No elimina ni reemplaza tablas existentes.

BEGIN;

-- Fuente: docs/compañeroA/instalacion_completa_A.sql

-- Instalación completa del bloque A en una base vacía.

SET LOCAL TIME ZONE 'America/Costa_Rica';

-- Tablas y relaciones.
CREATE TABLE cine (
    id_cine SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    ubicacion TEXT NOT NULL,
    zona_horaria VARCHAR(100) NOT NULL
);

CREATE TABLE pelicula (
    id_pelicula SERIAL PRIMARY KEY,
    titulo VARCHAR(200) NOT NULL,
    sinopsis TEXT NOT NULL,
    clasificacion VARCHAR(30) NOT NULL,
    duracion_min INT NOT NULL CHECK (duracion_min > 0),
    poster_url TEXT NOT NULL
);

CREATE TABLE genero (
    id_genero SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE categoria_entrada (
    id_categoria_entrada SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE,
    requiere_acreditacion BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE promocion (
    id_promocion SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    tipo VARCHAR(30) NOT NULL,
    condicion TEXT NOT NULL,
    vigente_desde TIMESTAMPTZ NOT NULL,
    vigente_hasta TIMESTAMPTZ NOT NULL,
    activa BOOLEAN NOT NULL DEFAULT TRUE,

    CONSTRAINT ck_promocion_vigencia
        CHECK (vigente_hasta > vigente_desde)
);

CREATE TABLE sala (
    id_sala SERIAL PRIMARY KEY,
    id_cine INT NOT NULL,
    nombre VARCHAR(100) NOT NULL,

    CONSTRAINT fk_sala_cine
        FOREIGN KEY (id_cine)
        REFERENCES cine(id_cine),

    CONSTRAINT uq_sala_nombre
        UNIQUE (id_cine, nombre)
);

CREATE TABLE zona (
    id_zona SERIAL PRIMARY KEY,
    id_sala INT NOT NULL,
    nombre VARCHAR(50) NOT NULL,

    CONSTRAINT fk_zona_sala
        FOREIGN KEY (id_sala)
        REFERENCES sala(id_sala),

    CONSTRAINT uq_zona_nombre
        UNIQUE (id_sala, nombre)
);

CREATE TABLE asiento (
    id_asiento SERIAL PRIMARY KEY,
    id_zona INT NOT NULL,
    fila VARCHAR(10) NOT NULL,
    numero INT NOT NULL CHECK (numero > 0),

    CONSTRAINT fk_asiento_zona
        FOREIGN KEY (id_zona)
        REFERENCES zona(id_zona),

    CONSTRAINT uq_asiento_ubicacion
        UNIQUE (id_zona, fila, numero)
);

CREATE TABLE funcion (
    id_funcion SERIAL PRIMARY KEY,
    id_pelicula INT NOT NULL,
    id_sala INT NOT NULL,
    inicio TIMESTAMPTZ NOT NULL,
    fin TIMESTAMPTZ NOT NULL,
    activa BOOLEAN NOT NULL DEFAULT TRUE,

    CONSTRAINT fk_funcion_pelicula
        FOREIGN KEY (id_pelicula)
        REFERENCES pelicula(id_pelicula),

    CONSTRAINT fk_funcion_sala
        FOREIGN KEY (id_sala)
        REFERENCES sala(id_sala),

    CONSTRAINT ck_funcion_horario
        CHECK (fin > inicio)
);

CREATE TABLE tarifa (
    id_tarifa SERIAL PRIMARY KEY,
    id_funcion INT NOT NULL,
    id_zona INT NOT NULL,
    id_categoria_entrada INT NOT NULL,
    monto NUMERIC(12,2) NOT NULL,
    moneda VARCHAR(3) NOT NULL DEFAULT 'USD',
    vigente_desde TIMESTAMPTZ NOT NULL,
    vigente_hasta TIMESTAMPTZ NOT NULL,

    CONSTRAINT fk_tarifa_funcion
        FOREIGN KEY (id_funcion)
        REFERENCES funcion(id_funcion),

    CONSTRAINT fk_tarifa_zona
        FOREIGN KEY (id_zona)
        REFERENCES zona(id_zona),

    CONSTRAINT fk_tarifa_categoria
        FOREIGN KEY (id_categoria_entrada)
        REFERENCES categoria_entrada(id_categoria_entrada),

    CONSTRAINT ck_tarifa_monto
        CHECK (monto >= 0),

    CONSTRAINT ck_tarifa_moneda
        CHECK (moneda = 'USD'),

    CONSTRAINT ck_tarifa_vigencia
        CHECK (vigente_hasta > vigente_desde)
);

CREATE TABLE pelicula_genero (
    id_pelicula INT NOT NULL,
    id_genero INT NOT NULL,

    PRIMARY KEY (id_pelicula, id_genero),

    CONSTRAINT fk_pelicula_genero_pelicula
        FOREIGN KEY (id_pelicula)
        REFERENCES pelicula(id_pelicula),

    CONSTRAINT fk_pelicula_genero_genero
        FOREIGN KEY (id_genero)
        REFERENCES genero(id_genero)
);

CREATE TABLE funcion_promocion (
    id_funcion INT NOT NULL,
    id_promocion INT NOT NULL,

    PRIMARY KEY (id_funcion, id_promocion),

    CONSTRAINT fk_funcion_promocion_funcion
        FOREIGN KEY (id_funcion)
        REFERENCES funcion(id_funcion),

    CONSTRAINT fk_funcion_promocion_promocion
        FOREIGN KEY (id_promocion)
        REFERENCES promocion(id_promocion)
);

CREATE TABLE promocion_dia (
    id_promocion INT NOT NULL,
    dia_semana INT NOT NULL CHECK (dia_semana BETWEEN 1 AND 7),
    PRIMARY KEY (id_promocion, dia_semana),
    CONSTRAINT fk_promocion_dia_promocion FOREIGN KEY (id_promocion) REFERENCES promocion(id_promocion)
);

CREATE TABLE promocion_zona (
    id_promocion INT NOT NULL,
    id_zona INT NOT NULL,
    PRIMARY KEY (id_promocion, id_zona),
    CONSTRAINT fk_promocion_zona_promocion FOREIGN KEY (id_promocion) REFERENCES promocion(id_promocion),
    CONSTRAINT fk_promocion_zona_zona FOREIGN KEY (id_zona) REFERENCES zona(id_zona)
);

CREATE TABLE promocion_categoria (
    id_promocion INT NOT NULL,
    id_categoria_entrada INT NOT NULL,
    PRIMARY KEY (id_promocion, id_categoria_entrada),
    CONSTRAINT fk_promocion_categoria_promocion FOREIGN KEY (id_promocion) REFERENCES promocion(id_promocion),
    CONSTRAINT fk_promocion_categoria_categoria FOREIGN KEY (id_categoria_entrada) REFERENCES categoria_entrada(id_categoria_entrada)
);

-- Funciones y triggers de validación.
CREATE OR REPLACE FUNCTION validar_zona_tarifa()
RETURNS TRIGGER
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

CREATE TRIGGER trg_validar_zona_tarifa
BEFORE INSERT OR UPDATE OF id_funcion, id_zona ON tarifa
FOR EACH ROW EXECUTE FUNCTION validar_zona_tarifa();

-- Evitar que un cambio posterior de sala invalide tarifas ya relacionadas.
-- Regla simple: una función o zona con tarifas no se reasigna a otra sala.
CREATE OR REPLACE FUNCTION proteger_sala_con_tarifas()
RETURNS TRIGGER
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

CREATE TRIGGER trg_proteger_sala_funcion
BEFORE UPDATE OF id_sala ON funcion
FOR EACH ROW EXECUTE FUNCTION proteger_sala_con_tarifas();

CREATE TRIGGER trg_proteger_sala_zona
BEFORE UPDATE OF id_sala ON zona
FOR EACH ROW EXECUTE FUNCTION proteger_sala_con_tarifas();

CREATE OR REPLACE FUNCTION validar_horario_funcion()
RETURNS TRIGGER
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

CREATE TRIGGER trg_validar_horario_funcion
BEFORE INSERT OR UPDATE OF id_sala, inicio, fin, activa ON funcion
FOR EACH ROW EXECUTE FUNCTION validar_horario_funcion();

CREATE OR REPLACE FUNCTION validar_vigencia_tarifa()
RETURNS TRIGGER
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

CREATE TRIGGER trg_validar_vigencia_tarifa
BEFORE INSERT OR UPDATE ON tarifa
FOR EACH ROW EXECUTE FUNCTION validar_vigencia_tarifa();

-- Datos de ejemplo con fechas relativas al día de ejecución.
INSERT INTO cine (nombre, ubicacion, zona_horaria)
VALUES ('IMAX Central', 'San José, Costa Rica', 'America/Costa_Rica');
INSERT INTO sala (id_cine, nombre)
VALUES (1, 'Sala 1');
INSERT INTO zona (id_sala, nombre)
VALUES (1, 'General'), (1, 'VIP');
INSERT INTO asiento (id_zona, fila, numero)
VALUES (1, 'A', 1), (1, 'A', 2), (1, 'A', 3),
       (2, 'B', 1), (2, 'B', 2), (2, 'B', 3);

INSERT INTO pelicula (
    titulo, sinopsis, clasificacion, duracion_min, poster_url
)
VALUES (
    'Horizonte estelar',
    'Una tripulación explora un planeta desconocido.',
    'Todo público', 120, '/static/img/horizonte_estelar.png'
);
INSERT INTO genero (nombre)
VALUES ('Ciencia ficción'), ('Aventura');
INSERT INTO pelicula_genero (id_pelicula, id_genero)
VALUES (1, 1), (1, 2);

INSERT INTO categoria_entrada (nombre, requiere_acreditacion)
VALUES ('Adulto', FALSE), ('Niño', TRUE),
       ('Estudiante', TRUE), ('Tercera edad', TRUE);
INSERT INTO funcion (id_pelicula, id_sala, inicio, fin, activa)
VALUES (1, 1, CURRENT_DATE + INTERVAL '7 days 18 hours',
        CURRENT_DATE + INTERVAL '7 days 20 hours', TRUE);
INSERT INTO tarifa (
    id_funcion, id_zona, id_categoria_entrada,
    monto, moneda, vigente_desde, vigente_hasta
)
VALUES
    (1, 1, 1, 8.00, 'USD', CURRENT_DATE - INTERVAL '1 day', CURRENT_DATE + INTERVAL '7 days 18 hours'),
    (1, 1, 2, 5.00, 'USD', CURRENT_DATE - INTERVAL '1 day', CURRENT_DATE + INTERVAL '7 days 18 hours'),
    (1, 1, 3, 6.00, 'USD', CURRENT_DATE - INTERVAL '1 day', CURRENT_DATE + INTERVAL '7 days 18 hours'),
    (1, 1, 4, 5.00, 'USD', CURRENT_DATE - INTERVAL '1 day', CURRENT_DATE + INTERVAL '7 days 18 hours'),
    (1, 2, 1, 12.00, 'USD', CURRENT_DATE - INTERVAL '1 day', CURRENT_DATE + INTERVAL '7 days 18 hours'),
    (1, 2, 2, 9.00, 'USD', CURRENT_DATE - INTERVAL '1 day', CURRENT_DATE + INTERVAL '7 days 18 hours'),
    (1, 2, 3, 10.00, 'USD', CURRENT_DATE - INTERVAL '1 day', CURRENT_DATE + INTERVAL '7 days 18 hours'),
    (1, 2, 4, 9.00, 'USD', CURRENT_DATE - INTERVAL '1 day', CURRENT_DATE + INTERVAL '7 days 18 hours');

INSERT INTO promocion (
    nombre, tipo, condicion, vigente_desde, vigente_hasta, activa
)
VALUES (
    'Pareja General', '2x1',
    'Dos entradas de adulto en zona General de la misma función.',
    CURRENT_DATE - INTERVAL '1 day', CURRENT_DATE + INTERVAL '7 days 18 hours', TRUE
);
INSERT INTO funcion_promocion (id_funcion, id_promocion)
VALUES (1, 1);

INSERT INTO promocion_dia (id_promocion, dia_semana)
VALUES (1, 1), (1, 2), (1, 3), (1, 4), (1, 5), (1, 6), (1, 7);

INSERT INTO promocion_zona (id_promocion, id_zona)
VALUES (1, 1);

INSERT INTO promocion_categoria (id_promocion, id_categoria_entrada)
VALUES (1, 1);

-- Fuente: docs/compañeroC/sql_C-01.sql

-- C-01: identidad, roles, autorización común, auditoría administrativa,
-- registro de puerta y solicitudes de reembolso.
-- Ejecutar DESPUÉS de relacional_A.sql (y sus ajustes). No toca tablas de A.
-- Mismo estilo que A: SERIAL / INT, restricciones con nombre.

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
    id_compra BIGINT NOT NULL,
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
    id_boleto BIGINT NOT NULL,
    PRIMARY KEY (id_solicitud_reembolso, id_boleto),
    CONSTRAINT fk_srd_solicitud FOREIGN KEY (id_solicitud_reembolso)
        REFERENCES solicitud_reembolso(id_solicitud_reembolso)
);

-- Logs: sin FK al boleto/función porque un QR inexistente también se registra.
CREATE TABLE acceso_puerta_log (
    id_acceso_puerta_log SERIAL PRIMARY KEY,
    fecha TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_boleto BIGINT,
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

-- Fuente: docs/compañeraB/sql_20_ventas_tablas.sql

-- Requiere A y sql_C-01.sql. Identidad y reembolsos usan las tablas de C.
CREATE TABLE compra (
id_compra BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
id_usuario_cliente BIGINT NOT NULL REFERENCES usuario(id_usuario),
id_usuario_actor BIGINT NOT NULL REFERENCES usuario(id_usuario),
id_funcion BIGINT NOT NULL REFERENCES funcion(id_funcion),
estado VARCHAR (30) NOT NULL DEFAULT 'Pendiente' CHECK (estado IN
('Pendiente', 'Pagada', 'Cancelada', 'Expirada', 'Reembolsada', 'ParcialmenteReembolsada')),
total NUMERIC (10,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
moneda CHAR(3) NOT NULL DEFAULT 'USD',
creada_en TIMESTAMPTZ NOT NULL DEFAULT now(),
UNIQUE(id_compra,id_funcion)
);

CREATE TABLE compra_detalle (
id_compra_detalle BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
id_compra BIGINT NOT NULL REFERENCES compra(id_compra),
id_asiento INT NOT NULL REFERENCES asiento(id_asiento),
id_categoria_entrada INT NOT NULL REFERENCES categoria_entrada(id_categoria_entrada),
id_tarifa INT NOT NULL REFERENCES tarifa(id_tarifa),
id_promocion BIGINT REFERENCES promocion(id_promocion),
precio_base NUMERIC (10,2) NOT NULL DEFAULT 0 CHECK (precio_base >= 0),
descuento NUMERIC (10,2) NOT NULL DEFAULT 0 CHECK (descuento >= 0),
cargo_servicio NUMERIC(10,2) NOT NULL DEFAULT 0,
total_linea NUMERIC(10,2) NOT NULL CHECK(total_linea=precio_base-descuento+cargo_servicio),
UNIQUE(id_compra,id_asiento)
);


-- Creación de tabla de reserva de asiento
CREATE TABLE reserva (
id_reserva BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
id_compra BIGINT NOT NULL REFERENCES compra(id_compra),
id_funcion BIGINT NOT NULL REFERENCES funcion(id_funcion),
id_asiento BIGINT NOT NULL REFERENCES asiento(id_asiento),
estado VARCHAR(12) NOT NULL DEFAULT 'activa'
CHECK (estado IN ('activa','confirmada','expirada','liberada')),
categoria VARCHAR(20) NOT NULL DEFAULT 'adulto',
precio_unitario NUMERIC(10,2) CHECK (precio_unitario >= 0),
creada_en TIMESTAMPTZ NOT NULL DEFAULT now(),
vence_en TIMESTAMPTZ NOT NULL,
FOREIGN KEY(id_compra,id_funcion) REFERENCES compra(id_compra,id_funcion)
);


-- Indice para evitar que dos usuarios mantengan el mismo asiento activo o confirmado
CREATE UNIQUE INDEX uq_ocupacion_vigente ON reserva (id_funcion, id_asiento)
WHERE estado IN ('activa', 'confirmada');


-- Creacion de tabla pagos
CREATE TABLE pago (
id_pago BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
id_compra BIGINT NOT NULL REFERENCES compra(id_compra),
estado VARCHAR(12) NOT NULL CHECK (estado IN
('Pendiente','Aprobado','Rechazado','Reembolsado')),
metodo VARCHAR(20) NOT NULL,
referencia VARCHAR(60) NOT NULL UNIQUE,
monto NUMERIC(10,2) NOT NULL CHECK (monto >= 0),
moneda CHAR(3) NOT NULL DEFAULT 'USD',
creado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Creación de tabla Boletos
CREATE TABLE boleto (
id_boleto BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
id_compra BIGINT NOT NULL REFERENCES compra(id_compra),
id_funcion BIGINT NOT NULL REFERENCES funcion(id_funcion),
id_asiento BIGINT NOT NULL REFERENCES asiento(id_asiento),
token_qr UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
estado VARCHAR(10) NOT NULL DEFAULT 'Emitido' CHECK (estado IN ('Emitido','Usado','Anulado')),
emitido_en TIMESTAMPTZ NOT NULL DEFAULT now(),
usado_en TIMESTAMPTZ,
CHECK((estado='Usado')=(usado_en IS NOT NULL)),
FOREIGN KEY(id_compra,id_funcion) REFERENCES compra(id_compra,id_funcion)
);

-- Creación de tabla Inventario
CREATE TABLE inventario_funcion (
id_funcion INT NOT NULL REFERENCES funcion(id_funcion),
id_asiento INT NOT NULL REFERENCES asiento(id_asiento),
estado VARCHAR(20) NOT NULL DEFAULT 'disponible',
CHECK (estado IN ('disponible', 'bloqueado', 'vendido')),
id_reserva BIGINT REFERENCES reserva(id_reserva),
id_boleto BIGINT UNIQUE REFERENCES boleto(id_boleto),
PRIMARY KEY (id_funcion, id_asiento),

CONSTRAINT ck_inventario_ocupante CHECK (
(estado = 'disponible' AND id_reserva IS NULL AND id_boleto IS NULL) OR
(estado = 'bloqueado' AND id_reserva IS NOT NULL AND id_boleto IS NULL) OR
(estado = 'vendido' AND id_reserva IS NOT NULL AND id_boleto IS NOT NULL))
);


-- Indice en caso de cancelaciones de compra
CREATE UNIQUE INDEX uq_boleto_vigente ON boleto (id_funcion, id_asiento)
WHERE estado IN ('Emitido','Usado');

-- Creación de tabla reembolso
CREATE TABLE reembolso (
id_reembolso BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
id_solicitud_reembolso BIGINT NOT NULL UNIQUE REFERENCES solicitud_reembolso(id_solicitud_reembolso),
id_pago BIGINT NOT NULL REFERENCES pago(id_pago),
referencia VARCHAR(80) NOT NULL UNIQUE,
monto NUMERIC(12,2) NOT NULL CHECK (monto > 0),
moneda VARCHAR(3) NOT NULL DEFAULT 'USD',
creado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE reembolso_detalle (
id_reembolso BIGINT NOT NULL REFERENCES reembolso(id_reembolso),
id_boleto BIGINT NOT NULL UNIQUE REFERENCES boleto(id_boleto),
monto NUMERIC(12,2) NOT NULL CHECK (monto > 0),
PRIMARY KEY (id_reembolso, id_boleto)
);

-- Fuente: docs/compañeraB/sql_21_ventas_logs.sql

--Logs de trasacciones finacieras y ciclo de pago
CREATE TABLE transaccion_log (
id_trasaccion_log BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
id_compra BIGINT,
id_pago BIGINT,
id_usuario_actor BIGINT,
resultado VARCHAR(10) NOT NULL,
evento VARCHAR(40) NOT NULL,
estado_anterior VARCHAR(15),
estado_nuevo VARCHAR(15),
monto NUMERIC(10,2),
moneda CHAR(3),
detalle TEXT,
CONSTRAINT ck_trasaccion_log_resultado CHECK (resultado IN
('Exito', 'Rechazado', 'Fallido'))
);

-- Logs de bloqueo de asientos y estados temporales
CREATE TABLE asiento_auditoria_log (
id_asiento_auditoria_log BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
id_funcion BIGINT NOT NULL,
id_asiento BIGINT NOT NULL,
id_compra BIGINT,
id_usuario_actor BIGINT,
evento VARCHAR(40) NOT NULL,
estado_anterior VARCHAR(15),
estado_nuevo VARCHAR(15),
detalle TEXT
);

CREATE OR REPLACE FUNCTION bloquear_modificacion_log_b()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
-- Lanza un mensaje de error y detiene la operación de golpe
RAISE EXCEPTION 'Los logs son inalterables (% en %)', TG_OP, TG_TABLE_NAME;
RETURN NULL;
END $$;

CREATE TRIGGER trg_tlog_inmutable
BEFORE UPDATE OR DELETE ON transaccion_log
FOR EACH ROW EXECUTE FUNCTION bloquear_modificacion_log_b();

CREATE TRIGGER trg_alog_inmutable
BEFORE UPDATE OR DELETE ON asiento_auditoria_log
FOR EACH ROW EXECUTE FUNCTION bloquear_modificacion_log_b();


-- Pruebas:
-- INSERT INTO transaccion_log (resultado, evento) VALUES ('Exito', 'Registro inicial');
-- UPDATE transaccion_log SET evento = 'x';

-- Fuente: docs/compañeraB/sql_22_ventas_funciones.sql

-- Ventas integradas con identidad de C y tarifas/promociones de A.
-- El servidor fija app.id_usuario desde la sesion, nunca desde el formulario.
CREATE OR REPLACE FUNCTION actor_ventas(p_actor bigint,p_accion text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE contexto text:=nullif(current_setting('app.id_usuario',true),'');
BEGIN
    IF contexto IS NULL OR contexto::bigint<>p_actor THEN
        RAISE EXCEPTION 'La operacion requiere el actor autenticado.' USING ERRCODE='42501';
    END IF;
    PERFORM u.id_usuario FROM usuario u JOIN rol r USING(id_rol)
    WHERE u.id_usuario=p_actor AND u.activo FOR SHARE OF u,r;
    IF NOT FOUND OR NOT autorizar_accion(p_actor::integer,p_accion) THEN
        RAISE EXCEPTION 'El usuario no tiene permiso para esta operacion.' USING ERRCODE='42501';
    END IF;
    PERFORM rp.accion FROM rol_permiso rp JOIN usuario u USING(id_rol)
    WHERE u.id_usuario=p_actor AND rp.accion=p_accion FOR SHARE OF rp;
END $$;

CREATE OR REPLACE FUNCTION coordinar_venta(p_funcion bigint)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('transaction_isolation')<>'read committed' THEN
        RAISE EXCEPTION 'Ventas requiere READ COMMITTED.' USING ERRCODE='55000';
    END IF;
    PERFORM s.id_sala FROM sala s JOIN funcion f USING(id_sala)
    WHERE f.id_funcion=p_funcion FOR SHARE OF s;
    IF NOT FOUND THEN RAISE EXCEPTION 'La funcion no existe.' USING ERRCODE='23503'; END IF;
END $$;

CREATE OR REPLACE FUNCTION preparar_inventario(p_funcion bigint)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM coordinar_venta(p_funcion);
    INSERT INTO inventario_funcion(id_funcion,id_asiento)
    SELECT f.id_funcion,a.id_asiento FROM funcion f JOIN zona z USING(id_sala)
    JOIN asiento a USING(id_zona) WHERE f.id_funcion=p_funcion
    ON CONFLICT(id_funcion,id_asiento) DO NOTHING;
END $$;

CREATE OR REPLACE FUNCTION liberar_reservas_vencidas()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    -- Bloquea cada compra antes de modificar su reserva/inventario, igual que pago.
    FOR r IN SELECT id_compra,id_funcion FROM compra
             WHERE estado='Pendiente' ORDER BY id_compra FOR UPDATE SKIP LOCKED LOOP
        IF EXISTS(SELECT 1 FROM reserva WHERE id_compra=r.id_compra AND estado='activa'
                  AND vence_en<=clock_timestamp()) THEN
            PERFORM coordinar_venta(r.id_funcion);
            UPDATE reserva SET estado='expirada' WHERE id_compra=r.id_compra AND estado='activa';
            UPDATE inventario_funcion i SET estado='disponible',id_reserva=NULL
            FROM reserva re WHERE i.id_reserva=re.id_reserva AND re.id_compra=r.id_compra AND i.estado='bloqueado';
            UPDATE compra SET estado='Expirada' WHERE id_compra=r.id_compra;
        END IF;
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION consultar_disponibilidad(p_id_funcion bigint)
RETURNS TABLE(asiento_id integer,estado_actual varchar,reserva_id bigint)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY SELECT i.id_asiento,i.estado,i.id_reserva FROM inventario_funcion i
    WHERE i.id_funcion=p_id_funcion ORDER BY i.id_asiento;
END $$;

CREATE OR REPLACE FUNCTION calcular_total(p_id_compra bigint)
RETURNS numeric LANGUAGE plpgsql AS $$
DECLARE total_compra numeric;
BEGIN
    SELECT coalesce(sum(total_linea),0) INTO total_compra FROM compra_detalle WHERE id_compra=p_id_compra;
    UPDATE compra SET total=total_compra WHERE id_compra=p_id_compra;
    RETURN total_compra;
END $$;

-- Cotizacion unica por categoria. El descuento 2x1 se reparte entre las dos lineas.
CREATE OR REPLACE FUNCTION reservar_asientos(p_id_usuario_cliente bigint,p_id_usuario_actor bigint,
    p_id_funcion bigint,p_asientos integer[],p_categoria integer)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE compra_nueva bigint; a integer; zona_actual integer; tarifa_actual integer;
        precio numeric; cantidad integer; instante timestamptz:=clock_timestamp();
        reserva_nueva bigint; promocion_actual integer; par record;
BEGIN
    IF p_id_usuario_actor=p_id_usuario_cliente THEN
        PERFORM actor_ventas(p_id_usuario_actor,'reservar_comprar');
    ELSIF autorizar_accion(p_id_usuario_actor::integer,'otorgar_cortesia') THEN
        PERFORM actor_ventas(p_id_usuario_actor,'otorgar_cortesia');
    ELSE PERFORM actor_ventas(p_id_usuario_actor,'venta_presencial'); END IF;
    IF NOT EXISTS(SELECT 1 FROM usuario u JOIN rol r USING(id_rol)
        WHERE u.id_usuario=p_id_usuario_cliente AND u.activo AND r.nombre='cliente') THEN
        RAISE EXCEPTION 'Seleccione un cliente activo.';
    END IF;
    cantidad:=cardinality(p_asientos);
    IF cantidad IS NULL OR cantidad NOT BETWEEN 1 AND 6 OR array_ndims(p_asientos)<>1
       OR array_position(p_asientos,NULL) IS NOT NULL
       OR (SELECT count(DISTINCT x) FROM unnest(p_asientos) x)<>cantidad THEN
        RAISE EXCEPTION 'Seleccione entre uno y seis asientos diferentes.';
    END IF;
    PERFORM coordinar_venta(p_id_funcion);
    -- El bloqueo de funcion impide que cambien estado, horario o tarifas al cotizar.
    PERFORM 1 FROM funcion WHERE id_funcion=p_id_funcion AND activa AND inicio>instante FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'La funcion no esta activa o ya inicio.'; END IF;
    PERFORM liberar_reservas_vencidas();
    PERFORM preparar_inventario(p_id_funcion);
    PERFORM i.id_asiento FROM inventario_funcion i WHERE i.id_funcion=p_id_funcion
    AND i.id_asiento=ANY(p_asientos) ORDER BY i.id_asiento FOR UPDATE;
    IF (SELECT count(*) FROM inventario_funcion WHERE id_funcion=p_id_funcion
        AND id_asiento=ANY(p_asientos) AND estado='disponible')<>cantidad THEN
        RAISE EXCEPTION 'Un asiento no se encuentra disponible. Operacion cancelada.';
    END IF;
    INSERT INTO compra(id_usuario_cliente,id_usuario_actor,id_funcion)
    VALUES(p_id_usuario_cliente,p_id_usuario_actor,p_id_funcion) RETURNING id_compra INTO compra_nueva;
    FOR a IN SELECT unnest(p_asientos) ORDER BY 1 LOOP
        SELECT id_zona INTO zona_actual FROM asiento WHERE id_asiento=a;
        SELECT count(*),min(id_tarifa),min(monto) INTO cantidad,tarifa_actual,precio FROM tarifa
        WHERE id_funcion=p_id_funcion AND id_zona=zona_actual AND id_categoria_entrada=p_categoria
          AND vigente_desde<=instante AND instante<vigente_hasta;
        IF cantidad<>1 THEN RAISE EXCEPTION 'No hay una tarifa vigente unica para la zona y categoria seleccionadas.'; END IF;
        INSERT INTO reserva(id_compra,id_funcion,id_asiento,vence_en,precio_unitario)
        VALUES(compra_nueva,p_id_funcion,a,instante+INTERVAL '120 seconds',precio) RETURNING id_reserva INTO reserva_nueva;
        INSERT INTO compra_detalle(id_compra,id_asiento,id_categoria_entrada,id_tarifa,precio_base,total_linea)
        VALUES(compra_nueva,a,p_categoria,tarifa_actual,precio,precio);
        UPDATE inventario_funcion SET estado='bloqueado',id_reserva=reserva_nueva
        WHERE id_funcion=p_id_funcion AND id_asiento=a;
    END LOOP;
    FOR par IN
        SELECT d.id_compra_detalle,d.precio_base,a.id_zona,
          row_number() OVER(PARTITION BY a.id_zona ORDER BY a.id_asiento) n,
          count(*) OVER(PARTITION BY a.id_zona) cuantos
        FROM compra_detalle d JOIN asiento a USING(id_asiento) WHERE d.id_compra=compra_nueva
    LOOP
        SELECT p.id_promocion INTO promocion_actual FROM promocion p
        JOIN funcion_promocion fp USING(id_promocion)
        WHERE fp.id_funcion=p_id_funcion AND p.activa AND p.tipo='2x1'
          AND p.vigente_desde<=instante AND instante<p.vigente_hasta
          AND EXISTS(SELECT 1 FROM promocion_dia pd JOIN funcion f ON f.id_funcion=p_id_funcion
                     JOIN sala s USING(id_sala) JOIN cine ci USING(id_cine)
                     WHERE pd.id_promocion=p.id_promocion
                     AND pd.dia_semana=extract(isodow FROM f.inicio AT TIME ZONE ci.zona_horaria))
          AND EXISTS(SELECT 1 FROM promocion_zona pz WHERE pz.id_promocion=p.id_promocion AND pz.id_zona=par.id_zona)
          AND EXISTS(SELECT 1 FROM promocion_categoria pc WHERE pc.id_promocion=p.id_promocion AND pc.id_categoria_entrada=p_categoria)
        ORDER BY p.id_promocion LIMIT 1;
        IF promocion_actual IS NOT NULL AND par.n<=par.cuantos-(par.cuantos%2) THEN
            UPDATE compra_detalle SET id_promocion=promocion_actual,
              descuento=CASE WHEN par.n%2=1 THEN ceil(par.precio_base*100/2)/100 ELSE floor(par.precio_base*100/2)/100 END,
              total_linea=par.precio_base-CASE WHEN par.n%2=1 THEN ceil(par.precio_base*100/2)/100 ELSE floor(par.precio_base*100/2)/100 END
            WHERE id_compra_detalle=par.id_compra_detalle;
        END IF;
    END LOOP;
    PERFORM calcular_total(compra_nueva);
    RETURN compra_nueva;
END $$;

-- Compatibilidad con llamadas de cuatro argumentos: solo si la categoria es unica.
CREATE OR REPLACE FUNCTION reservar_asientos(p_id_usuario_cliente bigint,p_id_usuario_actor bigint,
    p_id_funcion bigint,p_asientos integer[])
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE categoria integer; n integer;
BEGIN
    SELECT count(DISTINCT id_categoria_entrada),min(id_categoria_entrada) INTO n,categoria FROM tarifa
    WHERE id_funcion=p_id_funcion AND vigente_desde<=clock_timestamp() AND clock_timestamp()<vigente_hasta;
    IF n<>1 THEN RAISE EXCEPTION 'Seleccione la categoria de entrada.'; END IF;
    RETURN reservar_asientos(p_id_usuario_cliente,p_id_usuario_actor,p_id_funcion,p_asientos,categoria);
END $$;

CREATE OR REPLACE FUNCTION procesar_pago(p_id_compra bigint,p_resultado varchar,p_metodo varchar,p_referencia varchar)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE c compra%ROWTYPE; r record; pago_nuevo bigint; boleto_nuevo bigint; actor bigint;
BEGIN
    actor:=nullif(current_setting('app.id_usuario',true),'')::bigint;
    IF actor IS NULL THEN RAISE EXCEPTION 'Falta usuario autenticado.' USING ERRCODE='42501'; END IF;
    SELECT * INTO c FROM compra WHERE id_compra=p_id_compra;
    IF NOT FOUND THEN RAISE EXCEPTION 'La compra no existe.'; END IF;
    IF actor=c.id_usuario_cliente THEN PERFORM actor_ventas(actor,'reservar_comprar');
    ELSIF autorizar_accion(actor::integer,'otorgar_cortesia') THEN PERFORM actor_ventas(actor,'otorgar_cortesia');
    ELSE PERFORM actor_ventas(actor,'venta_presencial'); END IF;
    PERFORM coordinar_venta(c.id_funcion);
    SELECT * INTO c FROM compra WHERE id_compra=p_id_compra FOR UPDATE;
    IF p_metodo='Cortesia' THEN PERFORM actor_ventas(actor,'otorgar_cortesia'); END IF;
    IF p_resultado NOT IN ('Exito','Aprobado','Rechazado') OR p_metodo NOT IN ('Tarjeta','Transferencia','Efectivo','Cortesia')
        OR btrim(coalesce(p_referencia,''))='' THEN RAISE EXCEPTION 'Datos de pago invalidos.'; END IF;
    IF EXISTS(SELECT 1 FROM pago WHERE referencia=p_referencia AND id_compra=p_id_compra) THEN RETURN; END IF;
    IF c.estado<>'Pendiente' THEN RAISE EXCEPTION 'La compra ya no esta pendiente.'; END IF;
    IF NOT EXISTS(SELECT 1 FROM reserva WHERE id_compra=p_id_compra)
       OR EXISTS(SELECT 1 FROM reserva WHERE id_compra=p_id_compra AND (estado<>'activa' OR vence_en<=clock_timestamp()))
       OR NOT EXISTS(SELECT 1 FROM funcion WHERE id_funcion=c.id_funcion AND activa AND inicio>clock_timestamp()) THEN
        p_resultado:='Rechazado';
    END IF;
    PERFORM i.id_asiento FROM inventario_funcion i JOIN reserva re ON re.id_reserva=i.id_reserva
    WHERE re.id_compra=p_id_compra ORDER BY i.id_asiento FOR UPDATE OF i;
    INSERT INTO pago(id_compra,estado,metodo,referencia,monto)
    VALUES(p_id_compra,CASE WHEN p_resultado IN ('Exito','Aprobado') THEN 'Aprobado' ELSE 'Rechazado' END,p_metodo,p_referencia,c.total)
    RETURNING id_pago INTO pago_nuevo;
    IF p_resultado IN ('Exito','Aprobado') THEN
        FOR r IN SELECT * FROM reserva WHERE id_compra=p_id_compra ORDER BY id_asiento LOOP
            IF NOT EXISTS(SELECT 1 FROM inventario_funcion WHERE id_funcion=c.id_funcion AND id_asiento=r.id_asiento
                          AND estado='bloqueado' AND id_reserva=r.id_reserva) THEN RAISE EXCEPTION 'La reserva perdio el asiento.'; END IF;
            INSERT INTO boleto(id_compra,id_funcion,id_asiento) VALUES(p_id_compra,c.id_funcion,r.id_asiento)
            RETURNING id_boleto INTO boleto_nuevo;
            UPDATE inventario_funcion SET estado='vendido',id_boleto=boleto_nuevo
            WHERE id_funcion=c.id_funcion AND id_asiento=r.id_asiento;
        END LOOP;
        UPDATE reserva SET estado='confirmada' WHERE id_compra=p_id_compra;
        UPDATE compra SET estado='Pagada' WHERE id_compra=p_id_compra;
    ELSE
        UPDATE reserva SET estado='liberada' WHERE id_compra=p_id_compra AND estado IN ('activa','expirada');
        UPDATE inventario_funcion i SET estado='disponible',id_reserva=NULL FROM reserva re
        WHERE re.id_reserva=i.id_reserva AND re.id_compra=p_id_compra AND i.estado='bloqueado';
        UPDATE compra SET estado='Cancelada' WHERE id_compra=p_id_compra;
    END IF;
    INSERT INTO transaccion_log(id_compra,id_pago,id_usuario_actor,resultado,evento,monto,moneda)
    VALUES(p_id_compra,pago_nuevo,actor,CASE WHEN p_resultado IN ('Exito','Aprobado') THEN 'Exito' ELSE 'Fallido' END,'Procesar Pago',c.total,'USD');
END $$;

CREATE OR REPLACE FUNCTION consultar_boletos_usuario(p_id_usuario_cliente bigint,p_id_usuario_actor bigint)
RETURNS TABLE(boleto_id bigint,compra_id bigint,funcion_id bigint,asiento_id integer,estado_boleto varchar,qr_token uuid)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_id_usuario_cliente=p_id_usuario_actor THEN PERFORM actor_ventas(p_id_usuario_actor,'consultar_boletos_propios');
    ELSIF autorizar_accion(p_id_usuario_actor::integer,'consultar_boletos_admin') THEN PERFORM actor_ventas(p_id_usuario_actor,'consultar_boletos_admin');
    ELSE PERFORM actor_ventas(p_id_usuario_actor,'consultar_boletos_venta'); END IF;
    RETURN QUERY SELECT b.id_boleto,b.id_compra,b.id_funcion,b.id_asiento::integer,b.estado,b.token_qr
    FROM boleto b JOIN compra c USING(id_compra) WHERE c.id_usuario_cliente=p_id_usuario_cliente;
END $$;

-- C autoriza una solicitud concreta; B conserva pago, inventario y monto devuelto.
CREATE OR REPLACE FUNCTION revertir_venta(p_id_solicitud_reembolso integer,p_referencia text)
RETURNS TABLE(monto_reembolsado numeric,boletos_anulados integer)
LANGUAGE plpgsql AS $$
DECLARE solicitud solicitud_reembolso%ROWTYPE; c compra%ROWTYPE; actor bigint;
        monto numeric; n integer; pago_original bigint; reembolso_nuevo bigint; r record;
BEGIN
    actor:=nullif(current_setting('app.id_usuario',true),'')::bigint;
    PERFORM actor_ventas(actor,'resolver_reembolso');
    SELECT * INTO solicitud FROM solicitud_reembolso WHERE id_solicitud_reembolso=p_id_solicitud_reembolso FOR UPDATE;
    IF NOT FOUND OR solicitud.estado<>'pendiente' THEN RAISE EXCEPTION 'La solicitud ya no esta pendiente.'; END IF;
    SELECT * INTO c FROM compra WHERE id_compra=solicitud.id_compra;
    PERFORM coordinar_venta(c.id_funcion);
    SELECT * INTO c FROM compra WHERE id_compra=solicitud.id_compra FOR UPDATE;
    IF c.estado NOT IN ('Pagada','ParcialmenteReembolsada') THEN RAISE EXCEPTION 'La compra no admite devolucion.'; END IF;
    PERFORM b.id_boleto FROM boleto b JOIN solicitud_reembolso_detalle d USING(id_boleto)
    WHERE d.id_solicitud_reembolso=p_id_solicitud_reembolso ORDER BY b.id_boleto FOR UPDATE OF b;
    IF EXISTS(SELECT 1 FROM solicitud_reembolso_detalle d JOIN boleto b USING(id_boleto)
              WHERE d.id_solicitud_reembolso=p_id_solicitud_reembolso AND (b.id_compra<>c.id_compra OR b.estado<>'Emitido')) THEN
        RAISE EXCEPTION 'Un boleto ya fue utilizado o anulado.';
    END IF;
    SELECT count(*),sum(cd.total_linea) INTO n,monto FROM solicitud_reembolso_detalle d
    JOIN boleto b USING(id_boleto) JOIN compra_detalle cd ON cd.id_compra=b.id_compra AND cd.id_asiento=b.id_asiento
    WHERE d.id_solicitud_reembolso=p_id_solicitud_reembolso;
    IF n=0 OR monto<=0 THEN RAISE EXCEPTION 'No hay un monto reembolsable.'; END IF;
    SELECT id_pago INTO pago_original FROM pago WHERE id_compra=c.id_compra AND estado='Aprobado' ORDER BY id_pago LIMIT 1;
    IF pago_original IS NULL THEN RAISE EXCEPTION 'No existe pago aprobado.'; END IF;
    INSERT INTO reembolso(id_solicitud_reembolso,id_pago,referencia,monto)
    VALUES(p_id_solicitud_reembolso,pago_original,p_referencia,monto) RETURNING id_reembolso INTO reembolso_nuevo;
    FOR r IN SELECT b.id_boleto,b.id_asiento,cd.total_linea FROM solicitud_reembolso_detalle d
        JOIN boleto b USING(id_boleto) JOIN compra_detalle cd ON cd.id_compra=b.id_compra AND cd.id_asiento=b.id_asiento
        WHERE d.id_solicitud_reembolso=p_id_solicitud_reembolso ORDER BY b.id_boleto LOOP
        INSERT INTO reembolso_detalle VALUES(reembolso_nuevo,r.id_boleto,r.total_linea);
        UPDATE boleto SET estado='Anulado' WHERE id_boleto=r.id_boleto;
        UPDATE reserva SET estado='liberada' WHERE id_compra=c.id_compra AND id_asiento=r.id_asiento;
        UPDATE inventario_funcion SET estado='disponible',id_reserva=NULL,id_boleto=NULL
        WHERE id_funcion=c.id_funcion AND id_asiento=r.id_asiento AND id_boleto=r.id_boleto;
    END LOOP;
    UPDATE compra SET estado=CASE WHEN EXISTS(SELECT 1 FROM boleto WHERE id_compra=c.id_compra AND estado<>'Anulado')
      THEN 'ParcialmenteReembolsada' ELSE 'Reembolsada' END WHERE id_compra=c.id_compra;
    INSERT INTO transaccion_log(id_compra,id_pago,id_usuario_actor,resultado,evento,monto,moneda,detalle)
    VALUES(c.id_compra,pago_original,actor,'Exito','Reembolso',monto,'USD',p_referencia);
    RETURN QUERY SELECT monto,n;
END $$;

-- La firma anterior delega en C; no permite saltarse politica ni autorizacion.
CREATE OR REPLACE FUNCTION revertir_venta(p_id_compra bigint,p_id_usuario_actor bigint,p_motivo varchar)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE s record; res record;
BEGIN
    PERFORM actor_ventas(p_id_usuario_actor,'resolver_reembolso');
    SELECT * INTO s FROM solicitar_reembolso(p_id_usuario_actor::integer,p_id_compra,NULL::bigint[],p_motivo::text,
        coalesce(nullif(current_setting('app.ip',true),''),'127.0.0.1'));
    IF NOT s.exito THEN RAISE EXCEPTION '%',s.mensaje; END IF;
    SELECT * INTO res FROM resolver_reembolso(p_id_usuario_actor::integer,s.id_solicitud,'ejecutar',p_motivo::text,
        coalesce(nullif(current_setting('app.ip',true),''),'127.0.0.1'),FALSE);
    IF NOT res.exito THEN RAISE EXCEPTION '%',res.mensaje; END IF;
END $$;

-- Fuente: docs/compañeroC/sql_C-03.sql

-- C-03 integrado con las tablas reales de B.

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

-- Fuente: docs/compañeroC/sql_C-02.sql

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

-- Fuente: docs/compañeroC/integracion_C-01_B.sql

-- Integración de C con las tablas de B: agrega las FK que quedaron pendientes
-- y la regla de que un boleto solicitado pertenezca a la compra de la solicitud.
-- Ejecutar después de relacional_C.sql y de que existan compra, compra_detalle
-- y boleto (las reales de B o el fixture provisional). No borra datos.

DO $$
BEGIN
    IF to_regclass('public.compra') IS NULL OR to_regclass('public.boleto') IS NULL
       OR to_regclass('public.compra_detalle') IS NULL THEN
        RAISE EXCEPTION 'Faltan compra, compra_detalle o boleto. Instalar primero las tablas de B.';
    END IF;
    IF EXISTS (SELECT 1 FROM solicitud_reembolso s
               WHERE NOT EXISTS (SELECT 1 FROM compra c WHERE c.id_compra = s.id_compra)) THEN
        RAISE EXCEPTION 'Hay solicitudes de reembolso que refieren a compras inexistentes.';
    END IF;
    IF EXISTS (SELECT 1 FROM solicitud_reembolso_detalle d
               WHERE NOT EXISTS (SELECT 1 FROM boleto b WHERE b.id_boleto = d.id_boleto)) THEN
        RAISE EXCEPTION 'Hay detalles de solicitud que refieren a boletos inexistentes.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM solicitud_reembolso_detalle d
        INNER JOIN solicitud_reembolso s ON s.id_solicitud_reembolso = d.id_solicitud_reembolso
        INNER JOIN boleto b ON b.id_boleto = d.id_boleto
        INNER JOIN compra_detalle cd ON cd.id_compra = b.id_compra AND cd.id_asiento = b.id_asiento
        WHERE cd.id_compra <> s.id_compra) THEN
        RAISE EXCEPTION 'Hay boletos solicitados que no pertenecen a la compra de su solicitud.';
    END IF;
END;
$$;

ALTER TABLE solicitud_reembolso DROP CONSTRAINT IF EXISTS fk_solicitud_compra;
ALTER TABLE solicitud_reembolso
    ADD CONSTRAINT fk_solicitud_compra FOREIGN KEY (id_compra) REFERENCES compra(id_compra);

ALTER TABLE solicitud_reembolso_detalle DROP CONSTRAINT IF EXISTS fk_srd_boleto;
ALTER TABLE solicitud_reembolso_detalle
    ADD CONSTRAINT fk_srd_boleto FOREIGN KEY (id_boleto) REFERENCES boleto(id_boleto);

CREATE OR REPLACE FUNCTION validar_boleto_de_solicitud()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    compra_solicitud BIGINT;
    compra_boleto BIGINT;
BEGIN
    SELECT id_compra INTO compra_solicitud
    FROM solicitud_reembolso WHERE id_solicitud_reembolso = NEW.id_solicitud_reembolso FOR SHARE;
    SELECT cd.id_compra INTO compra_boleto
    FROM boleto b INNER JOIN compra_detalle cd ON cd.id_compra = b.id_compra AND cd.id_asiento = b.id_asiento
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

DROP TRIGGER IF EXISTS trg_validar_boleto_solicitud ON solicitud_reembolso_detalle;
CREATE TRIGGER trg_validar_boleto_solicitud
BEFORE INSERT OR UPDATE ON solicitud_reembolso_detalle
FOR EACH ROW EXECUTE FUNCTION validar_boleto_de_solicitud();

-- Fuente: docs/integracion/operaciones_compartidas.sql

CREATE OR REPLACE FUNCTION inventario_de_nueva_funcion()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN PERFORM preparar_inventario(NEW.id_funcion); RETURN NEW; END $$;
DROP TRIGGER IF EXISTS trg_inventario_nueva_funcion ON funcion;
CREATE TRIGGER trg_inventario_nueva_funcion AFTER INSERT ON funcion
FOR EACH ROW EXECUTE FUNCTION inventario_de_nueva_funcion();

CREATE OR REPLACE FUNCTION registrar_cambio_inventario()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD IS NOT DISTINCT FROM NEW THEN RETURN NEW; END IF;
    INSERT INTO asiento_auditoria_log(id_funcion,id_asiento,id_compra,id_usuario_actor,evento,estado_anterior,estado_nuevo,detalle)
    SELECT NEW.id_funcion,NEW.id_asiento,r.id_compra,nullif(current_setting('app.id_usuario',true),'')::bigint,
           'Cambio inventario',OLD.estado,NEW.estado,coalesce(nullif(current_setting('app.motivo',true),''),'Operacion de venta')
    FROM (SELECT coalesce(NEW.id_reserva,OLD.id_reserva) id_reserva) x LEFT JOIN reserva r USING(id_reserva);
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_log_inventario ON inventario_funcion;
CREATE TRIGGER trg_log_inventario AFTER UPDATE ON inventario_funcion
FOR EACH ROW EXECUTE FUNCTION registrar_cambio_inventario();

CREATE OR REPLACE FUNCTION validar_detalle_venta()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM compra c JOIN tarifa t ON t.id_tarifa=NEW.id_tarifa
        JOIN asiento a ON a.id_asiento=NEW.id_asiento JOIN zona z ON z.id_zona=a.id_zona
        WHERE c.id_compra=NEW.id_compra AND c.id_funcion=t.id_funcion AND z.id_sala=(SELECT id_sala FROM funcion WHERE id_funcion=c.id_funcion)
          AND a.id_zona=t.id_zona AND NEW.id_categoria_entrada=t.id_categoria_entrada) THEN
        RAISE EXCEPTION 'Detalle, tarifa, asiento y funcion no coinciden.' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_validar_detalle_venta ON compra_detalle;
CREATE TRIGGER trg_validar_detalle_venta BEFORE INSERT OR UPDATE ON compra_detalle
FOR EACH ROW EXECUTE FUNCTION validar_detalle_venta();

CREATE OR REPLACE FUNCTION impedir_vaciar_log()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'No se puede vaciar un log.' USING ERRCODE='42501'; END $$;
DO $$ DECLARE tabla text; BEGIN
FOREACH tabla IN ARRAY ARRAY['transaccion_log','asiento_auditoria_log','acceso_puerta_log','admin_operacion_audit'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_no_vaciar ON %I',tabla);
    EXECUTE format('CREATE TRIGGER trg_no_vaciar BEFORE TRUNCATE ON %I FOR EACH STATEMENT EXECUTE FUNCTION impedir_vaciar_log()',tabla);
END LOOP;
END $$;

-- Fuente: docs/compañeroA/proteccion_salas_A04.sql

-- A-04. Instalar después de A y de las tablas reales de B.
-- Contrato esperado: boleto tiene id_funcion/id_asiento (rama Compañera_B).
-- No crea ni reemplaza tablas de B ni instala el modelo provisional de C.

DO $$
DECLARE t text; col text; requeridas text[];
BEGIN
    FOREACH t IN ARRAY ARRAY['reserva','boleto','inventario_funcion'] LOOP
        IF to_regclass(t) IS NULL THEN
            RAISE EXCEPTION 'Falta la tabla % de B; no se instaló A-04.',t USING ERRCODE='55000';
        END IF;
        requeridas := CASE WHEN t='reserva'
            THEN ARRAY['id_funcion','id_asiento','estado','vence_en']
            ELSE ARRAY['id_funcion','id_asiento','estado'] END;
        FOREACH col IN ARRAY requeridas LOOP
            IF NOT EXISTS (SELECT 1 FROM pg_attribute
                WHERE attrelid=to_regclass(t) AND attname=col AND attnum>0 AND NOT attisdropped) THEN
                RAISE EXCEPTION 'Contrato de B incompatible: falta %.%.',t,col USING ERRCODE='55000';
            END IF;
        END LOOP;
    END LOOP;
END $$;

LOCK TABLE sala,zona,asiento,funcion,reserva,boleto,inventario_funcion IN SHARE ROW EXCLUSIVE MODE;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM (
            SELECT id_funcion,id_asiento FROM reserva
            UNION ALL SELECT id_funcion,id_asiento FROM boleto
            UNION ALL SELECT id_funcion,id_asiento FROM inventario_funcion
        ) b INNER JOIN funcion f ON f.id_funcion=b.id_funcion
        INNER JOIN asiento a ON a.id_asiento=b.id_asiento
        INNER JOIN zona z ON z.id_zona=a.id_zona
        WHERE z.id_sala<>f.id_sala
    ) THEN
        RAISE EXCEPTION 'Hay ocupaciones de B con asientos de otra sala. Corrige los datos antes de instalar A-04.'
            USING ERRCODE='55000';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION a04_exigir_aislamiento()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('transaction_isolation')<>'read committed' THEN
        RAISE EXCEPTION 'A-04 requiere READ COMMITTED para revalidar después del bloqueo.'
            USING ERRCODE='55000';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION a04_bloquear_sala(p_sala integer)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM a04_exigir_aislamiento();
    PERFORM id_sala FROM sala WHERE id_sala=p_sala FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La sala ya no existe.' USING ERRCODE='23503';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION a04_hay_actividad(p_sala integer,p_funcion integer DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
    IF p_sala IS NULL THEN RETURN FALSE; END IF;
    RETURN EXISTS (
        SELECT 1 FROM reserva r INNER JOIN funcion f ON f.id_funcion=r.id_funcion
        WHERE f.id_sala=p_sala AND (p_funcion IS NULL OR f.id_funcion=p_funcion)
          AND lower(r.estado)='activa' AND r.vence_en>clock_timestamp()
    ) OR EXISTS (
        SELECT 1 FROM boleto b INNER JOIN funcion f ON f.id_funcion=b.id_funcion
        WHERE f.id_sala=p_sala AND (p_funcion IS NULL OR f.id_funcion=p_funcion)
          AND lower(b.estado) IN ('emitido','usado') AND f.fin>clock_timestamp()
    ) OR EXISTS (
        SELECT 1 FROM inventario_funcion i INNER JOIN funcion f ON f.id_funcion=i.id_funcion
        WHERE f.id_sala=p_sala AND (p_funcion IS NULL OR f.id_funcion=p_funcion)
          AND i.estado IN ('bloqueado','vendido') AND f.fin>clock_timestamp()
    );
END $$;

-- B comparte la sala: no puede confirmar una ocupación durante un cambio de A.
CREATE OR REPLACE FUNCTION a04_coordinar_ocupacion()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE antes jsonb:=to_jsonb(OLD); despues jsonb:=to_jsonb(NEW);
        sala_funcion integer; sala_asiento integer;
BEGIN
    PERFORM a04_exigir_aislamiento();
    PERFORM s.id_sala FROM sala s INNER JOIN funcion f ON f.id_sala=s.id_sala
    WHERE f.id_funcion IN ((antes->>'id_funcion')::integer,(despues->>'id_funcion')::integer)
    ORDER BY s.id_sala FOR SHARE OF s;
    IF TG_OP<>'DELETE' THEN
        SELECT id_sala INTO sala_funcion FROM funcion WHERE id_funcion=NEW.id_funcion;
        SELECT z.id_sala INTO sala_asiento FROM asiento a INNER JOIN zona z ON z.id_zona=a.id_zona
        WHERE a.id_asiento=NEW.id_asiento;
        IF sala_funcion IS NULL OR sala_asiento IS DISTINCT FROM sala_funcion THEN
            RAISE EXCEPTION 'El asiento ya no pertenece a la sala de la función.' USING ERRCODE='23503';
        END IF;
    END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION a04_proteger_distribucion()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE antes jsonb:=to_jsonb(OLD); despues jsonb:=to_jsonb(NEW);
        sala_antes integer; sala_despues integer; funcion_objetivo integer;
BEGIN
    PERFORM a04_exigir_aislamiento();
    IF TG_OP='UPDATE' AND antes IS NOT DISTINCT FROM despues THEN RETURN NEW; END IF;
    IF TG_TABLE_NAME='asiento' THEN
        SELECT id_sala INTO sala_antes FROM zona WHERE id_zona=(antes->>'id_zona')::integer;
        SELECT id_sala INTO sala_despues FROM zona WHERE id_zona=(despues->>'id_zona')::integer;
    ELSE
        sala_antes:=(antes->>'id_sala')::integer;
        sala_despues:=(despues->>'id_sala')::integer;
    END IF;
    PERFORM id_sala FROM sala WHERE id_sala IN (sala_antes,sala_despues)
    ORDER BY id_sala FOR UPDATE;
    IF TG_TABLE_NAME='funcion' THEN
        funcion_objetivo:=OLD.id_funcion;
        IF EXISTS (SELECT 1 FROM boleto WHERE id_funcion=funcion_objetivo
                   AND lower(estado) IN ('emitido','usado')) THEN
            RAISE EXCEPTION 'La función tiene boletos vigentes; requiere un flujo de reprogramación.'
                USING ERRCODE='55000';
        END IF;
    END IF;
    IF a04_hay_actividad(sala_antes,funcion_objetivo)
       OR a04_hay_actividad(sala_despues,funcion_objetivo) THEN
        RAISE EXCEPTION 'La sala tiene reservas o ventas activas. No se puede cambiar su distribución o función.'
            USING ERRCODE='55000';
    END IF;
    -- Conservar la ubicación de asientos con referencias históricas.
    IF TG_TABLE_NAME='asiento' AND TG_OP='UPDATE' THEN
        IF EXISTS (SELECT 1 FROM reserva WHERE id_asiento=OLD.id_asiento)
           OR EXISTS (SELECT 1 FROM boleto WHERE id_asiento=OLD.id_asiento)
           OR EXISTS (SELECT 1 FROM inventario_funcion WHERE id_asiento=OLD.id_asiento) THEN
            RAISE EXCEPTION 'El asiento tiene referencias de B; conserva su ubicación.' USING ERRCODE='55000';
        END IF;
    END IF;
    IF TG_TABLE_NAME='zona' AND TG_OP='UPDATE' AND (antes->>'id_sala')::integer<>(despues->>'id_sala')::integer THEN
        IF EXISTS (SELECT 1 FROM asiento a WHERE a.id_zona=OLD.id_zona AND (
            EXISTS (SELECT 1 FROM inventario_funcion i WHERE i.id_asiento=a.id_asiento)
            OR EXISTS (SELECT 1 FROM reserva r WHERE r.id_asiento=a.id_asiento)
            OR EXISTS (SELECT 1 FROM boleto b WHERE b.id_asiento=a.id_asiento))) THEN
            RAISE EXCEPTION 'La zona tiene asientos referenciados por B; no se puede trasladar.' USING ERRCODE='55000';
        END IF;
    END IF;
    IF TG_TABLE_NAME='asiento' AND TG_OP='DELETE' THEN
        DELETE FROM inventario_funcion WHERE id_asiento=OLD.id_asiento AND estado='disponible';
    END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_a04_distribucion ON sala;
CREATE TRIGGER trg_a04_distribucion BEFORE UPDATE OR DELETE ON sala
FOR EACH ROW EXECUTE FUNCTION a04_proteger_distribucion();
DROP TRIGGER IF EXISTS trg_a04_distribucion ON zona;
CREATE TRIGGER trg_a04_distribucion BEFORE INSERT OR UPDATE OR DELETE ON zona
FOR EACH ROW EXECUTE FUNCTION a04_proteger_distribucion();
DROP TRIGGER IF EXISTS trg_a04_distribucion ON asiento;
CREATE TRIGGER trg_a04_distribucion BEFORE INSERT OR UPDATE OR DELETE ON asiento
FOR EACH ROW EXECUTE FUNCTION a04_proteger_distribucion();
DROP TRIGGER IF EXISTS trg_a04_distribucion ON funcion;
CREATE TRIGGER trg_a04_distribucion BEFORE UPDATE OR DELETE ON funcion
FOR EACH ROW EXECUTE FUNCTION a04_proteger_distribucion();

DROP TRIGGER IF EXISTS trg_a04_ocupacion ON reserva;
CREATE TRIGGER trg_a04_ocupacion BEFORE INSERT OR UPDATE OR DELETE ON reserva
FOR EACH ROW EXECUTE FUNCTION a04_coordinar_ocupacion();
DROP TRIGGER IF EXISTS trg_a04_ocupacion ON boleto;
CREATE TRIGGER trg_a04_ocupacion BEFORE INSERT OR UPDATE OR DELETE ON boleto
FOR EACH ROW EXECUTE FUNCTION a04_coordinar_ocupacion();
DROP TRIGGER IF EXISTS trg_a04_ocupacion ON inventario_funcion;
CREATE TRIGGER trg_a04_ocupacion BEFORE INSERT OR UPDATE OR DELETE ON inventario_funcion
FOR EACH ROW EXECUTE FUNCTION a04_coordinar_ocupacion();

-- Fuente: docs/compañeroC/c04_reportes.sql

-- =============================================================================
-- PROYECTO BD IMAX - BLOQUE C - ISSUE C-04 (#18)
-- Archivo sugerido: sql/c04_reportes.sql
-- Contenido: cuatro reportes analíticos con RBAC en servidor.
--

-- Definiciones comunes (acuerdos §4 y §11):
--   * Moneda: USD (CHECK en compra/tarifa). No se mezclan monedas.
--   * Ventanas móviles: semana = 168 h, mes = 720 h, intervalos [desde, hasta)
--     con un único instante de corte.
--   * Venta "cobrada": compra en pagada | parcialmente_reembolsada | reembolsada.
--   * Un boleto 'Anulado' solo se origina en un reembolso (revertir_venta), por lo que
--     el importe devuelto = suma de total_linea de los boletos anulados.
--   * Cada reporte preagrega por función/película/método ANTES de unir, para no
--     multiplicar importes ni conteos.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- REPORTE 1. Ocupación y recaudación por función (todas o una función)
--   Capacidad  = asientos de todas las zonas de la sala de la función.
--   Vendidos   = boletos emitidos + usados (los anulados no ocupan asiento).
--   Bruto      = suma de total_linea de las líneas de compras cobradas.
--   Devuelto   = suma de total_linea de los boletos anulados de esas compras.
--   Neto       = Bruto - Devuelto.  (No se resta dos veces: el bruto incluye las
--                líneas luego reembolsadas.)
--   Incluye funciones sin ventas (LEFT JOIN): ocupación 0 % e ingresos 0.00.
--   Filtro opcional por función y por rango del inicio de la función.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reporte_ocupacion_recaudacion(
    p_id_usuario integer,
    p_id_funcion integer     DEFAULT NULL,
    p_desde      timestamptz DEFAULT NULL,
    p_hasta      timestamptz DEFAULT NULL)
RETURNS TABLE (
    id_funcion           integer,
    pelicula             text,
    cine                 text,
    sala                 text,
    inicio               timestamptz,
    capacidad            bigint,
    boletos_vendidos     bigint,
    boletos_usados       bigint,
    porcentaje_ocupacion numeric,
    ingreso_bruto        numeric,
    total_devuelto       numeric,
    ingreso_neto         numeric,
    moneda               text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
    IF NOT autorizar_accion(p_id_usuario, 'ver_reportes_financieros') THEN
        RAISE EXCEPTION 'El usuario no posee permiso para consultar reportes financieros.'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    WITH capacidad AS (
        SELECT z.id_sala, count(a.id_asiento) AS asientos
        FROM zona z
        INNER JOIN asiento a ON a.id_zona = z.id_zona
        GROUP BY z.id_sala
    ),
    ventas AS (
        SELECT c.id_funcion,
               count(b.id_boleto) FILTER (WHERE b.estado IN ('Emitido', 'Usado')) AS vendidos,
               count(b.id_boleto) FILTER (WHERE b.estado = 'Usado')               AS usados,
               coalesce(sum(cd.total_linea), 0)                                   AS bruto,
               coalesce(sum(cd.total_linea) FILTER (WHERE b.estado = 'Anulado'), 0) AS devuelto
        FROM compra c
        INNER JOIN compra_detalle cd ON cd.id_compra = c.id_compra
        LEFT  JOIN boleto b          ON b.id_compra = cd.id_compra AND b.id_asiento = cd.id_asiento
        WHERE c.estado IN ('Pagada', 'ParcialmenteReembolsada', 'Reembolsada')
        GROUP BY c.id_funcion
    )
    SELECT f.id_funcion,
           p.titulo::text,
           ci.nombre::text,
           s.nombre::text,
           f.inicio,
           coalesce(cap.asientos, 0)::bigint,
           coalesce(v.vendidos, 0)::bigint,
           coalesce(v.usados, 0)::bigint,
           round(100.0 * coalesce(v.vendidos, 0) / nullif(cap.asientos, 0), 2),
           coalesce(v.bruto, 0)::numeric(12,2),
           coalesce(v.devuelto, 0)::numeric(12,2),
           (coalesce(v.bruto, 0) - coalesce(v.devuelto, 0))::numeric(12,2),
           'USD'::text
    FROM funcion f
    INNER JOIN pelicula p  ON p.id_pelicula = f.id_pelicula
    INNER JOIN sala s      ON s.id_sala = f.id_sala
    INNER JOIN cine ci     ON ci.id_cine = s.id_cine
    LEFT  JOIN capacidad cap ON cap.id_sala = f.id_sala
    LEFT  JOIN ventas v      ON v.id_funcion = f.id_funcion
    WHERE (p_id_funcion IS NULL OR f.id_funcion = p_id_funcion)
      AND (p_desde IS NULL OR f.inicio >= p_desde)
      AND (p_hasta IS NULL OR f.inicio <  p_hasta)
    ORDER BY f.inicio DESC, f.id_funcion;
END;
$$;

-- -----------------------------------------------------------------------------
-- REPORTE 2. Top 5 películas por boletos vendidos en los últimos 7 días
--   Ventana: [corte - 168 h, corte). Fecha usada: boleto.emitido_en.
--   Cuenta boletos emitidos/usados al corte (excluye anulados) de compras cobradas.
--   Los boletos de cortesía (total 0) cuentan como boleto emitido: son demanda real.
--   Desempate: menor id_pelicula.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reporte_top5_peliculas_semana(
    p_id_usuario integer,
    p_corte      timestamptz DEFAULT CURRENT_TIMESTAMP)
RETURNS TABLE (
    posicion         integer,
    id_pelicula      integer,
    titulo           text,
    clasificacion    text,
    boletos_vendidos bigint,
    recaudacion      numeric,
    moneda           text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
    IF NOT autorizar_accion(p_id_usuario, 'ver_reportes_financieros') THEN
        RAISE EXCEPTION 'El usuario no posee permiso para consultar reportes financieros.'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    WITH por_pelicula AS (
        SELECT f.id_pelicula,
               count(b.id_boleto)   AS vendidos,
               sum(cd.total_linea)  AS recaudado
        FROM boleto b
        INNER JOIN compra_detalle cd ON cd.id_compra = b.id_compra AND cd.id_asiento = b.id_asiento
        INNER JOIN compra c          ON c.id_compra = cd.id_compra
        INNER JOIN funcion f         ON f.id_funcion = c.id_funcion
        WHERE b.emitido_en >= p_corte - INTERVAL '168 hours'
          AND b.emitido_en <  p_corte
          AND b.estado IN ('Emitido', 'Usado')
          AND c.estado IN ('Pagada', 'ParcialmenteReembolsada')
        GROUP BY f.id_pelicula
    )
    SELECT (row_number() OVER (ORDER BY pp.vendidos DESC, pe.id_pelicula))::integer,
           pe.id_pelicula,
           pe.titulo::text,
           pe.clasificacion::text,
           pp.vendidos::bigint,
           pp.recaudado::numeric(12,2),
           'USD'::text
    FROM por_pelicula pp
    INNER JOIN pelicula pe ON pe.id_pelicula = pp.id_pelicula
    ORDER BY pp.vendidos DESC, pe.id_pelicula
    LIMIT 5;
END;
$$;

-- -----------------------------------------------------------------------------
-- REPORTE 3. Métodos de pago preferidos
--   Depende de la tabla `pago` de B (acuerdos §5: id_pago, id_compra, estado, metodo,
--   monto, moneda, creado_en), que AÚN NO EXISTE en imax.sql. Mientras B no la entregue,
--   la función falla con un mensaje claro y no inventa datos.
--   Denominadores explícitos (acuerdos §11), solo pagos 'Aprobado' del periodo:
--     pct_compras = compras pagadas con el método / compras pagadas totales
--     pct_monto   = monto del método / monto aprobado total
--   Las devoluciones NO cuentan como pagos nuevos y se muestran aparte.
--   Periodo por omisión: [corte - 720 h, corte).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reporte_metodos_pago(
    p_id_usuario integer,
    p_desde      timestamptz DEFAULT NULL,
    p_hasta      timestamptz DEFAULT NULL)
RETURNS TABLE (
    metodo       text,
    compras      bigint,
    pct_compras  numeric,
    monto        numeric,
    pct_monto    numeric,
    moneda       text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_hasta timestamptz := coalesce(p_hasta, CURRENT_TIMESTAMP);
    v_desde timestamptz := coalesce(p_desde, coalesce(p_hasta, CURRENT_TIMESTAMP) - INTERVAL '720 hours');
BEGIN
    IF NOT autorizar_accion(p_id_usuario, 'ver_reportes_financieros') THEN
        RAISE EXCEPTION 'El usuario no posee permiso para consultar reportes financieros.'
            USING ERRCODE = '42501';
    END IF;
    IF to_regclass('public.pago') IS NULL THEN
        RAISE EXCEPTION 'La tabla pago (B-01/B-03) aún no existe: el reporte de métodos de pago no puede calcularse.'
            USING ERRCODE = '55000';
    END IF;

    RETURN QUERY
    WITH por_metodo AS (
        SELECT pg.metodo::text AS met,
               count(DISTINCT pg.id_compra) AS n_compras,
               sum(pg.monto)                AS monto_met
        FROM pago pg
        WHERE pg.estado = 'Aprobado'
          AND pg.creado_en >= v_desde AND pg.creado_en < v_hasta
        GROUP BY pg.metodo
    ),
    totales AS (
        SELECT sum(pm.n_compras) AS t_compras, sum(pm.monto_met) AS t_monto
        FROM por_metodo pm
    )
    SELECT m.met,
           m.n_compras::bigint,
           round(100.0 * m.n_compras / nullif(t.t_compras, 0), 2),
           m.monto_met::numeric(12,2),
           round(100.0 * m.monto_met / nullif(t.t_monto, 0), 2),
           'USD'::text
    FROM por_metodo m CROSS JOIN totales t
    ORDER BY m.n_compras DESC, m.met;
END;
$$;

-- -----------------------------------------------------------------------------
-- REPORTE 4a. Auditoría crítica del último mes AGRUPADA por administrador
--   Ventana por omisión: [corte - 720 h, corte). Solo acciones del rol administrador;
--   los intentos denegados ('denegado:*') se cuentan aparte, no como acciones manuales.
--   Misma lógica que C-05 (consultas_sql_c_05.sql, Q2a), con control RBAC.
--   Permiso: ver_auditoria (contador y administrador).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reporte_auditoria_por_administrador(
    p_id_usuario integer,
    p_desde      timestamptz DEFAULT NULL,
    p_hasta      timestamptz DEFAULT NULL)
RETURNS TABLE (
    id_administrador               integer,
    nombre_administrador           text,
    acciones_manuales              bigint,
    cortesias                      bigint,
    reembolsos                     bigint,
    reembolsos_forzados            bigint,
    reembolsos_rechazados          bigint,
    cambios_asiento                bigint,
    cambios_politica               bigint,
    cambios_catalogo_precios_roles bigint,
    intentos_denegados             bigint,
    ultima_accion                  timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_hasta timestamptz := coalesce(p_hasta, CURRENT_TIMESTAMP);
    v_desde timestamptz := coalesce(p_desde, coalesce(p_hasta, CURRENT_TIMESTAMP) - INTERVAL '720 hours');
BEGIN
    IF NOT autorizar_accion(p_id_usuario, 'ver_auditoria') THEN
        RAISE EXCEPTION 'El usuario no posee permiso para consultar la auditoría.'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT a.id_usuario_actor,
           u.nombre::text,
           count(*) FILTER (WHERE a.accion NOT LIKE 'denegado:%'),
           count(*) FILTER (WHERE a.accion = 'otorgar_cortesia'),
           count(*) FILTER (WHERE a.accion IN ('reembolso_ordinario', 'reembolso_forzado')),
           count(*) FILTER (WHERE a.accion = 'reembolso_forzado'),
           count(*) FILTER (WHERE a.accion = 'rechazar_reembolso'),
           count(*) FILTER (WHERE a.accion = 'cambio_asiento'),
           count(*) FILTER (WHERE a.accion = 'configurar_politica'),
           count(*) FILTER (WHERE a.accion ~ '^(insert|update|delete)_'),
           count(*) FILTER (WHERE a.accion LIKE 'denegado:%'),
           max(a.fecha)
    FROM admin_operacion_audit a
    INNER JOIN usuario u ON u.id_usuario = a.id_usuario_actor
    WHERE a.rol_al_actuar = 'administrador'
      AND a.fecha >= v_desde AND a.fecha < v_hasta
    GROUP BY a.id_usuario_actor, u.nombre
    ORDER BY a.id_usuario_actor;
END;
$$;

-- -----------------------------------------------------------------------------
-- REPORTE 4b. Detalle consultable de las mismas acciones (misma ventana y filtro).
--   "cambios" no contiene password_hash: auditar_cambio_critico() lo elimina.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reporte_auditoria_detalle(
    p_id_usuario integer,
    p_desde      timestamptz DEFAULT NULL,
    p_hasta      timestamptz DEFAULT NULL)
RETURNS TABLE (
    id_administrador integer,
    fecha            timestamptz,
    accion           text,
    entidad          text,
    id_entidad       text,
    ip               text,
    motivo           text,
    cambios          jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
    v_hasta timestamptz := coalesce(p_hasta, CURRENT_TIMESTAMP);
    v_desde timestamptz := coalesce(p_desde, coalesce(p_hasta, CURRENT_TIMESTAMP) - INTERVAL '720 hours');
BEGIN
    IF NOT autorizar_accion(p_id_usuario, 'ver_auditoria') THEN
        RAISE EXCEPTION 'El usuario no posee permiso para consultar la auditoría.'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT a.id_usuario_actor,
           a.fecha,
           a.accion::text,
           a.entidad::text,
           a.id_entidad::text,
           a.ip::text,
           a.motivo,
           a.cambios
    FROM admin_operacion_audit a
    WHERE a.rol_al_actuar = 'administrador'
      AND a.accion NOT LIKE 'denegado:%'
      AND a.fecha >= v_desde AND a.fecha < v_hasta
    ORDER BY a.id_usuario_actor, a.fecha DESC, a.id_admin_operacion_audit DESC;
END;
$$;

-- -----------------------------------------------------------------------------
-- PRIVILEGIOS: solo la cuenta de aplicación puede ejecutar los reportes; el permiso
-- de negocio lo decide autorizar_accion dentro de cada función (SECURITY DEFINER).
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.reporte_ocupacion_recaudacion(integer, integer, timestamptz, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reporte_top5_peliculas_semana(integer, timestamptz)                       FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reporte_metodos_pago(integer, timestamptz, timestamptz)                   FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reporte_auditoria_por_administrador(integer, timestamptz, timestamptz)    FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reporte_auditoria_detalle(integer, timestamptz, timestamptz)              FROM PUBLIC;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'imax_app') THEN
        GRANT EXECUTE ON FUNCTION public.reporte_ocupacion_recaudacion(integer, integer, timestamptz, timestamptz) TO imax_app;
        GRANT EXECUTE ON FUNCTION public.reporte_top5_peliculas_semana(integer, timestamptz)                       TO imax_app;
        GRANT EXECUTE ON FUNCTION public.reporte_metodos_pago(integer, timestamptz, timestamptz)                   TO imax_app;
        GRANT EXECUTE ON FUNCTION public.reporte_auditoria_por_administrador(integer, timestamptz, timestamptz)    TO imax_app;
        GRANT EXECUTE ON FUNCTION public.reporte_auditoria_detalle(integer, timestamptz, timestamptz)              TO imax_app;
    END IF;
END $$;

COMMENT ON FUNCTION public.reporte_ocupacion_recaudacion(integer, integer, timestamptz, timestamptz) IS
  'C-04: ocupación y recaudación neta por función; preagrega ventas antes de unir; incluye funciones sin ventas.';
COMMENT ON FUNCTION public.reporte_top5_peliculas_semana(integer, timestamptz) IS
  'C-04: top 5 películas por boletos emitidos/usados en 168 h móviles; desempate por id_pelicula.';
COMMENT ON FUNCTION public.reporte_metodos_pago(integer, timestamptz, timestamptz) IS
  'C-04: porcentaje de compras y de monto por método de pago aprobado; requiere la tabla pago de B.';
COMMENT ON FUNCTION public.reporte_auditoria_por_administrador(integer, timestamptz, timestamptz) IS
  'C-04: acciones manuales de los últimos 720 h agrupadas por administrador (RN-20).';

COMMIT;
