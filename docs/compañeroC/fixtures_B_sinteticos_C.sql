-- FIXTURE PROVISIONAL de compra, compra_detalle y boleto para desarrollar C
-- sin esperar a B (B-01, issue #6). Usa los campos mínimos de 00_acuerdos.md.
-- NO es el modelo de B: cuando B entregue sus tablas, NO ejecutar este script
-- en esa base; se reemplaza por los datos sintéticos de B. Si compra, compra_detalle
-- o boleto ya existen, este script se detiene para no pisarlas.
-- Ejecutar después de instalacion_completa_A.sql y relacional_C.sql.
BEGIN;

DO $$
BEGIN
    IF to_regclass('public.compra') IS NOT NULL
       OR to_regclass('public.compra_detalle') IS NOT NULL
       OR to_regclass('public.boleto') IS NOT NULL THEN
        RAISE EXCEPTION 'Ya existen tablas de B (compra, compra_detalle o boleto). No instalar el fixture.';
    END IF;
END;
$$;

CREATE TABLE compra (
    id_compra SERIAL PRIMARY KEY,
    id_usuario_cliente INT NOT NULL,
    id_usuario_actor INT NOT NULL,
    id_funcion INT NOT NULL,
    estado VARCHAR(30) NOT NULL,
    total NUMERIC(12,2) NOT NULL,
    moneda VARCHAR(3) NOT NULL DEFAULT 'USD',
    creada_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_compra_cliente FOREIGN KEY (id_usuario_cliente) REFERENCES usuario(id_usuario),
    CONSTRAINT fk_compra_actor FOREIGN KEY (id_usuario_actor) REFERENCES usuario(id_usuario),
    CONSTRAINT fk_compra_funcion FOREIGN KEY (id_funcion) REFERENCES funcion(id_funcion),
    CONSTRAINT ck_compra_estado CHECK (estado IN ('pendiente','pagada','cancelada','expirada',
        'parcialmente_reembolsada','reembolsada')),
    CONSTRAINT ck_compra_total CHECK (total >= 0),
    CONSTRAINT ck_compra_moneda CHECK (moneda = 'USD')
);

CREATE TABLE compra_detalle (
    id_compra_detalle SERIAL PRIMARY KEY,
    id_compra INT NOT NULL,
    id_asiento INT NOT NULL,
    id_categoria_entrada INT NOT NULL,
    id_tarifa INT NOT NULL,
    id_promocion INT,
    precio_base NUMERIC(12,2) NOT NULL,
    descuento NUMERIC(12,2) NOT NULL DEFAULT 0,
    cargo_servicio NUMERIC(12,2) NOT NULL DEFAULT 0,
    total_linea NUMERIC(12,2) NOT NULL,
    CONSTRAINT fk_cd_compra FOREIGN KEY (id_compra) REFERENCES compra(id_compra),
    CONSTRAINT fk_cd_asiento FOREIGN KEY (id_asiento) REFERENCES asiento(id_asiento),
    CONSTRAINT fk_cd_categoria FOREIGN KEY (id_categoria_entrada) REFERENCES categoria_entrada(id_categoria_entrada),
    CONSTRAINT fk_cd_tarifa FOREIGN KEY (id_tarifa) REFERENCES tarifa(id_tarifa),
    CONSTRAINT fk_cd_promocion FOREIGN KEY (id_promocion) REFERENCES promocion(id_promocion),
    CONSTRAINT uq_cd_asiento UNIQUE (id_compra, id_asiento),
    CONSTRAINT ck_cd_montos CHECK (precio_base >= 0 AND descuento >= 0 AND cargo_servicio >= 0
        AND total_linea = precio_base - descuento + cargo_servicio)
);

CREATE TABLE boleto (
    id_boleto SERIAL PRIMARY KEY,
    id_compra_detalle INT NOT NULL,
    token_qr UUID NOT NULL DEFAULT gen_random_uuid(),
    estado VARCHAR(20) NOT NULL DEFAULT 'emitido',
    emitido_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usado_en TIMESTAMPTZ,
    CONSTRAINT fk_boleto_detalle FOREIGN KEY (id_compra_detalle) REFERENCES compra_detalle(id_compra_detalle),
    CONSTRAINT uq_boleto_token UNIQUE (token_qr),
    CONSTRAINT uq_boleto_detalle UNIQUE (id_compra_detalle),
    CONSTRAINT ck_boleto_estado CHECK (estado IN ('emitido','usado','anulado')),
    CONSTRAINT ck_boleto_usado CHECK ((estado = 'usado') = (usado_en IS NOT NULL))
);

-- Datos: función 1 y tarifas/asientos de los datos de ejemplo de A.
-- Compra 1: cliente 1, pagada. Boleto emitido (asiento 1) y boleto usado (asiento 2).
-- Compra 2: cliente 2, venta de taquilla, reembolsada. Boleto anulado (asiento 4).
-- Compra 3: cliente 1, pagada. Boleto emitido (asiento 3), para pruebas de reembolso.
DO $$
DECLARE
    c1 INT := (SELECT id_usuario FROM usuario WHERE correo = 'cliente1@imax.test');
    c2 INT := (SELECT id_usuario FROM usuario WHERE correo = 'cliente2@imax.test');
    tq INT := (SELECT id_usuario FROM usuario WHERE correo = 'taquillero@imax.test');
    k1 INT; k2 INT; k3 INT; d INT;
BEGIN
    INSERT INTO compra (id_usuario_cliente, id_usuario_actor, id_funcion, estado, total)
    VALUES (c1, c1, 1, 'pagada', 13.00) RETURNING id_compra INTO k1;
    INSERT INTO compra_detalle (id_compra, id_asiento, id_categoria_entrada, id_tarifa, precio_base, total_linea)
    VALUES (k1, 1, 1, 1, 8.00, 8.00) RETURNING id_compra_detalle INTO d;
    INSERT INTO boleto (id_compra_detalle, estado) VALUES (d, 'emitido');
    INSERT INTO compra_detalle (id_compra, id_asiento, id_categoria_entrada, id_tarifa, precio_base, total_linea)
    VALUES (k1, 2, 2, 2, 5.00, 5.00) RETURNING id_compra_detalle INTO d;
    INSERT INTO boleto (id_compra_detalle, estado, usado_en) VALUES (d, 'usado', CURRENT_TIMESTAMP);

    INSERT INTO compra (id_usuario_cliente, id_usuario_actor, id_funcion, estado, total)
    VALUES (c2, tq, 1, 'reembolsada', 12.00) RETURNING id_compra INTO k2;
    INSERT INTO compra_detalle (id_compra, id_asiento, id_categoria_entrada, id_tarifa, precio_base, total_linea)
    VALUES (k2, 4, 1, 3, 12.00, 12.00) RETURNING id_compra_detalle INTO d;
    INSERT INTO boleto (id_compra_detalle, estado) VALUES (d, 'anulado');

    INSERT INTO compra (id_usuario_cliente, id_usuario_actor, id_funcion, estado, total)
    VALUES (c1, c1, 1, 'pagada', 8.00) RETURNING id_compra INTO k3;
    INSERT INTO compra_detalle (id_compra, id_asiento, id_categoria_entrada, id_tarifa, precio_base, total_linea)
    VALUES (k3, 3, 1, 1, 8.00, 8.00) RETURNING id_compra_detalle INTO d;
    INSERT INTO boleto (id_compra_detalle, estado) VALUES (d, 'emitido');
END;
$$;

COMMIT;
