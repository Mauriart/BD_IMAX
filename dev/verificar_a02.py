r"""Ejecutar con: .venv\Scripts\python.exe verificar_a02.py

Usa un esquema temporal propio de PostgreSQL y lo elimina al terminar.
No cambia las tablas del proyecto. Requiere permiso CREATE en la base de prueba.
"""
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from pathlib import Path
import time
import unittest
from uuid import uuid4
import psycopg
from psycopg import sql
import app as modulo_app
import funciones as modulo_funciones
import salas as modulo_salas
import seguridad as modulo_seguridad
from flask.testing import FlaskClient
from conexion import obtener_conexion


class ClienteA(FlaskClient):
    """Las regresiones de A envían formularios válidos como un administrador."""
    def post(self, *args, **kwargs):
        with self.session_transaction() as sesion:
            token = sesion['csrf_token']
        datos = dict(kwargs.get('data') or {})
        datos.setdefault('csrf_token', token)
        datos.setdefault('motivo', 'Prueba aislada del módulo A')
        kwargs['data'] = datos
        return super().post(*args, **kwargs)


class PruebasA02(unittest.TestCase):
    @classmethod
    def conectar(cls):
        conexion = obtener_conexion()
        conexion.execute(sql.SQL("SET search_path TO {}, public").format(sql.Identifier(cls.esquema)))
        return conexion

    @classmethod
    def setUpClass(cls):
        cls.esquema = "ensayo_a02_" + uuid4().hex
        cls.clave_original = modulo_app.app.secret_key
        modulo_app.app.secret_key = 'clave_exclusiva_de_las_pruebas_temporales_A'
        cls.addClassCleanup(setattr, modulo_app.app, 'secret_key', cls.clave_original)
        cls.originales = [modulo_app.obtener_conexion, modulo_salas.obtener_conexion,
                          modulo_funciones.obtener_conexion, modulo_seguridad.obtener_conexion]
        with obtener_conexion() as conexion:
            conexion.execute(sql.SQL("CREATE SCHEMA {}").format(sql.Identifier(cls.esquema)))
        cls.addClassCleanup(cls.limpiar_esquema)
        carpeta = Path(__file__).resolve().parent.parent / "docs" / "compañeroA"
        conexion = cls.conectar()
        try:
            for archivo in ("relacional_A.sql", "ajuste_integridad_A.sql", "programacion_A.sql"):
                conexion.execute((carpeta / archivo).read_text(encoding="utf-8-sig"))
            archivo_c = carpeta.parent / 'compañeroC' / 'sql_C-01.sql'
            conexion.execute(archivo_c.read_text(encoding='utf-8-sig'))
            conexion.execute("INSERT INTO cine(nombre,ubicacion,zona_horaria) VALUES ('Cine ensayo','Ensayo','America/Costa_Rica')")
            conexion.execute("INSERT INTO pelicula(titulo,sinopsis,clasificacion,duracion_min,poster_url) VALUES ('Película ensayo','Sinopsis','Todo público',120,'/prueba.png')")
            conexion.execute("INSERT INTO sala(id_cine,nombre) VALUES (1,'Sala ensayo'),(1,'Sala simultánea')")
            conexion.execute("INSERT INTO zona(id_sala,nombre) VALUES (1,'General')")
            conexion.commit()
        finally:
            conexion.close()
        modulo_app.app.testing = True

    @classmethod
    def limpiar_esquema(cls):
        # El nombre solo procede del UUID creado por este script.
        if not cls.esquema.startswith("ensayo_a02_") or len(cls.esquema) != 43:
            raise RuntimeError("Nombre de esquema de ensayo inesperado")
        with obtener_conexion() as conexion:
            conexion.execute(sql.SQL("DROP SCHEMA {} CASCADE").format(sql.Identifier(cls.esquema)))

    def setUp(self):
        self.conexion = self.conectar()

        @contextmanager
        def temporal():
            # Cada operación usa un savepoint; el ensayo completo se revierte.
            with self.conexion.transaction():
                yield self.conexion

        modulo_app.obtener_conexion = temporal
        modulo_salas.obtener_conexion = temporal
        modulo_funciones.obtener_conexion = temporal
        modulo_seguridad.obtener_conexion = temporal
        self.cliente = ClienteA(modulo_app.app, modulo_app.app.response_class, use_cookies=True)
        administrador = self.conexion.execute("SELECT id_usuario FROM usuario WHERE correo='admin@imax.test'").fetchone()[0]
        with self.cliente.session_transaction() as sesion:
            sesion['id_usuario'] = administrador
            sesion['csrf_token'] = 'token_de_formulario_para_las_regresiones_A'

    def tearDown(self):
        self.conexion.rollback()
        self.conexion.close()
        (modulo_app.obtener_conexion, modulo_salas.obtener_conexion,
         modulo_funciones.obtener_conexion, modulo_seguridad.obtener_conexion) = self.originales

    def datos_funcion(self, inicio="2031-01-02T18:00:00"):
        return {"id_pelicula": "1", "id_sala": "1", "inicio": inicio, "activa": "on"}

    def crear_funcion(self, inicio="2031-01-02T18:00:00"):
        respuesta = self.cliente.post("/funciones/nueva", data=self.datos_funcion(inicio))
        self.assertEqual(respuesta.status_code, 302)
        return self.conexion.execute("SELECT id_funcion FROM funcion ORDER BY id_funcion DESC LIMIT 1").fetchone()[0]

    def test_pantallas_y_estilos(self):
        for ruta in ("/", "/peliculas/nueva", "/peliculas/1/editar", "/salas", "/salas/1",
                     "/funciones", "/funciones/nueva", "/static/estilos.css"):
            with self.subTest(ruta=ruta):
                with self.cliente.get(ruta) as respuesta:
                    self.assertEqual(respuesta.status_code, 200)

    def test_metadatos_pelicula(self):
        datos = dict(titulo="Título O'Brien", sinopsis="Sinopsis", clasificacion="Todo público",
                     duracion_min="95", poster_url="/poster.png")
        self.assertEqual(self.cliente.post("/peliculas/nueva", data=datos).status_code, 302)
        for campo in datos:
            with self.subTest(campo=campo):
                invalido = dict(datos); invalido[campo] = " "
                self.assertEqual(self.cliente.post("/peliculas/nueva", data=invalido).status_code, 400)

    def test_editar_pelicula(self):
        datos = dict(titulo="Título editado", sinopsis="Sinopsis", clasificacion="Todo público",
                     duracion_min="135", poster_url="/poster.png")
        self.assertEqual(self.cliente.post("/peliculas/1/editar", data=datos).status_code, 302)
        self.assertEqual(self.conexion.execute("SELECT titulo,duracion_min FROM pelicula WHERE id_pelicula=1").fetchone(), ("Título editado",135))

    def test_salas_zonas_y_lote(self):
        self.assertEqual(self.cliente.post("/salas", data={"id_cine":1,"nombre":"Sala nueva"}).status_code,302)
        self.assertEqual(self.cliente.post("/salas", data={"id_cine":1,"nombre":"Sala nueva"}).status_code,400)
        self.assertEqual(self.cliente.post("/salas/1/zonas", data={"nombre_zona":"VIP"}).status_code,302)
        datos = {"lote_zona":1,"lote_fila":"A","desde":1,"hasta":20}
        self.assertEqual(self.cliente.post("/salas/1/asientos/fila",data=datos).status_code,302)
        self.assertEqual(self.conexion.execute("SELECT COUNT(*) FROM asiento").fetchone()[0],20)
        self.assertEqual(self.cliente.post("/salas/1/asientos",data={"id_zona":1,"fila":"B","numero":3}).status_code,302)
        datos.update(lote_fila="B",desde=1,hasta=5)
        self.assertEqual(self.cliente.post("/salas/1/asientos/fila",data=datos).status_code,400)
        self.assertEqual(self.conexion.execute("SELECT numero FROM asiento WHERE fila='B'").fetchall(),[(3,)])

    def test_creacion_duracion_y_zona_horaria(self):
        self.crear_funcion()
        minutos, hora_utc = self.conexion.execute("SELECT EXTRACT(EPOCH FROM fin-inicio)/60, inicio AT TIME ZONE 'UTC' FROM funcion").fetchone()
        self.assertEqual(minutos,120)
        self.assertEqual(hora_utc.isoformat(),"2031-01-03T00:00:00")
        self.assertIn("02/01/2031 18:00",self.cliente.get("/funciones").get_data(as_text=True))

    def test_traslapes_y_limpieza(self):
        self.crear_funcion()
        for hora in ("17:00:00","19:00:00","20:10:00"):
            with self.subTest(hora=hora):
                r = self.cliente.post("/funciones/nueva",data=self.datos_funcion("2031-01-02T"+hora))
                self.assertEqual(r.status_code,400)
                self.assertIn("limpieza",r.get_data(as_text=True))
        self.crear_funcion("2031-01-02T20:15:00")
        self.assertEqual(self.conexion.execute("SELECT COUNT(*) FROM funcion WHERE id_sala=1").fetchone()[0],2)

    def test_edicion_y_horario_original(self):
        self.crear_funcion()
        segundo = self.crear_funcion("2031-01-02T20:15:00")
        ruta = f"/funciones/{segundo}/editar"
        self.assertEqual(self.cliente.get(ruta).status_code,200)
        self.assertEqual(self.cliente.post(ruta,data=self.datos_funcion("2031-01-02T19:30:00")).status_code,400)
        hora = self.conexion.execute("SELECT inicio AT TIME ZONE 'America/Costa_Rica' FROM funcion WHERE id_funcion=%s",(segundo,)).fetchone()[0]
        self.assertEqual(hora.hour,20)
        self.assertEqual(hora.minute,15)
        self.assertEqual(self.cliente.post(ruta,data=self.datos_funcion("2031-01-02T21:00:00")).status_code,302)

    def test_inactiva_y_reactivacion(self):
        self.crear_funcion()
        datos=self.datos_funcion();datos.pop("activa")
        self.assertEqual(self.cliente.post("/funciones/nueva",data=datos).status_code,302)
        identificador=self.conexion.execute("SELECT id_funcion FROM funcion WHERE NOT activa").fetchone()[0]
        self.assertEqual(self.cliente.post(f"/funciones/{identificador}/editar",data=self.datos_funcion()).status_code,400)

    def test_datos_y_referencias_invalidas(self):
        for cambio in ({"inicio":""},{"inicio":"fecha"},{"inicio":"2031-01-02"},{"inicio":"2031-01-02T18:00:00-06:00"},
                       {"id_pelicula":"999999"},{"id_sala":"999999"},{"id_sala":"abc"}):
            with self.subTest(cambio=cambio):
                datos=self.datos_funcion();datos.update(cambio)
                self.assertEqual(self.cliente.post("/funciones/nueva",data=datos).status_code,400)
        self.assertEqual(self.cliente.get("/funciones/999999/editar").status_code,404)
        self.assertEqual(self.cliente.post("/funciones/999999/editar",data=self.datos_funcion()).status_code,404)

    def test_sala_con_tarifas_protegida(self):
        identificador=self.crear_funcion()
        self.conexion.execute("INSERT INTO categoria_entrada(nombre) VALUES ('Adulto')")
        self.conexion.execute("""
            INSERT INTO tarifa(id_funcion,id_zona,id_categoria_entrada,monto,vigente_desde,vigente_hasta)
            VALUES (%s,1,1,8,'2030-01-01 00:00-06','2031-01-02 18:00-06')
        """,(identificador,))
        datos=self.datos_funcion();datos['id_sala']='2'
        respuesta=self.cliente.post(f"/funciones/{identificador}/editar",data=datos)
        self.assertEqual(respuesta.status_code,400)
        self.assertIn("tarifas",respuesta.get_data(as_text=True))
        self.assertEqual(self.conexion.execute("SELECT id_sala FROM funcion WHERE id_funcion=%s",(identificador,)).fetchone()[0],1)

    def test_programacion_simultanea(self):
        a=self.conectar(); b=self.conectar()
        try:
            pid_b=b.execute("SELECT pg_backend_pid()").fetchone()[0]
            a.execute("INSERT INTO funcion(id_pelicula,id_sala,inicio,fin) VALUES (1,2,'2032-01-01 18:00-06','2032-01-01 20:00-06')")
            def intentar():
                try:
                    b.execute("SET LOCAL statement_timeout='10s'")
                    b.execute("INSERT INTO funcion(id_pelicula,id_sala,inicio,fin) VALUES (1,2,'2032-01-01 19:00-06','2032-01-01 21:00-06')")
                    b.commit()
                    return "aceptada"
                except psycopg.errors.RaiseException:
                    b.rollback()
                    return "traslape"
            with ThreadPoolExecutor(max_workers=1) as ejecutor:
                futuro=ejecutor.submit(intentar)
                bloqueada=False
                limite=time.monotonic()+5
                while time.monotonic()<limite:
                    a.execute("SELECT pg_stat_clear_snapshot()")
                    fila=a.execute("SELECT wait_event_type FROM pg_stat_activity WHERE pid=%s",(pid_b,)).fetchone()
                    if fila and fila[0]=="Lock":
                        bloqueada=True
                        break
                    time.sleep(0.05)
                a.commit()
                self.assertTrue(bloqueada,"La segunda conexión debe esperar a la primera")
                self.assertEqual(futuro.result(timeout=12),"traslape")
            self.assertEqual(a.execute("SELECT COUNT(*) FROM funcion WHERE id_sala=2").fetchone()[0],1)
        finally:
            a.rollback();b.rollback();a.close();b.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
