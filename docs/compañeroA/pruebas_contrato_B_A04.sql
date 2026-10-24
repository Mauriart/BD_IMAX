-- Fixture de contrato para ensayos de A-04. No es la instalación de B.
-- Solo reproduce los campos/referencias que utiliza la protección de A.
DO $$
BEGIN
    IF current_schema() NOT LIKE 'ensayo_a02_%' THEN
        RAISE EXCEPTION 'Este fixture solo se ejecuta en un esquema temporal de ensayo.';
    END IF;
END $$;
CREATE TABLE reserva (
    id_reserva BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_funcion BIGINT NOT NULL REFERENCES funcion(id_funcion),
    id_asiento BIGINT NOT NULL REFERENCES asiento(id_asiento),
    estado VARCHAR(12) NOT NULL CHECK (estado IN ('activa','confirmada','expirada','liberada')),
    vence_en TIMESTAMPTZ NOT NULL
);
CREATE TABLE boleto (
    id_boleto BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_funcion BIGINT NOT NULL REFERENCES funcion(id_funcion),
    id_asiento BIGINT NOT NULL REFERENCES asiento(id_asiento),
    estado VARCHAR(10) NOT NULL CHECK (estado IN ('Emitido','Usado','Anulado'))
);
CREATE TABLE inventario_funcion (
    id_funcion INT NOT NULL REFERENCES funcion(id_funcion),
    id_asiento INT NOT NULL REFERENCES asiento(id_asiento),
    estado VARCHAR(20) NOT NULL CHECK (estado IN ('disponible','bloqueado','vendido')),
    id_reserva BIGINT REFERENCES reserva(id_reserva),
    id_boleto BIGINT UNIQUE REFERENCES boleto(id_boleto),
    PRIMARY KEY(id_funcion,id_asiento)
);
