-- Todo ocurre dentro de una transacción que termina en ROLLBACK: no deja filas en los logs.
-- Resultado esperado: todas las filas de la tabla final con resultado = 'OK'.

BEGIN;
CREATE TEMP TABLE _v (n int, caso text, esperado text, resultado text) ON COMMIT DROP;

DO $$
DECLARE
    v_op int; v_adm int; v_bol int; v_fun int; v_state text;
BEGIN
    SELECT u.id_usuario INTO v_op  FROM usuario u JOIN rol r USING (id_rol) WHERE r.nombre='operador_puerta' AND u.activo ORDER BY 1 LIMIT 1;
    SELECT u.id_usuario INTO v_adm FROM usuario u JOIN rol r USING (id_rol) WHERE r.nombre='administrador'   AND u.activo ORDER BY 1 LIMIT 1;
    SELECT b.id_boleto, c.id_funcion INTO v_bol, v_fun FROM boleto b JOIN compra_detalle cd USING (id_compra_detalle) JOIN compra c USING (id_compra) ORDER BY 1 LIMIT 1;

    -- Datos de ensayo (se revierten)
    INSERT INTO acceso_puerta_log (id_boleto, id_funcion_solicitada, id_usuario_operador, dispositivo, resultado, motivo)
    VALUES (v_bol, v_fun, v_op, 'TOTEM-VERIF', 'aceptado', 'Acceso concedido exitosamente');
    INSERT INTO admin_operacion_audit (id_usuario_actor, rol_al_actuar, ip, accion, entidad, id_entidad, motivo)
    VALUES (v_adm, 'administrador', '127.0.0.1', 'verificacion_c05', 'prueba', '1', 'Verificación C-05');

    -- 1-2 UPDATE / DELETE bloqueados por trigger (42501)
    BEGIN UPDATE acceso_puerta_log SET motivo='alterado';
          INSERT INTO _v VALUES (1,'UPDATE en acceso_puerta_log','42501','SE PERMITIÓ');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          INSERT INTO _v VALUES (1,'UPDATE en acceso_puerta_log','42501', CASE WHEN v_state='42501' THEN 'OK' ELSE 'FALLO '||v_state END); END;
    BEGIN DELETE FROM acceso_puerta_log;
          INSERT INTO _v VALUES (2,'DELETE en acceso_puerta_log','42501','SE PERMITIÓ');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          INSERT INTO _v VALUES (2,'DELETE en acceso_puerta_log','42501', CASE WHEN v_state='42501' THEN 'OK' ELSE 'FALLO '||v_state END); END;
    BEGIN UPDATE admin_operacion_audit SET motivo='alterado';
          INSERT INTO _v VALUES (3,'UPDATE en admin_operacion_audit','42501','SE PERMITIÓ');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          INSERT INTO _v VALUES (3,'UPDATE en admin_operacion_audit','42501', CASE WHEN v_state='42501' THEN 'OK' ELSE 'FALLO '||v_state END); END;
    BEGIN DELETE FROM admin_operacion_audit;
          INSERT INTO _v VALUES (4,'DELETE en admin_operacion_audit','42501','SE PERMITIÓ');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          INSERT INTO _v VALUES (4,'DELETE en admin_operacion_audit','42501', CASE WHEN v_state='42501' THEN 'OK' ELSE 'FALLO '||v_state END); END;
    -- 5-6 TRUNCATE bloqueado
    BEGIN TRUNCATE acceso_puerta_log;
          INSERT INTO _v VALUES (5,'TRUNCATE acceso_puerta_log','42501','SE PERMITIÓ');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          INSERT INTO _v VALUES (5,'TRUNCATE acceso_puerta_log','42501', CASE WHEN v_state='42501' THEN 'OK' ELSE 'FALLO '||v_state END); END;
    BEGIN TRUNCATE admin_operacion_audit;
          INSERT INTO _v VALUES (6,'TRUNCATE admin_operacion_audit','42501','SE PERMITIÓ');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          INSERT INTO _v VALUES (6,'TRUNCATE admin_operacion_audit','42501', CASE WHEN v_state='42501' THEN 'OK' ELSE 'FALLO '||v_state END); END;

    -- 7 resultado fuera de dominio (23514)
    BEGIN INSERT INTO acceso_puerta_log (id_usuario_operador, dispositivo, resultado, motivo) VALUES (v_op,'T','quizas','x');
          INSERT INTO _v VALUES (7,'resultado inválido','23514','SE PERMITIÓ');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          INSERT INTO _v VALUES (7,'resultado inválido','23514', CASE WHEN v_state='23514' THEN 'OK' ELSE 'FALLO '||v_state END); END;
    -- 8 rechazo sin motivo (23514)
    BEGIN INSERT INTO acceso_puerta_log (id_usuario_operador, dispositivo, resultado, motivo) VALUES (v_op,'T','rechazado',NULL);
          INSERT INTO _v VALUES (8,'rechazo sin motivo','23514','SE PERMITIÓ');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          INSERT INTO _v VALUES (8,'rechazo sin motivo','23514', CASE WHEN v_state='23514' THEN 'OK' ELSE 'FALLO '||v_state END); END;
    -- 9 sin operador (23502)
    BEGIN INSERT INTO acceso_puerta_log (id_usuario_operador, dispositivo, resultado, motivo) VALUES (NULL,'T','aceptado','x');
          INSERT INTO _v VALUES (9,'escaneo sin operador','23502','SE PERMITIÓ');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          INSERT INTO _v VALUES (9,'escaneo sin operador','23502', CASE WHEN v_state='23502' THEN 'OK' ELSE 'FALLO '||v_state END); END;
    -- 10 boleto inexistente (23503)
    BEGIN INSERT INTO acceso_puerta_log (id_boleto, id_usuario_operador, dispositivo, resultado, motivo) VALUES (999999999,v_op,'T','rechazado','x');
          INSERT INTO _v VALUES (10,'FK id_boleto inexistente','23503','SE PERMITIÓ');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          INSERT INTO _v VALUES (10,'FK id_boleto inexistente','23503', CASE WHEN v_state='23503' THEN 'OK' ELSE 'FALLO '||v_state END); END;
    -- 11 QR inexistente se registra con id_boleto NULL (debe permitirse)
    BEGIN INSERT INTO acceso_puerta_log (id_boleto, id_usuario_operador, dispositivo, resultado, motivo) VALUES (NULL,v_op,'T','rechazado','Código QR no registrado o inexistente en el sistema');
          INSERT INTO _v VALUES (11,'QR inexistente con id_boleto NULL','permitido','OK');
    EXCEPTION WHEN OTHERS THEN INSERT INTO _v VALUES (11,'QR inexistente con id_boleto NULL','permitido','FALLO'); END;
    -- 12 auditoría sin motivo (23514)
    BEGIN INSERT INTO admin_operacion_audit (id_usuario_actor, rol_al_actuar, ip, accion, entidad, motivo) VALUES (v_adm,'administrador','127.0.0.1','x','y','   ');
          INSERT INTO _v VALUES (12,'auditoría con motivo vacío','23514','SE PERMITIÓ');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          INSERT INTO _v VALUES (12,'auditoría con motivo vacío','23514', CASE WHEN v_state='23514' THEN 'OK' ELSE 'FALLO '||v_state END); END;
    -- 13 auditoría con IP inválida (23514)
    BEGIN INSERT INTO admin_operacion_audit (id_usuario_actor, rol_al_actuar, ip, accion, entidad, motivo) VALUES (v_adm,'administrador','no-es-ip','x','y','m');
          INSERT INTO _v VALUES (13,'auditoría con IP inválida','23514','SE PERMITIÓ');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          INSERT INTO _v VALUES (13,'auditoría con IP inválida','23514', CASE WHEN v_state='23514' THEN 'OK' ELSE 'FALLO '||v_state END); END;
    -- 14 auditoría con actor inexistente (23503)
    BEGIN INSERT INTO admin_operacion_audit (id_usuario_actor, rol_al_actuar, ip, accion, entidad, motivo) VALUES (987654321,'administrador','127.0.0.1','x','y','m');
          INSERT INTO _v VALUES (14,'auditoría con actor inexistente','23503','SE PERMITIÓ');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          INSERT INTO _v VALUES (14,'auditoría con actor inexistente','23503', CASE WHEN v_state='23503' THEN 'OK' ELSE 'FALLO '||v_state END); END;
    -- 15 auditar_accion exige motivo (23514)
    BEGIN PERFORM auditar_accion(v_adm,'127.0.0.1','x','y','1','',NULL);
          INSERT INTO _v VALUES (15,'auditar_accion sin motivo','23514','SE PERMITIÓ');
    EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
          INSERT INTO _v VALUES (15,'auditar_accion sin motivo','23514', CASE WHEN v_state='23514' THEN 'OK' ELSE 'FALLO '||v_state END); END;
END $$;

SELECT n, caso, esperado, resultado FROM _v ORDER BY n;
ROLLBACK;
