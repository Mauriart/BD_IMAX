-- Pruebas manuales de C-01: ejecutar cada sentencia por separado.
-- Requieren instalacion_completa_A.sql y relacional_C.sql aplicados.
-- Se espera un error en cada caso salvo los marcados como ACEPTADO.
-- Si la sesión queda abortada, usar Rollback antes de la siguiente prueba.
-- Atención: las filas ACEPTADAS de auditoría no se pueden borrar (log inmutable).
-- Para un ensayo sin residuos, usar verificacion_C.sql.

-- N1: correo repetido.
INSERT INTO usuario (id_rol, nombre, correo, password_hash)
VALUES (1, 'Repetido', 'cliente1@imax.test', 'x');

-- N2: correo no normalizado.
INSERT INTO usuario (id_rol, nombre, correo, password_hash)
VALUES (1, 'Mayúsculas', 'CLIENTE9@IMAX.TEST', 'x');

-- N3: rol inexistente.
INSERT INTO usuario (id_rol, nombre, correo, password_hash)
VALUES (999, 'Sin rol', 'sinrol@imax.test', 'x');

-- N4: motivo vacío en auditoría.
INSERT INTO admin_operacion_audit (id_usuario_actor, rol_al_actuar, ip, accion, entidad, motivo)
VALUES (7, 'administrador', '127.0.0.1', 'prueba', 'rol', ' ');

-- P1: ACEPTADO (deja una fila que no se puede borrar).
INSERT INTO admin_operacion_audit (id_usuario_actor, rol_al_actuar, ip, accion, entidad, motivo)
VALUES (7, 'administrador', '127.0.0.1', 'prueba', 'rol', 'ensayo');

-- N5: modificar un registro de auditoría.
UPDATE admin_operacion_audit SET motivo = 'cambio';

-- N6: borrar registros de auditoría.
DELETE FROM admin_operacion_audit;

-- N7: estado de solicitud inválido.
INSERT INTO solicitud_reembolso (id_compra, id_usuario_actor, motivo, estado)
VALUES (1, 1, 'prueba', 'inventado');

-- N8: solicitud ejecutada sin resolutor.
INSERT INTO solicitud_reembolso (id_compra, id_usuario_actor, motivo, estado, resuelta_en)
VALUES (1, 1, 'prueba', 'ejecutada', now());

-- P2: ACEPTADO, solicitud pendiente válida.
INSERT INTO solicitud_reembolso (id_compra, id_usuario_actor, motivo)
VALUES (1, 1, 'Cambio de planes');

-- N9: resultado de puerta inválido.
INSERT INTO acceso_puerta_log (id_usuario_operador, dispositivo, resultado)
VALUES (4, 'lector-1', 'quizas');
