from flask import Flask, abort, redirect, render_template, request, url_for
import psycopg
from conexion import obtener_conexion
from salas import salas_bp
from funciones import funciones_bp

app = Flask(__name__)
app.register_blueprint(salas_bp)
app.register_blueprint(funciones_bp)


def validar_pelicula(datos):
    if not all(datos.values()):
        return "Completa todos los campos."
    if len(datos["titulo"]) > 200:
        return "El título admite hasta 200 caracteres."
    if len(datos["clasificacion"]) > 30:
        return "La clasificación admite hasta 30 caracteres."
    try:
        duracion = int(datos["duracion_min"])
    except ValueError:
        return "La duración debe ser un número entero de minutos."
    if duracion <= 0 or duracion > 2147483647:
        return "La duración debe ser un entero positivo válido."
    return None


@app.route("/")
def listar_peliculas():
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT id_pelicula, titulo, clasificacion, duracion_min
                FROM pelicula
                ORDER BY id_pelicula;
            """)
            peliculas = cursor.fetchall()

    return render_template("peliculas.html", peliculas=peliculas)


@app.route("/peliculas/nueva", methods=["GET", "POST"])
def crear_pelicula():
    datos = {
        "titulo": "",
        "sinopsis": "",
        "clasificacion": "",
        "duracion_min": "",
        "poster_url": "",
    }
    error = None

    if request.method == "POST":
        for campo in datos:
            datos[campo] = request.form.get(campo, "").strip()

        error = validar_pelicula(datos)

        if error is None:
            try:
                with obtener_conexion() as conexion:
                    with conexion.cursor() as cursor:
                        cursor.execute("""
                            INSERT INTO pelicula (
                                titulo, sinopsis, clasificacion,
                                duracion_min, poster_url
                            )
                            VALUES (%s, %s, %s, %s, %s);
                        """, (
                            datos["titulo"],
                            datos["sinopsis"],
                            datos["clasificacion"],
                            int(datos["duracion_min"]),
                            datos["poster_url"],
                        ))
                return redirect(url_for("listar_peliculas"))
            except (psycopg.IntegrityError, psycopg.DataError):
                error = "No se pudo guardar la película. Revisa los datos."

    estado = 400 if error else 200
    return render_template(
        "pelicula_form.html", datos=datos, error=error,
        titulo_formulario="Agregar película",
        accion=url_for("crear_pelicula"),
    ), estado


@app.route("/peliculas/<int:id_pelicula>/editar", methods=["GET", "POST"])
def editar_pelicula(id_pelicula):
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT titulo, sinopsis, clasificacion, duracion_min, poster_url
                FROM pelicula
                WHERE id_pelicula = %s;
            """, (id_pelicula,))
            pelicula = cursor.fetchone()

    if pelicula is None:
        abort(404)

    datos = dict(zip(
        ["titulo", "sinopsis", "clasificacion", "duracion_min", "poster_url"],
        pelicula,
    ))
    error = None

    if request.method == "POST":
        for campo in datos:
            datos[campo] = request.form.get(campo, "").strip()
        error = validar_pelicula(datos)

        if error is None:
            try:
                with obtener_conexion() as conexion:
                    with conexion.cursor() as cursor:
                        cursor.execute("""
                            UPDATE pelicula
                            SET titulo = %s, sinopsis = %s, clasificacion = %s,
                                duracion_min = %s, poster_url = %s
                            WHERE id_pelicula = %s
                            RETURNING id_pelicula;
                        """, (
                            datos["titulo"], datos["sinopsis"],
                            datos["clasificacion"], int(datos["duracion_min"]),
                            datos["poster_url"], id_pelicula,
                        ))
                        if cursor.fetchone() is None:
                            abort(404)
                return redirect(url_for("listar_peliculas"))
            except (psycopg.IntegrityError, psycopg.DataError):
                error = "No se pudo guardar la película. Revisa los datos."

    estado = 400 if error else 200
    return render_template(
        "pelicula_form.html", datos=datos, error=error,
        titulo_formulario="Editar película",
        accion=url_for("editar_pelicula", id_pelicula=id_pelicula),
    ), estado
