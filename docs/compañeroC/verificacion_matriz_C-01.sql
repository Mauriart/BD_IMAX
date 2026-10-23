-- Verificación completa de la matriz de roles: 5 roles x 15 acciones = 75 combinaciones.
-- La lista esperada se copia de la sección 9 de 00_acuerdos.md y es independiente
-- de los datos cargados en rol_permiso. Ejecutar después de relacional_C.sql.
-- Termina sin cambios (solo lecturas).
DO $$
DECLARE
    fila RECORD;
    errores INT := 0;
    combinaciones INT := 0;
BEGIN
    FOR fila IN
        WITH esperado(rol, accion) AS (VALUES
            ('cliente','consultar_cartelera'), ('taquillero','consultar_cartelera'),
            ('operador_puerta','consultar_cartelera'), ('contador','consultar_cartelera'),
            ('administrador','consultar_cartelera'),
            ('administrador','gestionar_catalogo'),
            ('administrador','configurar_tarifas'),
            ('contador','ver_tarifas'), ('administrador','ver_tarifas'),
            ('cliente','reservar_comprar'),
            ('taquillero','venta_presencial'),
            ('cliente','consultar_boletos_propios'),
            ('taquillero','consultar_boletos_venta'),
            ('administrador','consultar_boletos_admin'),
            ('operador_puerta','validar_ingreso'),
            ('cliente','solicitar_reembolso'), ('taquillero','solicitar_reembolso'),
            ('administrador','solicitar_reembolso'),
            ('administrador','resolver_reembolso'),
            ('contador','ver_reportes_financieros'), ('administrador','ver_reportes_financieros'),
            ('contador','ver_auditoria'), ('administrador','ver_auditoria'),
            ('administrador','administrar_usuarios')),
        acciones AS (SELECT DISTINCT accion FROM esperado),
        representante AS (
            SELECT r.nombre AS rol, MIN(u.id_usuario) AS id_usuario
            FROM rol r INNER JOIN usuario u ON u.id_rol = r.id_rol GROUP BY r.nombre)
        SELECT rep.rol, a.accion, rep.id_usuario,
               EXISTS (SELECT 1 FROM esperado e WHERE e.rol = rep.rol AND e.accion = a.accion) AS debe
        FROM representante rep CROSS JOIN acciones a
    LOOP
        combinaciones := combinaciones + 1;
        IF autorizar_accion(fila.id_usuario, fila.accion) IS DISTINCT FROM fila.debe THEN
            errores := errores + 1;
            RAISE WARNING 'Discrepancia: rol %, acción %, esperado %', fila.rol, fila.accion, fila.debe;
        END IF;
    END LOOP;

    IF combinaciones <> 75 THEN
        RAISE EXCEPTION 'Se esperaban 75 combinaciones y se comprobaron %.', combinaciones;
    END IF;
    IF errores > 0 THEN
        RAISE EXCEPTION 'La matriz tiene % discrepancias.', errores;
    END IF;
    IF (SELECT COUNT(*) FROM rol_permiso) <> 24 THEN
        RAISE EXCEPTION 'rol_permiso contiene filas fuera de la matriz esperada.';
    END IF;
    RAISE NOTICE 'OK: 75 combinaciones rol-acción coinciden con la matriz de los acuerdos.';
END;
$$;
