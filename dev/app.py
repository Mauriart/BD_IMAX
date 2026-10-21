from flask import Flask, render_template
from conexion import obtener_conexion

app = Flask(__name__)


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