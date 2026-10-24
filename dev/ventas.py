import io
import uuid
 
import psycopg
from flask import (Blueprint, abort, current_app, flash, redirect,
                   render_template, request, send_file, session, url_for)
 
from conexion import obtener_conexion
 
ventas_bp = Blueprint("ventas", __name__, url_prefix="/ventas")
 
METODOS_PAGO = ("Tarjeta", "Transferencia", "Efectivo")
MAX_ASIENTOS = 6                                  # el limite real lo aplica la base de datos
CLAVES_SESION = ("id_usuario", "usuario_id", "user_id")   # nombres posibles de la sesion
 
 
# ----------------------------------------------------------------------
# Ayudas
# ----------------------------------------------------------------------
def usuario_actual():
    """Id del usuario con sesion iniciada (o None).
    Si C guarda el usuario con otro nombre en la sesion, agrega ese nombre a CLAVES_SESION."""
    for clave in CLAVES_SESION:
        valor = session.get(clave)
        if valor:
            try:
                return int(valor)
            except (TypeError, ValueError):
                pass
    return None
 
 
def requiere_usuario():
    id_usuario = usuario_actual()
    if id_usuario is None:
        flash("Primero inicia sesion (en pruebas: /ventas/entrar-prueba/1).", "error")
        abort(redirect(url_for("ventas.inicio")))
    return id_usuario
 
 
def todas(cursor):
    """Convierte todas las filas del cursor en diccionarios (columna -> valor)."""
    columnas = [c.name for c in cursor.description]
    return [dict(zip(columnas, fila)) for fila in cursor.fetchall()]
 
 
def una(cursor):
    """Convierte la primera fila en diccionario (o None si no hay)."""
    columnas = [c.name for c in cursor.description]
    fila = cursor.fetchone()
    return dict(zip(columnas, fila)) if fila else None
 
 
def liberar_vencidas():
    """Libera los apartados cuyo tiempo ya paso (funcion SQL de B)."""
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("SELECT liberar_reservas_vencidas();")
 
 
def nombre_usuario(id_usuario):
    """Nombre del cliente para la factura. Si la tabla de C no tiene esa columna, devuelve None."""
    try:
        with obtener_conexion() as conexion:
            with conexion.cursor() as cursor:
                cursor.execute("SELECT nombre FROM usuario WHERE id_usuario = %s;", (id_usuario,))
                fila = cursor.fetchone()
                return fila[0] if fila else None
    except psycopg.Error:
        return None
 
 
SQL_DATOS_COMPRA = """
    SELECT c.id_compra, c.estado, c.total, c.moneda, c.creada_en, c.id_funcion,
           c.id_usuario_cliente, p.titulo, ci.nombre AS cine, s.nombre AS sala,
           f.inicio AT TIME ZONE ci.zona_horaria AS inicio_local
      FROM compra c
      JOIN funcion f ON f.id_funcion = c.id_funcion
      JOIN pelicula p ON p.id_pelicula = f.id_pelicula
      JOIN sala s ON s.id_sala = f.id_sala
      JOIN cine ci ON ci.id_cine = s.id_cine
     WHERE c.id_compra = %s AND c.id_usuario_cliente = %s;
"""
 
SQL_LINEAS = """
    SELECT a.fila, a.numero, z.nombre AS zona, ce.nombre AS categoria,
           d.precio_base, d.descuento, d.cargo_servicio, d.total_linea
      FROM compra_detalle d
      JOIN asiento a ON a.id_asiento = d.id_asiento
      JOIN zona z ON z.id_zona = a.id_zona
      JOIN categoria_entrada ce ON ce.id_categoria_entrada = d.id_categoria_entrada
     WHERE d.id_compra = %s
     ORDER BY a.fila, a.numero;
"""
 
 
# ----------------------------------------------------------------------
# Sesion de prueba (hasta que el login de C este conectado)
# ----------------------------------------------------------------------
@ventas_bp.route("/entrar-prueba/<int:id_usuario>")
def entrar_prueba(id_usuario):
    """SOLO DESARROLLO: simula iniciar sesion. Funciona unicamente con debug=True."""
    if not current_app.debug:
        abort(404)
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("SELECT 1 FROM usuario WHERE id_usuario = %s;", (id_usuario,))
            if cursor.fetchone() is None:
                abort(404)
    session["id_usuario"] = id_usuario
    flash(f"Sesion de prueba iniciada como usuario {id_usuario}.", "ok")
    return redirect(url_for("ventas.inicio"))
 
 
# ----------------------------------------------------------------------
# Inicio: funciones disponibles
# ----------------------------------------------------------------------
@ventas_bp.route("/")
def inicio():
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT f.id_funcion, p.titulo, p.clasificacion, ci.nombre AS cine,
                       s.nombre AS sala,
                       f.inicio AT TIME ZONE ci.zona_horaria AS inicio_local
                  FROM funcion f
                  JOIN pelicula p ON p.id_pelicula = f.id_pelicula
                  JOIN sala s ON s.id_sala = f.id_sala
                  JOIN cine ci ON ci.id_cine = s.id_cine
                 WHERE f.activa AND f.inicio > now()
                 ORDER BY f.inicio;
            """)
            funciones = todas(cursor)
    return render_template("ventas_inicio.html", funciones=funciones)
 
 
# ----------------------------------------------------------------------
# MAPA de asientos
# ----------------------------------------------------------------------
@ventas_bp.route("/funciones/<int:id_funcion>/asientos")
def mapa(id_funcion):
    requiere_usuario()
    liberar_vencidas()          # primero libera lo vencido, para mostrar el mapa al dia
 
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT f.id_funcion, p.titulo, ci.nombre AS cine, s.nombre AS sala,
                       f.inicio AT TIME ZONE ci.zona_horaria AS inicio_local,
                       (f.activa AND f.inicio > now()) AS vendible
                  FROM funcion f
                  JOIN pelicula p ON p.id_pelicula = f.id_pelicula
                  JOIN sala s ON s.id_sala = f.id_sala
                  JOIN cine ci ON ci.id_cine = s.id_cine
                 WHERE f.id_funcion = %s;
            """, (id_funcion,))
            funcion = una(cursor)
            if funcion is None:
                abort(404)
 
            cursor.execute("""
                SELECT d.asiento_id, d.estado_actual, a.fila, a.numero, z.nombre AS zona
                  FROM consultar_disponibilidad(%s) d
                  JOIN asiento a ON a.id_asiento = d.asiento_id
                  JOIN zona z ON z.id_zona = a.id_zona
                 ORDER BY a.fila, a.numero;
            """, (id_funcion,))
            asientos = todas(cursor)
 
    filas_mapa = {}
    for asiento in asientos:
        filas_mapa.setdefault(asiento["fila"], []).append(asiento)
 
    resumen = {
        "disponible": sum(1 for a in asientos if a["estado_actual"] == "disponible"),
        "bloqueado": sum(1 for a in asientos if a["estado_actual"] == "bloqueado"),
        "vendido": sum(1 for a in asientos if a["estado_actual"] == "vendido"),
    }
    return render_template("ventas_mapa.html", funcion=funcion, filas_mapa=filas_mapa,
                           resumen=resumen, total_asientos=len(asientos),
                           max_asientos=MAX_ASIENTOS)
 
 
@ventas_bp.post("/funciones/<int:id_funcion>/reservar")
def reservar(id_funcion):
    usuario = requiere_usuario()
    try:
        asientos = [int(x) for x in request.form.getlist("asiento")]
    except ValueError:
        abort(400)
    if not asientos:
        flash("Selecciona al menos un asiento.", "error")
        return redirect(url_for("ventas.mapa", id_funcion=id_funcion))
 
    try:
        with obtener_conexion() as conexion:
            with conexion.cursor() as cursor:
                # (cliente, quien lo registra, funcion, lista de asientos)
                cursor.execute("SELECT reservar_asientos(%s, %s, %s, %s::int[]);",
                               (usuario, usuario, id_funcion, asientos))
                id_compra = cursor.fetchone()[0]
    except psycopg.errors.RaiseException as e:
        # Mensaje escrito por la funcion SQL (por ejemplo, "asiento no disponible")
        flash(e.diag.message_primary, "error")
        return redirect(url_for("ventas.mapa", id_funcion=id_funcion))
    except psycopg.Error as e:
        current_app.logger.exception("Error al reservar asientos de la funcion %s", id_funcion)
        mensaje = "No se pudo completar la reserva. Intenta de nuevo."
        if current_app.debug:       # solo mientras desarrollas: muestra el error real de la base
            mensaje += f" [Detalle tecnico: {e.diag.message_primary} (codigo {e.sqlstate})]"
        flash(mensaje, "error")
        return redirect(url_for("ventas.mapa", id_funcion=id_funcion))
 
    return redirect(url_for("ventas.compra", id_compra=id_compra))
 
 
# ----------------------------------------------------------------------
# COMPRA: resumen y pago simulado
# ----------------------------------------------------------------------
@ventas_bp.route("/compras/<int:id_compra>")
def compra(id_compra):
    usuario = requiere_usuario()
    liberar_vencidas()
 
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute(SQL_DATOS_COMPRA, (id_compra, usuario))
            datos = una(cursor)
            if datos is None:
                abort(404)
            cursor.execute(SQL_LINEAS, (id_compra,))
            lineas = todas(cursor)
            cursor.execute("""
                SELECT MIN(vence_en) AS vence_en
                  FROM reserva
                 WHERE id_compra = %s AND estado = 'activa';
            """, (id_compra,))
            vence = una(cursor)["vence_en"]
 
    if datos["estado"] in ("Pagada", "Reembolsada"):
        return redirect(url_for("ventas.factura", id_compra=id_compra))
 
    return render_template(
        "ventas_compra.html", compra=datos, lineas=lineas,
        vence_iso=vence.isoformat() if vence else None,
        referencia=f"PAG-{uuid.uuid4()}", metodos=METODOS_PAGO)
 
 
@ventas_bp.post("/compras/<int:id_compra>/pagar")
def pagar(id_compra):
    usuario = requiere_usuario()
    resultado = request.form.get("resultado", "")
    metodo = request.form.get("metodo", "")
    referencia = request.form.get("referencia", "").strip()
 
    if resultado not in ("Exito", "Rechazado") or metodo not in METODOS_PAGO or not referencia:
        abort(400)
 
    liberar_vencidas()
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute(SQL_DATOS_COMPRA, (id_compra, usuario))
            datos = una(cursor)
    if datos is None:
        abort(404)
 
    # La compra ya no esta pendiente (pagada, cancelada o vencida): no se vuelve a cobrar
    if datos["estado"] != "Pendiente":
        if datos["estado"] == "Pagada":
            return redirect(url_for("ventas.factura", id_compra=id_compra))
        flash("El tiempo de la reserva vencio o la compra ya fue cancelada. "
              "Elige tus asientos otra vez.", "error")
        return redirect(url_for("ventas.mapa", id_funcion=datos["id_funcion"]))
 
    try:
        with obtener_conexion() as conexion:
            with conexion.cursor() as cursor:
                cursor.execute("SELECT procesar_pago(%s, %s::varchar, %s::varchar, %s::varchar);",
                               (id_compra, resultado, metodo, referencia))
    except psycopg.errors.UniqueViolation:
        # El mismo formulario llego dos veces (doble clic): no se duplica el pago
        flash("Ese pago ya habia sido procesado.", "ok")
    except psycopg.errors.RaiseException as e:
        flash(e.diag.message_primary, "error")
        return redirect(url_for("ventas.compra", id_compra=id_compra))
    except psycopg.Error as e:
        current_app.logger.exception("Error al procesar el pago de la compra %s", id_compra)
        mensaje = "No se pudo procesar el pago. Intenta de nuevo."
        if current_app.debug:       # solo mientras desarrollas: muestra el error real de la base
            mensaje += f" [Detalle tecnico: {e.diag.message_primary} (codigo {e.sqlstate})]"
        flash(mensaje, "error")
        return redirect(url_for("ventas.compra", id_compra=id_compra))
 
    # Ver como quedo la compra despues del pago
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("SELECT estado FROM compra WHERE id_compra = %s;", (id_compra,))
            estado = cursor.fetchone()[0]
 
    if estado == "Pagada":
        flash("Pago aprobado. Esta es tu factura con los boletos.", "ok")
        return redirect(url_for("ventas.factura", id_compra=id_compra))
    flash("Pago rechazado: los asientos fueron liberados.", "error")
    return redirect(url_for("ventas.mapa", id_funcion=datos["id_funcion"]))
 
 
# ----------------------------------------------------------------------
# FACTURA con boletos y QR
# ----------------------------------------------------------------------
@ventas_bp.route("/compras/<int:id_compra>/factura")
def factura(id_compra):
    usuario = requiere_usuario()
 
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute(SQL_DATOS_COMPRA, (id_compra, usuario))
            datos = una(cursor)
            if datos is None:
                abort(404)
            if datos["estado"] in ("Pendiente", "Cancelada", "Expirada"):
                # Sin pago aprobado no hay factura ni boletos
                return redirect(url_for("ventas.compra", id_compra=id_compra))
 
            cursor.execute(SQL_LINEAS, (id_compra,))
            lineas = todas(cursor)
            cursor.execute("""
                SELECT b.id_boleto, b.token_qr, b.estado, a.fila, a.numero, z.nombre AS zona
                  FROM boleto b
                  JOIN asiento a ON a.id_asiento = b.id_asiento
                  JOIN zona z ON z.id_zona = a.id_zona
                 WHERE b.id_compra = %s
                 ORDER BY a.fila, a.numero;
            """, (id_compra,))
            boletos = todas(cursor)
            cursor.execute("""
                SELECT referencia, metodo, estado, monto, moneda, creado_en
                  FROM pago
                 WHERE id_compra = %s AND estado = 'Aprobado'
                 ORDER BY id_pago DESC LIMIT 1;
            """, (id_compra,))
            pago = una(cursor)
 
    return render_template("ventas_factura.html", compra=datos, lineas=lineas,
                           boletos=boletos, pago=pago,
                           cliente=nombre_usuario(usuario))
 
 
# ----------------------------------------------------------------------
# Mis compras
# ----------------------------------------------------------------------
@ventas_bp.route("/mis-compras")
def mis_compras():
    usuario = requiere_usuario()
    liberar_vencidas()
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT c.id_compra, c.estado, c.total, c.moneda, c.creada_en, p.titulo,
                       f.inicio AT TIME ZONE ci.zona_horaria AS inicio_local
                  FROM compra c
                  JOIN funcion f ON f.id_funcion = c.id_funcion
                  JOIN pelicula p ON p.id_pelicula = f.id_pelicula
                  JOIN sala s ON s.id_sala = f.id_sala
                  JOIN cine ci ON ci.id_cine = s.id_cine
                 WHERE c.id_usuario_cliente = %s
                 ORDER BY c.id_compra DESC;
            """, (usuario,))
            compras = todas(cursor)
    return render_template("ventas_mis_compras.html", compras=compras)
 
 
# ----------------------------------------------------------------------
# Imagen QR de un boleto (solo del dueño y solo si el boleto esta vigente)
# ----------------------------------------------------------------------
@ventas_bp.route("/qr/<token>.png")
def qr(token):
    usuario = usuario_actual()
    if usuario is None:
        abort(401)
    try:
        uuid.UUID(token)
    except ValueError:
        abort(404)
 
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT 1
                  FROM boleto b
                  JOIN compra c ON c.id_compra = b.id_compra
                 WHERE b.token_qr = %s::uuid
                   AND c.id_usuario_cliente = %s
                   AND b.estado = 'Emitido';
            """, (token, usuario))
            if cursor.fetchone() is None:
                abort(404)      # boleto ajeno, anulado o inexistente: misma respuesta
 
    try:
        import qrcode          # se importa aqui para que la app arranque aunque falte instalarlo
    except ImportError:
        abort(500, description='Falta instalar la libreria del QR: pip install "qrcode[pil]"')
 
    imagen = qrcode.make(token)
    buffer = io.BytesIO()
    imagen.save(buffer, format="PNG")
    buffer.seek(0)
    return send_file(buffer, mimetype="image/png")