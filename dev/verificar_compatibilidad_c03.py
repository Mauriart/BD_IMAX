"""Compatibilidad de A con las funciones reales de auditoría de C-03.

Uso: python verificar_compatibilidad_c03.py RUTA_AL_SQL_C03
Extrae solo cuatro funciones de C para ensayarlas en un esquema temporal.
No instala reembolsos, boletos, roles técnicos ni triggers en public.
"""
from pathlib import Path
import re
import sys
import unittest
from psycopg import sql
import psycopg
from verificar_seguridad_a import PruebasSeguridad
from verificar_a02 import PruebasA02

ARCHIVO_C03 = None


class PruebasCompatibilidadC03(unittest.TestCase):
    conectar = classmethod(PruebasA02.conectar.__func__)
    limpiar_esquema = classmethod(PruebasA02.limpiar_esquema.__func__)
    tearDown = PruebasA02.tearDown
    pelicula = PruebasSeguridad.pelicula
    cantidad_logs = PruebasSeguridad.cantidad_logs
    datos_promocion = PruebasSeguridad.datos_promocion

    @classmethod
    def setUpClass(cls):
        if ARCHIVO_C03 is None:
            raise unittest.SkipTest('Indica la ruta del SQL real de C-03.')
        PruebasSeguridad.setUpClass.__func__(cls)
        cls.fuente = Path(ARCHIVO_C03).read_text(encoding='utf-8-sig')

    def setUp(self):
        PruebasSeguridad.setUp(self)
        for nombre in ('normalizar_ip', 'auditar_accion', 'guardia_rbac', 'auditar_cambio_critico'):
            patron = r'CREATE OR REPLACE FUNCTION ' + nombre + r'\(.*?\$\$;'
            coincidencia = re.search(patron, self.fuente, re.S)
            self.assertIsNotNone(coincidencia, 'No se encontró en C-03: ' + nombre)
            texto = coincidencia.group().replace(
                'SET search_path = public, pg_temp',
                'SET search_path = "' + self.esquema + '", pg_temp')
            self.conexion.execute(texto)
        # Mismos triggers de C-03 sobre las tablas de A, en el esquema del ensayo.
        for tabla, permiso in [
            ('pelicula','gestionar_catalogo'), ('genero','gestionar_catalogo'),
            ('pelicula_genero','gestionar_catalogo'), ('cine','gestionar_catalogo'),
            ('sala','gestionar_catalogo'), ('zona','gestionar_catalogo'),
            ('asiento','gestionar_catalogo'), ('funcion','gestionar_catalogo'),
            ('tarifa','configurar_tarifas'), ('promocion','configurar_tarifas'),
            ('promocion_dia','configurar_tarifas'), ('promocion_zona','configurar_tarifas'),
            ('promocion_categoria','configurar_tarifas'), ('funcion_promocion','configurar_tarifas'),
            ('categoria_entrada','configurar_tarifas')]:
            self.conexion.execute(sql.SQL("""CREATE TRIGGER trg_guardia_rbac
                BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON {}
                FOR EACH STATEMENT EXECUTE FUNCTION guardia_rbac({})""").format(
                sql.Identifier(tabla), sql.Literal(permiso)))
        for tabla in ('sala','zona','asiento','funcion','tarifa','promocion','categoria_entrada'):
            self.conexion.execute(sql.SQL("""CREATE TRIGGER trg_auditar_cambio
                AFTER INSERT OR UPDATE OR DELETE ON {} FOR EACH ROW
                EXECUTE FUNCTION auditar_cambio_critico({})""").format(
                sql.Identifier(tabla), sql.Literal('id_' + tabla)))

    def test_once_escrituras_sin_eventos_duplicados(self):
        operaciones = [
            ('/peliculas/nueva', self.pelicula(), 1),
            ('/peliculas/1/editar', dict(self.pelicula(),titulo='Editada'), 1),
            ('/salas', {'id_cine':'1','nombre':'Sala auditada'}, 1),
            ('/salas/1/zonas', {'nombre_zona':'Nueva'}, 1),
            ('/salas/1/asientos', {'id_zona':'1','fila':'Z','numero':'1'}, 1),
            ('/salas/1/asientos/fila', {'lote_zona':'1','lote_fila':'Y','desde':'1','hasta':'3'}, 3),
            ('/funciones/nueva', {'id_pelicula':'1','id_sala':'1','inicio':'2031-02-01T18:00','activa':'on'}, 1),
            (self.ruta, dict(self.formulario,accion='tarifa',id_zona='1',id_categoria_entrada='1',monto='8'), 1),
            (self.ruta, self.datos_promocion(), 1),
            (self.ruta, {'accion':'categoria','nombre_categoria':'Cortesía'}, 1),
        ]
        cantidad = 0
        for ruta, datos, incremento in operaciones:
            with self.subTest(ruta=ruta):
                self.assertEqual(self.cliente.post(ruta,data=datos).status_code,302)
                cantidad += incremento
                self.assertEqual(self.cantidad_logs(),cantidad)
        identificador = self.conexion.execute('SELECT MAX(id_funcion) FROM funcion').fetchone()[0]
        self.assertEqual(self.cliente.post(f'/funciones/{identificador}/editar',data={
            'id_pelicula':'1','id_sala':'1','inicio':'2031-02-01T21:00','activa':'on'}).status_code,302)
        self.assertEqual(self.cantidad_logs(),13)
        registros = self.conexion.execute('SELECT rol_al_actuar,ip,motivo,cambios FROM admin_operacion_audit').fetchall()
        for rol,ip,motivo,cambios in registros:
            self.assertEqual((rol,ip,motivo),('administrador','127.0.0.1','Prueba aislada del módulo A'))
            self.assertIsNotNone(cambios['despues'])
        antes = self.conexion.execute("""SELECT cambios->'antes'->>'inicio' FROM admin_operacion_audit
            WHERE entidad='funcion' AND accion='update_funcion'""").fetchone()[0]
        self.assertIsNotNone(antes)

    def test_trigger_deshabilitado_tiene_respaldo_manual(self):
        self.conexion.execute('ALTER TABLE sala DISABLE TRIGGER trg_auditar_cambio')
        self.assertEqual(self.cliente.post('/salas',data={'id_cine':'1','nombre':'Sin trigger'}).status_code,302)
        self.assertEqual(self.cantidad_logs(),1)
        self.assertEqual(self.conexion.execute('SELECT accion FROM admin_operacion_audit').fetchone()[0],
                         'gestionar_catalogo')

    def test_pelicula_usa_funcion_comun_c03_y_revierte_si_falla(self):
        self.conexion.execute("""CREATE OR REPLACE FUNCTION auditar_accion(
            p_id_usuario_actor integer, p_ip text, p_accion text, p_entidad text,
            p_id_entidad text, p_motivo text, p_cambios jsonb DEFAULT NULL)
            RETURNS integer LANGUAGE plpgsql AS $$
            BEGIN RAISE EXCEPTION 'fallo controlado'; END $$""")
        self.assertEqual(self.cliente.post('/peliculas/nueva',data=self.pelicula()).status_code,503)
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM pelicula').fetchone()[0],1)
        self.assertEqual(self.cantidad_logs(),0)

    def test_auditoria_automatica_fallida_revierte_negocio(self):
        self.conexion.execute("""CREATE FUNCTION rechazar_auditoria_c03() RETURNS trigger LANGUAGE plpgsql AS $$
            BEGIN RAISE EXCEPTION 'fallo controlado' USING ERRCODE='23514'; END $$""")
        self.conexion.execute("""CREATE TRIGGER trg_rechazo_c03 BEFORE INSERT ON admin_operacion_audit
            FOR EACH ROW EXECUTE FUNCTION rechazar_auditoria_c03()""")
        self.assertEqual(self.cliente.post('/salas',data={'id_cine':'1','nombre':'No guardar'}).status_code,503)
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM sala').fetchone()[0],2)
        self.assertEqual(self.cantidad_logs(),0)

    def test_guardia_de_c03_rechaza_actor_sin_permiso(self):
        cliente = self.conexion.execute("SELECT id_usuario FROM usuario WHERE correo='cliente1@imax.test'").fetchone()[0]
        with self.assertRaises(psycopg.errors.InsufficientPrivilege):
            with self.conexion.transaction():
                self.conexion.execute("SELECT set_config('app.id_usuario',%s,true)",(str(cliente),))
                self.conexion.execute("INSERT INTO sala(id_cine,nombre) VALUES(1,'Denegada')")
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM sala').fetchone()[0],2)
        self.assertEqual(self.cantidad_logs(),0)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Uso: python verificar_compatibilidad_c03.py RUTA_AL_SQL_C03')
    ARCHIVO_C03 = sys.argv.pop()
    unittest.main(defaultTest='PruebasCompatibilidadC03',verbosity=2)
