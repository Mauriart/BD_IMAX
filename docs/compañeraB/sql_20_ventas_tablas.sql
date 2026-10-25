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
