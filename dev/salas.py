from flask import Blueprint, abort, redirect, render_template, request, url_for
import psycopg
from psycopg.rows import dict_row
from conexion import obtener_conexion

salas_bp = Blueprint("salas", __name__)


def entero_positivo(valor):
    try:
        numero = int(valor)
    except (ValueError, TypeError):
        return None
    return numero if 1 <= numero <= 2147483647 else None


def cargar_salas():
    with obtener_conexion() as conexion:
        with conexion.cursor(row_factory=dict_row) as cursor:
            cursor.execute("SELECT id_cine, nombre FROM cine ORDER BY nombre, id_cine;")
            cines = cursor.fetchall()
            cursor.execute("""
                SELECT s.id_sala, s.nombre, c.nombre AS cine,
                       COUNT(a.id_asiento) AS capacidad
                FROM sala s
                INNER JOIN cine c ON s.id_cine = c.id_cine
                LEFT JOIN zona z ON s.id_sala = z.id_sala
                LEFT JOIN asiento a ON z.id_zona = a.id_zona
                GROUP BY s.id_sala, s.nombre, c.nombre
                ORDER BY c.nombre, s.nombre, s.id_sala;
            """)
            salas = cursor.fetchall()
    return cines, salas


def cargar_detalle_sala(id_sala):
    with obtener_conexion() as conexion:
        with conexion.cursor(row_factory=dict_row) as cursor:
            cursor.execute("""
                SELECT s.id_sala, s.nombre, c.nombre AS cine
                FROM sala s INNER JOIN cine c ON s.id_cine = c.id_cine
                WHERE s.id_sala = %s;
            """, (id_sala,))
            sala = cursor.fetchone()
            if sala is None:
                abort(404)
            cursor.execute("""
                SELECT z.id_zona, z.nombre, COUNT(a.id_asiento) AS capacidad
                FROM zona z LEFT JOIN asiento a ON z.id_zona = a.id_zona
                WHERE z.id_sala = %s
                GROUP BY z.id_zona, z.nombre ORDER BY z.nombre, z.id_zona;
            """, (id_sala,))
            zonas = cursor.fetchall()
            cursor.execute("""
                SELECT a.id_asiento, z.nombre AS zona, a.fila, a.numero
                FROM asiento a INNER JOIN zona z ON a.id_zona = z.id_zona
                WHERE z.id_sala = %s
                ORDER BY z.nombre, a.fila, a.numero;
            """, (id_sala,))
            asientos = cursor.fetchall()
    return sala, zonas, asientos


def mostrar_distribucion(id_sala, error=None, datos=None):
    sala, zonas, asientos = cargar_detalle_sala(id_sala)
    return render_template(
        "sala_detalle.html", sala=sala, zonas=zonas, asientos=asientos,
        capacidad=len(asientos), error=error, datos=datos or {},
    ), 400 if error else 200


@salas_bp.route("/salas", methods=["GET", "POST"])
def listar_salas():
    datos = {"id_cine": "", "nombre": ""}
    error = None
    if request.method == "POST":
        datos = {campo: request.form.get(campo, "").strip() for campo in datos}
        id_cine = entero_positivo(datos["id_cine"])
        if not id_cine or not datos["nombre"]:
            error = "Selecciona un cine y escribe el nombre de la sala."
        elif len(datos["nombre"]) > 100:
            error = "El nombre de sala admite hasta 100 caracteres."
        else:
            try:
                with obtener_conexion() as conexion:
                    with conexion.cursor() as cursor:
                        cursor.execute("""
                            INSERT INTO sala (id_cine, nombre) VALUES (%s, %s)
                            RETURNING id_sala;
                        """, (id_cine, datos["nombre"]))
                        id_sala = cursor.fetchone()[0]
                return redirect(url_for("salas.detalle_sala", id_sala=id_sala))
            except psycopg.errors.UniqueViolation:
                error = "Ese cine ya tiene una sala con ese nombre."
            except psycopg.errors.ForeignKeyViolation:
                error = "El cine seleccionado no existe."
            except psycopg.DataError:
                error = "Revisa los datos de la sala."
    cines, salas = cargar_salas()
    return render_template(
        "salas.html", cines=cines, salas=salas, datos=datos, error=error,
    ), 400 if error else 200


@salas_bp.route("/salas/<int:id_sala>")
def detalle_sala(id_sala):
    return mostrar_distribucion(id_sala)


@salas_bp.route("/salas/<int:id_sala>/zonas", methods=["POST"])
def crear_zona(id_sala):
    cargar_detalle_sala(id_sala)
    datos = {"nombre_zona": request.form.get("nombre_zona", "").strip()}
    error = None
    if not datos["nombre_zona"]:
        error = "Escribe el nombre de la zona."
    elif len(datos["nombre_zona"]) > 50:
        error = "El nombre de zona admite hasta 50 caracteres."
    else:
        try:
            with obtener_conexion() as conexion:
                with conexion.cursor() as cursor:
                    cursor.execute("INSERT INTO zona (id_sala, nombre) VALUES (%s, %s);",
                                   (id_sala, datos["nombre_zona"]))
            return redirect(url_for("salas.detalle_sala", id_sala=id_sala))
        except psycopg.errors.UniqueViolation:
            error = "La sala ya tiene una zona con ese nombre."
        except psycopg.errors.ForeignKeyViolation:
            error = "La sala seleccionada ya no existe."
        except psycopg.DataError:
            error = "Revisa los datos de la zona."
    return mostrar_distribucion(id_sala, error, datos)


@salas_bp.route("/salas/<int:id_sala>/asientos/fila", methods=["POST"])
def crear_fila_asientos(id_sala):
    cargar_detalle_sala(id_sala)
    datos = {campo: request.form.get(campo, "").strip()
             for campo in ("lote_zona", "lote_fila", "desde", "hasta")}
    id_zona = entero_positivo(datos["lote_zona"])
    desde = entero_positivo(datos["desde"])
    hasta = entero_positivo(datos["hasta"])
    error = None
    if not id_zona or not desde or not hasta or not datos["lote_fila"]:
        error = "Selecciona una zona, escribe la fila y números inicial y final positivos."
    elif len(datos["lote_fila"]) > 10:
        error = "La fila admite hasta 10 caracteres."
    elif hasta < desde:
        error = "El número final debe ser mayor o igual que el inicial."
    elif hasta - desde + 1 > 1000:
        error = "Puedes crear hasta 1 000 asientos por operación."
    else:
        try:
            # La conexión confirma todos los asientos juntos o revierte el lote.
            with obtener_conexion() as conexion:
                with conexion.cursor() as cursor:
                    cursor.execute("""
                        SELECT id_zona FROM zona
                        WHERE id_zona = %s AND id_sala = %s FOR SHARE;
                    """, (id_zona, id_sala))
                    if cursor.fetchone() is None:
                        error = "La zona seleccionada no pertenece a esta sala."
                    else:
                        cursor.executemany("""
                            INSERT INTO asiento (id_zona, fila, numero)
                            VALUES (%s, %s, %s);
                        """, [(id_zona, datos["lote_fila"], numero)
                              for numero in range(desde, hasta + 1)])
            if error is None:
                return redirect(url_for("salas.detalle_sala", id_sala=id_sala) + "#asientos")
        except psycopg.errors.UniqueViolation:
            error = "Algún asiento de la fila ya existe. No se agregó ningún asiento del lote."
        except psycopg.errors.ForeignKeyViolation:
            error = "La zona seleccionada ya no existe. No se agregó el lote."
        except psycopg.DataError:
            error = "Revisa los datos de la fila. No se agregó el lote."
    return mostrar_distribucion(id_sala, error, datos)


@salas_bp.route("/salas/<int:id_sala>/asientos", methods=["POST"])
def crear_asiento(id_sala):
    cargar_detalle_sala(id_sala)
    datos = {campo: request.form.get(campo, "").strip()
             for campo in ("id_zona", "fila", "numero")}
    id_zona = entero_positivo(datos["id_zona"])
    numero = entero_positivo(datos["numero"])
    error = None
    if not id_zona or not numero or not datos["fila"]:
        error = "Selecciona una zona, escribe la fila y un número de asiento positivo."
    elif len(datos["fila"]) > 10:
        error = "La fila admite hasta 10 caracteres."
    else:
        try:
            with obtener_conexion() as conexion:
                with conexion.cursor() as cursor:
                    cursor.execute("""
                        SELECT id_zona FROM zona
                        WHERE id_zona = %s AND id_sala = %s FOR SHARE;
                    """, (id_zona, id_sala))
                    if cursor.fetchone() is None:
                        error = "La zona seleccionada no pertenece a esta sala."
                    else:
                        cursor.execute("""
                            INSERT INTO asiento (id_zona, fila, numero)
                            VALUES (%s, %s, %s);
                        """, (id_zona, datos["fila"], numero))
            if error is None:
                return redirect(url_for("salas.detalle_sala", id_sala=id_sala))
        except psycopg.errors.UniqueViolation:
            error = "Ya existe un asiento con esa fila y número en la zona."
        except psycopg.errors.ForeignKeyViolation:
            error = "La zona seleccionada ya no existe."
        except psycopg.DataError:
            error = "Revisa los datos del asiento."
    return mostrar_distribucion(id_sala, error, datos)
