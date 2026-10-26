from datetime import date
from flask import Blueprint, render_template, request
from psycopg.rows import dict_row
from modulos.conexion import obtener_conexion
from modulos.salas import entero_positivo

cartelera_bp = Blueprint("cartelera", __name__)


def consultar_funciones(id_cine=None, fecha_local=None, id_genero=None):
    """Funciones futuras activas; fecha interpretada en la zona local de cada cine."""
    consulta = """
        SELECT f.id_funcion, f.id_pelicula, f.id_sala,
               p.titulo, p.sinopsis, p.clasificacion, p.duracion_min, p.poster_url,
               s.nombre AS sala, c.id_cine, c.nombre AS cine,
               c.ubicacion, c.zona_horaria,
               f.inicio AT TIME ZONE c.zona_horaria AS inicio_local,
               ARRAY(SELECT g.nombre FROM genero g
                     INNER JOIN pelicula_genero pg ON g.id_genero = pg.id_genero
                     WHERE pg.id_pelicula = p.id_pelicula ORDER BY g.nombre) AS generos
        FROM funcion f
        INNER JOIN pelicula p ON f.id_pelicula = p.id_pelicula
        INNER JOIN sala s ON f.id_sala = s.id_sala
        INNER JOIN cine c ON s.id_cine = c.id_cine
        WHERE f.activa = TRUE AND f.inicio > CURRENT_TIMESTAMP
    """
    parametros = []
    if id_cine is not None:
        consulta += " AND c.id_cine = %s"
        parametros.append(id_cine)
    if fecha_local is not None:
        consulta += " AND (f.inicio AT TIME ZONE c.zona_horaria)::date = %s"
        parametros.append(fecha_local)
    if id_genero is not None:
        consulta += """ AND EXISTS (
            SELECT 1 FROM pelicula_genero pg
            WHERE pg.id_pelicula = p.id_pelicula AND pg.id_genero = %s
        )"""
        parametros.append(id_genero)
    consulta += " ORDER BY f.inicio, p.titulo, c.nombre, f.id_funcion;"
    with obtener_conexion() as conexion:
        with conexion.cursor(row_factory=dict_row) as cursor:
            cursor.execute(consulta, parametros)
            return cursor.fetchall()


@cartelera_bp.route("/cartelera")
def ver_cartelera():
    filtros = {campo: request.args.get(campo, "").strip()
               for campo in ("cine", "fecha", "genero")}
    error = None
    id_cine = entero_positivo(filtros["cine"]) if filtros["cine"] else None
    id_genero = entero_positivo(filtros["genero"]) if filtros["genero"] else None
    fecha_local = None
    if filtros["cine"] and id_cine is None:
        error = "Selecciona un cine válido."
    elif filtros["genero"] and id_genero is None:
        error = "Selecciona un género válido."
    if filtros["fecha"]:
        try:
            fecha_local = date.fromisoformat(filtros["fecha"])
        except ValueError:
            error = "Selecciona una fecha válida."

    with obtener_conexion() as conexion:
        with conexion.cursor(row_factory=dict_row) as cursor:
            cursor.execute("SELECT id_cine, nombre, ubicacion FROM cine ORDER BY nombre;")
            cines = cursor.fetchall()
            cursor.execute("SELECT id_genero, nombre FROM genero ORDER BY nombre;")
            generos = cursor.fetchall()
    if id_cine is not None and not any(c["id_cine"] == id_cine for c in cines):
        error = "El cine seleccionado no existe."
    if id_genero is not None and not any(g["id_genero"] == id_genero for g in generos):
        error = "El género seleccionado no existe."

    funciones = consultar_funciones(id_cine, fecha_local, id_genero) if error is None else []
    peliculas = {}
    for funcion in funciones:
        identificador = funcion["id_pelicula"]
        if identificador not in peliculas:
            peliculas[identificador] = {"datos": funcion, "funciones": []}
        peliculas[identificador]["funciones"].append(funcion)
    return render_template(
        "cartelera.html", peliculas=list(peliculas.values()), total_funciones=len(funciones),
        cines=cines, generos=generos, filtros=filtros, error=error,
    ), 400 if error else 200
