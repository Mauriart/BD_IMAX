"""Prueba reproducible de 50 reservas. Crea su esquema y lo elimina al terminar."""
from pathlib import Path
import argparse,sys,unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'dev'))
from verificar_integracion_global import IntegracionGlobal

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--n',type=int,choices=[50],default=50)
    parser.parse_args()
    suite=unittest.TestSuite([IntegracionGlobal('test_50_reservas_simultaneas_un_ganador')])
    resultado=unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if resultado.wasSuccessful() else 1)
