from flask import Blueprint,render_template,request,g,abort
from uuid import UUID
from psycopg.rows import dict_row
from modulos.conexion import obtener_conexion
from modulos.seguridad import autorizar_operacion

operacion_bp=Blueprint('operacion',__name__,url_prefix='/operacion')


@operacion_bp.route('/puerta',methods=['GET','POST'])
def puerta():
    resultado=None
    if request.method=='POST':
        try:
            token=UUID(request.form.get('token',''))
            funcion=int(request.form.get('funcion',''))
        except (ValueError,TypeError):abort(400,description='Revise el QR y la funcion.')
        with obtener_conexion() as c:
            autorizar_operacion(c,'validar_ingreso','Validacion de entrada en puerta')
            with c.cursor(row_factory=dict_row) as cur:
                cur.execute('SELECT * FROM validar_y_consumir_ingreso_qr(%s,%s,%s,%s,%s)',
                    (token,funcion,g.usuario['id_usuario'],request.form.get('dispositivo','').strip(),bool(request.form.get('acreditacion'))))
                resultado=cur.fetchone()
    with obtener_conexion() as c:
        with c.cursor(row_factory=dict_row) as cur:
            cur.execute('SELECT f.id_funcion,p.titulo,f.inicio FROM funcion f JOIN pelicula p USING(id_pelicula) WHERE f.activa ORDER BY f.inicio')
            funciones=cur.fetchall()
    return render_template('puerta.html',resultado=resultado,funciones=funciones),400 if resultado and not resultado['exito'] else 200


@operacion_bp.route('/reembolsos',methods=['GET','POST'])
def reembolsos():
    resultado=None
    if request.method=='POST':
        try:compra=int(request.form.get('compra',''))
        except ValueError:abort(400)
        with obtener_conexion() as c:
            autorizar_operacion(c,'solicitar_reembolso','Solicitud de devolucion')
            with c.cursor(row_factory=dict_row) as cur:
                cur.execute('SELECT * FROM solicitar_reembolso(%s,%s::bigint,NULL::bigint[],%s,%s)',
                    (g.usuario['id_usuario'],compra,request.form.get('motivo','').strip(),request.remote_addr or '127.0.0.1'))
                resultado=cur.fetchone()
    with obtener_conexion() as c:
        with c.cursor(row_factory=dict_row) as cur:
            cur.execute('SELECT * FROM solicitud_reembolso WHERE id_usuario_actor=%s ORDER BY creada_en DESC',(g.usuario['id_usuario'],))
            solicitudes=cur.fetchall()
            cur.execute("SELECT id_compra,total,estado FROM compra WHERE (id_usuario_cliente=%s OR id_usuario_actor=%s) AND estado IN ('Pagada','ParcialmenteReembolsada') ORDER BY id_compra DESC",(g.usuario['id_usuario'],g.usuario['id_usuario']))
            compras=cur.fetchall()
    return render_template('reembolsos.html',resultado=resultado,solicitudes=solicitudes,compras=compras),400 if resultado and not resultado['exito'] else 200


@operacion_bp.route('/resolver',methods=['GET','POST'])
def resolver():
    resultado=None
    if request.method=='POST':
        try:solicitud=int(request.form.get('solicitud',''))
        except ValueError:abort(400)
        with obtener_conexion() as c:
            autorizar_operacion(c,'resolver_reembolso','Resolucion de solicitud de devolucion')
            with c.cursor(row_factory=dict_row) as cur:
                cur.execute('SELECT * FROM resolver_reembolso(%s,%s,%s,%s,%s,%s)',
                    (g.usuario['id_usuario'],solicitud,request.form.get('decision',''),request.form.get('motivo','').strip(),
                     request.remote_addr or '127.0.0.1',bool(request.form.get('forzar'))))
                resultado=cur.fetchone()
    with obtener_conexion() as c:
        with c.cursor(row_factory=dict_row) as cur:
            cur.execute("SELECT s.*,u.nombre AS cliente FROM solicitud_reembolso s JOIN usuario u ON u.id_usuario=s.id_usuario_actor WHERE s.estado='pendiente' ORDER BY s.creada_en")
            solicitudes=cur.fetchall()
    return render_template('resolver.html',resultado=resultado,solicitudes=solicitudes),400 if resultado and not resultado['exito'] else 200


@operacion_bp.route('/ajustes',methods=['GET','POST'])
def ajustes():
    resultado=None
    if request.method=='POST':
        modo=request.form.get('modo')
        if modo not in ('cortesia','asiento'):abort(400)
        try:
            asiento=int(request.form.get('asiento',''))
            if modo=='cortesia':
                funcion=int(request.form.get('funcion',''));cliente=int(request.form.get('cliente',''));categoria=int(request.form.get('categoria',''))
            else:boleto=int(request.form.get('boleto',''))
        except ValueError:abort(400)
        with obtener_conexion() as c:
            autorizar_operacion(c,'otorgar_cortesia' if modo=='cortesia' else 'cambiar_asiento',request.form.get('motivo','').strip())
            with c.cursor(row_factory=dict_row) as cur:
                if modo=='cortesia':
                    cur.execute('SELECT * FROM otorgar_cortesia(%s,%s,%s,%s,%s,%s,%s)',
                        (g.usuario['id_usuario'],funcion,asiento,cliente,categoria,request.form.get('motivo',''),request.remote_addr or '127.0.0.1'))
                else:
                    cur.execute('SELECT * FROM cambiar_asiento_boleto(%s,%s::bigint,%s,%s,%s)',
                        (g.usuario['id_usuario'],boleto,asiento,request.form.get('motivo',''),request.remote_addr or '127.0.0.1'))
                resultado=cur.fetchone()
    with obtener_conexion() as c:
        with c.cursor(row_factory=dict_row) as cur:
            cur.execute("SELECT u.id_usuario,u.nombre FROM usuario u JOIN rol r USING(id_rol) WHERE r.nombre='cliente' AND u.activo ORDER BY u.nombre");clientes=cur.fetchall()
            cur.execute('SELECT id_categoria_entrada,nombre FROM categoria_entrada ORDER BY nombre');categorias=cur.fetchall()
            cur.execute('SELECT f.id_funcion,p.titulo FROM funcion f JOIN pelicula p USING(id_pelicula) WHERE f.activa AND f.inicio>clock_timestamp() ORDER BY f.inicio');funciones=cur.fetchall()
            cur.execute("SELECT a.id_asiento,s.nombre AS sala,z.nombre AS zona,a.fila,a.numero FROM asiento a JOIN zona z USING(id_zona) JOIN sala s USING(id_sala) ORDER BY s.nombre,z.nombre,a.fila,a.numero");asientos=cur.fetchall()
            cur.execute("SELECT id_boleto,id_funcion,id_asiento FROM boleto WHERE estado='Emitido' ORDER BY id_boleto DESC");boletos=cur.fetchall()
    return render_template('ajustes_venta.html',resultado=resultado,clientes=clientes,categorias=categorias,funciones=funciones,asientos=asientos,boletos=boletos),400 if resultado and not resultado['exito'] else 200
