"""Preparar una contraseña para un usuario existente de C, sin crear usuarios ni cambiar roles."""
from getpass import getpass
from pathlib import Path
import os
import secrets
from dotenv import set_key, dotenv_values
import psycopg
from werkzeug.security import generate_password_hash
from modulos.conexion import obtener_conexion

TABLAS_C = ('rol', 'usuario', 'rol_permiso', 'solicitud_reembolso',
            'solicitud_reembolso_detalle', 'acceso_puerta_log', 'admin_operacion_audit')


def verificar_instalacion():
    with obtener_conexion() as conexion:
        presentes = [conexion.execute('SELECT to_regclass(%s)', (tabla,)).fetchone()[0] for tabla in TABLAS_C]
        if not all(presentes):
            raise ValueError('Primero instala la base completa con instalar.py o sql/instalacion_completa.sql.')


def configurar_usuario(correo, password):
    """Solo reemplaza el marcador inicial de C; nunca una contraseña ya configurada."""
    if len(password) < 12 or len(password) > 1024:
        raise ValueError('Utiliza una contraseña de entre 12 y 1024 caracteres.')
    with obtener_conexion() as conexion:
        fila = conexion.execute('SELECT id_usuario,password_hash FROM usuario WHERE correo=%s AND activo=TRUE FOR UPDATE',
                                (correo.strip().lower(),)).fetchone()
        if fila is None:
            raise ValueError('El usuario no existe o está inactivo.')
        if fila[1] != 'HASH_DE_PRUEBA':
            raise ValueError('Ese usuario ya tiene una contraseña configurada. No se modificó.')
        conexion.execute('UPDATE usuario SET password_hash=%s WHERE id_usuario=%s',
                         (generate_password_hash(password), fila[0]))


def preparar_clave(archivo=None):
    archivo = Path(archivo) if archivo else Path(__file__).resolve().parent / '.env'
    guardada = dotenv_values(archivo).get('SECRET_KEY') if archivo.exists() else None
    clave = os.environ.get('SECRET_KEY') or guardada
    if clave:
        if len(clave) < 32:
            raise ValueError('SECRET_KEY debe tener al menos 32 caracteres. No se reemplazó su valor actual.')
        return
    set_key(str(archivo), 'SECRET_KEY', secrets.token_urlsafe(48))


def main():
    try:
        preparar_clave()
        verificar_instalacion()
        correo = input('Correo del usuario existente (ej. admin@imax.test): ').strip()
        password = getpass('Nueva contraseña (mínimo 12 caracteres): ')
        if password != getpass('Repite la contraseña: '):
            raise ValueError('Las contraseñas no coinciden.')
        configurar_usuario(correo, password)
    except ValueError as ex:
        print(str(ex))
        return 1
    except psycopg.Error:
        print('No se pudo preparar el acceso. Revisa la conexión y el esquema de C.')
        return 1
    print('Acceso preparado. Reinicia la aplicación. No se crearon usuarios ni se cambiaron roles.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
