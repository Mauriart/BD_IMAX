"""Pruebas de cartelera en un esquema temporal; no modifican los datos del proyecto."""
from datetime import timedelta
import unittest
import app
import cartelera
from verificar_a02 import PruebasA02


class PruebasCartelera(unittest.TestCase):
    conectar = classmethod(PruebasA02.conectar.__func__)
    setUpClass = classmethod(PruebasA02.setUpClass.__func__)
    limpiar_esquema = classmethod(PruebasA02.limpiar_esquema.__func__)
    tearDown = PruebasA02.tearDown

    def setUp(self):
        PruebasA02.setUp(self)
        original = cartelera.obtener_conexion
        self.addCleanup(setattr, cartelera, "obtener_conexion", original)
        cartelera.obtener_conexion = app.obtener_conexion
        self.conexion.execute("INSERT INTO genero(id_genero,nombre) VALUES (1,'Acción'),(2,'Aventura'),(3,'Drama')")
        self.conexion.execute("INSERT INTO pelicula_genero VALUES (1,1),(1,2)")

    def funcion(self, dias=3, activa=True, sala=1):
        return self.conexion.execute("""
            INSERT INTO funcion(id_pelicula,id_sala,inicio,fin,activa)
            VALUES (1,%s,CURRENT_TIMESTAMP + %s * INTERVAL '1 day',
                    CURRENT_TIMESTAMP + %s * INTERVAL '1 day' + INTERVAL '120 minutes',%s)
            RETURNING id_funcion
        """, (sala, dias, dias, activa)).fetchone()[0]

    def test_solo_futuras_activas_y_sin_duplicar_por_generos(self):
        identificador = self.funcion()
        self.funcion(-3)
        self.funcion(4, False)
        filas = cartelera.consultar_funciones()
        self.assertEqual([f['id_funcion'] for f in filas], [identificador])
        self.assertEqual(filas[0]['generos'], ['Acción', 'Aventura'])
        contenido = self.cliente.get('/cartelera').get_data(as_text=True)
        self.assertEqual(contenido.count('class="tarjeta pelicula-cartelera"'), 1)
        for dato in ('Sinopsis', 'Todo público', '120 min', 'Cine ensayo', 'Sala ensayo'):
            self.assertIn(dato, contenido)

    def test_filtros_combinados_y_fecha_local(self):
        # A las 23:30 del cine la fecha UTC ya corresponde al día siguiente.
        identificador = self.conexion.execute("""
            INSERT INTO funcion(id_pelicula,id_sala,inicio,fin)
            SELECT 1,1,instante,instante + INTERVAL '120 minutes'
            FROM (SELECT ((CURRENT_TIMESTAMP AT TIME ZONE 'America/Costa_Rica')::date
                          + 10 + TIME '23:30') AT TIME ZONE 'America/Costa_Rica' AS instante) t
            RETURNING id_funcion
        """).fetchone()[0]
        fila = cartelera.consultar_funciones()[0]
        fecha = fila['inicio_local'].date()
        self.assertEqual([f['id_funcion'] for f in cartelera.consultar_funciones(1, fecha, 2)], [identificador])
        self.assertEqual(cartelera.consultar_funciones(1, fecha + timedelta(days=1), 2), [])
        self.assertEqual(cartelera.consultar_funciones(id_genero=3), [])
        segundo_cine = self.conexion.execute("INSERT INTO cine(nombre,ubicacion,zona_horaria) VALUES ('Otro','Otra ubicación','UTC') RETURNING id_cine").fetchone()[0]
        self.assertEqual(cartelera.consultar_funciones(id_cine=segundo_cine), [])
        respuesta = self.cliente.get('/cartelera', query_string={'cine':1,'fecha':fecha.isoformat(),'genero':2})
        self.assertEqual(respuesta.status_code, 200)
        self.assertIn('23:30', respuesta.get_data(as_text=True))

    def test_varios_horarios_agrupados_y_busqueda_vacia(self):
        self.funcion(3)
        self.funcion(4)
        contenido = self.cliente.get('/cartelera').get_data(as_text=True)
        self.assertEqual(contenido.count('class="tarjeta pelicula-cartelera"'), 1)
        self.assertIn('2 funciones disponibles', contenido)
        respuesta = self.cliente.get('/cartelera?genero=3')
        self.assertEqual(respuesta.status_code, 200)
        self.assertIn('No hay funciones para esta búsqueda', respuesta.get_data(as_text=True))

    def test_filtros_invalidos(self):
        for parametros in ({'cine':'abc'}, {'cine':'99999'}, {'genero':'-1'},
                           {'genero':'99999'}, {'fecha':'2026-02-30'}, {'cine':"1 OR 1=1"}):
            with self.subTest(parametros=parametros):
                respuesta = self.cliente.get('/cartelera', query_string=parametros)
                self.assertEqual(respuesta.status_code, 400)
                self.assertIn('Revisa los filtros', respuesta.get_data(as_text=True))

    def test_guardar_editar_y_validar_generos(self):
        datos = dict(titulo='Película con géneros', sinopsis='Descripción', clasificacion='TP',
                     duracion_min='90', poster_url='/static/poster.png', generos=['1','2'])
        self.assertEqual(self.cliente.post('/peliculas/nueva', data=datos).status_code, 302)
        identificador = self.conexion.execute("SELECT id_pelicula FROM pelicula WHERE titulo=%s", (datos['titulo'],)).fetchone()[0]
        def asociados():
            return self.conexion.execute('SELECT id_genero FROM pelicula_genero WHERE id_pelicula=%s ORDER BY id_genero', (identificador,)).fetchall()
        self.assertEqual(asociados(), [(1,), (2,)])
        ruta = f'/peliculas/{identificador}/editar'
        self.assertEqual(self.cliente.get(ruta).get_data(as_text=True).count('checked'), 2)
        datos['generos'] = ['3']
        self.assertEqual(self.cliente.post(ruta, data=datos).status_code, 302)
        self.assertEqual(asociados(), [(3,)])
        datos.update(titulo='No debe guardarse', generos=['99999'])
        self.assertEqual(self.cliente.post(ruta, data=datos).status_code, 400)
        self.assertEqual(asociados(), [(3,)])
        self.assertEqual(self.conexion.execute('SELECT titulo FROM pelicula WHERE id_pelicula=%s', (identificador,)).fetchone()[0], 'Película con géneros')
        datos['generos'] = []
        self.assertEqual(self.cliente.post(ruta, data=datos).status_code, 302)
        self.assertEqual(asociados(), [])


if __name__ == '__main__':
    unittest.main(defaultTest='PruebasCartelera', verbosity=2)
