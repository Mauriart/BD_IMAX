from datetime import timedelta
from hmac import compare_digest
import os
import secrets
from flask import Blueprint, abort, current_app, g, redirect, render_template, request, session, url_for
import psycopg
from psycopg import sql
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb
from werkzeug.exceptions import ServiceUnavailable
from werkzeug.security import check_password_hash, generate_password_hash
from conexion import obtener_conexion

seguridad_bp = Blueprint('seguridad', __name__)
HASH_INEXISTENTE = generate_password_hash(secrets.token_urlsafe(32))
PUBLICOS = {'static', 'cartelera.ver_cartelera', 'precios.ver_precios',
            'seguridad.login', 'seguridad.logout'}


def puede(accion):
    return accion in getattr(g, 'permisos', set())


def token_csrf():
    if 'csrf_token' not in session:
        session['csrf_token'] = secrets.token_urlsafe(32)
    return session['csrf_token']


def preparar_seguridad(app):
    app.config.update(SECRET_KEY=os.environ.get('SECRET_KEY'),
                      SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE='Lax',
                      PERMANENT_SESSION_LIFETIME=timedelta(minutes=30))
    app.register_blueprint(seguridad_bp)
    app.before_request(comprobar_solicitud)
    app.context_processor(lambda: {'puede': puede, 'csrf_token': token_csrf})
    app.register_error_handler(psycopg.Error, mostrar_error_bd)
    for codigo in (400, 403, 503):
        app.register_error_handler(codigo, mostrar_error)


def mostrar_error_bd(error):
    return mostrar_error(ServiceUnavailable(
        'No se pudo completar la operación con la base de datos. Inténtalo de nuevo.'))


def mostrar_error(error):
    return render_template('error.html', error=error), error.code


def comprobar_solicitud():
    g.usuario = None
    g.permisos = set()
    if request.endpoint is None or request.endpoint == 'static':
        return None
    clave = current_app.secret_key
    configurada = isinstance(clave, str) and len(clave) >= 32
    if not configurada:
        if request.endpoint in {'cartelera.ver_cartelera', 'precios.ver_precios'}:
            return None
        raise ServiceUnavailable('El acceso todavÃ­a no estÃ¡ configurado. Ejecuta configurar_acceso.py desde dev.')
    identificador = session.get('id_usuario')
    if type(identificador) is int and 1 <= identificador <= 2147483647:
        try:
            with obtener_conexion() as conexion:
                with conexion.cursor(row_factory=dict_row) as cursor:
                    cursor.execute('''SELECT u.id_usuario,u.nombre,u.id_rol,r.nombre AS rol
                        FROM usuario u INNER JOIN rol r ON r.id_rol=u.id_rol
                        WHERE u.id_usuario=%s AND u.activo=TRUE''', (identificador,))
                    g.usuario = cursor.fetchone()
                    if g.usuario:
                        cursor.execute('''SELECT accion FROM rol_permiso
                            WHERE id_rol=%s AND autorizar_accion(%s,accion)''',
                            (g.usuario['id_rol'], identificador))
                        g.permisos = {fila['accion'] for fila in cursor.fetchall()}
                    else:
                        session.clear()
        except psycopg.Error as ex:
            raise ServiceUnavailable('El servicio de usuarios y permisos no estÃ¡ disponible.') from ex
    elif identificador is not None:
        session.clear()
    if request.endpoint not in PUBLICOS:
        if not g.usuario:
            return redirect(url_for('seguridad.login'))
        if request.blueprint == 'precios':
            accion = 'configurar_tarifas' if request.method == 'POST' else 'ver_tarifas'
        elif request.blueprint in (None, 'salas', 'funciones'):
            accion = 'gestionar_catalogo'
        else:
            abort(403, description='Esta operaciÃ³n no tiene un permiso configurado.')
        if not puede(accion):
            abort(403, description='Tu usuario no tiene permiso para realizar esta operaciÃ³n.')
    if request.method == 'POST':
        esperado = session.get('csrf_token')
        recibido = request.form.get('csrf_token', '')
        if not isinstance(esperado, str) or not compare_digest(esperado.encode(), recibido.encode()):
            abort(400, description='El formulario venciÃ³ o no es vÃ¡lido. Recarga la pÃ¡gina e intÃ©ntalo de nuevo.')


@seguridad_bp.route('/login', methods=['GET', 'POST'])
def login():
    error = None
    correo = request.form.get('correo', '').strip().lower()
    if request.method == 'POST':
        password = request.form.get('password', '')
        usuario = None
        if len(correo) <= 150 and len(password) <= 1024:
            try:
                with obtener_conexion() as conexion:
                    with conexion.cursor(row_factory=dict_row) as cursor:
                        cursor.execute('SELECT id_usuario,password_hash FROM usuario WHERE correo=%s AND activo=TRUE', (correo,))
                        usuario = cursor.fetchone()
            except psycopg.Error as ex:
                raise ServiceUnavailable('El esquema de usuarios de C no estÃ¡ disponible.') from ex
        hash_guardado = usuario['password_hash'] if usuario else ''
        hash_valido = hash_guardado.startswith(('scrypt:', 'pbkdf2:'))
        try:
            coincide = check_password_hash(hash_guardado if hash_valido else HASH_INEXISTENTE, password)
        except (ValueError, TypeError):
            coincide = False
        if usuario and hash_valido and coincide:
            session.clear()
            session['id_usuario'] = usuario['id_usuario']
            session.permanent = True
            return redirect(url_for('cartelera.ver_cartelera'))
        error = 'Correo o contraseÃ±a incorrectos, o usuario inactivo.'
    return render_template('login.html', correo=correo, error=error), 400 if error else 200


@seguridad_bp.route('/logout', methods=['POST'])
def logout():
    session.clear()
    return redirect(url_for('cartelera.ver_cartelera'))


def autorizar_cambio(conexion, accion):
    """Revalidar identidad/permiso y conservarlos estables durante el cambio."""
    if not getattr(g, 'usuario', None):
        abort(403)
    motivo = request.form.get('motivo', '').strip()
    if not motivo or len(motivo) > 500:
        abort(400, description='Indica el motivo del cambio, con un mÃ¡ximo de 500 caracteres.')
    with conexion.cursor(row_factory=dict_row) as cursor:
        cursor.execute('''SELECT u.id_usuario,u.id_rol,r.nombre AS rol
            FROM usuario u INNER JOIN rol r ON r.id_rol=u.id_rol
            WHERE u.id_usuario=%s AND u.activo=TRUE FOR SHARE OF u,r''', (g.usuario['id_usuario'],))
        actor = cursor.fetchone()
        if not actor:
            abort(403)
        cursor.execute('SELECT accion FROM rol_permiso WHERE id_rol=%s AND accion=%s FOR SHARE', (actor['id_rol'], accion))
        permiso = cursor.fetchone()
        cursor.execute('SELECT autorizar_accion(%s,%s) AS permitido', (actor['id_usuario'], accion))
        permitido = cursor.fetchone()['permitido']
        if not permiso or not permitido:
            abort(403, description='El permiso cambiÃ³. No se guardÃ³ la operaciÃ³n.')
    # C-03 lee este contexto para sus guardias y triggers. Solo dura la transacciÃ³n.
    conexion.execute("""SELECT set_config('app.id_usuario',%s,true),
        set_config('app.ip',%s,true), set_config('app.motivo',%s,true)""",
        (str(actor['id_usuario']), request.remote_addr or 'desconocida', motivo))
    actor['motivo'] = motivo
    return actor


def leer_registro(conexion, tabla, identificador, bloquear=False):
    if tabla not in {'pelicula', 'sala', 'zona', 'asiento', 'funcion', 'tarifa', 'promocion', 'categoria_entrada'}:
        raise ValueError('Entidad de auditorÃ­a no permitida')
    consulta = sql.SQL('SELECT to_jsonb(t) FROM {} t WHERE {}=%s').format(
        sql.Identifier(tabla), sql.Identifier('id_' + tabla))
    if bloquear:
        consulta += sql.SQL(' FOR UPDATE')
    with conexion.cursor() as cursor:
        cursor.execute(consulta, (identificador,))
        fila = cursor.fetchone()
    if fila is None:
        abort(404)
    return fila[0]


def auditar(conexion, actor, accion, entidad, identificador, antes=None, despues=None):
    try:
        # El cambio ya mantiene el bloqueo de la tabla: su trigger no puede
        # desaparecer entre la escritura y esta comprobaciÃ³n.
        evento = 4 if antes is None else 16  # INSERT o UPDATE en pg_trigger.
        automatica = conexion.execute(
            """SELECT EXISTS (
                SELECT 1 FROM pg_trigger t
                INNER JOIN pg_proc p ON p.oid=t.tgfoid
                INNER JOIN pg_class c ON c.oid=t.tgrelid
                WHERE t.tgrelid=to_regclass(%s) AND NOT t.tgisinternal
                  AND p.proname='auditar_cambio_critico' AND p.pronamespace=c.relnamespace
                  AND t.tgenabled IN ('O','A') AND t.tgqual IS NULL AND t.tgattr=''::int2vector
                  AND (t.tgtype::int & 1)=1 AND (t.tgtype::int & 2)=0
                  AND (t.tgtype::int & 64)=0 AND (t.tgtype::int & %s)<>0
            )""", (entidad, evento)).fetchone()[0]
        if automatica:
            return
        valores = (actor['id_usuario'], request.remote_addr or 'desconocida',
                   accion, entidad, str(identificador), actor['motivo'],
                   Jsonb({'antes': antes, 'despues': despues}))
        funcion_c = conexion.execute(
            "SELECT to_regprocedure('auditar_accion(integer,text,text,text,text,text,jsonb)')"
        ).fetchone()[0]
        if funcion_c:
            conexion.execute('SELECT auditar_accion(%s,%s,%s,%s,%s,%s,%s)', valores)
        else:
            conexion.execute("""INSERT INTO admin_operacion_audit
                (id_usuario_actor,rol_al_actuar,ip,accion,entidad,id_entidad,motivo,cambios)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s)""",
                (actor['id_usuario'], actor['rol'], *valores[1:]))
    except psycopg.Error as ex:
        raise ServiceUnavailable('No se pudo registrar la auditorÃ­a. El cambio no se guardÃ³.') from ex
