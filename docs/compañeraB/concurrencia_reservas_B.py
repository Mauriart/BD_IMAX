"""
Prueba de concurrencia (B-T12)

IDEA: muchas personas intentan reservar el MISMO asiento en el MISMO instante.
La base de datos debe dejar que SOLO UNA lo consiga; las demas reciben el
error ASIENTO_NO_DISPONIBLE.

COMO USARLO
  1. Activa tu entorno virtual y ubicate en la carpeta del proyecto.
  2. Asegurate de que el archivo .env tenga DATABASE_URL (la conexion a tu base).
  3. Ejecuta:
         python concurrencia_reservas.py
     o con otros valores:
         python concurrencia_reservas.py --n 50 --funcion 1 --asiento 3 --categoria 1
  4. Guarda el informe que se crea en la carpeta "evidencias".

IMPORTANTE: usa un asiento de prueba. El script libera ese asiento antes de empezar.
"""
import argparse
import os
import threading
import uuid
from collections import Counter
from datetime import datetime

import psycopg
from psycopg import errors
from dotenv import load_dotenv

load_dotenv()
DSN = "postgresql://postgres:postgres@localhost:5432/cine"

parser = argparse.ArgumentParser()
parser.add_argument("--n", type=int, default=50, help="solicitudes simultaneas (20 a 50)")
parser.add_argument("--funcion", type=int, default=1, help="id de la funcion")
parser.add_argument("--asiento", type=int, default=3, help="id del asiento de prueba")
parser.add_argument("--categoria", type=int, default=1, help="id de la categoria de entrada")
args = parser.parse_args()

N, ID_FUNCION, ID_ASIENTO, ID_CATEGORIA = args.n, args.funcion, args.asiento, args.categoria
CORRIDA = uuid.uuid4().hex[:8]          # para que las referencias no se repitan entre corridas

# --- Preparacion: leer usuarios y dejar el asiento libre ---
with psycopg.connect(DSN) as conn:
    usuarios = [r[0] for r in conn.execute("SELECT id_usuario FROM usuario ORDER BY id_usuario")]
    if not usuarios:
        raise SystemExit("No hay usuarios en la base (revisa stub_C_local.sql).")

    conn.execute(
        """UPDATE reserva SET estado = 'liberada'
            WHERE estado = 'activa'
              AND id_reserva IN (SELECT id_reserva FROM inventario_funcion
                                  WHERE id_funcion = %s AND id_asiento = %s)""",
        (ID_FUNCION, ID_ASIENTO),
    )
    conn.execute(
        """UPDATE inventario_funcion
              SET estado = 'disponible', id_reserva = NULL, id_boleto = NULL
            WHERE id_funcion = %s AND id_asiento = %s""",
        (ID_FUNCION, ID_ASIENTO),
    )
    conn.commit()

resultados = [None] * N
barrera = threading.Barrier(N)          # todos arrancan al mismo tiempo


def intentar(i):
    usuario = usuarios[i % len(usuarios)]
    referencia = f"CONC-{CORRIDA}-{i}"
    try:
        with psycopg.connect(DSN) as conn:          # cada intento usa su propia conexion
            barrera.wait(timeout=60)                 # esperar a que todos esten listos
            try:
                conn.execute(
                    "SELECT reservar_asientos(%s, %s, %s, %s::int[]);",
                    (ID_FUNCION, usuario, 1, [ID_ASIENTO]),
                )
                conn.commit()
                resultados[i] = "exito"
            except errors.RaiseException as e:
                conn.rollback()
                mensaje_error = e.diag.message_primary.lower()
                if "no se encuentra disponible" in mensaje_error or "bloqueado" in mensaje_error:
                    resultados[i] = "conflicto"
                else:
                    resultados[i] = f"negocio:{e.diag.message_primary}"
    except Exception as e:                           
        resultados[i] = f"inesperado:{e!r}"


hilos = [threading.Thread(target=intentar, args=(i,)) for i in range(N)]
for h in hilos:
    h.start()
for h in hilos:
    h.join()

conteo = Counter(resultados)

# --- Comprobacion final en la base de datos ---
with psycopg.connect(DSN) as conn:
    row = conn.execute(
        "SELECT estado, id_reserva FROM inventario_funcion WHERE id_funcion = %s AND id_asiento = %s",
        (ID_FUNCION, ID_ASIENTO),
    ).fetchone()
    
    estado_asiento = row[0] if row else "desconocido"
    # Si hay un id_reserva asociado, significa que hay 1 reserva activa en el inventario
    reservas_activas = 1 if (row and row[1] is not None) else 0

otros = {k: v for k, v in conteo.items() if k not in ("exito", "conflicto")}
informe = [
    f"Fecha: {datetime.now().isoformat(timespec='seconds')}",
    f"Solicitudes simultaneas: {N}  (funcion {ID_FUNCION}, asiento {ID_ASIENTO})",
    f"Exitos: {conteo.get('exito', 0)}  (esperado: 1)",
    f"Rechazos por conflicto: {conteo.get('conflicto', 0)}  (esperado: {N - 1})",
    f"Errores inesperados u otros: {otros if otros else 'ninguno'}",
    f"Estado final del asiento: {estado_asiento}  (esperado: bloqueado)",
    f"Reservas activas de ese asiento: {reservas_activas}  (esperado: 1)",
]
print("\n".join(informe))

os.makedirs("evidencias", exist_ok=True)
archivo = f"evidencias/concurrencia_{N}_{datetime.now():%Y%m%d_%H%M%S}.txt"
with open(archivo, "w", encoding="utf-8") as f:
    f.write("\n".join(informe) + "\n")

correcto = (conteo.get("exito", 0) == 1 and conteo.get("conflicto", 0) == N - 1
            and not otros and estado_asiento == "bloqueado" and reservas_activas == 1)
print("\nRESULTADO:", "CORRECTO" if correcto else "REVISAR (algo no coincide con lo esperado)")
print("Informe guardado en:", archivo)
