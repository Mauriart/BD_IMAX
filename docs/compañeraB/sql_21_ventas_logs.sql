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
('Exito', 'Rechazo', 'Fallo'))
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

CREATE OR REPLACE FUNCTION bloquear_modificacion_log() 
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
-- Lanza un mensaje de error y detiene la operación de golpe
RAISE EXCEPTION 'Los logs son inalterables (% en %)', TG_OP, TG_TABLE_NAME;
RETURN NULL;
END $$;

CREATE TRIGGER trg_tlog_inmutable
BEFORE UPDATE OR DELETE ON transaccion_log
FOR EACH ROW EXECUTE FUNCTION bloquear_modificacion_log();

CREATE TRIGGER trg_alog_inmutable
BEFORE UPDATE OR DELETE ON asiento_auditoria_log
FOR EACH ROW EXECUTE FUNCTION bloquear_modificacion_log();


-- Pruebas:
INSERT INTO transaccion_log (resultado, evento) VALUES ('Exito', 'Registro inicial');
UPDATE transaccion_log SET evento = 'x';