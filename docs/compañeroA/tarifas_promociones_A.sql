-- Ejecutar después de relacional_A.sql, ajuste_integridad_A.sql y programacion_A.sql.
-- Agrega condiciones consultables y rechaza tarifas ambiguas. No borra datos.
BEGIN;

LOCK TABLE funcion, tarifa IN SHARE ROW EXCLUSIVE MODE;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM tarifa a INNER JOIN tarifa b
          ON a.id_funcion = b.id_funcion AND a.id_zona = b.id_zona
         AND a.id_categoria_entrada = b.id_categoria_entrada AND a.id_tarifa < b.id_tarifa
        WHERE a.vigente_desde < b.vigente_hasta AND a.vigente_hasta > b.vigente_desde
    ) THEN
        RAISE EXCEPTION 'Hay tarifas con vigencias superpuestas. Revisarlas antes de instalar el ajuste.';
    END IF;
END;
$$;

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

DROP TRIGGER IF EXISTS trg_validar_vigencia_tarifa ON tarifa;
CREATE TRIGGER trg_validar_vigencia_tarifa
BEFORE INSERT OR UPDATE ON tarifa
FOR EACH ROW EXECUTE FUNCTION validar_vigencia_tarifa();

CREATE TABLE IF NOT EXISTS promocion_dia (
    id_promocion INT NOT NULL,
    dia_semana INT NOT NULL CHECK (dia_semana BETWEEN 1 AND 7),
    PRIMARY KEY (id_promocion, dia_semana),
    CONSTRAINT fk_promocion_dia_promocion FOREIGN KEY (id_promocion) REFERENCES promocion(id_promocion)
);

CREATE TABLE IF NOT EXISTS promocion_zona (
    id_promocion INT NOT NULL,
    id_zona INT NOT NULL,
    PRIMARY KEY (id_promocion, id_zona),
    CONSTRAINT fk_promocion_zona_promocion FOREIGN KEY (id_promocion) REFERENCES promocion(id_promocion),
    CONSTRAINT fk_promocion_zona_zona FOREIGN KEY (id_zona) REFERENCES zona(id_zona)
);

CREATE TABLE IF NOT EXISTS promocion_categoria (
    id_promocion INT NOT NULL,
    id_categoria_entrada INT NOT NULL,
    PRIMARY KEY (id_promocion, id_categoria_entrada),
    CONSTRAINT fk_promocion_categoria_promocion FOREIGN KEY (id_promocion) REFERENCES promocion(id_promocion),
    CONSTRAINT fk_promocion_categoria_categoria FOREIGN KEY (id_categoria_entrada) REFERENCES categoria_entrada(id_categoria_entrada)
);

-- Días ISO: lunes=1 a domingo=7. Sin selecciones la promoción no es aplicable.
-- Las promociones antiguas conservan su texto; sus condiciones no se deducen automáticamente.
COMMIT;
