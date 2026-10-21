-- Ejecutar también en una base que ya tiene las 12 tablas.
-- No elimina tablas ni datos. Si existen tarifas incoherentes, se detiene.
BEGIN;

LOCK TABLE funcion, zona, tarifa IN SHARE ROW EXCLUSIVE MODE;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM tarifa
        INNER JOIN funcion ON tarifa.id_funcion = funcion.id_funcion
        INNER JOIN zona ON tarifa.id_zona = zona.id_zona
        WHERE funcion.id_sala <> zona.id_sala
    ) THEN
        RAISE EXCEPTION 'Hay tarifas cuya zona no pertenece a la sala de la función.';
    END IF;
END;
$$;

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

DROP TRIGGER IF EXISTS trg_validar_zona_tarifa ON tarifa;
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

DROP TRIGGER IF EXISTS trg_proteger_sala_funcion ON funcion;
CREATE TRIGGER trg_proteger_sala_funcion
BEFORE UPDATE OF id_sala ON funcion
FOR EACH ROW EXECUTE FUNCTION proteger_sala_con_tarifas();

DROP TRIGGER IF EXISTS trg_proteger_sala_zona ON zona;
CREATE TRIGGER trg_proteger_sala_zona
BEFORE UPDATE OF id_sala ON zona
FOR EACH ROW EXECUTE FUNCTION proteger_sala_con_tarifas();

COMMIT;
