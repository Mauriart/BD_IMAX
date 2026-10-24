-- C-06 · Verificación de continuidad, inalterabilidad y consistencia
-- Responsable: C (IanDavid1406)
--
-- SOLO LECTURA: no modifica datos ni esquema. Se puede ejecutar en la base


-- V01 · Versión del servidor (registrar en la evidencia)
SELECT 'V01 versión del servidor' AS verificacion,
       'registrar'                AS esperado,
       current_setting('server_version') AS obtenido,
       'INFORMATIVO'              AS resultado;

-- V02 · Parámetros relevantes para continuidad (informativo)
SELECT 'V02 parámetro ' || name AS verificacion,
       'registrar'              AS esperado,
       setting                  AS obtenido,
       'INFORMATIVO'            AS resultado
FROM pg_settings
WHERE name IN ('wal_level', 'archive_mode', 'archive_timeout',
               'synchronous_commit', 'synchronous_standby_names',
               'max_wal_senders', 'data_checksums')
ORDER BY name;

-- V03 · Triggers de inmutabilidad en los logs de C (RN-20)
SELECT 'V03 triggers de inmutabilidad (admin + puerta)' AS verificacion,
       '4'                         AS esperado,
       count(*)::text              AS obtenido,
       CASE WHEN count(*) = 4 THEN 'OK' ELSE 'REVISAR' END AS resultado
FROM pg_trigger t
WHERE NOT t.tgisinternal
  AND t.tgrelid IN ('public.admin_operacion_audit'::regclass,
                    'public.acceso_puerta_log'::regclass)
  AND t.tgname IN ('trg_admin_audit_inmutable', 'trg_admin_audit_sin_truncate',
                   'trg_puerta_log_inmutable',  'trg_puerta_log_sin_truncate');

-- V04 · La cuenta de aplicación no puede alterar los logs
--       (no devuelve filas si el rol imax_app no existe en esta instancia)
SELECT 'V04 imax_app sin UPDATE/DELETE/TRUNCATE en ' || v.t AS verificacion,
       'sin privilegios de modificación' AS esperado,
       CASE WHEN has_table_privilege(r.oid, v.t::regclass, 'UPDATE')
              OR has_table_privilege(r.oid, v.t::regclass, 'DELETE')
              OR has_table_privilege(r.oid, v.t::regclass, 'TRUNCATE')
            THEN 'tiene privilegios' ELSE 'sin privilegios' END AS obtenido,
       CASE WHEN has_table_privilege(r.oid, v.t::regclass, 'UPDATE')
              OR has_table_privilege(r.oid, v.t::regclass, 'DELETE')
              OR has_table_privilege(r.oid, v.t::regclass, 'TRUNCATE')
            THEN 'REVISAR' ELSE 'OK' END AS resultado
FROM pg_roles r
CROSS JOIN (VALUES ('public.admin_operacion_audit'),
                   ('public.acceso_puerta_log')) AS v(t)
WHERE r.rolname = 'imax_app';

-- V05 · Existencia y partición de las cuatro categorías de log
SELECT 'V05 log ' || l.nombre || ' (propietario ' || l.propietario || ')' AS verificacion,
       'existe'                                   AS esperado,
       CASE WHEN c.oid IS NULL THEN 'ausente'
            WHEN c.relkind = 'p'  THEN 'presente, particionada'
            ELSE 'presente, no particionada' END  AS obtenido,
       CASE WHEN c.oid IS NULL THEN 'PENDIENTE'
            WHEN c.relkind = 'p' THEN 'OK'
            ELSE 'INFORMATIVO' END                AS resultado
FROM (VALUES ('transaccion_log',        'B'),
             ('asiento_auditoria_log',  'B'),
             ('acceso_puerta_log',      'C'),
             ('admin_operacion_audit',  'C')) AS l(nombre, propietario)
LEFT JOIN pg_class c ON c.oid = to_regclass('public.' || l.nombre);

-- V06 · Columnas con nombres de datos sensibles (solo debe aparecer password_hash)
SELECT 'V06 columna sensible ' || table_name || '.' || column_name AS verificacion,
       'solo usuario.password_hash'                               AS esperado,
       table_name || '.' || column_name                           AS obtenido,
       CASE WHEN table_name = 'usuario' AND column_name = 'password_hash'
            THEN 'OK' ELSE 'REVISAR' END                          AS resultado
FROM information_schema.columns
WHERE table_schema = 'public'
  AND column_name ~* '(cvv|cvc|numero_tarjeta|tarjeta|card_number|password)';

-- V07 · Los logs no contienen secretos (RN-09, acuerdos §5)
SELECT 'V07 admin_operacion_audit sin password_hash/token_qr/cvv' AS verificacion,
       '0'                       AS esperado,
       count(*)::text            AS obtenido,
       CASE WHEN count(*) = 0 THEN 'OK' ELSE 'REVISAR' END AS resultado
FROM admin_operacion_audit
WHERE coalesce(cambios::text, '') || ' ' || motivo ~* '(password_hash|token_qr|cvv)';

-- V08 · Cobertura de retención (nada eliminado dentro de los 60 meses)
SELECT 'V08 retención ' || t.nombre AS verificacion,
       'sin eventos eliminados; antigüedad < 60 meses para borrar' AS esperado,
       t.filas || ' filas; desde ' || coalesce(t.desde::text, 'n/a')
              || ' hasta ' || coalesce(t.hasta::text, 'n/a')        AS obtenido,
       'INFORMATIVO' AS resultado
FROM (
    SELECT 'admin_operacion_audit' AS nombre, count(*) AS filas,
           min(fecha) AS desde, max(fecha) AS hasta
    FROM admin_operacion_audit
    UNION ALL
    SELECT 'acceso_puerta_log', count(*), min(fecha), max(fecha)
    FROM acceso_puerta_log
    -- Agregar transaccion_log y asiento_auditoria_log cuando existan (B-05).
) t;

-- V09 · Consistencia que debe cumplir una base restaurada
SELECT 'V09a boletos emitidos/usados en compras no pagadas' AS verificacion,
       '0' AS esperado, count(*)::text AS obtenido,
       CASE WHEN count(*) = 0 THEN 'OK' ELSE 'REVISAR' END AS resultado
FROM boleto b
JOIN compra_detalle cd ON cd.id_compra_detalle = b.id_compra_detalle
JOIN compra c          ON c.id_compra = cd.id_compra
WHERE b.estado IN ('emitido', 'usado')
  AND c.estado NOT IN ('pagada', 'parcialmente_reembolsada')

UNION ALL
SELECT 'V09b compras con total distinto de la suma de sus líneas',
       '0', count(*)::text,
       CASE WHEN count(*) = 0 THEN 'OK' ELSE 'REVISAR' END
FROM compra c
JOIN (SELECT id_compra, sum(total_linea) AS suma
      FROM compra_detalle GROUP BY id_compra) x ON x.id_compra = c.id_compra
WHERE c.total <> x.suma

UNION ALL
SELECT 'V09c asientos con más de una ocupación vigente por función (doble venta)',
       '0', count(*)::text,
       CASE WHEN count(*) = 0 THEN 'OK' ELSE 'REVISAR' END
FROM (
    SELECT c.id_funcion, cd.id_asiento
    FROM compra_detalle cd
    JOIN compra c ON c.id_compra = cd.id_compra
    LEFT JOIN boleto b ON b.id_compra_detalle = cd.id_compra_detalle
    WHERE c.estado IN ('pendiente', 'pagada', 'parcialmente_reembolsada')
      AND b.estado IS DISTINCT FROM 'anulado'
    GROUP BY c.id_funcion, cd.id_asiento
    HAVING count(*) > 1
) d

UNION ALL
SELECT 'V09d boletos usados sin ingreso aceptado en acceso_puerta_log',
       '0', count(*)::text,
       CASE WHEN count(*) = 0 THEN 'OK' ELSE 'INFORMATIVO' END
FROM boleto b
WHERE b.estado = 'usado'
  AND NOT EXISTS (SELECT 1 FROM acceso_puerta_log l
                  WHERE l.id_boleto = b.id_boleto AND l.resultado = 'aceptado')

UNION ALL
SELECT 'V09e solicitudes de reembolso pendientes sin boletos asociados',
       '0', count(*)::text,
       CASE WHEN count(*) = 0 THEN 'OK' ELSE 'REVISAR' END
FROM solicitud_reembolso s
WHERE s.estado = 'pendiente'
  AND NOT EXISTS (SELECT 1 FROM solicitud_reembolso_detalle d
                  WHERE d.id_solicitud_reembolso = s.id_solicitud_reembolso);

-- V10 · Resumen por rol de los permisos críticos (RN-17), para anexar a la evidencia
SELECT 'V10 permisos de ' || r.nombre AS verificacion,
       'según matriz de acuerdos §9'  AS esperado,
       string_agg(rp.accion, ', ' ORDER BY rp.accion) AS obtenido,
       'INFORMATIVO' AS resultado
FROM rol r
JOIN rol_permiso rp ON rp.id_rol = r.id_rol
GROUP BY r.nombre
ORDER BY r.nombre;

-- V11 · Restricciones del endurecimiento de C-05 (campos obligatorios de RN-20)
SELECT 'V11 restricción ' || e.conname AS verificacion,
       'presente'                      AS esperado,
       CASE WHEN c.oid IS NULL THEN 'ausente' ELSE 'presente' END AS obtenido,
       CASE WHEN c.oid IS NULL THEN 'REVISAR' ELSE 'OK' END       AS resultado
FROM (VALUES ('ck_puerta_motivo_rechazo'), ('ck_puerta_dispositivo'),
             ('fk_puerta_boleto'), ('ck_audit_ip'), ('ck_audit_motivo')) AS e(conname)
LEFT JOIN pg_constraint c ON c.conname = e.conname;

-- V12 · Si los logs se particionan, cada partición necesita sus propios triggers:
--       el BEFORE TRUNCATE del padre NO se dispara con TRUNCATE sobre una partición
--       (hallazgo de C-05 §4.4). No devuelve filas mientras no existan particiones.
SELECT 'V12 partición ' || ch.relname || ' (padre ' || pa.relname || ')' AS verificacion,
       '2 triggers (inmutable + sin_truncate)'                           AS esperado,
       count(t.oid)::text || ' triggers'                                 AS obtenido,
       CASE WHEN count(t.oid) >= 2 THEN 'OK' ELSE 'REVISAR' END          AS resultado
FROM pg_inherits i
JOIN pg_class pa ON pa.oid = i.inhparent
JOIN pg_class ch ON ch.oid = i.inhrelid
LEFT JOIN pg_trigger t ON t.tgrelid = ch.oid AND NOT t.tgisinternal
                      AND t.tgname ~ '(inmutable|sin_truncate)'
WHERE pa.relname IN ('transaccion_log', 'asiento_auditoria_log',
                     'acceso_puerta_log', 'admin_operacion_audit',
                     'acceso_puerta_log_p')
GROUP BY ch.relname, pa.relname;
