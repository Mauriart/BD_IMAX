-- 20_indices_c07.sql · Índices candidatos de C-07 (aplicar DESPUÉS de medir el "antes").
-- Conservar solo los que EXPLAIN (ANALYZE, BUFFERS) demuestre que el optimizador usa y que mejoran.
-- Reversión para repetir la medición: sql/perf/c07_drop_indices.sql
CREATE INDEX IF NOT EXISTS idx_compra_funcion        ON compra (id_funcion);
CREATE INDEX IF NOT EXISTS idx_boleto_emitido        ON boleto (emitido_en) INCLUDE (estado, id_compra_detalle);
CREATE INDEX IF NOT EXISTS idx_funcion_pelicula      ON funcion (id_pelicula);
CREATE INDEX IF NOT EXISTS idx_audit_admin_fecha     ON admin_operacion_audit (fecha, id_usuario_actor)
                                                     WHERE rol_al_actuar = 'administrador';
CREATE INDEX IF NOT EXISTS idx_puerta_funcion_fecha  ON acceso_puerta_log (id_funcion_solicitada, fecha);
CREATE INDEX IF NOT EXISTS idx_puerta_boleto         ON acceso_puerta_log (id_boleto);
ANALYZE;
