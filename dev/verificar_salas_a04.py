"""Pruebas de A-04 con contrato de B, no con su módulo completo."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import re
import time
import unittest
import psycopg
from verificar_a02 import PruebasA02
from verificar_precios_a03 import PruebasPrecios

SQL_C03 = None


class PruebasSalasProtegidas(unittest.TestCase):
    conectar = classmethod(PruebasA02.conectar.__func__)
    limpiar_esquema = classmethod(PruebasA02.limpiar_esquema.__func__)
    tearDown = PruebasA02.tearDown

    @classmethod
    def setUpClass(cls):
        PruebasPrecios.setUpClass.__func__(cls)
        cls.carpeta = Path(__file__).resolve().parent.parent/'docs'/'compañeroA'
        cls.migracion = (cls.carpeta/'proteccion_salas_A04.sql').read_text(encoding='utf-8-sig')
        with cls.conectar() as c:
            c.execute((cls.carpeta/'pruebas_contrato_B_A04.sql').read_text(encoding='utf-8-sig'))
            c.execute(cls.migracion)
            c.execute(cls.migracion)  # Reejecución sin duplicar triggers ni borrar datos.

    def setUp(self):
        PruebasPrecios.setUp(self)
        self.asiento = self.conexion.execute("INSERT INTO asiento(id_zona,fila,numero) VALUES(1,'A',1) RETURNING id_asiento").fetchone()[0]
        self.otro = self.conexion.execute("INSERT INTO asiento(id_zona,fila,numero) VALUES(1,'A',2) RETURNING id_asiento").fetchone()[0]
        self.ruta_borrar = f'/salas/1/asientos/{self.asiento}/eliminar'

    def reserva(self, vencida=False):
        return self.conexion.execute("""INSERT INTO reserva(id_funcion,id_asiento,estado,vence_en)
            VALUES(%s,%s,'activa',clock_timestamp()+%s*INTERVAL '1 minute') RETURNING id_reserva""",
            (self.funcion,self.asiento,-1 if vencida else 10)).fetchone()[0]

    def boleto(self, estado='Emitido'):
        return self.conexion.execute('INSERT INTO boleto(id_funcion,id_asiento,estado) VALUES(%s,%s,%s) RETURNING id_boleto',
                                     (self.funcion,self.asiento,estado)).fetchone()[0]

    def test_borrado_permitido_auditado_y_pantalla(self):
        self.assertEqual(self.cliente.get(self.ruta_borrar).status_code,200)
        self.assertIn('Eliminar',self.cliente.get('/salas/1').get_data(as_text=True))
        self.assertEqual(self.cliente.post(self.ruta_borrar).status_code,302)
        self.assertIsNone(self.conexion.execute('SELECT 1 FROM asiento WHERE id_asiento=%s',(self.asiento,)).fetchone())
        cambios=self.conexion.execute('SELECT cambios FROM admin_operacion_audit').fetchone()[0]
        self.assertEqual(cambios['antes']['id_asiento'],self.asiento)
        self.assertIsNone(cambios['despues'])

    def test_reserva_activa_rechaza_borrado_y_nuevos_asientos(self):
        self.reserva()
        self.assertEqual(self.cliente.post(self.ruta_borrar).status_code,400)
        self.assertEqual(self.cliente.post('/salas/1/asientos',data={'id_zona':'1','fila':'B','numero':'1'}).status_code,400)
        self.assertEqual(self.cliente.post('/salas/1/asientos/fila',data={
            'lote_zona':'1','lote_fila':'B','desde':'1','hasta':'4'}).status_code,400)
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM asiento WHERE id_zona=1').fetchone()[0],2)
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM admin_operacion_audit').fetchone()[0],0)

    def test_emitido_y_usado_protegen_la_sala(self):
        for estado in ('Emitido','Usado'):
            with self.subTest(estado=estado),self.conexion.transaction(force_rollback=True):
                self.boleto(estado)
                self.assertEqual(self.cliente.post(self.ruta_borrar).status_code,400)
                with self.assertRaises(psycopg.errors.ObjectNotInPrerequisiteState),self.conexion.transaction():
                    self.conexion.execute('DELETE FROM sala WHERE id_sala=1')

    def test_historia_no_se_elimina(self):
        self.boleto('Anulado')
        respuesta=self.cliente.post(self.ruta_borrar)
        self.assertEqual(respuesta.status_code,400)
        self.assertIn('historia',respuesta.get_data(as_text=True))
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM boleto').fetchone()[0],1)
        self.assertIsNotNone(self.conexion.execute('SELECT 1 FROM asiento WHERE id_asiento=%s',(self.asiento,)).fetchone())

    def test_reserva_vencida_no_bloquea_otro_asiento_sin_referencias(self):
        self.reserva(vencida=True)
        self.assertEqual(self.cliente.post(f'/salas/1/asientos/{self.otro}/eliminar').status_code,302)
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM reserva WHERE id_funcion=%s',(self.funcion,)).fetchone()[0],1)

    def test_reprogramacion_con_reserva_rechazada(self):
        self.reserva()
        original=self.conexion.execute('SELECT inicio,fin FROM funcion WHERE id_funcion=%s',(self.funcion,)).fetchone()
        respuesta=self.cliente.post(f'/funciones/{self.funcion}/editar',data={
            'id_pelicula':'1','id_sala':'1','inicio':'2031-04-02T18:00','activa':'on'})
        self.assertEqual(respuesta.status_code,400)
        self.assertEqual(self.conexion.execute('SELECT inicio,fin FROM funcion WHERE id_funcion=%s',(self.funcion,)).fetchone(),original)

    def test_zona_con_inventario_no_se_traslada(self):
        self.conexion.execute("INSERT INTO inventario_funcion VALUES(%s,%s,'disponible',NULL,NULL)",(self.funcion,self.asiento))
        with self.assertRaises(psycopg.errors.ObjectNotInPrerequisiteState),self.conexion.transaction():
            self.conexion.execute('UPDATE zona SET id_sala=2 WHERE id_zona=1')

    def test_ocupacion_rechaza_asiento_de_otra_sala(self):
        z=self.conexion.execute("INSERT INTO zona(id_sala,nombre) VALUES(2,'Otra') RETURNING id_zona").fetchone()[0]
        a=self.conexion.execute("INSERT INTO asiento(id_zona,fila,numero) VALUES(%s,'B',1) RETURNING id_asiento",(z,)).fetchone()[0]
        with self.assertRaises(psycopg.errors.ForeignKeyViolation),self.conexion.transaction():
            self.conexion.execute("""INSERT INTO reserva(id_funcion,id_asiento,estado,vence_en)
                VALUES(%s,%s,'activa',clock_timestamp()+INTERVAL '1 minute')""",(self.funcion,a))

    def test_permisos_csrf_y_ambito_sala(self):
        self.assertEqual(self.cliente.get(f'/salas/2/asientos/{self.asiento}/eliminar').status_code,404)
        self.assertEqual(self.cliente.post(self.ruta_borrar,data={'csrf_token':'incorrecto'}).status_code,400)
        cliente=self.conexion.execute("SELECT id_usuario FROM usuario WHERE correo='cliente1@imax.test'").fetchone()[0]
        with self.cliente.session_transaction() as s:s['id_usuario']=cliente
        respuesta=self.cliente.post(self.ruta_borrar)
        self.assertEqual(respuesta.status_code,403)
        self.assertIn('Tu usuario no tiene permiso para realizar esta operación.',respuesta.get_data(as_text=True))
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM asiento WHERE id_zona=1').fetchone()[0],2)

    def test_fallo_auditoria_revierte_borrado(self):
        self.conexion.execute("""CREATE FUNCTION fallar_a04() RETURNS trigger LANGUAGE plpgsql AS $$
            BEGIN RAISE EXCEPTION 'fallo de ensayo'; END $$""")
        self.conexion.execute('CREATE TRIGGER trg_fallar_a04 BEFORE INSERT ON admin_operacion_audit FOR EACH ROW EXECUTE FUNCTION fallar_a04()')
        self.assertEqual(self.cliente.post(self.ruta_borrar).status_code,503)
        self.assertIsNotNone(self.conexion.execute('SELECT 1 FROM asiento WHERE id_asiento=%s',(self.asiento,)).fetchone())

    def test_instalacion_incompatible_se_rechaza_sin_cambios_parciales(self):
        script=re.sub(r'(?m)^(BEGIN|COMMIT);$','',self.migracion)
        with self.assertRaises(psycopg.errors.ObjectNotInPrerequisiteState),self.conexion.transaction():
            self.conexion.execute('ALTER TABLE boleto RENAME COLUMN id_funcion TO columna_incompatible')
            self.conexion.execute(script)
        self.assertEqual(self.cliente.get(self.ruta_borrar).status_code,200)

    def test_otro_aislamiento_no_omite_la_proteccion(self):
        c=self.conectar()
        try:
            c.commit()
            c.execute('BEGIN ISOLATION LEVEL REPEATABLE READ')
            with self.assertRaises(psycopg.errors.ObjectNotInPrerequisiteState):
                c.execute('SELECT a04_bloquear_sala(1)')
            c.rollback()
        finally:
            c.close()

    def test_sin_instalacion_no_habilita_eliminar(self):
        with self.conexion.transaction(force_rollback=True):
            self.conexion.execute('DROP FUNCTION a04_bloquear_sala(integer)')
            self.assertEqual(self.cliente.get(self.ruta_borrar).status_code,503)
            self.assertNotIn('>Eliminar</a>',self.cliente.get('/salas/1').get_data(as_text=True))

    def test_instalacion_rechaza_ocupacion_preexistente_incompatible(self):
        script=re.sub(r'(?m)^(BEGIN|COMMIT);$','',self.migracion)
        with self.conexion.transaction(force_rollback=True):
            z=self.conexion.execute("INSERT INTO zona(id_sala,nombre) VALUES(2,'Incompatible') RETURNING id_zona").fetchone()[0]
            a=self.conexion.execute("INSERT INTO asiento(id_zona,fila,numero) VALUES(%s,'X',1) RETURNING id_asiento",(z,)).fetchone()[0]
            self.conexion.execute('ALTER TABLE reserva DISABLE TRIGGER trg_a04_ocupacion')
            self.conexion.execute("INSERT INTO reserva(id_funcion,id_asiento,estado,vence_en) VALUES(%s,%s,'activa',clock_timestamp()+INTERVAL '1 minute')",(self.funcion,a))
            self.conexion.execute('ALTER TABLE reserva ENABLE TRIGGER trg_a04_ocupacion')
            with self.assertRaises(psycopg.errors.ObjectNotInPrerequisiteState),self.conexion.transaction():
                self.conexion.execute(script)

    def test_delete_con_trigger_real_c03_sin_duplicacion(self):
        if SQL_C03 is None:self.skipTest('Indica --c03 con el SQL real de C-03.')
        fuente=Path(SQL_C03).read_text(encoding='utf-8-sig')
        for nombre in ('normalizar_ip','auditar_accion','auditar_cambio_critico'):
            texto=re.search(r'CREATE OR REPLACE FUNCTION '+nombre+r'\(.*?\$\$;',fuente,re.S).group()
            texto=texto.replace('SET search_path = public, pg_temp',f'SET search_path = "{self.esquema}", pg_temp')
            self.conexion.execute(texto)
        self.conexion.execute("""CREATE TRIGGER trg_c03_delete AFTER DELETE ON asiento
            FOR EACH ROW EXECUTE FUNCTION auditar_cambio_critico('id_asiento')""")
        self.assertEqual(self.cliente.post(self.ruta_borrar).status_code,302)
        filas=self.conexion.execute('SELECT accion,cambios FROM admin_operacion_audit').fetchall()
        self.assertEqual(len(filas),1)
        self.assertEqual(filas[0][0],'delete_asiento')
        self.assertEqual(filas[0][1]['antes']['id_asiento'],self.asiento)

    def escenario_concurrente(self):
        with self.conectar() as c:
            s=c.execute("INSERT INTO sala(id_cine,nombre) VALUES(1,%s) RETURNING id_sala",
                        ('Carrera '+self._testMethodName,)).fetchone()[0]
            z=c.execute("INSERT INTO zona(id_sala,nombre) VALUES(%s,'General') RETURNING id_zona",(s,)).fetchone()[0]
            a=c.execute("INSERT INTO asiento(id_zona,fila,numero) VALUES(%s,'R',1) RETURNING id_asiento",(z,)).fetchone()[0]
            f=c.execute("""INSERT INTO funcion(id_pelicula,id_sala,inicio,fin)
                VALUES(1,%s,'2031-06-01 18:00-06','2031-06-01 20:00-06') RETURNING id_funcion""",(s,)).fetchone()[0]
        return s,a,f

    def esperar_bloqueo(self,pid):
        limite=time.monotonic()+3
        with self.conectar() as observador:
            while time.monotonic()<limite:
                fila=observador.execute('SELECT wait_event_type FROM pg_stat_activity WHERE pid=%s',(pid,)).fetchone()
                if fila and fila[0]=='Lock':return
                time.sleep(.02)
        self.fail('No se observó la espera por bloqueo.')

    def test_concurrencia_reserva_primero_rechaza_borrado(self):
        sala,asiento,funcion=self.escenario_concurrente()
        primero,segundo=self.conectar(),self.conectar()
        self.addCleanup(primero.close);self.addCleanup(segundo.close)
        primero.execute("""INSERT INTO reserva(id_funcion,id_asiento,estado,vence_en)
            VALUES(%s,%s,'activa',clock_timestamp()+INTERVAL '10 minutes')""",(funcion,asiento))
        pid=segundo.execute('SELECT pg_backend_pid()').fetchone()[0]
        def borrar():
            try:
                segundo.execute("SET LOCAL lock_timeout='6s'")
                segundo.execute('SELECT a04_bloquear_sala(%s)',(sala,))
                segundo.execute('DELETE FROM asiento WHERE id_asiento=%s',(asiento,))
                segundo.commit();return 'aceptado'
            except psycopg.Error as e:
                segundo.rollback();return e.sqlstate
        with ThreadPoolExecutor(1) as pool:
            futuro=pool.submit(borrar)
            try:self.esperar_bloqueo(pid)
            finally:primero.commit()
            self.assertEqual(futuro.result(timeout=8),'55000')
        with self.conectar() as c:
            self.assertIsNotNone(c.execute('SELECT 1 FROM asiento WHERE id_asiento=%s',(asiento,)).fetchone())

    def test_concurrencia_borrado_primero_rechaza_reserva(self):
        sala,asiento,funcion=self.escenario_concurrente()
        primero,segundo=self.conectar(),self.conectar()
        self.addCleanup(primero.close);self.addCleanup(segundo.close)
        primero.execute('SELECT a04_bloquear_sala(%s)',(sala,))
        primero.execute('DELETE FROM asiento WHERE id_asiento=%s',(asiento,))
        pid=segundo.execute('SELECT pg_backend_pid()').fetchone()[0]
        def reservar():
            try:
                segundo.execute("SET LOCAL lock_timeout='6s'")
                segundo.execute("""INSERT INTO reserva(id_funcion,id_asiento,estado,vence_en)
                    VALUES(%s,%s,'activa',clock_timestamp()+INTERVAL '10 minutes')""",(funcion,asiento))
                segundo.commit();return 'aceptado'
            except psycopg.Error as e:
                segundo.rollback();return e.sqlstate
        with ThreadPoolExecutor(1) as pool:
            futuro=pool.submit(reservar)
            try:self.esperar_bloqueo(pid)
            finally:primero.commit()
            self.assertEqual(futuro.result(timeout=8),'23503')
        with self.conectar() as c:
            self.assertEqual(c.execute('SELECT COUNT(*) FROM reserva WHERE id_asiento=%s',(asiento,)).fetchone()[0],0)


if __name__=='__main__':
    import sys
    parser=argparse.ArgumentParser()
    parser.add_argument('--c03')
    argumentos,resto=parser.parse_known_args()
    SQL_C03=argumentos.c03
    unittest.main(argv=[sys.argv[0],*resto],defaultTest='PruebasSalasProtegidas',verbosity=2)
