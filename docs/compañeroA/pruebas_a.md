# Pruebas iniciales del esquema A — A-01

Este documento conserva la evidencia de A-01. Para el estado actual, las 97 pruebas automatizadas y el estado integrado, consultar [pruebas_modulo_A.md](pruebas_modulo_A.md).

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

Las primeras comprobaciones fueron confirmadas desde DBeaver. Adicionalmente se ejecutó una instalación limpia y la verificación siguiente en PostgreSQL 18.6, en una instancia temporal separada. No se modificó la base de DBeaver. La versión de esa base no se ha comprobado.

| Verificación adicional | Resultado |
| --- | --- |
| Instalación de relacional_A.sql y ajuste_integridad_A.sql con detención ante errores | Correcta: 12 tablas. |
| Carga de datos y consultas | Ocho tarifas y capacidad de seis asientos; función, película y ubicación correctas. |
| Repetición de los cinco errores básicos | Todos rechazados por la clase de restricción esperada. |
| Insertar tarifa con zona ajena a la sala de su función | Rechazado. |
| Actualizar tarifa para usar una zona ajena | Rechazado. |
| Cambiar sala de una función con tarifas | Rechazado. |
| Cambiar sala de una zona con tarifas | Rechazado. |
| Actualizar importe conservando referencias válidas | Aceptado. |
| Actualizar sala al mismo valor | Aceptado. |
| Mover una zona sin tarifas | Aceptado. |
| Crear una segunda función en la misma sala | Aceptado; los asientos físicos no quedan ocupados globalmente. |

La [salida de ejecución](resultado_verificacion_A.txt) conserva los resultados reales. [verificacion_A.sql](verificacion_A.sql) permite repetirlos sobre los datos de ejemplo y revierte sus registros auxiliares al terminar.

Orden usado: relacional_A.sql → ajuste_integridad_A.sql → datos_A.sql → consultas_A.sql → verificacion_A.sql. La ejecución se detuvo ante cualquier error no previsto mediante ON_ERROR_STOP=1. Las comprobaciones de rechazo usan bloques EXCEPTION para distinguir el fallo esperado de otro problema.

En el alcance de aquella entrega de A-01 no se habían ejecutado pruebas de concurrencia, traslapes, tarifas con vigencias superpuestas, permisos, ventas o auditoría. No se han medido tiempos ni planes de ejecución. Esas verificaciones corresponden a las tareas posteriores.

A-01 entrega el modelo parcial, la normalización, el diccionario, el esquema, los datos, los contratos y esta verificación. Mauriart indicó que no requiere revisión por otra persona para esta entrega. El ajuste deberá ejecutarse también en su base existente para que incorpore la validación nueva.
