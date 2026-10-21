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