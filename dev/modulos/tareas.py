"""Liberacion periodica de reservas en el servidor local."""
import logging
from threading import Thread,Event
import psycopg
from modulos.conexion import obtener_conexion


def iniciar_mantenimiento():
    detener=Event()
    def ejecutar():
        while not detener.wait(2):
            try:
                with obtener_conexion() as c:
                    if c.execute("SELECT to_regprocedure('liberar_reservas_vencidas()') IS NOT NULL").fetchone()[0]:
                        c.execute('SELECT liberar_reservas_vencidas()')
            except psycopg.Error:
                logging.getLogger(__name__).warning('No se pudo liberar reservas en este ciclo.')
    Thread(target=ejecutar,name='reservas-vencidas',daemon=True).start()
    return detener
