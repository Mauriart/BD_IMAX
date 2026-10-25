BEGIN;
CREATE OR REPLACE FUNCTION inventario_de_nueva_funcion()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN PERFORM preparar_inventario(NEW.id_funcion); RETURN NEW; END $$;
DROP TRIGGER IF EXISTS trg_inventario_nueva_funcion ON funcion;
CREATE TRIGGER trg_inventario_nueva_funcion AFTER INSERT ON funcion
FOR EACH ROW EXECUTE FUNCTION inventario_de_nueva_funcion();

CREATE OR REPLACE FUNCTION registrar_cambio_inventario()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD IS NOT DISTINCT FROM NEW THEN RETURN NEW; END IF;
    INSERT INTO asiento_auditoria_log(id_funcion,id_asiento,id_compra,id_usuario_actor,evento,estado_anterior,estado_nuevo,detalle)
    SELECT NEW.id_funcion,NEW.id_asiento,r.id_compra,nullif(current_setting('app.id_usuario',true),'')::bigint,
           'Cambio inventario',OLD.estado,NEW.estado,coalesce(nullif(current_setting('app.motivo',true),''),'Operacion de venta')
    FROM (SELECT coalesce(NEW.id_reserva,OLD.id_reserva) id_reserva) x LEFT JOIN reserva r USING(id_reserva);
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_log_inventario ON inventario_funcion;
CREATE TRIGGER trg_log_inventario AFTER UPDATE ON inventario_funcion
FOR EACH ROW EXECUTE FUNCTION registrar_cambio_inventario();

CREATE OR REPLACE FUNCTION validar_detalle_venta()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM compra c JOIN tarifa t ON t.id_tarifa=NEW.id_tarifa
        JOIN asiento a ON a.id_asiento=NEW.id_asiento JOIN zona z ON z.id_zona=a.id_zona
        WHERE c.id_compra=NEW.id_compra AND c.id_funcion=t.id_funcion AND z.id_sala=(SELECT id_sala FROM funcion WHERE id_funcion=c.id_funcion)
          AND a.id_zona=t.id_zona AND NEW.id_categoria_entrada=t.id_categoria_entrada) THEN
        RAISE EXCEPTION 'Detalle, tarifa, asiento y funcion no coinciden.' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_validar_detalle_venta ON compra_detalle;
CREATE TRIGGER trg_validar_detalle_venta BEFORE INSERT OR UPDATE ON compra_detalle
FOR EACH ROW EXECUTE FUNCTION validar_detalle_venta();

CREATE OR REPLACE FUNCTION impedir_vaciar_log()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'No se puede vaciar un log.' USING ERRCODE='42501'; END $$;
DO $$ DECLARE tabla text; BEGIN
FOREACH tabla IN ARRAY ARRAY['transaccion_log','asiento_auditoria_log','acceso_puerta_log','admin_operacion_audit'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_no_vaciar ON %I',tabla);
    EXECUTE format('CREATE TRIGGER trg_no_vaciar BEFORE TRUNCATE ON %I FOR EACH STATEMENT EXECUTE FUNCTION impedir_vaciar_log()',tabla);
END LOOP;
END $$;
COMMIT;
