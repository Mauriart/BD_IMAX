"""A-04 con los tres SQL reales de B y las tablas de identidad de C-01.

Crea y elimina un esquema de ensayo; no instala en public.
"""
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
from pathlib import Path
import unittest
import psycopg
from verificar_a02 import PruebasA02
from verificar_precios_a03 import PruebasPrecios
from verificar_salas_a04 import PruebasSalasProtegidas


class PruebasIntegracionB(unittest.TestCase):
    @classmethod
    def conectar(cls):
        c = PruebasA02.conectar.__func__(cls)
        c.execute("SET statement_timeout='12s'")
        c.execute("SET lock_timeout='6s'")
        return c
    limpiar_esquema = classmethod(PruebasA02.limpiar_esquema.__func__)
    tearDown = PruebasA02.tearDown
    tarifa = PruebasPrecios.tarifa
    esperar_bloqueo = PruebasSalasProtegidas.esperar_bloqueo
    escenario_concurrente = PruebasSalasProtegidas.escenario_concurrente

    @classmethod
    def setUpClass(cls):
        PruebasPrecios.setUpClass.__func__(cls)
        docs = Path(__file__).resolve().parent.parent / 'docs'
        with cls.conectar() as c:
            identidad = c.execute('SELECT id_usuario,correo,password_hash FROM usuario ORDER BY id_usuario').fetchall()
            bloqueo_c = c.execute("SELECT prosrc FROM pg_proc WHERE oid='bloquear_modificacion_log()'::regprocedure").fetchone()[0]
            for nombre in ('sql_20_ventas_tablas.sql','sql_21_ventas_logs.sql','sql_22_ventas_funciones.sql'):
                c.execute((docs / 'compa\u00f1eraB' / nombre).read_text(encoding='utf-8-sig'))
            assert identidad == c.execute('SELECT id_usuario,correo,password_hash FROM usuario ORDER BY id_usuario').fetchall()
            assert bloqueo_c == c.execute("SELECT prosrc FROM pg_proc WHERE oid='bloquear_modificacion_log()'::regprocedure").fetchone()[0]
            cls.usuario = c.execute("SELECT id_usuario FROM usuario WHERE correo='cliente1@imax.test'").fetchone()[0]
            migracion = (docs / 'compa\u00f1eroA' / 'proteccion_salas_A04.sql').read_text(encoding='utf-8-sig')
            c.execute(migracion)
            c.execute(migracion)
            fuente=(docs/'compa\u00f1eroC'/'sql_C-03.sql').read_text(encoding='utf-8-sig')
            fuente=fuente.replace('public.',cls.esquema+'.').replace('search_path = public','search_path = '+cls.esquema).replace("'public'","'"+cls.esquema+"'")
            c.execute(fuente)

    def setUp(self):
        PruebasPrecios.setUp(self)
        self.addCleanup(self.conexion.close)
        self.asiento = self.conexion.execute("INSERT INTO asiento(id_zona,fila,numero) VALUES(1,'A',1) RETURNING id_asiento").fetchone()[0]
        self.libre = self.conexion.execute("INSERT INTO asiento(id_zona,fila,numero) VALUES(1,'A',2) RETURNING id_asiento").fetchone()[0]
        self.conexion.execute("INSERT INTO inventario_funcion(id_funcion,id_asiento) VALUES(%s,%s)",(self.funcion,self.asiento))
        self.tarifa()
        self.ruta = f'/salas/1/asientos/{self.libre}/eliminar'

    def reservar(self, asientos=None):
        self.conexion.execute("SELECT set_config('app.id_usuario',%s,true),set_config('app.ip','127.0.0.1',true),set_config('app.motivo','Ensayo',true)",(str(self.usuario),))
        return self.conexion.execute('SELECT reservar_asientos(%s::bigint,%s::bigint,%s::bigint,%s::int[])',
            (self.usuario,self.usuario,self.funcion,asientos or [self.asiento])).fetchone()[0]

    def pagar(self, compra, resultado='Exito', referencia='pago-ensayo'):
        self.conexion.execute("SELECT set_config('app.id_usuario',%s,true)",(str(self.usuario),))
        self.conexion.execute('SELECT procesar_pago(%s::bigint,%s::varchar,%s::varchar,%s::varchar)',
            (compra,resultado,'Tarjeta',referencia))

    def test_reserva_real_protege_distribucion(self):
        compra = self.reservar()
        disponibilidad=self.conexion.execute('SELECT * FROM consultar_disponibilidad(%s::bigint)',(self.funcion,)).fetchall()
        self.assertEqual(disponibilidad[0][0:2],(self.asiento,'bloqueado'))
        self.assertEqual(self.conexion.execute('SELECT total FROM compra WHERE id_compra=%s',(compra,)).fetchone()[0],Decimal('8.00'))
        self.assertEqual(self.cliente.post(self.ruta).status_code,400)
        admin=self.conexion.execute("SELECT id_usuario FROM usuario WHERE correo='admin@imax.test'").fetchone()[0]
        self.conexion.execute("SELECT set_config('app.id_usuario',%s,true)",(str(admin),))
        for consulta in ('DELETE FROM sala WHERE id_sala=1',"UPDATE zona SET nombre='Cambio' WHERE id_zona=1",
                         "INSERT INTO asiento(id_zona,fila,numero) VALUES(1,'B',1)"):
            with self.subTest(consulta=consulta),self.assertRaises(psycopg.errors.ObjectNotInPrerequisiteState),self.conexion.transaction():
                self.conexion.execute(consulta)
        self.assertEqual(self.conexion.execute('SELECT estado FROM inventario_funcion WHERE id_asiento=%s',(self.asiento,)).fetchone()[0],'bloqueado')

    def test_pago_real_emite_boleto_y_protege(self):
        compra=self.reservar()
        self.pagar(compra)
        self.assertEqual(self.conexion.execute('SELECT estado FROM compra WHERE id_compra=%s',(compra,)).fetchone()[0],'Pagada')
        self.assertEqual(self.conexion.execute('SELECT estado FROM boleto WHERE id_compra=%s',(compra,)).fetchone()[0],'Emitido')
        self.assertEqual(self.conexion.execute('SELECT estado FROM inventario_funcion WHERE id_asiento=%s',(self.asiento,)).fetchone()[0],'vendido')
        self.assertEqual(self.cliente.post(self.ruta).status_code,400)
        admin=self.conexion.execute("SELECT id_usuario FROM usuario WHERE correo='admin@imax.test'").fetchone()[0]
        self.conexion.execute("SELECT set_config('app.id_usuario',%s,true)",(str(admin),))
        with self.assertRaises(psycopg.errors.ObjectNotInPrerequisiteState),self.conexion.transaction():
            self.conexion.execute("UPDATE funcion SET inicio=inicio+INTERVAL '1 day',fin=fin+INTERVAL '1 day' WHERE id_funcion=%s",(self.funcion,))
        self.conexion.execute("SELECT set_config('app.id_usuario',%s,true)",(str(self.usuario),))
        boletos=self.conexion.execute('SELECT * FROM consultar_boletos_usuario(%s::bigint,%s::bigint)',(self.usuario,self.usuario)).fetchall()
        self.assertEqual(len(boletos),1)

    def test_pago_rechazado_libera_y_permite_cambio_auditado(self):
        compra=self.reservar()
        self.pagar(compra,'Rechazado')
        self.assertEqual(self.conexion.execute('SELECT estado FROM compra WHERE id_compra=%s',(compra,)).fetchone()[0],'Cancelada')
        self.assertEqual(self.conexion.execute('SELECT estado FROM inventario_funcion WHERE id_asiento=%s',(self.asiento,)).fetchone()[0],'disponible')
        self.assertEqual(self.cliente.post(self.ruta).status_code,302)
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM admin_operacion_audit').fetchone()[0],1)
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM reserva WHERE id_compra=%s',(compra,)).fetchone()[0],1)

    def test_expiracion_real_libera_inventario(self):
        compra=self.reservar()
        self.conexion.execute("UPDATE reserva SET vence_en=clock_timestamp()-INTERVAL '1 minute' WHERE id_compra=%s",(compra,))
        self.assertEqual(self.cliente.post(self.ruta).status_code,400)
        self.conexion.execute('SELECT liberar_reservas_vencidas()')
        self.assertEqual(self.conexion.execute('SELECT estado FROM compra WHERE id_compra=%s',(compra,)).fetchone()[0],'Expirada')
        self.assertEqual(self.cliente.post(self.ruta).status_code,302)

    def test_reversion_real_conserva_historia(self):
        compra=self.reservar()
        self.pagar(compra)
        admin=self.conexion.execute("SELECT id_usuario FROM usuario WHERE correo='admin@imax.test'").fetchone()[0]
        self.conexion.execute("SELECT set_config('app.id_usuario',%s,true)",(str(admin),))
        self.conexion.execute("SELECT revertir_venta(%s::bigint,%s::bigint,'Ensayo'::varchar)",(compra,admin))
        self.assertEqual(self.conexion.execute('SELECT estado FROM boleto WHERE id_compra=%s',(compra,)).fetchone()[0],'Anulado')
        self.assertEqual(self.cliente.post(self.ruta).status_code,302)
        respuesta=self.cliente.post(f'/salas/1/asientos/{self.asiento}/eliminar')
        self.assertEqual(respuesta.status_code,400)
        self.assertIn('historia',respuesta.get_data(as_text=True))
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM boleto WHERE id_compra=%s',(compra,)).fetchone()[0],1)

    def test_indice_reserva_impide_duplicado_activo(self):
        compra=self.reservar()
        with self.assertRaises(psycopg.errors.UniqueViolation),self.conexion.transaction():
            self.conexion.execute("""INSERT INTO reserva(id_compra,id_funcion,id_asiento,vence_en)
                VALUES(%s,%s,%s,clock_timestamp()+INTERVAL '1 minute')""",(compra,self.funcion,self.asiento))
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM reserva WHERE id_funcion=%s',(self.funcion,)).fetchone()[0],1)

    def test_reserva_multiple_revierte_si_un_asiento_no_disponible(self):
        with self.assertRaises(psycopg.errors.RaiseException),self.conexion.transaction():
            self.reservar([self.asiento,1000000])
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM compra WHERE id_funcion=%s',(self.funcion,)).fetchone()[0],0)
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM reserva WHERE id_funcion=%s',(self.funcion,)).fetchone()[0],0)
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM compra_detalle cd JOIN compra c USING(id_compra) WHERE c.id_funcion=%s',(self.funcion,)).fetchone()[0],0)
        self.assertEqual(self.conexion.execute('SELECT estado FROM inventario_funcion WHERE id_asiento=%s',(self.asiento,)).fetchone()[0],'disponible')

    def test_logs_de_b_y_c_conservan_sus_funciones(self):
        self.reservar()
        self.conexion.execute("INSERT INTO transaccion_log(resultado,evento) VALUES('Exito','Ensayo')")
        with self.assertRaises(psycopg.errors.RaiseException),self.conexion.transaction():
            self.conexion.execute("UPDATE transaccion_log SET evento='Cambio'")
        self.conexion.execute("""INSERT INTO admin_operacion_audit(id_usuario_actor,rol_al_actuar,ip,accion,entidad,motivo)
            VALUES(%s,'cliente','127.0.0.1','ensayo','ensayo','Ensayo')""",(self.usuario,))
        with self.assertRaises(psycopg.errors.InsufficientPrivilege),self.conexion.transaction():
            self.conexion.execute('DELETE FROM admin_operacion_audit')

    def escenario_real(self):
        sala,asiento,funcion=self.escenario_concurrente()
        with self.conectar() as c:
            zona=c.execute('SELECT id_zona FROM asiento WHERE id_asiento=%s',(asiento,)).fetchone()[0]
            libre=c.execute("INSERT INTO asiento(id_zona,fila,numero) VALUES(%s,'R',2) RETURNING id_asiento",(zona,)).fetchone()[0]
            c.execute('INSERT INTO inventario_funcion(id_funcion,id_asiento) VALUES(%s,%s)',(funcion,asiento))
            c.execute("""INSERT INTO tarifa(id_funcion,id_zona,id_categoria_entrada,monto,vigente_desde,vigente_hasta)
                VALUES(%s,%s,1,8,clock_timestamp()-INTERVAL '1 day',clock_timestamp()+INTERVAL '1 day')""",(funcion,zona))
        return sala,asiento,funcion,libre

    def carrera(self, reserva_primero):
        sala,asiento,funcion,libre=self.escenario_real()
        primero,segundo=self.conectar(),self.conectar()
        self.addCleanup(primero.close)
        self.addCleanup(segundo.close)
        for c in (primero,segundo):c.execute("SET LOCAL lock_timeout='6s'")
        def reservar(c):
            c.execute("SELECT set_config('app.id_usuario',%s,true),set_config('app.ip','127.0.0.1',true),set_config('app.motivo','Ensayo',true)",(str(self.usuario),))
            c.execute('SELECT reservar_asientos(%s::bigint,%s::bigint,%s::bigint,%s::int[])',
                      (self.usuario,self.usuario,funcion,[asiento]))
        def borrar(c):
            c.execute('SELECT a04_bloquear_sala(%s)',(sala,))
            c.execute('DELETE FROM asiento WHERE id_asiento=%s',(libre,))
        (reservar if reserva_primero else borrar)(primero)
        pid=segundo.execute('SELECT pg_backend_pid()').fetchone()[0]
        def ejecutar():
            try:
                (borrar if reserva_primero else reservar)(segundo)
                segundo.commit()
                return 'aceptado'
            except psycopg.Error as e:
                segundo.rollback()
                return e.sqlstate
        with ThreadPoolExecutor(1) as pool:
            futuro=pool.submit(ejecutar)
            try:self.esperar_bloqueo(pid)
            finally:primero.commit()
            self.assertEqual(futuro.result(timeout=8),'55000' if reserva_primero else 'aceptado')
        with self.conectar() as c:
            self.assertEqual(c.execute('SELECT COUNT(*) FROM reserva WHERE id_funcion=%s AND estado=\'activa\'',(funcion,)).fetchone()[0],1)
            self.assertEqual(c.execute('SELECT COUNT(*) FROM asiento WHERE id_asiento=%s',(libre,)).fetchone()[0],1 if reserva_primero else 0)
            self.assertEqual(c.execute('SELECT estado FROM inventario_funcion WHERE id_funcion=%s AND id_asiento=%s',(funcion,asiento)).fetchone()[0],'bloqueado')

    def test_concurrencia_reserva_real_primero_rechaza_borrado(self):
        self.carrera(True)

    def test_concurrencia_borrado_primero_reserva_real_espera_y_revalida(self):
        self.carrera(False)


if __name__=='__main__':
    unittest.main(defaultTest='PruebasIntegracionB',verbosity=2)
