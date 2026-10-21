"""Pruebas de tarifas/promociones en un esquema temporal independiente."""
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from decimal import Decimal
from pathlib import Path
import time
import unittest
import psycopg
import app
import precios
from verificar_a02 import PruebasA02


class PruebasPrecios(unittest.TestCase):
    conectar = classmethod(PruebasA02.conectar.__func__)
    limpiar_esquema = classmethod(PruebasA02.limpiar_esquema.__func__)
    tearDown = PruebasA02.tearDown

    @classmethod
    def setUpClass(cls):
        PruebasA02.setUpClass.__func__(cls)
        archivo = Path(__file__).resolve().parent.parent / 'docs' / 'compañeroA' / 'tarifas_promociones_A.sql'
        with cls.conectar() as conexion:
            conexion.execute(archivo.read_text(encoding='utf-8'))
            # La reinstalación no debe borrar las condiciones ni duplicar tablas.
            conexion.execute(archivo.read_text(encoding='utf-8'))
            conexion.execute("INSERT INTO categoria_entrada(nombre,requiere_acreditacion) VALUES ('Adulto',FALSE),('Estudiante',TRUE)")

    def setUp(self):
        PruebasA02.setUp(self)
        original = precios.obtener_conexion
        self.addCleanup(setattr, precios, 'obtener_conexion', original)
        precios.obtener_conexion = app.obtener_conexion
        self.ahora, local = self.conexion.execute("SELECT CURRENT_TIMESTAMP, CURRENT_TIMESTAMP AT TIME ZONE 'America/Costa_Rica'").fetchone()
        self.desde = self.ahora - timedelta(days=1)
        self.hasta = self.ahora + timedelta(days=5)
        self.funcion = self.conexion.execute('''
            INSERT INTO funcion(id_pelicula,id_sala,inicio,fin)
            VALUES (1,1,%s,%s) RETURNING id_funcion
        ''', (self.ahora + timedelta(days=10), self.ahora + timedelta(days=10, hours=2))).fetchone()[0]
        self.formulario = {'vigente_desde':(local - timedelta(days=1)).isoformat(timespec='seconds'),
                           'vigente_hasta':(local + timedelta(days=5)).isoformat(timespec='seconds')}
        self.ruta = f'/funciones/{self.funcion}/precios'

    def tarifa(self, desde=None, hasta=None, categoria=1):
        return self.conexion.execute('''
            INSERT INTO tarifa(id_funcion,id_zona,id_categoria_entrada,monto,vigente_desde,vigente_hasta)
            VALUES (%s,1,%s,8,%s,%s) RETURNING id_tarifa
        ''', (self.funcion,categoria,desde or self.desde,hasta or self.hasta)).fetchone()[0]

    def datos_promocion(self):
        return dict(self.formulario, accion='promocion', nombre='Parejas', condicion='Dos entradas de la misma zona y categoría.',
                    dias=[str(d) for d in range(1,8)], zonas=['1'], categorias=['1'])

    def test_vigencia_desde_incluido_hasta_excluido_y_decimal(self):
        identificador = self.tarifa()
        tarifa = precios.consultar_tarifas(self.funcion,1,1,self.desde)
        self.assertEqual(tarifa['id_tarifa'],identificador)
        self.assertEqual(tarifa['monto'],Decimal('8.00'))
        for instante in (self.desde-timedelta(seconds=1), self.hasta):
            with self.subTest(instante=instante), self.assertRaises(ValueError):
                precios.consultar_tarifas(self.funcion,1,1,instante)
        with self.assertRaises(ValueError):
            precios.consultar_tarifas(self.funcion,1,2,self.ahora)
        with self.assertRaises(ValueError):
            precios.consultar_tarifas(self.funcion,1,1,self.ahora.replace(tzinfo=None))

    def test_cruces_rechazados_y_vigencias_contiguas_permitidas(self):
        self.tarifa()
        for desde,hasta in ((self.desde,self.hasta),(self.desde-timedelta(hours=1),self.desde+timedelta(hours=1)),
                            (self.hasta-timedelta(hours=1),self.hasta+timedelta(hours=1))):
            with self.subTest(desde=desde), self.assertRaises(psycopg.errors.CheckViolation):
                with self.conexion.transaction():
                    self.tarifa(desde,hasta)
        segundo = self.tarifa(self.hasta,self.hasta+timedelta(days=1))
        self.assertEqual(precios.consultar_tarifas(self.funcion,1,1,self.hasta)['id_tarifa'],segundo)
        self.tarifa(categoria=2)
        with self.assertRaises(psycopg.errors.CheckViolation):
            with self.conexion.transaction():
                self.conexion.execute('UPDATE tarifa SET vigente_desde=%s WHERE id_tarifa=%s',(self.hasta-timedelta(minutes=1),segundo))

    def test_formulario_tarifa_categoria_y_matriz_publica(self):
        self.assertEqual(self.cliente.get(self.ruta).status_code,200)
        datos = dict(self.formulario,accion='tarifa',id_zona='1',id_categoria_entrada='2',monto='6.25')
        self.assertEqual(self.cliente.post(self.ruta,data=datos).status_code,302)
        tarifa = precios.consultar_tarifas(self.funcion,1,2,self.ahora)
        self.assertTrue(tarifa['requiere_acreditacion'])
        self.assertEqual(tarifa['monto'],Decimal('6.25'))
        respuesta = self.cliente.get(f'/cartelera/{self.funcion}/precios')
        self.assertEqual(respuesta.status_code,200)
        contenido = respuesta.get_data(as_text=True)
        for texto in ('$6.25','Requiere acreditación','No disponible'):
            self.assertIn(texto,contenido)
        self.assertEqual(self.cliente.post(self.ruta,data={'accion':'categoria','nombre_categoria':'Niño','requiere_acreditacion':'on'}).status_code,302)
        self.assertTrue(self.conexion.execute("SELECT requiere_acreditacion FROM categoria_entrada WHERE nombre='Niño'").fetchone()[0])

    def test_datos_invalidos_no_guardan_y_zona_ajena(self):
        otra_zona = self.conexion.execute("INSERT INTO zona(id_sala,nombre) VALUES (2,'Ajena') RETURNING id_zona").fetchone()[0]
        datos = dict(self.formulario,accion='tarifa',id_zona='1',id_categoria_entrada='1',monto='8')
        for cambio in ({'monto':'-1'},{'monto':'8.001'},{'monto':'NaN'},{'monto':'Infinity'},
                       {'monto':'10000000000'},{'id_zona':str(otra_zona)}, {'id_categoria_entrada':'99999'},
                       {'vigente_hasta':datos['vigente_desde']},{'vigente_desde':'fecha'}):
            with self.subTest(cambio=cambio):
                self.assertEqual(self.cliente.post(self.ruta,data=dict(datos,**cambio)).status_code,400)
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM tarifa').fetchone()[0],0)
        with self.assertRaises(psycopg.errors.CheckViolation):
            with self.conexion.transaction():
                self.conexion.execute('''INSERT INTO tarifa(id_funcion,id_zona,id_categoria_entrada,monto,vigente_desde,vigente_hasta)
                    VALUES (%s,%s,1,8,%s,%s)''',(self.funcion,otra_zona,self.desde,self.hasta))

    def test_promocion_estructurada_filtros_y_limites(self):
        self.assertEqual(self.cliente.post(self.ruta,data=self.datos_promocion()).status_code,302)
        promociones = precios.consultar_promociones(self.funcion,self.ahora,1,1)
        self.assertEqual(len(promociones),1)
        promocion = promociones[0]
        self.assertEqual(promocion['dias'],list(range(1,8)))
        self.assertEqual(promocion['zonas'],[1])
        self.assertEqual(promocion['categorias'],[1])
        self.assertEqual(precios.consultar_promociones(self.funcion,self.ahora,1,2),[])
        self.assertEqual(precios.consultar_promociones(self.funcion,promocion['vigente_hasta']),[])
        self.assertEqual(len(precios.consultar_promociones(self.funcion,promocion['vigente_desde'])),1)
        contenido = self.cliente.get(f'/cartelera/{self.funcion}/precios').get_data(as_text=True)
        self.assertIn('Parejas',contenido)
        self.assertIn('no se acumulan',contenido)
        self.conexion.execute('UPDATE promocion SET activa=FALSE WHERE id_promocion=%s',(promocion['id_promocion'],))
        self.assertEqual(precios.consultar_promociones(self.funcion,self.ahora),[])

    def test_dia_de_funcion_local_y_promocion_antigua_incompleta(self):
        # La función comienza a las 23:30; en UTC es otro día.
        self.conexion.execute('''UPDATE funcion SET
            inicio=((%s AT TIME ZONE 'America/Costa_Rica')::date+10+TIME '23:30') AT TIME ZONE 'America/Costa_Rica',
            fin=((%s AT TIME ZONE 'America/Costa_Rica')::date+11+TIME '01:30') AT TIME ZONE 'America/Costa_Rica'
            WHERE id_funcion=%s''',(self.ahora,self.ahora,self.funcion))
        dia = self.conexion.execute("SELECT EXTRACT(ISODOW FROM inicio AT TIME ZONE 'America/Costa_Rica')::int FROM funcion WHERE id_funcion=%s",(self.funcion,)).fetchone()[0]
        datos = self.datos_promocion(); datos['dias']=[str(dia)]
        self.assertEqual(self.cliente.post(self.ruta,data=datos).status_code,302)
        identificador = precios.consultar_promociones(self.funcion,self.ahora)[0]['id_promocion']
        self.conexion.execute('UPDATE promocion_dia SET dia_semana=%s WHERE id_promocion=%s',(dia % 7 + 1,identificador))
        self.assertEqual(precios.consultar_promociones(self.funcion,self.ahora),[])
        self.conexion.execute('DELETE FROM promocion_dia WHERE id_promocion=%s',(identificador,))
        self.assertEqual(precios.consultar_promociones(self.funcion,self.ahora),[])
        self.assertIn('Sin condiciones estructuradas',self.cliente.get(self.ruta).get_data(as_text=True))

    def test_promocion_invalida_no_deja_registros_parciales(self):
        for cambio in ({'dias':[]},{'dias':['8']},{'zonas':['99999']},{'categorias':[]},{'nombre':''}):
            with self.subTest(cambio=cambio):
                self.assertEqual(self.cliente.post(self.ruta,data=dict(self.datos_promocion(),**cambio)).status_code,400)
        for tabla in ('promocion','funcion_promocion','promocion_dia','promocion_zona','promocion_categoria'):
            self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM '+tabla).fetchone()[0],0)

    def test_funcion_inactiva_pasada_e_inexistente(self):
        self.tarifa()
        self.conexion.execute('UPDATE funcion SET activa=FALSE WHERE id_funcion=%s',(self.funcion,))
        with self.assertRaises(ValueError):
            precios.consultar_tarifas(self.funcion,1,1,self.ahora)
        self.assertEqual(self.cliente.get(f'/cartelera/{self.funcion}/precios').status_code,404)
        self.assertEqual(self.cliente.get('/funciones/99999/precios').status_code,404)
        self.conexion.execute('UPDATE funcion SET activa=TRUE,inicio=%s,fin=%s WHERE id_funcion=%s',
                              (self.ahora-timedelta(days=1),self.ahora-timedelta(hours=22),self.funcion))
        self.assertEqual(self.cliente.get(f'/cartelera/{self.funcion}/precios').status_code,404)

    def test_ambiguedad_no_cotiza_aun_sin_trigger(self):
        self.conexion.execute('DROP TRIGGER trg_validar_vigencia_tarifa ON tarifa')
        self.tarifa()
        self.tarifa()
        with self.assertRaisesRegex(ValueError,'varias tarifas'):
            precios.consultar_tarifas(self.funcion,1,1,self.ahora)
        contenido=self.cliente.get(f'/cartelera/{self.funcion}/precios').get_data(as_text=True)
        self.assertIn('No disponible',contenido)
        self.assertNotIn('$8.00',contenido)

    def test_fallo_en_ultima_condicion_revierte_toda_promocion(self):
        self.conexion.execute('ALTER TABLE promocion_categoria ADD CONSTRAINT ck_ensayo_rechazo CHECK (id_categoria_entrada <> 1)')
        self.assertEqual(self.cliente.post(self.ruta,data=self.datos_promocion()).status_code,400)
        for tabla in ('promocion','funcion_promocion','promocion_dia','promocion_zona','promocion_categoria'):
            self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM '+tabla).fetchone()[0],0)

    def test_tarifas_simultaneas(self):
        # Datos propios de este ensayo, visibles para ambas conexiones.
        a=self.conectar(); b=self.conectar()
        try:
            id_categoria=a.execute("INSERT INTO categoria_entrada(nombre) VALUES ('Concurrente') RETURNING id_categoria_entrada").fetchone()[0]
            id_funcion=a.execute("INSERT INTO funcion(id_pelicula,id_sala,inicio,fin) VALUES (1,2,'2035-01-01 18:00+00','2035-01-01 20:00+00') RETURNING id_funcion").fetchone()[0]
            id_zona=a.execute("INSERT INTO zona(id_sala,nombre) VALUES (2,'Concurrente') RETURNING id_zona").fetchone()[0]
            a.commit()
            pid_b=b.execute('SELECT pg_backend_pid()').fetchone()[0]
            sentencia='''INSERT INTO tarifa(id_funcion,id_zona,id_categoria_entrada,monto,vigente_desde,vigente_hasta)
                         VALUES (%s,%s,%s,8,'2034-01-01+00','2035-01-01+00')'''
            parametros=(id_funcion,id_zona,id_categoria)
            a.execute(sentencia,parametros)
            def intentar():
                try:
                    b.execute("SET LOCAL statement_timeout='10s'")
                    b.execute(sentencia,parametros)
                    b.commit()
                    return 'aceptada'
                except psycopg.errors.CheckViolation:
                    b.rollback()
                    return 'rechazada'
            with ThreadPoolExecutor(max_workers=1) as ejecutor:
                futuro=ejecutor.submit(intentar)
                limite=time.monotonic()+5
                bloqueada=False
                while time.monotonic()<limite:
                    a.execute('SELECT pg_stat_clear_snapshot()')
                    fila=a.execute('SELECT wait_event_type FROM pg_stat_activity WHERE pid=%s',(pid_b,)).fetchone()
                    if fila and fila[0]=='Lock':
                        bloqueada=True
                        break
                    time.sleep(0.05)
                a.commit()
                self.assertTrue(bloqueada)
                self.assertEqual(futuro.result(timeout=12),'rechazada')
            self.assertEqual(a.execute('SELECT COUNT(*) FROM tarifa WHERE id_funcion=%s',(id_funcion,)).fetchone()[0],1)
        finally:
            a.rollback();b.rollback();a.close();b.close()


if __name__ == '__main__':
    unittest.main(defaultTest='PruebasPrecios',verbosity=2)
