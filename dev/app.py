from flask import Flask, abort, redirect, render_template, request, url_for
import psycopg
from modulos.conexion import obtener_conexion
from modulos.salas import salas_bp
from modulos.funciones import funciones_bp
from modulos.cartelera import cartelera_bp
from modulos.precios import precios_bp
from modulos.ventas import ventas_bp
from modulos.reportes import reportes_bp
from modulos.operacion import operacion_bp
from modulos.seguridad import preparar_seguridad, autorizar_cambio, auditar, leer_registro

app = Flask(__name__)
app.register_blueprint(salas_bp)
app.register_blueprint(funciones_bp)
app.register_blueprint(cartelera_bp)
app.register_blueprint(precios_bp)
app.register_blueprint(ventas_bp)
app.register_blueprint(reportes_bp)
app.register_blueprint(operacion_bp)
preparar_seguridad(app)


def cargar_generos():
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("SELECT id_genero, nombre FROM genero ORDER BY nombre;")
            return cursor.fetchall()


def validar_generos(seleccionados, generos):
    disponibles = {str(genero[0]) for genero in generos}
    if not seleccionados.issubset(disponibles):
        return "Selecciona géneros existentes en el catálogo."
    return None


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
    generos = cargar_generos()
    seleccionados = set()
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
        seleccionados = set(request.form.getlist("generos"))
        if error is None:
            error = validar_generos(seleccionados, generos)

        if error is None:
            try:
                with obtener_conexion() as conexion:
                    actor = autorizar_cambio(conexion, 'gestionar_catalogo')
                    with conexion.cursor() as cursor:
                        cursor.execute("""
                            INSERT INTO pelicula (
                                titulo, sinopsis, clasificacion,
                                duracion_min, poster_url
                            )
                            VALUES (%s, %s, %s, %s, %s)
                            RETURNING id_pelicula;
                        """, (
                            datos["titulo"],
                            datos["sinopsis"],
                            datos["clasificacion"],
                            int(datos["duracion_min"]),
                            datos["poster_url"],
                        ))
                        id_pelicula = cursor.fetchone()[0]
                        if seleccionados:
                            cursor.executemany("""
                                INSERT INTO pelicula_genero (id_pelicula, id_genero)
                                VALUES (%s, %s);
                            """, [(id_pelicula, int(genero)) for genero in sorted(seleccionados)])
                    despues = leer_registro(conexion, 'pelicula', id_pelicula)
                    despues['generos'] = sorted(int(genero) for genero in seleccionados)
                    auditar(conexion, actor, 'gestionar_catalogo', 'pelicula', id_pelicula,
                            antes=None, despues=despues)
                return redirect(url_for("listar_peliculas"))
            except (psycopg.IntegrityError, psycopg.DataError):
                error = "No se pudo guardar la película. Revisa los datos."

    estado = 400 if error else 200
    return render_template(
        "pelicula_form.html", datos=datos, error=error,
        titulo_formulario="Agregar película",
        accion=url_for("crear_pelicula"),
        generos=generos, seleccionados=seleccionados,
    ), estado


@app.route("/peliculas/<int:id_pelicula>/editar", methods=["GET", "POST"])
def editar_pelicula(id_pelicula):
    generos = cargar_generos()
    with obtener_conexion() as conexion:
        with conexion.cursor() as cursor:
            cursor.execute("""
                SELECT titulo, sinopsis, clasificacion, duracion_min, poster_url
                FROM pelicula
                WHERE id_pelicula = %s;
            """, (id_pelicula,))
            pelicula = cursor.fetchone()
            cursor.execute("SELECT id_genero FROM pelicula_genero WHERE id_pelicula = %s;",
                           (id_pelicula,))
            seleccionados = {str(fila[0]) for fila in cursor.fetchall()}

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
        seleccionados = set(request.form.getlist("generos"))
        if error is None:
            error = validar_generos(seleccionados, generos)

        if error is None:
            try:
                with obtener_conexion() as conexion:
                    actor = autorizar_cambio(conexion, 'gestionar_catalogo')
                    antes = leer_registro(conexion, 'pelicula', id_pelicula, bloquear=True)
                    antes['generos'] = [fila[0] for fila in conexion.execute('SELECT id_genero FROM pelicula_genero WHERE id_pelicula=%s ORDER BY id_genero', (id_pelicula,)).fetchall()]
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
                        cursor.execute("DELETE FROM pelicula_genero WHERE id_pelicula = %s;",
                                       (id_pelicula,))
                        if seleccionados:
                            cursor.executemany("""
                                INSERT INTO pelicula_genero (id_pelicula, id_genero)
                                VALUES (%s, %s);
                            """, [(id_pelicula, int(genero)) for genero in sorted(seleccionados)])
                    despues = leer_registro(conexion, 'pelicula', id_pelicula)
                    despues['generos'] = sorted(int(genero) for genero in seleccionados)
                    auditar(conexion, actor, 'gestionar_catalogo', 'pelicula', id_pelicula,
                            antes=antes, despues=despues)
                return redirect(url_for("listar_peliculas"))
            except (psycopg.IntegrityError, psycopg.DataError):
                error = "No se pudo guardar la película. Revisa los datos."

    estado = 400 if error else 200
    return render_template(
        "pelicula_form.html", datos=datos, error=error,
        titulo_formulario="Editar película",
        accion=url_for("editar_pelicula", id_pelicula=id_pelicula),
        generos=generos, seleccionados=seleccionados,
    ), estado
