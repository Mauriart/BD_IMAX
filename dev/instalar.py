"""Instalar la base completa y preparar las cuentas de demostración."""
from getpass import getpass
from pathlib import Path
import os
import secrets

import psycopg
from psycopg import sql
from dotenv import set_key
from werkzeug.security import generate_password_hash

RAIZ = Path(__file__).resolve().parent


def instalar_base(parametros):
    """Crea la base si no existe e instala únicamente sobre un esquema vacío."""
    base = parametros['dbname']
    if not base or base in {'postgres', 'template0', 'template1'}:
        raise ValueError('Usa una base del proyecto, por ejemplo p2. No una base de mantenimiento.')
    with psycopg.connect(**dict(parametros, dbname='postgres'), autocommit=True) as conexion:
        existe = conexion.execute('SELECT 1 FROM pg_database WHERE datname=%s', (base,)).fetchone()
        if not existe:
            conexion.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(base)))
    with psycopg.connect(**parametros) as conexion:
        objetos = conexion.execute("""SELECT EXISTS (
            SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='public' AND c.relkind IN ('r','p','v','m','S','f')
            UNION ALL
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='public'
        )""").fetchone()[0]
        if objetos:
            raise ValueError('La base ya contiene objetos. No se borró ni reinstaló nada. Usa otra base vacía o conserva tu .env actual para iniciar.')
        conexion.execute((RAIZ/'sql/instalacion_completa.sql').read_text(encoding='utf-8-sig'))


def preparar_cuentas(parametros, password):
    if not 12 <= len(password) <= 1024:
        raise ValueError('La contraseña debe tener entre 12 y 1024 caracteres.')
    with psycopg.connect(**parametros) as conexion:
        conexion.execute("UPDATE usuario SET password_hash=%s WHERE password_hash='HASH_DE_PRUEBA'",
                         (generate_password_hash(password),))


def guardar_configuracion(parametros):
    archivo = RAIZ/'.env'
    for campo, valor in {'DB_HOST':parametros['host'], 'DB_PORT':parametros['port'],
                         'DB_NAME':parametros['dbname'], 'DB_USER':parametros['user'],
                         'DB_PASSWORD':parametros['password'], 'SECRET_KEY':secrets.token_urlsafe(48)}.items():
        set_key(str(archivo), campo, str(valor))


def preguntar(etiqueta, defecto):
    return input(f'{etiqueta} [{defecto}]: ').strip() or defecto


def main():
    try:
        print('Instalación en una base vacía. PostgreSQL debe estar instalado y en ejecución.')
        parametros = {'host':preguntar('Servidor','127.0.0.1'), 'port':preguntar('Puerto','5432'),
                      'dbname':preguntar('Nombre de la base','p2'), 'user':preguntar('Usuario PostgreSQL','postgres'),
                      'password':getpass('Contraseña de PostgreSQL: '), 'connect_timeout':10}
        password = getpass('Contraseña inicial para las cuentas de demostración (mínimo 12 caracteres): ')
        if not 12 <= len(password) <= 1024:
            raise ValueError('La contraseña debe tener entre 12 y 1024 caracteres.')
        if password != getpass('Repite la contraseña inicial: '):
            raise ValueError('Las contraseñas no coinciden.')
        instalar_base(parametros)
        preparar_cuentas(parametros, password)
        guardar_configuracion(parametros)
    except (ValueError, psycopg.Error) as error:
        if isinstance(error, psycopg.Error):
            print('No se pudo terminar la instalación. Revisa el servicio PostgreSQL, las credenciales y los permisos para crear la base.')
        else:
            print(str(error))
        return 1
    except KeyboardInterrupt:
        print('\nInstalación cancelada.')
        return 1
    print('Base y acceso preparados. Ejecuta iniciar.cmd en Windows o python iniciar.py.')
    print('Administrador: admin@imax.test. Las cuentas de demostración usan la contraseña que elegiste.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
