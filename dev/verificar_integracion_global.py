"""Flujo A/B/C contra la instalacion completa, en un esquema temporal."""
from pathlib import Path
from contextlib import contextmanager
from datetime import timedelta
from decimal import Decimal
from uuid import uuid4
import re,unittest
import psycopg
from psycopg import sql
import app,seguridad,salas,funciones,ventas,reportes,operacion,precios,cartelera
from conexion import obtener_conexion
from verificar_a02 import PruebasA02
from generar_instalacion import generar,generar_actualizacion


class IntegracionGlobal(unittest.TestCase):
    conectar=classmethod(PruebasA02.conectar.__func__)
    limpiar_esquema=classmethod(PruebasA02.limpiar_esquema.__func__)
    tearDown=PruebasA02.tearDown

    @classmethod
    def setUpClass(cls):
        cls.esquema='ensayo_a02_'+uuid4().hex
        cls.addClassCleanup(cls.limpiar_esquema)
        with obtener_conexion() as c:c.execute(sql.SQL('CREATE SCHEMA {}').format(sql.Identifier(cls.esquema)))
        with cls.conectar() as c:
            c.execute(sql.SQL('SET search_path TO {},pg_temp').format(sql.Identifier(cls.esquema)))
            texto=generar().replace('public.',cls.esquema+'.').replace("'public'","'"+cls.esquema+"'").replace('search_path = public','search_path = '+cls.esquema)
            c.execute(texto)
        cls.originales=[app.obtener_conexion,salas.obtener_conexion,funciones.obtener_conexion,seguridad.obtener_conexion]
        clave=app.app.secret_key
        app.app.secret_key='clave_solo_para_el_ensayo_de_integracion_global'
        app.app.testing=True
        cls.addClassCleanup(setattr,app.app,'secret_key',clave)

    def setUp(self):
        PruebasA02.setUp(self)
        self.addCleanup(self.conexion.close)
        for modulo in (ventas,reportes,operacion,precios,cartelera):
            self.addCleanup(setattr,modulo,'obtener_conexion',modulo.obtener_conexion)
            modulo.obtener_conexion=app.obtener_conexion
        c=self.conexion
        self.roles={r[0]:r[1] for r in c.execute('SELECT r.nombre,min(u.id_usuario) FROM usuario u JOIN rol r USING(id_rol) GROUP BY r.nombre').fetchall()}
        self.sala=c.execute("INSERT INTO sala(id_cine,nombre) VALUES(1,'Integracion') RETURNING id_sala").fetchone()[0]
        self.zona=c.execute("INSERT INTO zona(id_sala,nombre) VALUES(%s,'General') RETURNING id_zona",(self.sala,)).fetchone()[0]
        self.asientos=[c.execute("INSERT INTO asiento(id_zona,fila,numero) VALUES(%s,'I',%s) RETURNING id_asiento",(self.zona,n)).fetchone()[0] for n in range(1,5)]
        self.ahora=c.execute('SELECT clock_timestamp()').fetchone()[0]
        self.funcion=c.execute("INSERT INTO funcion(id_pelicula,id_sala,inicio,fin) VALUES(1,%s,%s,%s) RETURNING id_funcion",(self.sala,self.ahora+timedelta(days=1),self.ahora+timedelta(days=1,hours=2))).fetchone()[0]
        self.categoria=c.execute('SELECT min(id_categoria_entrada) FROM categoria_entrada').fetchone()[0]
        self.tarifa=c.execute("INSERT INTO tarifa(id_funcion,id_zona,id_categoria_entrada,monto,vigente_desde,vigente_hasta) VALUES(%s,%s,%s,8,%s,%s) RETURNING id_tarifa",(self.funcion,self.zona,self.categoria,self.ahora-timedelta(days=1),self.ahora+timedelta(days=2))).fetchone()[0]
        self.actor('cliente')

    def actor(self,rol):
        identificador=self.roles[rol]
        self.conexion.execute("SELECT set_config('app.id_usuario',%s,true),set_config('app.ip','127.0.0.1',true),set_config('app.motivo','Ensayo global',true)",(str(identificador),))
        with self.cliente.session_transaction() as s:s['id_usuario']=identificador
        return identificador

    def reservar(self,asientos=None):
        self.actor('cliente')
        return self.conexion.execute('SELECT reservar_asientos(%s::bigint,%s::bigint,%s::bigint,%s::int[],%s::int)',
            (self.roles['cliente'],self.roles['cliente'],self.funcion,asientos or [self.asientos[0]],self.categoria)).fetchone()[0]

    def pagar(self,compra,resultado='Exito',ref='pago-global'):
        self.actor('cliente')
        self.conexion.execute("SELECT procesar_pago(%s::bigint,%s::varchar,'Tarjeta'::varchar,%s::varchar)",(compra,resultado,ref))

    def promocion(self):
        self.actor('administrador')
        p=self.conexion.execute("INSERT INTO promocion(nombre,tipo,condicion,vigente_desde,vigente_hasta) VALUES('Parejas','2x1','Misma zona y categoria',%s,%s) RETURNING id_promocion",(self.ahora-timedelta(days=1),self.ahora+timedelta(days=2))).fetchone()[0]
        self.conexion.execute('INSERT INTO funcion_promocion VALUES(%s,%s)',(self.funcion,p))
        self.conexion.execute('INSERT INTO promocion_dia SELECT %s,generate_series(1,7)',(p,))
        self.conexion.execute('INSERT INTO promocion_zona VALUES(%s,%s)',(p,self.zona))
        self.conexion.execute('INSERT INTO promocion_categoria VALUES(%s,%s)',(p,self.categoria))

    def solicitar(self,compra,ids=None):
        self.actor('cliente')
        return self.conexion.execute("SELECT * FROM solicitar_reembolso(%s,%s::bigint,%s::bigint[],'Ensayo'::text,'127.0.0.1'::text)",(self.roles['cliente'],compra,ids)).fetchone()

    def resolver(self,solicitud,forzar=False):
        self.actor('administrador')
        return self.conexion.execute("SELECT * FROM resolver_reembolso(%s,%s,'ejecutar','Motivo documentado','127.0.0.1',%s)",(self.roles['administrador'],solicitud,forzar)).fetchone()

    def test_instalacion_y_generacion_inventario(self):
        self.assertEqual(self.conexion.execute('SELECT count(*) FROM inventario_funcion WHERE id_funcion=%s',(self.funcion,)).fetchone()[0],4)
        self.assertEqual(self.conexion.execute('SELECT count(*) FROM pg_tables WHERE schemaname=%s',(self.esquema,)).fetchone()[0],33)

    def test_2x1_impar_cotizacion_congelada(self):
        self.promocion();compra=self.reservar(self.asientos[:3])
        self.assertEqual(self.conexion.execute('SELECT total FROM compra WHERE id_compra=%s',(compra,)).fetchone()[0],Decimal('16'))
        self.actor('administrador')
        self.conexion.execute('UPDATE tarifa SET monto=20 WHERE id_tarifa=%s',(self.tarifa,))
        self.pagar(compra)
        self.assertEqual(self.conexion.execute('SELECT monto FROM pago WHERE id_compra=%s',(compra,)).fetchone()[0],Decimal('16'))
        self.assertEqual(self.conexion.execute('SELECT count(*) FROM boleto WHERE id_compra=%s',(compra,)).fetchone()[0],3)

    def test_funcion_inactiva_y_asientos_repetidos_rechazados(self):
        with self.assertRaises(psycopg.errors.RaiseException),self.conexion.transaction():self.reservar([self.asientos[0]]*2)
        self.actor('administrador');self.conexion.execute('UPDATE funcion SET activa=FALSE WHERE id_funcion=%s',(self.funcion,))
        with self.assertRaises(psycopg.errors.RaiseException),self.conexion.transaction():self.reservar()

    def test_sin_tarifa_no_inventa_precio(self):
        self.actor('administrador');self.conexion.execute('DELETE FROM tarifa WHERE id_tarifa=%s',(self.tarifa,))
        with self.assertRaises(psycopg.errors.RaiseException),self.conexion.transaction():self.reservar()
        self.assertEqual(self.conexion.execute('SELECT count(*) FROM compra WHERE id_funcion=%s',(self.funcion,)).fetchone()[0],0)

    def test_checkout_web_factura_qr_y_propiedad(self):
        self.assertIn('Integracion',self.cliente.get('/cartelera').get_data(as_text=True))
        self.assertEqual(self.cliente.get(f'/ventas/funciones/{self.funcion}/asientos').status_code,200)
        r=self.cliente.post(f'/ventas/funciones/{self.funcion}/reservar',data={'asiento':str(self.asientos[0]),'categoria':str(self.categoria)})
        self.assertEqual(r.status_code,302)
        compra=int(r.location.rsplit('/',1)[1])
        r=self.cliente.post(f'/ventas/compras/{compra}/pagar',data={'resultado':'Exito','metodo':'Tarjeta','referencia':'web-global'})
        self.assertEqual(r.status_code,302)
        self.assertEqual(self.cliente.get(r.location).status_code,200)
        token=self.conexion.execute('SELECT token_qr FROM boleto WHERE id_compra=%s',(compra,)).fetchone()[0]
        imagen=self.cliente.get(f'/ventas/qr/{token}.png');self.assertEqual(imagen.status_code,200);self.assertTrue(imagen.data.startswith(b'\x89PNG'))
        otro=self.conexion.execute("SELECT id_usuario FROM usuario WHERE correo='cliente2@imax.test'").fetchone()[0]
        if otro==self.roles['cliente']:otro=self.conexion.execute("SELECT id_usuario FROM usuario WHERE correo='cliente1@imax.test'").fetchone()[0]
        with self.cliente.session_transaction() as s:s['id_usuario']=otro
        self.assertEqual(self.cliente.get(f'/ventas/qr/{token}.png').status_code,404)
        self.assertEqual(self.cliente.get(f'/ventas/compras/{compra}').status_code,404)

    def test_pago_rechazado_y_repeticion_idempotente(self):
        compra=self.reservar();self.pagar(compra,'Rechazado');self.pagar(compra,'Rechazado')
        self.assertEqual(self.conexion.execute('SELECT count(*) FROM pago WHERE id_compra=%s',(compra,)).fetchone()[0],1)
        self.assertEqual(self.conexion.execute('SELECT estado FROM inventario_funcion WHERE id_funcion=%s AND id_asiento=%s',(self.funcion,self.asientos[0])).fetchone()[0],'disponible')

    def test_expiracion_y_pago_tardio_no_emiten(self):
        compra=self.reservar();self.conexion.execute("UPDATE reserva SET vence_en=clock_timestamp()-INTERVAL '1 second' WHERE id_compra=%s",(compra,))
        self.conexion.execute('SELECT liberar_reservas_vencidas()')
        self.assertEqual(self.conexion.execute('SELECT estado FROM compra WHERE id_compra=%s',(compra,)).fetchone()[0],'Expirada')
        with self.assertRaises(psycopg.errors.RaiseException),self.conexion.transaction():self.pagar(compra)
        self.assertEqual(self.conexion.execute('SELECT count(*) FROM boleto WHERE id_compra=%s',(compra,)).fetchone()[0],0)

    def test_qr_una_vez_y_rol_puerta(self):
        self.actor('administrador');self.conexion.execute("UPDATE funcion SET inicio=clock_timestamp()+INTERVAL '10 minutes',fin=clock_timestamp()+INTERVAL '130 minutes' WHERE id_funcion=%s",(self.funcion,))
        compra=self.reservar();self.pagar(compra)
        token=self.conexion.execute('SELECT token_qr FROM boleto WHERE id_compra=%s',(compra,)).fetchone()[0]
        self.actor('operador_puerta')
        for esperado in (True,False):
            r=self.cliente.post('/operacion/puerta',data={'token':str(token),'funcion':str(self.funcion),'dispositivo':'Puerta ensayo'})
            self.assertEqual(r.status_code,200 if esperado else 400)
        self.assertEqual(self.conexion.execute('SELECT count(*) FROM acceso_puerta_log WHERE id_funcion_solicitada=%s',(self.funcion,)).fetchone()[0],2)
        self.actor('cliente');self.assertEqual(self.cliente.get('/operacion/puerta').status_code,403)

    def test_reembolso_parcial_reventa_y_reportes(self):
        compra=self.reservar(self.asientos[:2]);self.pagar(compra)
        boleto=self.conexion.execute('SELECT min(id_boleto) FROM boleto WHERE id_compra=%s',(compra,)).fetchone()[0]
        s=self.solicitar(compra,[boleto]);self.assertTrue(s[0]);r=self.resolver(s[3]);self.assertTrue(r[0]);self.assertEqual(r[3],Decimal('8'))
        self.assertFalse(self.resolver(s[3])[0])
        self.assertEqual(self.conexion.execute('SELECT estado FROM compra WHERE id_compra=%s',(compra,)).fetchone()[0],'ParcialmenteReembolsada')
        self.actor('administrador')
        rep=self.conexion.execute('SELECT boletos_vendidos,ingreso_bruto,total_devuelto,ingreso_neto FROM reporte_ocupacion_recaudacion(%s,%s)',(self.roles['administrador'],self.funcion)).fetchone()
        self.assertEqual(rep,(1,Decimal('16'),Decimal('8'),Decimal('8')))
        self.assertEqual(self.cliente.get('/reportes/').status_code,200)
        compra2=self.reservar();self.pagar(compra2,ref='reventa')
        self.assertEqual(self.conexion.execute('SELECT count(*) FROM boleto WHERE id_funcion=%s',(self.funcion,)).fetchone()[0],3)
        self.assertEqual(self.conexion.execute('SELECT count(*) FROM reembolso_detalle WHERE id_boleto=%s',(boleto,)).fetchone()[0],1)

    def test_permisos_sql_y_csrf_sin_sesion_de_prueba(self):
        self.assertEqual(self.cliente.get('/ventas/entrar-prueba/1').status_code,404)
        self.assertEqual(self.cliente.post(f'/ventas/funciones/{self.funcion}/reservar',data={'csrf_token':'incorrecto'}).status_code,400)
        compra=self.reservar();self.pagar(compra)
        otro=self.roles['contador'];self.actor('contador')
        with self.assertRaises(psycopg.errors.InsufficientPrivilege),self.conexion.transaction():
            self.conexion.execute('SELECT * FROM consultar_boletos_usuario(%s::bigint,%s::bigint)',(self.roles['cliente'],otro))
        self.actor('cliente')
        with self.assertRaises(psycopg.errors.InsufficientPrivilege),self.conexion.transaction():
            self.conexion.execute("SELECT revertir_venta(%s::bigint,%s::bigint,'Sin permiso'::varchar)",(compra,self.roles['cliente']))


    def test_acreditacion_y_qr_de_otra_funcion(self):
        self.actor('administrador')
        self.conexion.execute('UPDATE categoria_entrada SET requiere_acreditacion=TRUE WHERE id_categoria_entrada=%s',(self.categoria,))
        self.conexion.execute("UPDATE funcion SET inicio=clock_timestamp()+INTERVAL '10 minutes',fin=clock_timestamp()+INTERVAL '130 minutes' WHERE id_funcion=%s",(self.funcion,))
        compra=self.reservar();self.pagar(compra)
        token=self.conexion.execute('SELECT token_qr FROM boleto WHERE id_compra=%s',(compra,)).fetchone()[0]
        operador=self.actor('operador_puerta')
        for funcion,acreditacion,esperado in ((1,True,False),(self.funcion,False,False),(self.funcion,True,True)):
            r=self.conexion.execute("SELECT * FROM validar_y_consumir_ingreso_qr(%s,%s,%s,'Ensayo',%s)",(token,funcion,operador,acreditacion)).fetchone()
            self.assertEqual(r[0],esperado)

    def test_reembolso_fuera_de_politica_y_usado(self):
        self.actor('administrador')
        self.conexion.execute("UPDATE funcion SET inicio=clock_timestamp()+INTERVAL '1 hour',fin=clock_timestamp()+INTERVAL '3 hours' WHERE id_funcion=%s",(self.funcion,))
        compra=self.reservar();self.pagar(compra)
        s=self.solicitar(compra);self.assertFalse(s[0]);self.assertEqual(s[1],'FUERA_DE_POLITICA')
        self.actor('administrador')
        s=self.conexion.execute("SELECT * FROM solicitar_reembolso(%s,%s::bigint,NULL::bigint[],'Excepcion','127.0.0.1')",(self.roles['administrador'],compra)).fetchone()
        self.assertTrue(s[0]);self.assertFalse(self.resolver(s[3])[0]);self.assertTrue(self.resolver(s[3],True)[0])
        self.assertEqual(self.conexion.execute("SELECT count(*) FROM admin_operacion_audit WHERE accion='reembolso_forzado' AND id_entidad=%s",(str(s[3]),)).fetchone()[0],1)

    def test_cortesia_cambio_asiento_auditado_y_conflicto(self):
        admin=self.actor('administrador')
        r=self.conexion.execute("SELECT * FROM otorgar_cortesia(%s,%s,%s,%s,%s,'Ensayo cortesia','127.0.0.1')",(admin,self.funcion,self.asientos[0],self.roles['cliente'],self.categoria)).fetchone()
        self.assertTrue(r[0]);compra,boleto=r[3:]
        self.assertEqual(self.conexion.execute('SELECT total FROM compra WHERE id_compra=%s',(compra,)).fetchone()[0],Decimal('0'))
        r=self.conexion.execute("SELECT * FROM cambiar_asiento_boleto(%s,%s::bigint,%s,'Ensayo cambio','127.0.0.1')",(admin,boleto,self.asientos[1])).fetchone()
        self.assertTrue(r[0])
        self.assertEqual(self.conexion.execute('SELECT id_asiento FROM boleto WHERE id_boleto=%s',(boleto,)).fetchone()[0],self.asientos[1])
        self.assertEqual(self.conexion.execute('SELECT estado FROM inventario_funcion WHERE id_funcion=%s AND id_asiento=%s',(self.funcion,self.asientos[0])).fetchone()[0],'disponible')
        self.assertEqual(self.cliente.get('/operacion/ajustes').status_code,200)
        r=self.conexion.execute("SELECT * FROM otorgar_cortesia(%s,%s,%s,%s,%s,'No duplicar','127.0.0.1')",(admin,self.funcion,self.asientos[1],self.roles['cliente'],self.categoria)).fetchone()
        self.assertFalse(r[0])
        self.assertFalse(self.solicitar(compra)[0])

    def test_reportes_pago_top5_y_logs_inmutables(self):
        previos=self.conexion.execute("SELECT count(*),coalesce(sum(monto),0) FROM pago WHERE estado='Aprobado'").fetchone()
        compra=self.reservar();self.pagar(compra)
        admin=self.actor('administrador')
        r=self.conexion.execute("SELECT compras,monto FROM reporte_metodos_pago(%s,NULL,clock_timestamp()+INTERVAL '1 second')",(admin,)).fetchone()
        self.assertEqual(r,(previos[0]+1,previos[1]+Decimal('8')))
        self.assertEqual(len(self.conexion.execute("SELECT * FROM reporte_top5_peliculas_semana(%s,clock_timestamp()+INTERVAL '1 second')",(admin,)).fetchall()),1)
        self.assertGreater(self.conexion.execute('SELECT count(*) FROM asiento_auditoria_log').fetchone()[0],0)
        for tabla in ('transaccion_log','asiento_auditoria_log','acceso_puerta_log','admin_operacion_audit'):
            with self.subTest(tabla=tabla),self.assertRaises(psycopg.errors.InsufficientPrivilege),self.conexion.transaction():
                self.conexion.execute(sql.SQL('TRUNCATE {}').format(sql.Identifier(tabla)))

    def escenario_concurrente_global(self,pagada=False):
        with self.conectar() as c:
            c.execute("SET LOCAL statement_timeout='15s'")
            sala=c.execute("INSERT INTO sala(id_cine,nombre) VALUES(1,%s) RETURNING id_sala",('Carrera '+uuid4().hex,)).fetchone()[0]
            zona=c.execute("INSERT INTO zona(id_sala,nombre) VALUES(%s,'Carrera') RETURNING id_zona",(sala,)).fetchone()[0]
            asiento=c.execute("INSERT INTO asiento(id_zona,fila,numero) VALUES(%s,'C',1) RETURNING id_asiento",(zona,)).fetchone()[0]
            funcion=c.execute("INSERT INTO funcion(id_pelicula,id_sala,inicio,fin) VALUES(1,%s,clock_timestamp()+INTERVAL '10 minutes',clock_timestamp()+INTERVAL '130 minutes') RETURNING id_funcion",(sala,)).fetchone()[0]
            c.execute("INSERT INTO tarifa(id_funcion,id_zona,id_categoria_entrada,monto,vigente_desde,vigente_hasta) VALUES(%s,%s,%s,8,clock_timestamp()-INTERVAL '1 day',clock_timestamp()+INTERVAL '1 day')",(funcion,zona,self.categoria))
            token=None
            if pagada:
                c.execute("SELECT set_config('app.id_usuario',%s,true)",(str(self.roles['cliente']),))
                compra=c.execute('SELECT reservar_asientos(%s::bigint,%s::bigint,%s::bigint,%s::int[],%s)',(self.roles['cliente'],self.roles['cliente'],funcion,[asiento],self.categoria)).fetchone()[0]
                c.execute("SELECT procesar_pago(%s::bigint,'Exito'::varchar,'Tarjeta'::varchar,%s::varchar)",(compra,'Carrera-'+uuid4().hex))
                token=c.execute('SELECT token_qr FROM boleto WHERE id_compra=%s',(compra,)).fetchone()[0]
        return funcion,asiento,token

    def carrera_50(self,puerta):
        from concurrent.futures import ThreadPoolExecutor
        from threading import Barrier
        funcion,asiento,token=self.escenario_concurrente_global(puerta)
        barrera=Barrier(50,timeout=15)
        def ejecutar(_):
            try:
                with self.conectar() as c:
                    c.execute("SET LOCAL statement_timeout='15s'")
                    actor=self.roles['operador_puerta' if puerta else 'cliente']
                    c.execute("SELECT set_config('app.id_usuario',%s,true)",(str(actor),))
                    barrera.wait()
                    if puerta:
                        return c.execute("SELECT exito FROM validar_y_consumir_ingreso_qr(%s,%s,%s,'Carrera')",(token,funcion,actor)).fetchone()[0]
                    c.execute('SELECT reservar_asientos(%s::bigint,%s::bigint,%s::bigint,%s::int[],%s)',(actor,actor,funcion,[asiento],self.categoria))
                    return True
            except psycopg.errors.RaiseException as e:
                if not puerta and 'no se encuentra disponible' in e.diag.message_primary:return False
                raise
        with ThreadPoolExecutor(50) as pool:resultados=list(pool.map(ejecutar,range(50)))
        self.assertEqual(resultados.count(True),1);self.assertEqual(resultados.count(False),49)
        with self.conectar() as c:
            if puerta:
                self.assertEqual(c.execute("SELECT count(*),count(*) FILTER(WHERE resultado='aceptado') FROM acceso_puerta_log WHERE id_funcion_solicitada=%s",(funcion,)).fetchone(),(50,1))
                self.assertEqual(c.execute('SELECT estado FROM boleto WHERE token_qr=%s',(token,)).fetchone()[0],'Usado')
            else:self.assertEqual(c.execute("SELECT count(*) FROM reserva WHERE id_funcion=%s AND estado='activa'",(funcion,)).fetchone()[0],1)

    def test_50_reservas_simultaneas_un_ganador(self):self.carrera_50(False)

    def test_50_escaneos_simultaneos_un_ingreso(self):self.carrera_50(True)


    def test_boleto_usado_no_se_reembolsa(self):
        self.actor('administrador');self.conexion.execute("UPDATE funcion SET inicio=clock_timestamp()+INTERVAL '10 minutes',fin=clock_timestamp()+INTERVAL '130 minutes' WHERE id_funcion=%s",(self.funcion,))
        compra=self.reservar();self.pagar(compra)
        token=self.conexion.execute('SELECT token_qr FROM boleto WHERE id_compra=%s',(compra,)).fetchone()[0]
        operador=self.actor('operador_puerta')
        self.assertTrue(self.conexion.execute("SELECT exito FROM validar_y_consumir_ingreso_qr(%s,%s,%s,'Ensayo')",(token,self.funcion,operador)).fetchone()[0])
        s=self.solicitar(compra);self.assertFalse(s[0]);self.assertEqual(s[1],'ESTADO_INVALIDO')

    def test_auditoria_fallida_revierte_cortesia_y_pago(self):
        admin=self.actor('administrador')
        self.conexion.execute("CREATE FUNCTION fallo_audit_global() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'Fallo de ensayo' USING ERRCODE='23514'; END $$")
        self.conexion.execute('CREATE TRIGGER fallo_audit_global BEFORE INSERT ON admin_operacion_audit FOR EACH ROW EXECUTE FUNCTION fallo_audit_global()')
        with self.assertRaises(psycopg.errors.CheckViolation),self.conexion.transaction():
            self.conexion.execute("SELECT * FROM otorgar_cortesia(%s,%s,%s,%s,%s,'Ensayo','127.0.0.1')",(admin,self.funcion,self.asientos[0],self.roles['cliente'],self.categoria))
        self.assertEqual(self.conexion.execute('SELECT count(*) FROM compra WHERE id_funcion=%s',(self.funcion,)).fetchone()[0],0)
        self.assertEqual(self.conexion.execute("SELECT count(*) FROM inventario_funcion WHERE id_funcion=%s AND estado='disponible'",(self.funcion,)).fetchone()[0],4)

    def test_reinstalacion_rechaza_sin_borrar_y_script_actualizado(self):
        archivo=Path(__file__).resolve().parent.parent/'docs'/'integracion'/'instalacion_completa.sql'
        self.assertEqual(generar(),archivo.read_text(encoding='utf-8-sig'))
        with self.conectar() as c:
            with self.assertRaises(psycopg.errors.DuplicateTable),c.transaction():
                texto=generar().replace('public.',self.esquema+'.').replace("'public'","'"+self.esquema+"'").replace('search_path = public','search_path = '+self.esquema)
                c.execute(texto)
            self.assertEqual(c.execute('SELECT count(*) FROM pg_tables WHERE schemaname=%s',(self.esquema,)).fetchone()[0],33)

    def test_ingreso_contra_reembolso_concurrente(self):
        from concurrent.futures import ThreadPoolExecutor
        from threading import Barrier
        funcion,asiento,token=self.escenario_concurrente_global(True)
        with self.conectar() as c:
            compra=c.execute('SELECT id_compra FROM boleto WHERE token_qr=%s',(token,)).fetchone()[0]
            admin=self.roles['administrador']
            c.execute("SELECT set_config('app.id_usuario',%s,true)",(str(admin),))
            s=c.execute("SELECT * FROM solicitar_reembolso(%s,%s::bigint,NULL::bigint[],'Excepcion','127.0.0.1')",(admin,compra)).fetchone()
            self.assertTrue(s[0]);solicitud=s[3]
        barrera=Barrier(2,timeout=10)
        def ejecutar(es_puerta):
            with self.conectar() as c:
                c.execute("SET LOCAL statement_timeout='10s'")
                actor=self.roles['operador_puerta'] if es_puerta else admin
                c.execute("SELECT set_config('app.id_usuario',%s,true)",(str(actor),))
                barrera.wait()
                if es_puerta:return c.execute("SELECT exito FROM validar_y_consumir_ingreso_qr(%s,%s,%s,'Carrera')",(token,funcion,actor)).fetchone()[0]
                return c.execute("SELECT exito FROM resolver_reembolso(%s,%s,'ejecutar','Excepcion documentada','127.0.0.1',TRUE)",(actor,solicitud)).fetchone()[0]
        with ThreadPoolExecutor(2) as pool:resultados=list(pool.map(ejecutar,[True,False]))
        self.assertEqual(resultados.count(True),1)
        with self.conectar() as c:
            estado=c.execute('SELECT estado FROM boleto WHERE token_qr=%s',(token,)).fetchone()[0]
            self.assertEqual(estado,'Usado' if resultados[0] else 'Anulado')
            self.assertEqual(c.execute('SELECT count(*) FROM reembolso WHERE id_solicitud_reembolso=%s',(solicitud,)).fetchone()[0],0 if resultados[0] else 1)


    def test_venta_presencial_y_reembolso_desde_interfaz(self):
        self.actor('taquillero')
        r=self.cliente.post(f'/ventas/funciones/{self.funcion}/reservar',data={'asiento':str(self.asientos[0]),'categoria':str(self.categoria),'cliente':str(self.roles['cliente'])})
        self.assertEqual(r.status_code,302);compra=int(r.location.rsplit('/',1)[1])
        r=self.cliente.post(f'/ventas/compras/{compra}/pagar',data={'resultado':'Exito','metodo':'Efectivo','referencia':'taquilla-web'})
        self.assertEqual(r.status_code,302)
        self.assertEqual(self.cliente.get(r.location).status_code,200)
        token=self.conexion.execute('SELECT token_qr FROM boleto WHERE id_compra=%s',(compra,)).fetchone()[0]
        self.assertEqual(self.cliente.get(f'/ventas/qr/{token}.png').status_code,200)
        self.assertIn(str(compra),self.cliente.get('/ventas/mis-compras').get_data(as_text=True))
        self.actor('cliente')
        r=self.cliente.post('/operacion/reembolsos',data={'compra':str(compra),'motivo':'Cambio de planes'})
        self.assertEqual(r.status_code,200)
        solicitud=self.conexion.execute('SELECT id_solicitud_reembolso FROM solicitud_reembolso WHERE id_compra=%s',(compra,)).fetchone()[0]
        self.actor('administrador')
        r=self.cliente.post('/operacion/resolver',data={'solicitud':str(solicitud),'decision':'ejecutar','motivo':'Solicitud revisada'})
        self.assertEqual(r.status_code,200)
        self.assertEqual(self.conexion.execute('SELECT estado FROM compra WHERE id_compra=%s',(compra,)).fetchone()[0],'Reembolsada')


    def test_actualizacion_desde_a_c_conserva_datos_y_contrasenas(self):
        esquema='ensayo_a02_'+uuid4().hex
        with obtener_conexion() as c:c.execute(sql.SQL('CREATE SCHEMA {}').format(sql.Identifier(esquema)))
        def adaptar(texto):return texto.replace('public.',esquema+'.').replace("'public'","'"+esquema+"'").replace('search_path = public','search_path = '+esquema)
        try:
            with obtener_conexion() as c:
                c.execute(sql.SQL('SET search_path TO {},pg_temp').format(sql.Identifier(esquema)))
                raiz=Path(__file__).resolve().parent.parent
                c.execute((raiz/'docs'/'compa\u00f1eroA'/'instalacion_completa_A.sql').read_text(encoding='utf-8-sig'))
                c.execute((raiz/'docs'/'compa\u00f1eroC'/'sql_C-01.sql').read_text(encoding='utf-8-sig'))
                c.execute("UPDATE usuario SET password_hash='clave_configurada_de_ensayo' WHERE correo='admin@imax.test'")
                usuarios=c.execute('SELECT * FROM usuario ORDER BY id_usuario').fetchall()
                peliculas=c.execute('SELECT * FROM pelicula ORDER BY id_pelicula').fetchall()
                asientos=c.execute('SELECT * FROM asiento ORDER BY id_asiento').fetchall()
                c.commit()
                c.execute(adaptar(generar_actualizacion()))
                self.assertEqual(c.execute('SELECT * FROM usuario ORDER BY id_usuario').fetchall(),usuarios)
                self.assertEqual(c.execute('SELECT * FROM pelicula ORDER BY id_pelicula').fetchall(),peliculas)
                self.assertEqual(c.execute('SELECT * FROM asiento ORDER BY id_asiento').fetchall(),asientos)
                self.assertEqual(c.execute('SELECT count(*) FROM inventario_funcion WHERE id_funcion=1').fetchone()[0],6)
                with self.assertRaises(psycopg.errors.RaiseException),c.transaction():c.execute(adaptar(generar_actualizacion()))
                self.assertEqual(c.execute('SELECT count(*) FROM pg_tables WHERE schemaname=%s',(esquema,)).fetchone()[0],33)
        finally:
            with obtener_conexion() as c:c.execute(sql.SQL('DROP SCHEMA {} CASCADE').format(sql.Identifier(esquema)))


if __name__=='__main__':unittest.main(defaultTest='IntegracionGlobal',verbosity=2)
