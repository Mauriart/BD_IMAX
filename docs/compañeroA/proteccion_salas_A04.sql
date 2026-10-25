-- A-04. Instalar después de A y de las tablas reales de B.
-- Contrato esperado: boleto tiene id_funcion/id_asiento (rama Compañera_B).
-- No crea ni reemplaza tablas de B ni instala el modelo provisional de C.
BEGIN;

DO $$
DECLARE t text; col text; requeridas text[];
BEGIN
    FOREACH t IN ARRAY ARRAY['reserva','boleto','inventario_funcion'] LOOP
        IF to_regclass(t) IS NULL THEN
            RAISE EXCEPTION 'Falta la tabla % de B; no se instaló A-04.',t USING ERRCODE='55000';
        END IF;
        requeridas := CASE WHEN t='reserva'
            THEN ARRAY['id_funcion','id_asiento','estado','vence_en']
            ELSE ARRAY['id_funcion','id_asiento','estado'] END;
        FOREACH col IN ARRAY requeridas LOOP
            IF NOT EXISTS (SELECT 1 FROM pg_attribute
                WHERE attrelid=to_regclass(t) AND attname=col AND attnum>0 AND NOT attisdropped) THEN
                RAISE EXCEPTION 'Contrato de B incompatible: falta %.%.',t,col USING ERRCODE='55000';
            END IF;
        END LOOP;
    END LOOP;
END $$;

LOCK TABLE sala,zona,asiento,funcion,reserva,boleto,inventario_funcion IN SHARE ROW EXCLUSIVE MODE;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM (
            SELECT id_funcion,id_asiento FROM reserva
            UNION ALL SELECT id_funcion,id_asiento FROM boleto
            UNION ALL SELECT id_funcion,id_asiento FROM inventario_funcion
        ) b INNER JOIN funcion f ON f.id_funcion=b.id_funcion
        INNER JOIN asiento a ON a.id_asiento=b.id_asiento
        INNER JOIN zona z ON z.id_zona=a.id_zona
        WHERE z.id_sala<>f.id_sala
    ) THEN
        RAISE EXCEPTION 'Hay ocupaciones de B con asientos de otra sala. Corrige los datos antes de instalar A-04.'
            USING ERRCODE='55000';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION a04_exigir_aislamiento()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('transaction_isolation')<>'read committed' THEN
        RAISE EXCEPTION 'A-04 requiere READ COMMITTED para revalidar después del bloqueo.'
            USING ERRCODE='55000';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION a04_bloquear_sala(p_sala integer)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM a04_exigir_aislamiento();
    PERFORM id_sala FROM sala WHERE id_sala=p_sala FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La sala ya no existe.' USING ERRCODE='23503';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION a04_hay_actividad(p_sala integer,p_funcion integer DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
    IF p_sala IS NULL THEN RETURN FALSE; END IF;
    RETURN EXISTS (
        SELECT 1 FROM reserva r INNER JOIN funcion f ON f.id_funcion=r.id_funcion
        WHERE f.id_sala=p_sala AND (p_funcion IS NULL OR f.id_funcion=p_funcion)
          AND lower(r.estado)='activa' AND r.vence_en>clock_timestamp()
    ) OR EXISTS (
        SELECT 1 FROM boleto b INNER JOIN funcion f ON f.id_funcion=b.id_funcion
        WHERE f.id_sala=p_sala AND (p_funcion IS NULL OR f.id_funcion=p_funcion)
          AND lower(b.estado) IN ('emitido','usado') AND f.fin>clock_timestamp()
    ) OR EXISTS (
        SELECT 1 FROM inventario_funcion i INNER JOIN funcion f ON f.id_funcion=i.id_funcion
        WHERE f.id_sala=p_sala AND (p_funcion IS NULL OR f.id_funcion=p_funcion)
          AND i.estado IN ('bloqueado','vendido') AND f.fin>clock_timestamp()
    );
END $$;

-- B comparte la sala: no puede confirmar una ocupación durante un cambio de A.
CREATE OR REPLACE FUNCTION a04_coordinar_ocupacion()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE antes jsonb:=to_jsonb(OLD); despues jsonb:=to_jsonb(NEW);
        sala_funcion integer; sala_asiento integer;
BEGIN
    PERFORM a04_exigir_aislamiento();
    PERFORM s.id_sala FROM sala s INNER JOIN funcion f ON f.id_sala=s.id_sala
    WHERE f.id_funcion IN ((antes->>'id_funcion')::integer,(despues->>'id_funcion')::integer)
    ORDER BY s.id_sala FOR SHARE OF s;
    IF TG_OP<>'DELETE' THEN
        SELECT id_sala INTO sala_funcion FROM funcion WHERE id_funcion=NEW.id_funcion;
        SELECT z.id_sala INTO sala_asiento FROM asiento a INNER JOIN zona z ON z.id_zona=a.id_zona
        WHERE a.id_asiento=NEW.id_asiento;
        IF sala_funcion IS NULL OR sala_asiento IS DISTINCT FROM sala_funcion THEN
            RAISE EXCEPTION 'El asiento ya no pertenece a la sala de la función.' USING ERRCODE='23503';
        END IF;
    END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION a04_proteger_distribucion()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE antes jsonb:=to_jsonb(OLD); despues jsonb:=to_jsonb(NEW);
        sala_antes integer; sala_despues integer; funcion_objetivo integer;
BEGIN
    PERFORM a04_exigir_aislamiento();
    IF TG_OP='UPDATE' AND antes IS NOT DISTINCT FROM despues THEN RETURN NEW; END IF;
    IF TG_TABLE_NAME='asiento' THEN
        SELECT id_sala INTO sala_antes FROM zona WHERE id_zona=(antes->>'id_zona')::integer;
        SELECT id_sala INTO sala_despues FROM zona WHERE id_zona=(despues->>'id_zona')::integer;
    ELSE
        sala_antes:=(antes->>'id_sala')::integer;
        sala_despues:=(despues->>'id_sala')::integer;
    END IF;
    PERFORM id_sala FROM sala WHERE id_sala IN (sala_antes,sala_despues)
    ORDER BY id_sala FOR UPDATE;
    IF TG_TABLE_NAME='funcion' THEN
        funcion_objetivo:=OLD.id_funcion;
        IF EXISTS (SELECT 1 FROM boleto WHERE id_funcion=funcion_objetivo
                   AND lower(estado) IN ('emitido','usado')) THEN
            RAISE EXCEPTION 'La función tiene boletos vigentes; requiere un flujo de reprogramación.'
                USING ERRCODE='55000';
        END IF;
    END IF;
    IF a04_hay_actividad(sala_antes,funcion_objetivo)
       OR a04_hay_actividad(sala_despues,funcion_objetivo) THEN
        RAISE EXCEPTION 'La sala tiene reservas o ventas activas. No se puede cambiar su distribución o función.'
            USING ERRCODE='55000';
    END IF;
    -- Conservar la ubicación de asientos con referencias históricas.
    IF TG_TABLE_NAME='asiento' AND TG_OP='UPDATE' THEN
        IF EXISTS (SELECT 1 FROM reserva WHERE id_asiento=OLD.id_asiento)
           OR EXISTS (SELECT 1 FROM boleto WHERE id_asiento=OLD.id_asiento)
           OR EXISTS (SELECT 1 FROM inventario_funcion WHERE id_asiento=OLD.id_asiento) THEN
            RAISE EXCEPTION 'El asiento tiene referencias de B; conserva su ubicación.' USING ERRCODE='55000';
        END IF;
    END IF;
    IF TG_TABLE_NAME='zona' AND TG_OP='UPDATE' AND (antes->>'id_sala')::integer<>(despues->>'id_sala')::integer THEN
        IF EXISTS (SELECT 1 FROM asiento a WHERE a.id_zona=OLD.id_zona AND (
            EXISTS (SELECT 1 FROM inventario_funcion i WHERE i.id_asiento=a.id_asiento)
            OR EXISTS (SELECT 1 FROM reserva r WHERE r.id_asiento=a.id_asiento)
            OR EXISTS (SELECT 1 FROM boleto b WHERE b.id_asiento=a.id_asiento))) THEN
            RAISE EXCEPTION 'La zona tiene asientos referenciados por B; no se puede trasladar.' USING ERRCODE='55000';
        END IF;
    END IF;
    IF TG_TABLE_NAME='asiento' AND TG_OP='DELETE' THEN
        DELETE FROM inventario_funcion WHERE id_asiento=OLD.id_asiento AND estado='disponible';
    END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_a04_distribucion ON sala;
CREATE TRIGGER trg_a04_distribucion BEFORE UPDATE OR DELETE ON sala
FOR EACH ROW EXECUTE FUNCTION a04_proteger_distribucion();
DROP TRIGGER IF EXISTS trg_a04_distribucion ON zona;
CREATE TRIGGER trg_a04_distribucion BEFORE INSERT OR UPDATE OR DELETE ON zona
FOR EACH ROW EXECUTE FUNCTION a04_proteger_distribucion();
DROP TRIGGER IF EXISTS trg_a04_distribucion ON asiento;
CREATE TRIGGER trg_a04_distribucion BEFORE INSERT OR UPDATE OR DELETE ON asiento
FOR EACH ROW EXECUTE FUNCTION a04_proteger_distribucion();
DROP TRIGGER IF EXISTS trg_a04_distribucion ON funcion;
CREATE TRIGGER trg_a04_distribucion BEFORE UPDATE OR DELETE ON funcion
FOR EACH ROW EXECUTE FUNCTION a04_proteger_distribucion();

DROP TRIGGER IF EXISTS trg_a04_ocupacion ON reserva;
CREATE TRIGGER trg_a04_ocupacion BEFORE INSERT OR UPDATE OR DELETE ON reserva
FOR EACH ROW EXECUTE FUNCTION a04_coordinar_ocupacion();
DROP TRIGGER IF EXISTS trg_a04_ocupacion ON boleto;
CREATE TRIGGER trg_a04_ocupacion BEFORE INSERT OR UPDATE OR DELETE ON boleto
FOR EACH ROW EXECUTE FUNCTION a04_coordinar_ocupacion();
DROP TRIGGER IF EXISTS trg_a04_ocupacion ON inventario_funcion;
CREATE TRIGGER trg_a04_ocupacion BEFORE INSERT OR UPDATE OR DELETE ON inventario_funcion
FOR EACH ROW EXECUTE FUNCTION a04_coordinar_ocupacion();
COMMIT;
