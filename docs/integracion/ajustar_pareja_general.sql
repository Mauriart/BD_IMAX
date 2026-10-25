-- Ajuste autorizado de la promoción inicial en una base existente.
-- Requiere app.id_usuario de un administrador activo en la conexión.
-- Conserva funciones asociadas, vigencia, compras y cotizaciones anteriores.
BEGIN;
DO $$
DECLARE
    v_actor integer := nullif(current_setting('app.id_usuario',true),'')::integer;
    v_promocion integer;
    v_categoria integer;
    v_antes jsonb;
BEGIN
    IF v_actor IS NULL OR NOT autorizar_accion(v_actor,'configurar_tarifas') THEN
        RAISE EXCEPTION 'Se requiere un administrador con permiso para configurar tarifas.'
            USING ERRCODE='42501';
    END IF;
    IF (SELECT count(*) FROM promocion WHERE nombre='Pareja General' AND tipo='2x1') <> 1 THEN
        RAISE EXCEPTION 'Debe existir una única promoción Pareja General de tipo 2x1.';
    END IF;
    SELECT id_promocion INTO v_promocion FROM promocion WHERE nombre='Pareja General' AND tipo='2x1' FOR UPDATE;
    IF (SELECT count(*) FROM categoria_entrada WHERE nombre='Adulto') <> 1 THEN
        RAISE EXCEPTION 'Debe existir una única categoría Adulto.';
    END IF;
    SELECT id_categoria_entrada INTO v_categoria FROM categoria_entrada WHERE nombre='Adulto';
    IF NOT EXISTS (
        SELECT 1 FROM funcion_promocion fp JOIN funcion f USING(id_funcion)
        JOIN zona z USING(id_sala)
        WHERE fp.id_promocion=v_promocion AND z.nombre='General'
    ) THEN
        RAISE EXCEPTION 'Las funciones de la promoción deben tener una zona General.';
    END IF;
    SELECT jsonb_build_object(
        'promocion',to_jsonb(p),
        'dias',(SELECT jsonb_agg(dia_semana ORDER BY dia_semana) FROM promocion_dia WHERE id_promocion=v_promocion),
        'zonas',(SELECT jsonb_agg(id_zona ORDER BY id_zona) FROM promocion_zona WHERE id_promocion=v_promocion),
        'categorias',(SELECT jsonb_agg(id_categoria_entrada ORDER BY id_categoria_entrada) FROM promocion_categoria WHERE id_promocion=v_promocion)
    ) INTO v_antes FROM promocion p WHERE id_promocion=v_promocion;
    PERFORM set_config('app.motivo','Decisión de Mauriart: Pareja General 2x1 solo miércoles, Adulto/General.',true);
    PERFORM set_config('app.ip','127.0.0.1',true);
    DELETE FROM promocion_dia WHERE id_promocion=v_promocion;
    INSERT INTO promocion_dia VALUES(v_promocion,3);
    DELETE FROM promocion_zona WHERE id_promocion=v_promocion;
    INSERT INTO promocion_zona
        SELECT DISTINCT v_promocion,z.id_zona
        FROM funcion_promocion fp JOIN funcion f USING(id_funcion) JOIN zona z USING(id_sala)
        WHERE fp.id_promocion=v_promocion AND z.nombre='General';
    DELETE FROM promocion_categoria WHERE id_promocion=v_promocion;
    INSERT INTO promocion_categoria VALUES(v_promocion,v_categoria);
    UPDATE promocion SET condicion='Dos entradas de adulto en zona General de la misma función, únicamente los miércoles.'
        WHERE id_promocion=v_promocion;
    PERFORM auditar_accion(v_actor,'127.0.0.1','configurar_tarifas','promocion',v_promocion::text,
        current_setting('app.motivo',true),jsonb_build_object('antes',v_antes,'dia_semana',3,'categoria','Adulto','zona','General'));
END $$;
COMMIT;
