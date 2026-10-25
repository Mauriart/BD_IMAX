-- Ventas integradas con identidad de C y tarifas/promociones de A.
-- El servidor fija app.id_usuario desde la sesion, nunca desde el formulario.
CREATE OR REPLACE FUNCTION actor_ventas(p_actor bigint,p_accion text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE contexto text:=nullif(current_setting('app.id_usuario',true),'');
BEGIN
    IF contexto IS NULL OR contexto::bigint<>p_actor THEN
        RAISE EXCEPTION 'La operacion requiere el actor autenticado.' USING ERRCODE='42501';
    END IF;
    PERFORM u.id_usuario FROM usuario u JOIN rol r USING(id_rol)
    WHERE u.id_usuario=p_actor AND u.activo FOR SHARE OF u,r;
    IF NOT FOUND OR NOT autorizar_accion(p_actor::integer,p_accion) THEN
        RAISE EXCEPTION 'El usuario no tiene permiso para esta operacion.' USING ERRCODE='42501';
    END IF;
    PERFORM rp.accion FROM rol_permiso rp JOIN usuario u USING(id_rol)
    WHERE u.id_usuario=p_actor AND rp.accion=p_accion FOR SHARE OF rp;
END $$;

CREATE OR REPLACE FUNCTION coordinar_venta(p_funcion bigint)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('transaction_isolation')<>'read committed' THEN
        RAISE EXCEPTION 'Ventas requiere READ COMMITTED.' USING ERRCODE='55000';
    END IF;
    PERFORM s.id_sala FROM sala s JOIN funcion f USING(id_sala)
    WHERE f.id_funcion=p_funcion FOR SHARE OF s;
    IF NOT FOUND THEN RAISE EXCEPTION 'La funcion no existe.' USING ERRCODE='23503'; END IF;
END $$;

CREATE OR REPLACE FUNCTION preparar_inventario(p_funcion bigint)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM coordinar_venta(p_funcion);
    INSERT INTO inventario_funcion(id_funcion,id_asiento)
    SELECT f.id_funcion,a.id_asiento FROM funcion f JOIN zona z USING(id_sala)
    JOIN asiento a USING(id_zona) WHERE f.id_funcion=p_funcion
    ON CONFLICT(id_funcion,id_asiento) DO NOTHING;
END $$;

CREATE OR REPLACE FUNCTION liberar_reservas_vencidas()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    -- Bloquea cada compra antes de modificar su reserva/inventario, igual que pago.
    FOR r IN SELECT id_compra,id_funcion FROM compra
             WHERE estado='Pendiente' ORDER BY id_compra FOR UPDATE SKIP LOCKED LOOP
        IF EXISTS(SELECT 1 FROM reserva WHERE id_compra=r.id_compra AND estado='activa'
                  AND vence_en<=clock_timestamp()) THEN
            PERFORM coordinar_venta(r.id_funcion);
            UPDATE reserva SET estado='expirada' WHERE id_compra=r.id_compra AND estado='activa';
            UPDATE inventario_funcion i SET estado='disponible',id_reserva=NULL
            FROM reserva re WHERE i.id_reserva=re.id_reserva AND re.id_compra=r.id_compra AND i.estado='bloqueado';
            UPDATE compra SET estado='Expirada' WHERE id_compra=r.id_compra;
        END IF;
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION consultar_disponibilidad(p_id_funcion bigint)
RETURNS TABLE(asiento_id integer,estado_actual varchar,reserva_id bigint)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY SELECT i.id_asiento,i.estado,i.id_reserva FROM inventario_funcion i
    WHERE i.id_funcion=p_id_funcion ORDER BY i.id_asiento;
END $$;

CREATE OR REPLACE FUNCTION calcular_total(p_id_compra bigint)
RETURNS numeric LANGUAGE plpgsql AS $$
DECLARE total_compra numeric;
BEGIN
    SELECT coalesce(sum(total_linea),0) INTO total_compra FROM compra_detalle WHERE id_compra=p_id_compra;
    UPDATE compra SET total=total_compra WHERE id_compra=p_id_compra;
    RETURN total_compra;
END $$;

-- Cotizacion unica por categoria. El descuento 2x1 se reparte entre las dos lineas.
CREATE OR REPLACE FUNCTION reservar_asientos(p_id_usuario_cliente bigint,p_id_usuario_actor bigint,
    p_id_funcion bigint,p_asientos integer[],p_categoria integer)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE compra_nueva bigint; a integer; zona_actual integer; tarifa_actual integer;
        precio numeric; cantidad integer; instante timestamptz:=clock_timestamp();
        reserva_nueva bigint; promocion_actual integer; par record;
BEGIN
    IF p_id_usuario_actor=p_id_usuario_cliente THEN
        PERFORM actor_ventas(p_id_usuario_actor,'reservar_comprar');
    ELSIF autorizar_accion(p_id_usuario_actor::integer,'otorgar_cortesia') THEN
        PERFORM actor_ventas(p_id_usuario_actor,'otorgar_cortesia');
    ELSE PERFORM actor_ventas(p_id_usuario_actor,'venta_presencial'); END IF;
    IF NOT EXISTS(SELECT 1 FROM usuario u JOIN rol r USING(id_rol)
        WHERE u.id_usuario=p_id_usuario_cliente AND u.activo AND r.nombre='cliente') THEN
        RAISE EXCEPTION 'Seleccione un cliente activo.';
    END IF;
    cantidad:=cardinality(p_asientos);
    IF cantidad IS NULL OR cantidad NOT BETWEEN 1 AND 6 OR array_ndims(p_asientos)<>1
       OR array_position(p_asientos,NULL) IS NOT NULL
       OR (SELECT count(DISTINCT x) FROM unnest(p_asientos) x)<>cantidad THEN
        RAISE EXCEPTION 'Seleccione entre uno y seis asientos diferentes.';
    END IF;
    PERFORM coordinar_venta(p_id_funcion);
    -- El bloqueo de funcion impide que cambien estado, horario o tarifas al cotizar.
    PERFORM 1 FROM funcion WHERE id_funcion=p_id_funcion AND activa AND inicio>instante FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'La funcion no esta activa o ya inicio.'; END IF;
    PERFORM liberar_reservas_vencidas();
    PERFORM preparar_inventario(p_id_funcion);
    PERFORM i.id_asiento FROM inventario_funcion i WHERE i.id_funcion=p_id_funcion
    AND i.id_asiento=ANY(p_asientos) ORDER BY i.id_asiento FOR UPDATE;
    IF (SELECT count(*) FROM inventario_funcion WHERE id_funcion=p_id_funcion
        AND id_asiento=ANY(p_asientos) AND estado='disponible')<>cantidad THEN
        RAISE EXCEPTION 'Un asiento no se encuentra disponible. Operacion cancelada.';
    END IF;
    INSERT INTO compra(id_usuario_cliente,id_usuario_actor,id_funcion)
    VALUES(p_id_usuario_cliente,p_id_usuario_actor,p_id_funcion) RETURNING id_compra INTO compra_nueva;
    FOR a IN SELECT unnest(p_asientos) ORDER BY 1 LOOP
        SELECT id_zona INTO zona_actual FROM asiento WHERE id_asiento=a;
        SELECT count(*),min(id_tarifa),min(monto) INTO cantidad,tarifa_actual,precio FROM tarifa
        WHERE id_funcion=p_id_funcion AND id_zona=zona_actual AND id_categoria_entrada=p_categoria
          AND vigente_desde<=instante AND instante<vigente_hasta;
        IF cantidad<>1 THEN RAISE EXCEPTION 'No hay una tarifa vigente unica para la zona y categoria seleccionadas.'; END IF;
        INSERT INTO reserva(id_compra,id_funcion,id_asiento,vence_en,precio_unitario)
        VALUES(compra_nueva,p_id_funcion,a,instante+INTERVAL '120 seconds',precio) RETURNING id_reserva INTO reserva_nueva;
        INSERT INTO compra_detalle(id_compra,id_asiento,id_categoria_entrada,id_tarifa,precio_base,total_linea)
        VALUES(compra_nueva,a,p_categoria,tarifa_actual,precio,precio);
        UPDATE inventario_funcion SET estado='bloqueado',id_reserva=reserva_nueva
        WHERE id_funcion=p_id_funcion AND id_asiento=a;
    END LOOP;
    FOR par IN
        SELECT d.id_compra_detalle,d.precio_base,a.id_zona,
          row_number() OVER(PARTITION BY a.id_zona ORDER BY a.id_asiento) n,
          count(*) OVER(PARTITION BY a.id_zona) cuantos
        FROM compra_detalle d JOIN asiento a USING(id_asiento) WHERE d.id_compra=compra_nueva
    LOOP
        SELECT p.id_promocion INTO promocion_actual FROM promocion p
        JOIN funcion_promocion fp USING(id_promocion)
        WHERE fp.id_funcion=p_id_funcion AND p.activa AND p.tipo='2x1'
          AND p.vigente_desde<=instante AND instante<p.vigente_hasta
          AND EXISTS(SELECT 1 FROM promocion_dia pd JOIN funcion f ON f.id_funcion=p_id_funcion
                     JOIN sala s USING(id_sala) JOIN cine ci USING(id_cine)
                     WHERE pd.id_promocion=p.id_promocion
                     AND pd.dia_semana=extract(isodow FROM f.inicio AT TIME ZONE ci.zona_horaria))
          AND EXISTS(SELECT 1 FROM promocion_zona pz WHERE pz.id_promocion=p.id_promocion AND pz.id_zona=par.id_zona)
          AND EXISTS(SELECT 1 FROM promocion_categoria pc WHERE pc.id_promocion=p.id_promocion AND pc.id_categoria_entrada=p_categoria)
        ORDER BY p.id_promocion LIMIT 1;
        IF promocion_actual IS NOT NULL AND par.n<=par.cuantos-(par.cuantos%2) THEN
            UPDATE compra_detalle SET id_promocion=promocion_actual,
              descuento=CASE WHEN par.n%2=1 THEN ceil(par.precio_base*100/2)/100 ELSE floor(par.precio_base*100/2)/100 END,
              total_linea=par.precio_base-CASE WHEN par.n%2=1 THEN ceil(par.precio_base*100/2)/100 ELSE floor(par.precio_base*100/2)/100 END
            WHERE id_compra_detalle=par.id_compra_detalle;
        END IF;
    END LOOP;
    PERFORM calcular_total(compra_nueva);
    RETURN compra_nueva;
END $$;

-- Compatibilidad con llamadas de cuatro argumentos: solo si la categoria es unica.
CREATE OR REPLACE FUNCTION reservar_asientos(p_id_usuario_cliente bigint,p_id_usuario_actor bigint,
    p_id_funcion bigint,p_asientos integer[])
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE categoria integer; n integer;
BEGIN
    SELECT count(DISTINCT id_categoria_entrada),min(id_categoria_entrada) INTO n,categoria FROM tarifa
    WHERE id_funcion=p_id_funcion AND vigente_desde<=clock_timestamp() AND clock_timestamp()<vigente_hasta;
    IF n<>1 THEN RAISE EXCEPTION 'Seleccione la categoria de entrada.'; END IF;
    RETURN reservar_asientos(p_id_usuario_cliente,p_id_usuario_actor,p_id_funcion,p_asientos,categoria);
END $$;

CREATE OR REPLACE FUNCTION procesar_pago(p_id_compra bigint,p_resultado varchar,p_metodo varchar,p_referencia varchar)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE c compra%ROWTYPE; r record; pago_nuevo bigint; boleto_nuevo bigint; actor bigint;
BEGIN
    actor:=nullif(current_setting('app.id_usuario',true),'')::bigint;
    IF actor IS NULL THEN RAISE EXCEPTION 'Falta usuario autenticado.' USING ERRCODE='42501'; END IF;
    SELECT * INTO c FROM compra WHERE id_compra=p_id_compra;
    IF NOT FOUND THEN RAISE EXCEPTION 'La compra no existe.'; END IF;
    IF actor=c.id_usuario_cliente THEN PERFORM actor_ventas(actor,'reservar_comprar');
    ELSIF autorizar_accion(actor::integer,'otorgar_cortesia') THEN PERFORM actor_ventas(actor,'otorgar_cortesia');
    ELSE PERFORM actor_ventas(actor,'venta_presencial'); END IF;
    PERFORM coordinar_venta(c.id_funcion);
    SELECT * INTO c FROM compra WHERE id_compra=p_id_compra FOR UPDATE;
    IF p_metodo='Cortesia' THEN PERFORM actor_ventas(actor,'otorgar_cortesia'); END IF;
    IF p_resultado NOT IN ('Exito','Aprobado','Rechazado') OR p_metodo NOT IN ('Tarjeta','Transferencia','Efectivo','Cortesia')
        OR btrim(coalesce(p_referencia,''))='' THEN RAISE EXCEPTION 'Datos de pago invalidos.'; END IF;
    IF EXISTS(SELECT 1 FROM pago WHERE referencia=p_referencia AND id_compra=p_id_compra) THEN RETURN; END IF;
    IF c.estado<>'Pendiente' THEN RAISE EXCEPTION 'La compra ya no esta pendiente.'; END IF;
    IF NOT EXISTS(SELECT 1 FROM reserva WHERE id_compra=p_id_compra)
       OR EXISTS(SELECT 1 FROM reserva WHERE id_compra=p_id_compra AND (estado<>'activa' OR vence_en<=clock_timestamp()))
       OR NOT EXISTS(SELECT 1 FROM funcion WHERE id_funcion=c.id_funcion AND activa AND inicio>clock_timestamp()) THEN
        p_resultado:='Rechazado';
    END IF;
    PERFORM i.id_asiento FROM inventario_funcion i JOIN reserva re ON re.id_reserva=i.id_reserva
    WHERE re.id_compra=p_id_compra ORDER BY i.id_asiento FOR UPDATE OF i;
    INSERT INTO pago(id_compra,estado,metodo,referencia,monto)
    VALUES(p_id_compra,CASE WHEN p_resultado IN ('Exito','Aprobado') THEN 'Aprobado' ELSE 'Rechazado' END,p_metodo,p_referencia,c.total)
    RETURNING id_pago INTO pago_nuevo;
    IF p_resultado IN ('Exito','Aprobado') THEN
        FOR r IN SELECT * FROM reserva WHERE id_compra=p_id_compra ORDER BY id_asiento LOOP
            IF NOT EXISTS(SELECT 1 FROM inventario_funcion WHERE id_funcion=c.id_funcion AND id_asiento=r.id_asiento
                          AND estado='bloqueado' AND id_reserva=r.id_reserva) THEN RAISE EXCEPTION 'La reserva perdio el asiento.'; END IF;
            INSERT INTO boleto(id_compra,id_funcion,id_asiento) VALUES(p_id_compra,c.id_funcion,r.id_asiento)
            RETURNING id_boleto INTO boleto_nuevo;
            UPDATE inventario_funcion SET estado='vendido',id_boleto=boleto_nuevo
            WHERE id_funcion=c.id_funcion AND id_asiento=r.id_asiento;
        END LOOP;
        UPDATE reserva SET estado='confirmada' WHERE id_compra=p_id_compra;
        UPDATE compra SET estado='Pagada' WHERE id_compra=p_id_compra;
    ELSE
        UPDATE reserva SET estado='liberada' WHERE id_compra=p_id_compra AND estado IN ('activa','expirada');
        UPDATE inventario_funcion i SET estado='disponible',id_reserva=NULL FROM reserva re
        WHERE re.id_reserva=i.id_reserva AND re.id_compra=p_id_compra AND i.estado='bloqueado';
        UPDATE compra SET estado='Cancelada' WHERE id_compra=p_id_compra;
    END IF;
    INSERT INTO transaccion_log(id_compra,id_pago,id_usuario_actor,resultado,evento,monto,moneda)
    VALUES(p_id_compra,pago_nuevo,actor,CASE WHEN p_resultado IN ('Exito','Aprobado') THEN 'Exito' ELSE 'Fallido' END,'Procesar Pago',c.total,'USD');
END $$;

CREATE OR REPLACE FUNCTION consultar_boletos_usuario(p_id_usuario_cliente bigint,p_id_usuario_actor bigint)
RETURNS TABLE(boleto_id bigint,compra_id bigint,funcion_id bigint,asiento_id integer,estado_boleto varchar,qr_token uuid)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_id_usuario_cliente=p_id_usuario_actor THEN PERFORM actor_ventas(p_id_usuario_actor,'consultar_boletos_propios');
    ELSIF autorizar_accion(p_id_usuario_actor::integer,'consultar_boletos_admin') THEN PERFORM actor_ventas(p_id_usuario_actor,'consultar_boletos_admin');
    ELSE PERFORM actor_ventas(p_id_usuario_actor,'consultar_boletos_venta'); END IF;
    RETURN QUERY SELECT b.id_boleto,b.id_compra,b.id_funcion,b.id_asiento::integer,b.estado,b.token_qr
    FROM boleto b JOIN compra c USING(id_compra) WHERE c.id_usuario_cliente=p_id_usuario_cliente;
END $$;

-- C autoriza una solicitud concreta; B conserva pago, inventario y monto devuelto.
CREATE OR REPLACE FUNCTION revertir_venta(p_id_solicitud_reembolso integer,p_referencia text)
RETURNS TABLE(monto_reembolsado numeric,boletos_anulados integer)
LANGUAGE plpgsql AS $$
DECLARE solicitud solicitud_reembolso%ROWTYPE; c compra%ROWTYPE; actor bigint;
        monto numeric; n integer; pago_original bigint; reembolso_nuevo bigint; r record;
BEGIN
    actor:=nullif(current_setting('app.id_usuario',true),'')::bigint;
    PERFORM actor_ventas(actor,'resolver_reembolso');
    SELECT * INTO solicitud FROM solicitud_reembolso WHERE id_solicitud_reembolso=p_id_solicitud_reembolso FOR UPDATE;
    IF NOT FOUND OR solicitud.estado<>'pendiente' THEN RAISE EXCEPTION 'La solicitud ya no esta pendiente.'; END IF;
    SELECT * INTO c FROM compra WHERE id_compra=solicitud.id_compra;
    PERFORM coordinar_venta(c.id_funcion);
    SELECT * INTO c FROM compra WHERE id_compra=solicitud.id_compra FOR UPDATE;
    IF c.estado NOT IN ('Pagada','ParcialmenteReembolsada') THEN RAISE EXCEPTION 'La compra no admite devolucion.'; END IF;
    PERFORM b.id_boleto FROM boleto b JOIN solicitud_reembolso_detalle d USING(id_boleto)
    WHERE d.id_solicitud_reembolso=p_id_solicitud_reembolso ORDER BY b.id_boleto FOR UPDATE OF b;
    IF EXISTS(SELECT 1 FROM solicitud_reembolso_detalle d JOIN boleto b USING(id_boleto)
              WHERE d.id_solicitud_reembolso=p_id_solicitud_reembolso AND (b.id_compra<>c.id_compra OR b.estado<>'Emitido')) THEN
        RAISE EXCEPTION 'Un boleto ya fue utilizado o anulado.';
    END IF;
    SELECT count(*),sum(cd.total_linea) INTO n,monto FROM solicitud_reembolso_detalle d
    JOIN boleto b USING(id_boleto) JOIN compra_detalle cd ON cd.id_compra=b.id_compra AND cd.id_asiento=b.id_asiento
    WHERE d.id_solicitud_reembolso=p_id_solicitud_reembolso;
    IF n=0 OR monto<=0 THEN RAISE EXCEPTION 'No hay un monto reembolsable.'; END IF;
    SELECT id_pago INTO pago_original FROM pago WHERE id_compra=c.id_compra AND estado='Aprobado' ORDER BY id_pago LIMIT 1;
    IF pago_original IS NULL THEN RAISE EXCEPTION 'No existe pago aprobado.'; END IF;
    INSERT INTO reembolso(id_solicitud_reembolso,id_pago,referencia,monto)
    VALUES(p_id_solicitud_reembolso,pago_original,p_referencia,monto) RETURNING id_reembolso INTO reembolso_nuevo;
    FOR r IN SELECT b.id_boleto,b.id_asiento,cd.total_linea FROM solicitud_reembolso_detalle d
        JOIN boleto b USING(id_boleto) JOIN compra_detalle cd ON cd.id_compra=b.id_compra AND cd.id_asiento=b.id_asiento
        WHERE d.id_solicitud_reembolso=p_id_solicitud_reembolso ORDER BY b.id_boleto LOOP
        INSERT INTO reembolso_detalle VALUES(reembolso_nuevo,r.id_boleto,r.total_linea);
        UPDATE boleto SET estado='Anulado' WHERE id_boleto=r.id_boleto;
        UPDATE reserva SET estado='liberada' WHERE id_compra=c.id_compra AND id_asiento=r.id_asiento;
        UPDATE inventario_funcion SET estado='disponible',id_reserva=NULL,id_boleto=NULL
        WHERE id_funcion=c.id_funcion AND id_asiento=r.id_asiento AND id_boleto=r.id_boleto;
    END LOOP;
    UPDATE compra SET estado=CASE WHEN EXISTS(SELECT 1 FROM boleto WHERE id_compra=c.id_compra AND estado<>'Anulado')
      THEN 'ParcialmenteReembolsada' ELSE 'Reembolsada' END WHERE id_compra=c.id_compra;
    INSERT INTO transaccion_log(id_compra,id_pago,id_usuario_actor,resultado,evento,monto,moneda,detalle)
    VALUES(c.id_compra,pago_original,actor,'Exito','Reembolso',monto,'USD',p_referencia);
    RETURN QUERY SELECT monto,n;
END $$;

-- La firma anterior delega en C; no permite saltarse politica ni autorizacion.
CREATE OR REPLACE FUNCTION revertir_venta(p_id_compra bigint,p_id_usuario_actor bigint,p_motivo varchar)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE s record; res record;
BEGIN
    PERFORM actor_ventas(p_id_usuario_actor,'resolver_reembolso');
    SELECT * INTO s FROM solicitar_reembolso(p_id_usuario_actor::integer,p_id_compra,NULL::bigint[],p_motivo::text,
        coalesce(nullif(current_setting('app.ip',true),''),'127.0.0.1'));
    IF NOT s.exito THEN RAISE EXCEPTION '%',s.mensaje; END IF;
    SELECT * INTO res FROM resolver_reembolso(p_id_usuario_actor::integer,s.id_solicitud,'ejecutar',p_motivo::text,
        coalesce(nullif(current_setting('app.ip',true),''),'127.0.0.1'),FALSE);
    IF NOT res.exito THEN RAISE EXCEPTION '%',res.mensaje; END IF;
END $$;
