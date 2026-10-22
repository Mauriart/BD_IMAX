-- Instalación completa del bloque A en una base vacía.
BEGIN;
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

COMMIT;
