from app import app
from modulos.tareas import iniciar_mantenimiento

if __name__=='__main__':
    detener=iniciar_mantenimiento()
    try:app.run(host='127.0.0.1',port=5000,debug=False)
    finally:detener.set()
