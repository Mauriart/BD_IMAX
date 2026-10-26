"""Soporte para pruebas aisladas en un esquema temporal."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent.parent))
from contextlib import contextmanager
import unittest
from psycopg import sql
from flask.testing import FlaskClient
import app as modulo_app
from modulos import funciones as modulo_funciones, salas as modulo_salas, seguridad as modulo_seguridad
from modulos.conexion import obtener_conexion

def generar():
    return (Path(__file__).resolve().parent.parent/'sql/instalacion_completa.sql').read_text(encoding='utf-8-sig')

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
        conexion.execute(sql.SQL("SET search_path TO {}, pg_temp").format(sql.Identifier(cls.esquema)))
        return conexion


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
