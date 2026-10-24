BEGIN;

-- 1. PRIVILEGIOS MÍNIMOS -
-- La aplicación solo puede leer e insertar en los logs; nunca UPDATE/DELETE/TRUNCATE.
REVOKE ALL ON public.acceso_puerta_log, public.admin_operacion_audit FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'imax_app') THEN
        REVOKE UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
            ON public.acceso_puerta_log, public.admin_operacion_audit FROM imax_app;
        GRANT SELECT, INSERT ON public.acceso_puerta_log, public.admin_operacion_audit TO imax_app;
    END IF;
END $$;

-- 2. RESTRICCIONES DE CAMPOS OBLIGATORIOS (RN-20 / acuerdos §5) 
DO $$
BEGIN
    -- 2.1 Un escaneo con id_boleto debe apuntar a un boleto real. id_boleto sigue siendo NULL
    --     para "QR inexistente" (acuerdos §5: no se exige FK a un boleto que no existe).
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_puerta_boleto') THEN
        ALTER TABLE public.acceso_puerta_log
            ADD CONSTRAINT fk_puerta_boleto FOREIGN KEY (id_boleto) REFERENCES public.boleto (id_boleto);
    END IF;
    -- 2.2 Todo rechazo documenta su motivo; el dispositivo no puede ser vacío.
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_puerta_motivo_rechazo') THEN
        ALTER TABLE public.acceso_puerta_log
            ADD CONSTRAINT ck_puerta_motivo_rechazo
            CHECK (resultado::text = 'aceptado' OR btrim(coalesce(motivo, '')) <> '');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_puerta_dispositivo') THEN
        ALTER TABLE public.acceso_puerta_log
            ADD CONSTRAINT ck_puerta_dispositivo CHECK (btrim(dispositivo::text) <> '');
    END IF;
    -- 2.3 La IP de la auditoría administrativa debe ser una dirección válida (RN-20 exige IP).
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_audit_ip') THEN
        ALTER TABLE public.admin_operacion_audit
            ADD CONSTRAINT ck_audit_ip CHECK (public.normalizar_ip(ip::text) IS NOT NULL);
    END IF;
END $$;

-- id_funcion_solicitada queda SIN FK a propósito: el log debe registrar también un intento con una
-- función mal digitada; con FK ese intento abortaría la transacción y no quedaría registrado.

-- 3. DOCUMENTACIÓN EN CATÁLOGO 
COMMENT ON TABLE public.acceso_puerta_log IS
  'C-05 / RN-20 categoría 3 (puerta). Solo INSERT. Inmutable por trigger y privilegios. Retención mínima 60 meses desde el evento; los meses > 6 se exportan a archivo WORM. Se elimina únicamente por DROP de partición ya vencida (ver documentación C-05 §4).';
COMMENT ON TABLE public.admin_operacion_audit IS
  'C-05 / RN-20 categoría 4 (administración). Solo INSERT, escrita por auditar_accion/triggers. Inmutable por trigger y privilegios. Retención mínima 60 meses desde el evento.';

COMMIT;

-- 4. ÍNDICES PROPUESTOS — NO se ejecutan aquí. Pertenecen a C-07 (EXPLAIN ANALYZE antes/después).
--    Crearlos antes de medir el "antes" invalidaría la comparación exigida por la consigna.
--    Su tamaño ya está incluido en c05_dimensionamiento.sql (columna b_idx).

-- CREATE INDEX ix_puerta_func_fecha ON public.acceso_puerta_log (id_funcion_solicitada, fecha);
-- CREATE INDEX ix_puerta_rechazos   ON public.acceso_puerta_log (id_usuario_operador, id_funcion_solicitada, fecha)
--        WHERE resultado = 'rechazado';
-- CREATE INDEX ix_puerta_boleto     ON public.acceso_puerta_log (id_boleto) WHERE id_boleto IS NOT NULL;
-- CREATE INDEX brin_puerta_fecha    ON public.acceso_puerta_log USING brin (fecha);
-- CREATE INDEX ix_audit_actor_fecha ON public.admin_operacion_audit (id_usuario_actor, fecha DESC);
-- CREATE INDEX ix_audit_accion      ON public.admin_operacion_audit (accion, fecha);
-- CREATE INDEX brin_audit_fecha     ON public.admin_operacion_audit USING brin (fecha);
