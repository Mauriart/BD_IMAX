> Version de trabajo anterior. La aplicacion, SQL y evidencia de la integracion actual se describen en [integracion/guia.md](../integracion/guia.md). Los resultados historicos de este archivo no sustituyen las pruebas sobre las tablas reales de B.

# Evidencias del bloque C (C-07)

Una carpeta por caso o suite. Guardar la salida **tal como se obtuvo**; no editar resultados.

| Ruta | Contenido | Generado por |
| --- | --- | --- |
| `junit.xml` | Resultado de pytest (PC-01 a PC-42 excepto PC-15 CLI) | `pytest tests/operacion --junitxml=evidencias/c/junit.xml` |
| `PC-15/resultado.json` | 50 escaneos simultáneos: conteos, estado final, log de puerta, versión de PostgreSQL | `concurrencia_qr.py` |
| `PC-14/` | Igual, con `--n 2 --indice 2` | `concurrencia_qr.py` |
| `REP/salida.txt` | Reportes 1, 2 y 4 con sus ASSERT | `c07_verificar_reportes.sql` |
| `EXPLAIN/antes/`, `EXPLAIN/despues/` | `entorno.txt`, un `.txt` por consulta (plan de la mediana) y `resumen.csv` | `medir_explain.py` |

Un conflicto esperado ("Entrada ya utilizada") no es un error del programa; el resumen los separa.
Una captura de pantalla no sustituye la consulta SQL del estado final.
