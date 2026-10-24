from datetime import datetime
from flask import Blueprint, abort, redirect, render_template, request, url_for
import psycopg
from psycopg.rows import dict_row
from conexion import obtener_conexion
from salas import entero_positivo
from seguridad import autorizar_cambio, auditar, leer_registro

funciones_bp = Blueprint("funciones", __name__)


def cargar_opciones():
    with obtener_conexion() as conexion:
        with conexion.cursor(row_factory=dict_row) as cursor:
            cursor.execute("SELECT id_pelicula, titulo, duracion_min FROM pelicula ORDER BY titulo;")
            peliculas = cursor.fetchall()
            cursor.execute("""
                SELECT s.id_sala, s.nombre, c.nombre AS cine, c.zona_horaria
                FROM sala s INNER JOIN cine c ON s.id_cine = c.id_cine
                ORDER BY c.nombre, s.nombre;
            """)
            salas = cursor.fetchall()
    return peliculas, salas


@funciones_bp.route("/funciones")
def listar_funciones():
    with obtener_conexion() as conexion:
        with conexion.cursor(row_factory=dict_row) as cursor:
            cursor.execute("""
                SELECT f.id_funcion, p.titulo, s.nombre AS sala, c.nombre AS cine,
                       f.inicio AT TIME ZONE c.zona_horaria AS inicio_local,
                       f.fin AT TIME ZONE c.zona_horaria AS fin_local,
                       c.zona_horaria, f.activa
                FROM funcion f
                INNER JOIN pelicula p ON f.id_pelicula = p.id_pelicula
                INNER JOIN sala s ON f.id_sala = s.id_sala
                INNER JOIN cine c ON s.id_cine = c.id_cine
                ORDER BY f.inicio DESC, f.id_funcion DESC;
            """)
            funciones = cursor.fetchall()
    return render_template("funciones.html", funciones=funciones)


@funciones_bp.route("/funciones/nueva", methods=["GET", "POST"])
@funciones_bp.route("/funciones/<int:id_funcion>/editar", methods=["GET", "POST"])
def formulario_funcion(id_funcion=None):
    datos = {"id_pelicula": "", "id_sala": "", "inicio": "", "activa": True}
    if id_funcion is not None:
        with obtener_conexion() as conexion:
            with conexion.cursor(row_factory=dict_row) as cursor:
                cursor.execute("""
                    SELECT f.id_pelicula, f.id_sala, f.activa,
                           f.inicio AT TIME ZONE c.zona_horaria AS inicio_local
                    FROM funcion f
                    INNER JOIN sala s ON f.id_sala = s.id_sala
                    INNER JOIN cine c ON s.id_cine = c.id_cine
                    WHERE f.id_funcion = %s;
                """, (id_funcion,))
                funcion = cursor.fetchone()
        if funcion is None:
            abort(404)
        datos = {
            "id_pelicula": str(funcion["id_pelicula"]),
            "id_sala": str(funcion["id_sala"]),
            "inicio": funcion["inicio_local"].isoformat(timespec="seconds"),
            "activa": funcion["activa"],
        }

    peliculas, salas = cargar_opciones()
    error = None
    if request.method == "POST":
        datos = {campo: request.form.get(campo, "").strip()
                 for campo in ("id_pelicula", "id_sala", "inicio")}
        datos["activa"] = request.form.get("activa") == "on"
        id_pelicula = entero_positivo(datos["id_pelicula"])
        id_sala = entero_positivo(datos["id_sala"])
        if not id_pelicula or not id_sala or not datos["inicio"]:
            error = "Selecciona película, sala y fecha/hora de inicio."
        elif not any(p["id_pelicula"] == id_pelicula for p in peliculas):
            error = "La película seleccionada no existe."
        elif not any(s["id_sala"] == id_sala for s in salas):
            error = "La sala seleccionada no existe."
        else:
            try:
                inicio = datetime.fromisoformat(datos["inicio"])
                if "T" not in datos["inicio"] or inicio.tzinfo is not None:
                    error = "Introduce el horario local del cine sin un desfase adicional."
            except ValueError:
                error = "Introduce una fecha y hora válidas."

        if error is None:
            try:
                with obtener_conexion() as conexion:
                    actor = autorizar_cambio(conexion, 'gestionar_catalogo')
                    antes = leer_registro(conexion, 'funcion', id_funcion, bloquear=True) if id_funcion is not None else None
                    identificador = id_funcion
                    with conexion.cursor() as cursor:
                        # La duración se consulta en BD; no se confía en un fin del formulario.
                        cursor.execute("""
                            SELECT (%s::timestamp AT TIME ZONE c.zona_horaria),
                                   (%s::timestamp AT TIME ZONE c.zona_horaria)
                                   + p.duracion_min * INTERVAL '1 minute'
                            FROM sala s
                            INNER JOIN cine c ON s.id_cine = c.id_cine
                            INNER JOIN pelicula p ON p.id_pelicula = %s
                            WHERE s.id_sala = %s
                            FOR UPDATE OF s FOR SHARE OF p, c;
                        """, (inicio, inicio, id_pelicula, id_sala))
                        horario = cursor.fetchone()
                        if horario is None:
                            error = "La película o sala ya no está disponible. Revisa la selección."
                        elif id_funcion is None:
                            cursor.execute("""
                                INSERT INTO funcion (id_pelicula, id_sala, inicio, fin, activa)
                                VALUES (%s, %s, %s, %s, %s) RETURNING id_funcion;
                            """, (id_pelicula, id_sala, horario[0], horario[1], datos["activa"]))
                            identificador = cursor.fetchone()[0]
                        else:
                            cursor.execute("""
                                UPDATE funcion
                                SET id_pelicula = %s, id_sala = %s,
                                    inicio = %s, fin = %s, activa = %s
                                WHERE id_funcion = %s RETURNING id_funcion;
                            """, (id_pelicula, id_sala, horario[0], horario[1],
                                  datos["activa"], id_funcion))
                            if cursor.fetchone() is None:
                                abort(404)
                    if error is None:
                        auditar(conexion, actor, 'gestionar_catalogo', 'funcion', identificador,
                                antes=antes, despues=leer_registro(conexion, 'funcion', identificador))
                if error is None:
                    return redirect(url_for("funciones.listar_funciones"))
            except psycopg.errors.RaiseException:
                error = "El horario se cruza con otra función o con sus 15 minutos de limpieza."
            except psycopg.errors.CheckViolation:
                error = "No se puede guardar el cambio. Revisa el horario; una función con tarifas no puede cambiar de sala."
            except psycopg.errors.ForeignKeyViolation:
                error = "La película o sala seleccionada ya no existe."
            except psycopg.errors.DeadlockDetected:
                error = "Otra operación está modificando la programación. Inténtalo de nuevo."
            except psycopg.errors.SerializationFailure:
                error = "La programación cambió mientras guardabas. Inténtalo de nuevo."
            except psycopg.DataError:
                error = "No se pudo interpretar el horario. Revisa la fecha y la zona horaria del cine."

    titulo = "Editar función" if id_funcion is not None else "Programar función"
    accion = url_for("funciones.formulario_funcion", id_funcion=id_funcion)
    return render_template(
        "funcion_form.html", datos=datos, peliculas=peliculas, salas=salas,
        error=error, titulo_formulario=titulo, accion=accion,
    ), 400 if error else 200
