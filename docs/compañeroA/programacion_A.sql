-- Instalar después de relacional_A.sql y ajuste_integridad_A.sql.
-- También se puede aplicar en una base existente; no elimina datos.
BEGIN;
LOCK TABLE sala, funcion IN SHARE ROW EXCLUSIVE MODE;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM funcion a
        INNER JOIN funcion b ON a.id_sala = b.id_sala AND a.id_funcion < b.id_funcion
        WHERE a.activa AND b.activa
          AND a.inicio < b.fin + INTERVAL '15 minutes'
          AND b.inicio < a.fin + INTERVAL '15 minutes'
    ) THEN
        RAISE EXCEPTION 'Existen funciones incompatibles. Revisa los horarios antes de instalar.';
    END IF;
END;
$$;

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

DROP TRIGGER IF EXISTS trg_validar_horario_funcion ON funcion;
CREATE TRIGGER trg_validar_horario_funcion
BEFORE INSERT OR UPDATE OF id_sala, inicio, fin, activa ON funcion
FOR EACH ROW EXECUTE FUNCTION validar_horario_funcion();
COMMIT;
