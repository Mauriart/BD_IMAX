"""
C-04 · Dashboard de reportes (Blueprint Flask).  Archivo sugerido: src/operacion/reportes_c04.py

SUPUESTOS (no vi el código de la aplicación; ajustar a su estructura real):
  * Psycopg 3 y app.config['DATABASE_URL'] (acuerdos §3).
  * El usuario autenticado está en session['id_usuario'] (nunca viene del formulario).
  * Solo lectura: no hay formularios que escriban, por eso no requiere CSRF.
El permiso REAL lo decide la BD (autorizar_accion dentro de cada función, SQLSTATE 42501);
la interfaz solo refleja el resultado. Registro:  app.register_blueprint(reportes_bp)
"""
import csv
import io
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import psycopg
from psycopg.rows import dict_row
from flask import Blueprint, Response, abort, current_app, render_template, request, session

reportes_bp = Blueprint("reportes_c04", __name__, url_prefix="/reportes")

ZONA = ZoneInfo("America/Costa_Rica")  # zona IANA del cine de ejemplo (acuerdos §4)

REPORTES = {
    "r1": ("Ocupación y recaudación por función",
           "SELECT * FROM reporte_ocupacion_recaudacion(%(u)s, %(f)s, %(d)s, %(h)s)"),
    "r2": ("Top 5 películas (últimos 7 días)",
           "SELECT * FROM reporte_top5_peliculas_semana(%(u)s)"),
    "r3": ("Métodos de pago",
           "SELECT * FROM reporte_metodos_pago(%(u)s, %(d)s, %(h)s)"),
    "r4": ("Auditoría crítica por administrador (últimos 30 días)",
           "SELECT * FROM reporte_auditoria_por_administrador(%(u)s, %(d)s, %(h)s)"),
    "r4d": ("Detalle de auditoría",
            "SELECT * FROM reporte_auditoria_detalle(%(u)s, %(d)s, %(h)s)"),
}


def _fecha_local(texto, fin_de_dia=False):
    """'AAAA-MM-DD' -> instante en la zona del cine; el 'hasta' es exclusivo (día siguiente)."""
    if not texto:
        return None
    try:
        d = datetime.strptime(texto, "%Y-%m-%d").replace(tzinfo=ZONA)
    except ValueError:
        abort(400, "Fecha inválida; use AAAA-MM-DD.")
    return d + timedelta(days=1) if fin_de_dia else d


def _params():
    f = request.args.get("funcion", "").strip()
    if f and not f.isdigit():
        abort(400, "La función debe ser un número.")
    return {
        "u": session.get("id_usuario"),
        "f": int(f) if f else None,
        "d": _fecha_local(request.args.get("desde")),
        "h": _fecha_local(request.args.get("hasta"), fin_de_dia=True),
    }


def _ejecutar(clave, params):
    """Devuelve (filas, mensaje_de_error). Traduce los rechazos de la BD a mensajes de pantalla."""
    sql = REPORTES[clave][1]
    try:
        with psycopg.connect(current_app.config["DATABASE_URL"], row_factory=dict_row) as con:
            with con.cursor() as cur:
                cur.execute(sql, params)
                return cur.fetchall(), None
    except psycopg.errors.InsufficientPrivilege:
        return [], "Su rol no tiene permiso para este reporte."
    except psycopg.errors.ObjectNotInPrerequisiteState as e:   # 55000: falta la tabla pago de B
        return [], str(e).splitlines()[0]


@reportes_bp.route("/")
def dashboard():
    if session.get("id_usuario") is None:
        abort(401)
    p = _params()
    secciones = {}
    for clave in ("r1", "r2", "r3", "r4"):
        filas, error = _ejecutar(clave, p)
        secciones[clave] = {"titulo": REPORTES[clave][0], "filas": filas, "error": error}
    # Métricas resumen sobre el reporte 1 (sin consultas adicionales)
    r1 = secciones["r1"]["filas"]
    resumen = {
        "funciones": len(r1),
        "vendidos": sum(x["boletos_vendidos"] for x in r1),
        "neto": sum(x["ingreso_neto"] for x in r1),
    } if r1 else None
    return render_template("reportes_c04.html", secciones=secciones, resumen=resumen, filtros=request.args)


@reportes_bp.route("/exportar/<clave>.csv")
def exportar(clave):
    """Exportación CSV (contador/administrador). Misma verificación de permisos en la BD."""
    if session.get("id_usuario") is None:
        abort(401)
    if clave not in REPORTES:
        abort(404)
    filas, error = _ejecutar(clave, _params())
    if error:
        abort(403, error)
    salida = io.StringIO()
    if filas:
        w = csv.DictWriter(salida, fieldnames=list(filas[0].keys()))
        w.writeheader()
        w.writerows(filas)
    return Response(salida.getvalue(), mimetype="text/csv",
                    headers={"Content-Disposition": f"attachment; filename={clave}.csv"})
