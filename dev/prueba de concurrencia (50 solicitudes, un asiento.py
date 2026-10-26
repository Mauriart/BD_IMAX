"""Prueba de doble venta: N solicitudes simultaneas sobre el MISMO asiento.
Criterio: exactamente 1 exito, N-1 conflictos esperados, 0 errores inesperados.
Uso (desde dev/):  python concurrencia_reservas.py --n 50
"""
import argparse, threading, collections, datetime, psycopg
from conexion import obtener_conexion

SQL_ESCENARIO = """
SELECT f.id_funcion, t.id_categoria_entrada, i.id_asiento
FROM funcion f
JOIN tarifa t ON t.id_funcion=f.id_funcion AND t.vigente_desde<=now() AND now()<t.vigente_hasta
JOIN asiento a ON a.id_zona=t.id_zona
JOIN inventario_funcion i ON i.id_funcion=f.id_funcion AND i.id_asiento=a.id_asiento
WHERE f.activa AND f.inicio>now() AND i.estado='disponible'
ORDER BY f.id_funcion, i.id_asiento LIMIT 1"""

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--n', type=int, default=50)
    ap.add_argument('--funcion', type=int); ap.add_argument('--asiento', type=int)
    ap.add_argument('--categoria', type=int)
    a = ap.parse_args()

    with obtener_conexion() as c:
        if not (a.funcion and a.asiento and a.categoria):
            fila = c.execute(SQL_ESCENARIO).fetchone()
            if not fila: raise SystemExit('No hay funcion futura con tarifa vigente y asiento disponible.')
            a.funcion, a.categoria, a.asiento = fila
        cliente = c.execute("""SELECT u.id_usuario FROM usuario u JOIN rol r USING(id_rol)
                               WHERE r.nombre='cliente' AND u.activo ORDER BY 1 LIMIT 1""").fetchone()[0]
    print(f'Funcion {a.funcion}, asiento {a.asiento}, categoria {a.categoria}, cliente {cliente}, hilos {a.n}')

    barrera = threading.Barrier(a.n, timeout=30)
    resultados = []; cerrojo = threading.Lock()

    def trabajador(_):
        try:
            conn = obtener_conexion()           # una conexion independiente por hilo
        except Exception as e:
            with cerrojo: resultados.append('ERROR conexion: ' + repr(e)); return
        try:
            conn.execute("SELECT set_config('app.id_usuario',%s,true)", (str(cliente),))
            barrera.wait()                      # todos arrancan a la vez
            conn.execute("SELECT reservar_asientos(%s::bigint,%s::bigint,%s::bigint,%s::int[],%s::int)",
                         (cliente, cliente, a.funcion, [a.asiento], a.categoria))
            conn.commit(); r = 'EXITO'
        except psycopg.errors.RaiseException as e:
            conn.rollback()
            r = 'CONFLICTO' if 'no se encuentra disponible' in e.diag.message_primary \
                else 'ERROR: ' + e.diag.message_primary
        except psycopg.errors.UniqueViolation:   # uq_ocupacion_vigente
            conn.rollback(); r = 'CONFLICTO'
        except Exception as e:
            try: conn.rollback()
            except Exception: pass
            r = 'ERROR: ' + repr(e)
        finally:
            conn.close()
        with cerrojo: resultados.append(r)

    hilos = [threading.Thread(target=trabajador, args=(i,)) for i in range(a.n)]
    [h.start() for h in hilos]; [h.join() for h in hilos]

    cuenta = collections.Counter('ERROR' if r.startswith('ERROR') else r for r in resultados)
    with obtener_conexion() as c:
        activas = c.execute("SELECT count(*) FROM reserva WHERE id_funcion=%s AND id_asiento=%s AND estado='activa'",
                            (a.funcion, a.asiento)).fetchone()[0]
        estado = c.execute("SELECT estado FROM inventario_funcion WHERE id_funcion=%s AND id_asiento=%s",
                           (a.funcion, a.asiento)).fetchone()[0]
    ok = cuenta['EXITO'] == 1 and cuenta['CONFLICTO'] == a.n - 1 and cuenta['ERROR'] == 0 \
         and activas == 1 and estado == 'bloqueado'
    informe = (f"Fecha: {datetime.datetime.now().isoformat(timespec='seconds')}\n"
               f"Solicitudes simultaneas: {a.n} (funcion {a.funcion}, asiento {a.asiento})\n"
               f"Exitos: {cuenta['EXITO']} (esperado 1)\n"
               f"Conflictos esperados: {cuenta['CONFLICTO']} (esperado {a.n-1})\n"
               f"Errores inesperados: {cuenta['ERROR']} (esperado 0)\n"
               f"Reservas activas del asiento: {activas} (esperado 1)\n"
               f"Estado final del inventario: {estado} (esperado bloqueado)\n"
               f"RESULTADO: {'APROBADO' if ok else 'FALLIDO'}\n")
    print(informe)
    for r in set(resultados):
        if r.startswith('ERROR'): print('  ', r)
    open(f'concurrencia_{a.n}_{datetime.datetime.now():%Y%m%d_%H%M%S}.txt', 'w', encoding='utf-8').write(informe)
    raise SystemExit(0 if ok else 1)

if __name__ == '__main__':
    main()