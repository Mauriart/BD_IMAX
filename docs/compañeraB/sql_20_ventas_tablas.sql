------------------------------------------------------------------------------
--Creación de tablas temporales
-- 1. Crear la tabla de roles básica de la Persona C
CREATE TABLE IF NOT EXISTS rol (
id_rol BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
nombre VARCHAR(30) NOT NULL UNIQUE
);

-- 2. Crear la tabla de usuarios básica de la Persona C
CREATE TABLE IF NOT EXISTS usuario (
id_usuario BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
id_rol BIGINT REFERENCES rol(id_rol),
nombre VARCHAR(100) NOT NULL,
correo VARCHAR(100) UNIQUE NOT NULL,
password_hash TEXT NOT NULL DEFAULT '123456',
activo BOOLEAN NOT NULL DEFAULT TRUE,
creado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Insertar un usuario de prueba para que puedas simular compras
INSERT INTO rol (nombre) VALUES ('cliente') ON CONFLICT DO NOTHING;
INSERT INTO usuario (id_rol, nombre, correo) 
VALUES (1, 'Cliente de Prueba', 'cliente@cine.com') ON CONFLICT DO NOTHING;
------------------------------------------------------------------------------

-- Creación de tabla compras
CREATE TABLE compra (
id_compra BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
id_usuario BIGINT NOT NULL REFERENCES usuario(id_usuario),
id_funcion BIGINT NOT NULL REFERENCES funcion(id_funcion),
id_promocion BIGINT REFERENCES promocion(id_promocion),
estado VARCHAR (15) NOT NULL DEFAULT 'Pendiente' CHECK (estado IN
('Pendiente', 'Pagada', 'Cancelada', 'Expirada', 'Reembolsada')),
subtotal NUMERIC (10,2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
descuento NUMERIC (10,2) NOT NULL DEFAULT 0 CHECK (descuento >= 0),
total NUMERIC (10,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
moneda CHAR(3) NOT NULL DEFAULT 'USD',
creada_en TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- Creación de tabla de reserva de asiento
CREATE TABLE reserva_asiento (
id_reserva BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
id_compra BIGINT NOT NULL REFERENCES compra(id_compra),
id_funcion BIGINT NOT NULL REFERENCES funcion(id_funcion),
id_asiento BIGINT NOT NULL REFERENCES asiento(id_asiento),
estado VARCHAR(12) NOT NULL DEFAULT 'Activa' CHECK (estado IN 
('Activa','Confirmada','Expirada','Liberada')),
categoria VARCHAR(20) NOT NULL DEFAULT 'adulto',
precio_unitariO NUMERIC(10,2) CHECK (precio_unitario >= 0),
creada_en TIMESTAMPTZ NOT NULL DEFAULT now(),
vence_en TIMESTAMPTZ NOT NULL
);


-- Indice para evitar que dos usuarios mantengan el mismo asiento activo o confirmado
CREATE UNIQUE INDEX uq_ocupacion_vigente ON reserva_asiento (id_funcion, id_asiento)
WHERE estado IN ('Activa', 'Confirmada');

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
usado_en TIMESTAMPTZ
);

-- Indice en caso de cancelaciones de compra
CREATE UNIQUE INDEX uq_boleto_vigente ON boleto (id_funcion, id_asiento)
WHERE estado IN ('Emitido','Usado');