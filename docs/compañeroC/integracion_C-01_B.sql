-- Integración de C con las tablas de B: agrega las FK que quedaron pendientes
-- y la regla de que un boleto solicitado pertenezca a la compra de la solicitud.
-- Ejecutar después de relacional_C.sql y de que existan compra, compra_detalle
-- y boleto (las reales de B o el fixture provisional). No borra datos.
BEGIN;

DO $$
BEGIN
    IF to_regclass('public.compra') IS NULL OR to_regclass('public.boleto') IS NULL
       OR to_regclass('public.compra_detalle') IS NULL THEN
        RAISE EXCEPTION 'Faltan compra, compra_detalle o boleto. Instalar primero las tablas de B.';
    END IF;
    IF EXISTS (SELECT 1 FROM solicitud_reembolso s
               WHERE NOT EXISTS (SELECT 1 FROM compra c WHERE c.id_compra = s.id_compra)) THEN
        RAISE EXCEPTION 'Hay solicitudes de reembolso que refieren a compras inexistentes.';
    END IF;
    IF EXISTS (SELECT 1 FROM solicitud_reembolso_detalle d
               WHERE NOT EXISTS (SELECT 1 FROM boleto b WHERE b.id_boleto = d.id_boleto)) THEN
        RAISE EXCEPTION 'Hay detalles de solicitud que refieren a boletos inexistentes.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM solicitud_reembolso_detalle d
        INNER JOIN solicitud_reembolso s ON s.id_solicitud_reembolso = d.id_solicitud_reembolso
        INNER JOIN boleto b ON b.id_boleto = d.id_boleto
        INNER JOIN compra_detalle cd ON cd.id_compra_detalle = b.id_compra_detalle
        WHERE cd.id_compra <> s.id_compra) THEN
        RAISE EXCEPTION 'Hay boletos solicitados que no pertenecen a la compra de su solicitud.';
    END IF;
END;
$$;

ALTER TABLE solicitud_reembolso DROP CONSTRAINT IF EXISTS fk_solicitud_compra;
ALTER TABLE solicitud_reembolso
    ADD CONSTRAINT fk_solicitud_compra FOREIGN KEY (id_compra) REFERENCES compra(id_compra);

ALTER TABLE solicitud_reembolso_detalle DROP CONSTRAINT IF EXISTS fk_srd_boleto;
ALTER TABLE solicitud_reembolso_detalle
    ADD CONSTRAINT fk_srd_boleto FOREIGN KEY (id_boleto) REFERENCES boleto(id_boleto);

CREATE OR REPLACE FUNCTION validar_boleto_de_solicitud()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    compra_solicitud INT;
    compra_boleto INT;
BEGIN
    SELECT id_compra INTO compra_solicitud
    FROM solicitud_reembolso WHERE id_solicitud_reembolso = NEW.id_solicitud_reembolso FOR SHARE;
    SELECT cd.id_compra INTO compra_boleto
    FROM boleto b INNER JOIN compra_detalle cd ON cd.id_compra_detalle = b.id_compra_detalle
    WHERE b.id_boleto = NEW.id_boleto;
    -- Las referencias inexistentes las rechazan las FK.
    IF compra_solicitud IS NOT NULL AND compra_boleto IS NOT NULL
       AND compra_solicitud <> compra_boleto THEN
        RAISE EXCEPTION 'El boleto no pertenece a la compra de la solicitud de reembolso.'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_boleto_solicitud ON solicitud_reembolso_detalle;
CREATE TRIGGER trg_validar_boleto_solicitud
BEFORE INSERT OR UPDATE ON solicitud_reembolso_detalle
FOR EACH ROW EXECUTE FUNCTION validar_boleto_de_solicitud();

COMMIT;
