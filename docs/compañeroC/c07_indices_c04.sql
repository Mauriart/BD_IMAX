-- =============================================================================
-- Índices propuestos para los reportes de C-04 — PERTENECEN A C-07
-- Archivo sugerido: sql/c07_indices_c04.sql
--
-- NO ejecutar con C-04. La consigna exige EXPLAIN ANALYZE "antes y después": si se crean
-- antes de medir, el "antes" queda invalidado (mismo criterio que c05_logs_endurecimiento.sql).
-- Orden: 1) cargar dataset representativo, 2) ANALYZE, 3) guardar EXPLAIN (ANALYZE, BUFFERS)
-- "antes", 4) ejecutar este script, 5) ANALYZE, 6) guardar el "después".
--
-- Ya existen y NO se duplican: uq_cd_asiento (id_compra, id_asiento) cubre compra_detalle por
-- compra; uq_boleto_detalle cubre boleto por detalle; uq_asiento_ubicacion y uq_zona_nombre
-- cubren las uniones de capacidad. Los índices de admin_operacion_audit y acceso_puerta_log
-- ya están propuestos en c05_logs_endurecimiento.sql (sección 4).
-- Se retira idx_admin_audit_fecha_actor del borrador: usaba la columna inexistente creada_en
-- (la columna real es fecha).
-- =============================================================================

-- Reporte 2 (top 5 en 168 h): filtra por emitido_en y estado.
CREATE INDEX IF NOT EXISTS ix_boleto_emitido_vigente
    ON public.boleto (emitido_en)
    WHERE estado IN ('emitido', 'usado');

-- Reporte 1: agregación de ventas por función y estado de compra.
CREATE INDEX IF NOT EXISTS ix_compra_funcion_estado
    ON public.compra (id_funcion, estado);

-- Panel de administración: solicitudes pendientes.
CREATE INDEX IF NOT EXISTS ix_solicitud_estado_fecha
    ON public.solicitud_reembolso (estado, creada_en)
    WHERE estado = 'pendiente';

-- Reporte 3: solo si B ya entregó la tabla pago.
DO $$
BEGIN
    IF to_regclass('public.pago') IS NOT NULL THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS ix_pago_aprobado_fecha
                 ON public.pago (creado_en, metodo) WHERE estado = ''aprobado''';
    END IF;
END $$;

ANALYZE public.boleto;
ANALYZE public.compra;
ANALYZE public.solicitud_reembolso;

-- Consultas a medir (EXPLAIN no entra en el cuerpo de funciones plpgsql; se mide la consulta base).
-- Ejemplo del reporte 2:
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT f.id_pelicula, count(b.id_boleto), sum(cd.total_linea)
-- FROM boleto b
-- JOIN compra_detalle cd ON cd.id_compra_detalle = b.id_compra_detalle
-- JOIN compra c          ON c.id_compra = cd.id_compra
-- JOIN funcion f         ON f.id_funcion = c.id_funcion
-- WHERE b.emitido_en >= CURRENT_TIMESTAMP - INTERVAL '168 hours' AND b.emitido_en < CURRENT_TIMESTAMP
--   AND b.estado IN ('emitido','usado') AND c.estado IN ('pagada','parcialmente_reembolsada')
-- GROUP BY f.id_pelicula;
