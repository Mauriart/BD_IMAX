"""Verificación real de sesión, permisos y auditoría de A con el esquema C."""
import unittest
import tempfile
from pathlib import Path
from dotenv import dotenv_values
from unittest.mock import patch
import psycopg
from werkzeug.security import generate_password_hash, check_password_hash
import app
import seguridad
import configurar_acceso
from verificar_precios_a03 import PruebasPrecios
from verificar_a02 import PruebasA02


class PruebasSeguridad(unittest.TestCase):
    conectar = classmethod(PruebasA02.conectar.__func__)
    limpiar_esquema = classmethod(PruebasA02.limpiar_esquema.__func__)
    tearDown = PruebasA02.tearDown

    @classmethod
    def setUpClass(cls):
        PruebasPrecios.setUpClass.__func__(cls)
        cls.password = 'Solo_para_ensayos_123'
        with cls.conectar() as conexion:
            conexion.execute("""UPDATE usuario SET password_hash=%s
                WHERE correo IN ('admin@imax.test','cliente1@imax.test','contador@imax.test','taquillero@imax.test','puerta1@imax.test')""",
                (generate_password_hash(cls.password),))

    def setUp(self):
        PruebasPrecios.setUp(self)

    def entrar(self, correo):
        cliente = app.app.test_client()
        self.assertEqual(cliente.get('/login').status_code, 200)
        with cliente.session_transaction() as sesion:
            token = sesion['csrf_token']
        self.assertEqual(cliente.post('/login', data={
            'correo':correo, 'password':self.password, 'csrf_token':token
        }).status_code, 302)
        return cliente

    def formulario_con_token(self, cliente, datos):
        cliente.get('/cartelera')
        with cliente.session_transaction() as sesion:
            token = sesion['csrf_token']
        return dict(datos, csrf_token=token, motivo='Comprobación de seguridad')

    def pelicula(self):
        return dict(titulo='Película auditada',sinopsis='Sinopsis',clasificacion='TP',
                    duracion_min='120',poster_url='/poster.png')

    def cantidad_logs(self):
        return self.conexion.execute('SELECT COUNT(*) FROM admin_operacion_audit').fetchone()[0]

    def test_anonimo_no_modifica_y_cartelera_es_publica(self):
        cliente = app.app.test_client()
        self.assertEqual(cliente.get('/cartelera').status_code,200)
        for ruta in ('/','/salas','/funciones','/tarifas',self.ruta):
            with self.subTest(ruta=ruta):
                self.assertEqual(cliente.get(ruta).status_code,302)
        respuesta=cliente.post('/peliculas/nueva',data=dict(self.pelicula(),id_usuario=7,rol='administrador'),
                               headers={'X-User-ID':'7'})
        self.assertEqual(respuesta.status_code,302)
        self.assertEqual(self.cantidad_logs(),0)
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM pelicula').fetchone()[0],1)

    def test_roles_rechazados_en_solicitud_directa(self):
        for correo in ('cliente1@imax.test','taquillero@imax.test','puerta1@imax.test'):
            cliente=self.entrar(correo)
            datos=self.formulario_con_token(cliente,self.pelicula())
            for ruta in ('/peliculas/nueva','/salas/1/zonas','/funciones/nueva',self.ruta):
                with self.subTest(correo=correo,ruta=ruta):
                    self.assertEqual(cliente.post(ruta,data=datos).status_code,403)
            self.assertNotIn('Salas y asientos',cliente.get('/cartelera').get_data(as_text=True))
        self.assertEqual(self.cantidad_logs(),0)

    def test_contador_consulta_pero_no_escribe(self):
        cliente=self.entrar('contador@imax.test')
        self.assertEqual(cliente.get('/tarifas').status_code,200)
        respuesta=cliente.get(self.ruta)
        self.assertEqual(respuesta.status_code,200)
        self.assertNotIn('Guardar tarifa',respuesta.get_data(as_text=True))
        datos=self.formulario_con_token(cliente,dict(self.formulario,accion='tarifa',id_zona='1',id_categoria_entrada='1',monto='8'))
        self.assertEqual(cliente.post(self.ruta,data=datos).status_code,403)
        self.assertEqual(self.cantidad_logs(),0)

    def test_login_invalido_marcador_y_sesion_falsificada(self):
        cliente=app.app.test_client()
        cliente.get('/login')
        with cliente.session_transaction() as sesion:
            token=sesion['csrf_token']
        for correo,password in (('admin@imax.test','incorrecta'),
                                ('cliente2@imax.test','HASH_DE_PRUEBA'),
                                ('inexistente@imax.test',self.password)):
            self.assertEqual(cliente.post('/login',data={'correo':correo,'password':password,'csrf_token':token}).status_code,400)
        cliente.set_cookie('session','cookie_sin_firma_id_usuario_7')
        self.assertEqual(cliente.get('/salas').status_code,302)

    def test_csrf_y_motivo_obligatorios(self):
        cliente=self.entrar('admin@imax.test')
        datos=self.formulario_con_token(cliente,self.pelicula())
        for token in ('','incorrecto','inválido'):
            with self.subTest(token=token):
                self.assertEqual(cliente.post('/peliculas/nueva',data=dict(datos,csrf_token=token)).status_code,400)
        for motivo in ('','   ','x'*501):
            self.assertEqual(cliente.post('/peliculas/nueva',data=dict(datos,motivo=motivo)).status_code,400)
        self.assertEqual(self.cantidad_logs(),0)
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM pelicula').fetchone()[0],1)

    def test_desactivar_usuario_o_revocar_permiso_se_aplica(self):
        cliente=self.entrar('admin@imax.test')
        datos=self.formulario_con_token(cliente,self.pelicula())
        self.conexion.execute("UPDATE usuario SET activo=FALSE WHERE correo='admin@imax.test'")
        self.assertEqual(cliente.post('/peliculas/nueva',data=datos).status_code,302)
        self.conexion.execute("UPDATE usuario SET activo=TRUE WHERE correo='admin@imax.test'")
        cliente=self.entrar('admin@imax.test')
        self.conexion.execute("DELETE FROM rol_permiso WHERE accion='gestionar_catalogo'")
        self.assertEqual(cliente.post('/peliculas/nueva',data=self.formulario_con_token(cliente,self.pelicula())).status_code,403)
        self.assertEqual(self.cantidad_logs(),0)

    def test_revalidar_permiso_dentro_de_la_transaccion(self):
        original=app.autorizar_cambio
        def revocar(conexion,accion):
            conexion.execute("DELETE FROM rol_permiso WHERE accion='gestionar_catalogo'")
            return original(conexion,accion)
        with patch.object(app,'autorizar_cambio',side_effect=revocar):
            self.assertEqual(self.cliente.post('/peliculas/nueva',data=self.pelicula()).status_code,403)
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM pelicula').fetchone()[0],1)
        self.assertEqual(self.cantidad_logs(),0)

    def test_actor_real_y_cambios_antes_despues(self):
        datos=dict(self.pelicula(),id_usuario='1',rol='cliente',ip='1.2.3.4')
        self.assertEqual(self.cliente.post('/peliculas/1/editar',data=datos).status_code,302)
        actor,rol,ip,cambios=self.conexion.execute('SELECT id_usuario_actor,rol_al_actuar,ip,cambios FROM admin_operacion_audit').fetchone()
        admin=self.conexion.execute("SELECT id_usuario FROM usuario WHERE correo='admin@imax.test'").fetchone()[0]
        self.assertEqual((actor,rol,ip),(admin,'administrador','127.0.0.1'))
        self.assertEqual(cambios['antes']['titulo'],'Película ensayo')
        self.assertEqual(cambios['despues']['titulo'],'Película auditada')

    def test_auditoria_fallida_revierte_el_cambio(self):
        self.conexion.execute("""CREATE FUNCTION rechazar_audit_ensayo() RETURNS TRIGGER LANGUAGE plpgsql AS $$
            BEGIN RAISE EXCEPTION 'fallo de auditoria de ensayo'; END $$""")
        self.conexion.execute('CREATE TRIGGER trg_audit_ensayo BEFORE INSERT ON admin_operacion_audit FOR EACH ROW EXECUTE FUNCTION rechazar_audit_ensayo()')
        self.assertEqual(self.cliente.post('/peliculas/nueva',data=self.pelicula()).status_code,503)
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM pelicula').fetchone()[0],1)
        self.assertEqual(self.cantidad_logs(),0)

    def test_todas_las_escrituras_de_a_tienen_auditoria(self):
        operaciones=[
            ('/peliculas/nueva',self.pelicula()),
            ('/peliculas/1/editar',dict(self.pelicula(),titulo='Editada')),
            ('/salas',{'id_cine':'1','nombre':'Sala auditada'}),
            ('/salas/1/zonas',{'nombre_zona':'Nueva'}),
            ('/salas/1/asientos',{'id_zona':'1','fila':'Z','numero':'1'}),
            ('/salas/1/asientos/fila',{'lote_zona':'1','lote_fila':'Y','desde':'1','hasta':'3'}),
            ('/funciones/nueva',{'id_pelicula':'1','id_sala':'1','inicio':'2031-02-01T18:00','activa':'on'}),
            (self.ruta,dict(self.formulario,accion='tarifa',id_zona='1',id_categoria_entrada='1',monto='8')),
            (self.ruta,self.datos_promocion()),
            (self.ruta,{'accion':'categoria','nombre_categoria':'Cortesía'}),
        ]
        for numero,(ruta,datos) in enumerate(operaciones,1):
            with self.subTest(ruta=ruta,numero=numero):
                self.assertEqual(self.cliente.post(ruta,data=datos).status_code,302)
                self.assertEqual(self.cantidad_logs(),numero)
        identificador=self.conexion.execute('SELECT id_funcion FROM funcion ORDER BY id_funcion DESC LIMIT 1').fetchone()[0]
        self.assertEqual(self.cliente.post(f'/funciones/{identificador}/editar',data={
            'id_pelicula':'1','id_sala':'1','inicio':'2031-02-01T21:00','activa':'on'}).status_code,302)
        self.assertEqual(self.cantidad_logs(),11)
        entidades=self.conexion.execute('SELECT entidad,COUNT(*) FROM admin_operacion_audit GROUP BY entidad ORDER BY entidad').fetchall()
        self.assertEqual(entidades,[('asiento',2),('categoria_entrada',1),('funcion',2),('pelicula',2),('promocion',1),('sala',1),('tarifa',1),('zona',1)])

    def datos_promocion(self):
        return PruebasPrecios.datos_promocion(self)

    def test_lote_rechazado_no_genera_auditoria_de_exito(self):
        self.assertEqual(self.cliente.post('/salas/1/asientos',data={'id_zona':'1','fila':'A','numero':'2'}).status_code,302)
        self.assertEqual(self.cliente.post('/salas/1/asientos/fila',data={'lote_zona':'1','lote_fila':'A','desde':'1','hasta':'4'}).status_code,400)
        self.assertEqual(self.cantidad_logs(),1)
        self.assertEqual(self.conexion.execute('SELECT COUNT(*) FROM asiento').fetchone()[0],1)

    def test_sin_clave_o_servicio_de_permisos_no_hay_acceso_administrativo(self):
        with patch.dict(app.app.config,{'SECRET_KEY':None}):
            cliente=app.app.test_client()
            self.assertEqual(cliente.get('/login').status_code,503)
            self.assertEqual(cliente.get('/cartelera').status_code,200)
        with patch.object(seguridad,'obtener_conexion',side_effect=psycopg.OperationalError('ensayo')):
            self.assertEqual(self.cliente.get('/salas').status_code,503)

    def test_logout_y_sesion_no_conserva_el_formulario_anterior(self):
        cliente=self.entrar('admin@imax.test')
        datos=self.formulario_con_token(cliente,{})
        self.assertEqual(cliente.get('/logout').status_code,405)
        self.assertEqual(cliente.post('/logout',data=datos).status_code,302)
        self.assertEqual(cliente.get('/salas').status_code,302)
        self.assertEqual(cliente.post('/login',data={
            'correo':'admin@imax.test','password':self.password,'csrf_token':datos['csrf_token']}).status_code,400)

    def test_configurar_acceso_solo_sustituye_marcador_y_no_cambia_rol(self):
        original=seguridad.obtener_conexion
        with patch.object(configurar_acceso,'obtener_conexion',original):
            with self.assertRaises(ValueError):
                configurar_acceso.configurar_usuario('cliente2@imax.test','corta')
            configurar_acceso.configurar_usuario('cliente2@imax.test',self.password)
            hash_guardado,rol=self.conexion.execute("""SELECT password_hash,r.nombre FROM usuario u
                INNER JOIN rol r ON r.id_rol=u.id_rol WHERE correo='cliente2@imax.test'""").fetchone()
            self.assertTrue(check_password_hash(hash_guardado,self.password))
            self.assertEqual(rol,'cliente')
            with self.assertRaises(ValueError):
                configurar_acceso.configurar_usuario('cliente2@imax.test','Otra_contraseña_123')

    def test_clave_local_se_crea_una_vez_sin_reemplazar_otra(self):
        raiz=Path(__file__).resolve().parent
        with tempfile.TemporaryDirectory(dir=raiz,prefix='ensayo_clave_') as carpeta:
            assert Path(carpeta).resolve().parent == raiz
            archivo=Path(carpeta)/'.env'
            with patch.dict(configurar_acceso.os.environ,{'SECRET_KEY':''}):
                configurar_acceso.preparar_clave(archivo)
                primera=dotenv_values(archivo)['SECRET_KEY']
                self.assertGreaterEqual(len(primera),32)
                configurar_acceso.preparar_clave(archivo)
                self.assertEqual(dotenv_values(archivo)['SECRET_KEY'],primera)
            with patch.dict(configurar_acceso.os.environ,{'SECRET_KEY':'corta'}):
                with self.assertRaises(ValueError):
                    configurar_acceso.preparar_clave(archivo)
                self.assertEqual(dotenv_values(archivo)['SECRET_KEY'],primera)

if __name__ == '__main__':
    unittest.main(defaultTest='PruebasSeguridad',verbosity=2)
