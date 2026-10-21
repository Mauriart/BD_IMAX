# Pruebas del esquema A

## Condiciones

Las comprobaciones se realizaron en PostgreSQL desde DBeaver con el esquema y los datos de ejemplo de este directorio. Los resultados siguientes fueron confirmados por el integrante al ejecutarlos. No se adjuntan capturas ni transcripciones de mensajes de error; esta tabla registra el resultado comunicado, no una ejecución automatizada independiente.

Las instrucciones de error se ejecutan por separado. Deben existir los datos válidos antes de probar duplicados y deben haberse confirmado para evitar que un Rollback los deshaga. Los fallos pueden consumir números de secuencia sin insertar registros; esto es normal con SERIAL.

## Comprobaciones positivas

| Caso | Comprobación | Esperado | Resultado comunicado |
| --- | --- | --- | --- |
| A-P01 | Crear esquema y listar tablas del esquema public. | Las 12 tablas del bloque A. | Confirmado. |
| A-P02 | Cargar los INSERT de ejemplo. | Registros conectados sin errores. | Confirmado. |
| A-P03 | Unir función, película, sala y cine. | IMAX Central, Sala 1 y Horizonte estelar, con su horario. | Confirmado. |
| A-P04 | Consultar tarifas por función/zona/categoría. | Ocho tarifas, cuatro por zona. | Confirmado. |
| A-P05 | Contar asientos por sala. | Sala 1 con capacidad calculada de seis asientos. | Confirmado. |

Las consultas están en [consultas_A.sql](consultas_A.sql). La carga de ejemplo está en [datos_A.sql](datos_A.sql).

## Comprobaciones negativas

| Caso | Instrucción de prueba | Esperado | Resultado comunicado |
| --- | --- | --- | --- |
| A-N01 | Reinsertar asiento de zona 1, fila A, número 1. | Rechazo por `uq_asiento_ubicacion`. | Rechazado. |
| A-N02 | Insertar película con duración de -10 minutos. | Rechazo por CHECK de duración positiva. | Rechazado. |
| A-N03 | Insertar función que termina antes de iniciar. | Rechazo por `ck_funcion_horario`. | Rechazado. |
| A-N04 | Insertar tarifa con monto -5.00. | Rechazo por `ck_tarifa_monto`. | Rechazado. |
| A-N05 | Insertar sala con `id_cine = -1`, inexistente. | Rechazo por `fk_sala_cine`. | Rechazado. |

Las sentencias están en [pruebas_A.sql](pruebas_A.sql). Las restricciones esperadas se identifican a partir del DDL; no se cuenta con el mensaje exacto de cada ejecución para cotejarlo.

## Alcance de los resultados

Estas pruebas comprueban creación, relaciones básicas, consultas y cinco rechazos. No prueban concurrencia, traslapes, tarifas con vigencias superpuestas, pertenencia zona/función, permisos, ventas ni auditoría. No se han medido tiempos ni planes de ejecución.

A-01 mantiene pendiente la revisión de coherencia completa con los acuerdos y la integración compartida. No se cierra un issue por publicar estos archivos.
