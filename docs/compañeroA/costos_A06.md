# Comparación económica A-06: AWS y Azure

## Resultado y alcance

Con los supuestos de este documento, el escenario con crecimiento de 10 % anual cuesta 303.417,05 USD en AWS y 305.146,10 USD en Azure durante 36 meses, incluida una inversión inicial de 20.000 USD. La diferencia de 1.729,05 USD, aproximadamente 0,57 %, es menor que la incertidumbre del presupuesto.

Por ahora no se recomienda adjudicar por esa diferencia. Es una comparación de un escenario IaaS autogestionado equivalente, no una cotización cerrada del sistema mundial ni prueba de que los servidores elegidos soporten 8 millones de usuarios o 50.000 TPS.

A-06 queda en avance preliminar: hay cifras reproducibles, fuentes, inversión inicial, OPEX, costo unitario y ROI condicional. Faltan conciliar las tablas reales de B, dimensionar cómputo/IOPS/red con carga y sustituir las reservas por cotizaciones regionales completas.

## Base recibida de C

Se usa C-05 versión 1.0, commit 02ff08bc0b8d12e52a5f6827395c320d8a64cf51: [dimensionamiento](../compañeroC/documentacion_tecnica_c_05.md), R4/R5 de [su SQL](../compañeroC/c05_dimensionamiento.sql) y [operación de C-06](../compañeroC/operacion.md). La entrada capturada y las salidas de C se conservan en [base_C05.json](costos/base_C05.json).

C parte de 15 millones de boletos mensuales, 2,5 boletos por compra y 60 % de conversión de reservas a pago. Se derivan 6 millones de compras pagadas y 10 millones de compras/reservas creadas por mes, en el escenario inicial. Son supuestos de C para el análisis, no ventas observadas.

Se conservan seis meses de datos activos, dos réplicas adicionales, dos copias del archivo con retención de 60 meses y respaldos de 30 días con completos, incrementales y WAL. Las compresiones 4:1 del archivo y 2:1 de respaldos, y el factor WAL 2,5 son supuestos no medidos.

C estima al mes 60, con 10 % de crecimiento, 323,3 GiB de datos activos por copia, 646,6 GiB en las dos réplicas, 648,3 GiB de archivo entre sus dos copias y 883,7 GiB de backups. No se cobran esos valores máximos desde el primer mes: la proyección recalcula cada uno de los 36 meses. Los datos archivados se conservan completos desde el primer mes, como en C-05. La proyección financiera termina al mes 36, pero la obligación de retener 60 meses continúa: los gastos de los años 4 y 5 no se pagan con este total ni se consideran gratuitos.

Las filas de pagos, reservas, inventario y logs de B todavía usan tamaños provisionales. La captura de C no incorpora automáticamente lo publicado después en Compañera_B.

## Qué se compara en ambos proveedores

| Componente | Cantidad y capacidad en ambos casos | AWS | Azure |
| --- | --- | --- | --- |
| Región principal / recuperación | Dos regiones de Estados Unidos. | N. Virginia / Ohio | East US / East US 2 |
| Base de datos | 3 VM Linux, 16 vCPU y 64 GiB cada una: primario, réplica local y réplica remota. | m6i.4xlarge | D16s v5 |
| Aplicación | 4 VM Linux, 4 vCPU y 16 GiB: 3 principales y 1 remota encendida. | m6i.xlarge | D4s v5 |
| Proxy, balanceo y WAF | 2 VM Linux, 2 vCPU y 8 GiB: 1 por región; software abierto. | m6i.large | D2s v5 |
| Disco de datos | 512 GiB por VM de BD; referencia de 3.000 IOPS y 125 MB/s incluidos. | EBS gp3 | Premium SSD v2 |
| Arranque | 64 GiB por cada una de las 9 VM. | gp3 | Premium SSD P6 |
| Archivo y backups | Mismos bytes y retención. Archivo: una copia por región; backups en región de recuperación. | S3 Standard | Blob Hot LRS |

Las VM de proxy son el recurso presupuestado para balanceo y WAF autogestionados; no se suman ALB/WAF ni Application Gateway administrados. El arreglo de un proxy por región no acredita alta disponibilidad del frontal dentro de cada región: si se requiere duplicarlo, hay que sumarlo. DNS, conmutación, admisión, pool y servicios auxiliares requieren diseño y validación.

La réplica local debe ubicarse en otra zona. Los niveles de servicio 99,99 %, RPO ≤ 5 s y RTO < 5 min se conservan como objetivos de la arquitectura: no se deducen del tamaño de una VM ni de esta suma de precios. No se presupuestó un servicio administrado de PostgreSQL en un proveedor frente a servidores autogestionados en el otro.

La equivalencia es de CPU/RAM, capacidad de datos y función operativa; no acredita igual rendimiento. Los discos de arranque tienen rendimientos distintos y no alojan la BD. Los discos de datos incluyen solo rendimiento base, por lo que las IOPS o el throughput adicionales deben cotizarse después de medir.

## Precios y supuestos separados

Consulta: 24 de octubre de 2026. USD, pago por uso, Linux, sin Spot, reservas, créditos, compromisos a tres años ni impuestos. Las 730 horas mensuales son una convención presupuestaria; no se aplica además otro factor de 30 días.

Los [registros consultados](costos/precios_consultados_A06.json) conservan SKU, región, unidad, tramos y datos de la fuente. Se seleccionaron tarifas Consumption de Linux, excluyendo Windows, Spot y Low Priority.

| Unidad | AWS | Azure principal / recuperación |
| --- | ---: | ---: |
| VM BD, USD/h | 0,768 / 0,768 | 0,768 / 0,768 |
| VM aplicación, USD/h | 0,192 / 0,192 | 0,192 / 0,192 |
| VM proxy, USD/h | 0,096 / 0,096 | 0,096 / 0,096 |
| Datos, USD/GiB-mes | 0,08 de referencia | 0,00011 USD/GiB-h × 730 = 0,0803 |
| Arranque, USD/disco-mes | 64 × 0,08 = 5,12 | 10,207 / 9,2801 |
| Objetos, USD/GiB-mes | 0,023 / 0,023 | 0,0208 / 0,0184 |

La tarifa gp3 de AWS se tomó del ejemplo de la página oficial de EBS, no de un resultado regional autenticado de la calculadora; se marca como referencia pendiente de reconfirmar. Los valores de cómputo y S3 proceden de sus catálogos públicos; Azure procede de Retail Prices. Una consulta pública de precios no es una oferta comercial vinculante.

S3 y Blob calculan su unidad de almacenamiento en gigabytes binarios, equivalentes a GiB. No se aplica una conversión decimal adicional. Se cobra el disco provisionado completo de 512 GiB por BD, aunque los datos usen menos.

El archivo histórico usa S3 Standard y Blob Hot para comparar acceso inmediato sin costos distintos de rehidratación. No se afirma que sean las clases más baratas. WORM requiere configurar Object Lock o inmutabilidad; una segunda copia exige retención independiente. El tamaño comprimido supuesto por C se conserva. El costo de operaciones, versiones adicionales y replicación no está incluido en la tarifa de capacidad.

## Inversión inicial y operación

Los siguientes valores son supuestos de presupuesto editables, no tarifas publicadas por AWS o Microsoft:

| Concepto | Cálculo | Importe |
| --- | --- | ---: |
| Implementación y configuración inicial | 400 h × 40 USD/h | 16.000 USD |
| Capacitación y migración de prueba | Monto inicial supuesto | 4.000 USD |
| Inversión inicial total | Una sola vez | 20.000 USD |
| Operación y mantenimiento | 80 h/mes × 40 USD/h | 3.200 USD/mes |
| Reserva para consumos variables | Base mensual, crece 10 % anual en ese escenario | 1.200 USD/mes iniciales |
| Contingencia | 20 % sobre nube + reserva; no sobre el personal | Variable |

La inversión inicial no implica comprar equipos: en este escenario el CAPEX de hardware es cero. Los 20.000 USD son desembolso inicial de proyecto; su tratamiento contable como gasto o activo no se presupone.

La reserva de 1.200 USD cubre provisionalmente red entre zonas/regiones, salida a internet, IP/NAT, DNS, peticiones de objetos, observabilidad y soporte del proveedor. No es una cotización de cada servicio ni un límite que el proveedor vaya a respetar. Debe reemplazarse por cantidades y tarifas, especialmente si crecen el tráfico público, las conexiones o el WAL.

Las 80 horas son dedicación estimada de operación; no equivalen a un equipo exclusivo de guardia 24×7. La cobertura adicional se cotizará si se exige. Linux, PostgreSQL y el software abierto elegido no llevan una licencia comercial por servidor en el modelo; sí requieren trabajo de operación y comprobación de sus licencias.

No se incluyen comisiones de pasarela, impuestos, auditoría/certificación externa, conectividad/equipos en los cines ni desarrollo funcional completo del producto. Por eso el total es TCO del escenario tecnológico y sus recursos operativos supuestos, no costo de toda la licitación.

## Proyección y fórmulas

Los [resultados](costos/resultados_A06.md), las [144 filas mensuales](costos/proyeccion_mensual_A06.csv) y el [resumen numérico](costos/resumen_A06.json) se generan a partir de entradas editables.

Por mes:

- Cómputo = suma de VM × tarifa horaria × 730.
- Discos = capacidad provisionada × tarifa, más los discos de arranque.
- Objetos = media del precio de ambas regiones × archivo total, más backups × precio de recuperación.
- Nube = cómputo + discos + objetos + reserva variable.
- OPEX = nube × 1,20 + 3.200 USD de operación.
- TCO = 20.000 USD iniciales + suma de OPEX de los 36 meses.

El crecimiento se aplica por escalones anuales a ventas, datos y reserva. El número de VM queda fijo como hipótesis: no se afirma que alcance para el crecimiento o el pico. Los precios unitarios permanecen constantes durante tres años como supuesto financiero, no garantía contractual.

| Escenario | AWS, total 36 meses | Azure, total 36 meses |
| --- | ---: | ---: |
| Sin crecimiento | 297.996,86 USD | 299.738,09 USD |
| +10 % anual | 303.417,05 USD | 305.146,10 USD |
| +10 % y reserva variable duplicada | 360.613,85 USD | 362.342,90 USD |

La sensibilidad a la reserva cambia el resultado en aproximadamente 57.197 USD, mucho más que la diferencia entre proveedores. Eso impide una elección firme solo por el precio de este escenario.

## Costo por millón y ROI

Para este análisis una transacción de negocio es una compra/reserva creada, pagada o no. C estima 10 millones mensuales iniciales. El escenario creciente acumula 397,2 millones en 36 meses. No son peticiones HTTP, eventos de log ni transacciones SQL, y no se extrapolan los 50.000 TPS a todo el mes.

Costo total por millón = TCO / (compras creadas acumuladas / 1.000.000).

| Indicador, con crecimiento | AWS | Azure |
| --- | ---: | ---: |
| TCO por millón de compras creadas | 763,89 USD | 768,24 USD |
| TCO por millón de compras pagadas | 1.273,15 USD | 1.280,40 USD |

El ROI usa beneficio incremental, no todo el precio de los boletos. Se supone, únicamente para sensibilidad, un margen de 3 USD por compra adicional recuperada gracias a menos fallos. Sobre 238,32 millones de compras pagadas de referencia en tres años:

ROI = (beneficio incremental acumulado − TCO) / TCO × 100.

| Fracción adicional recuperada | Beneficio supuesto | ROI AWS | ROI Azure |
| --- | ---: | ---: | ---: |
| 0,025 % | 178.740 USD | −41,09 % | −41,42 % |
| 0,05 % | 357.480 USD | 17,82 % | 17,15 % |
| 0,10 % | 714.960 USD | 135,64 % | 134,30 % |

El equilibrio está en aproximadamente 0,0424 % de recuperación para AWS y 0,0427 % para Azure, manteniendo el margen de 3 USD y todos los supuestos. No hay datos observados que demuestren ese margen o esa recuperación. No se suman ahorros de personal adicionales, no se confunde facturación con beneficio y no se promete rentabilidad. No se calcula VAN ni inflación.

## Cómo se obtuvo y cómo repetirlo

El SQL de C-05 se ejecutó en una conexión con tablas temporales y búsqueda restringida a pg_temp. Se omitieron únicamente sus instrucciones de presentación de psql. La transacción se revirtió después de capturar las entradas y R4. No se instaló el dump imax.sql ni se modificaron datos de negocio.

Python recalcula los 36 meses con Decimal para conservar precisión y escribe el CSV y los resúmenes. No se conecta a PostgreSQL, no consulta precios en vivo y no modifica la aplicación. Desde dev:

    .\.venv\Scripts\python.exe calcular_costos_a06.py

Cambiar parámetros o precios requiere regenerar los resultados y actualizar las tablas explicativas de este documento. Las entradas se conservan en [parametros_A06.json](costos/parametros_A06.json) y precios_consultados_A06.json.

La comprobación del cálculo reproduce, al mes 60, las cuatro magnitudes de R4 de C-05 para ambos escenarios. También comprueba capacidad de disco, el total de 144 filas y que duplicar la reserva incremente el costo. Esto verifica aritmética y coherencia con C; no verifica rendimiento.

## Fuentes oficiales

- [AWS EC2: precios bajo demanda](https://aws.amazon.com/ec2/pricing/on-demand/). Los registros conservan el endpoint público de la tabla y su publicación.
- [AWS EBS: tarifas y ejemplo gp3](https://aws.amazon.com/ebs/pricing/). Referencia pendiente de reconfirmación regional.
- [Amazon S3: precios y unidades binarias](https://aws.amazon.com/s3/pricing/).
- [Microsoft: API pública de precios](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices). Se conservan SKU, unidad y región de cada registro.
- [Azure: discos y Premium SSD v2](https://azure.microsoft.com/en-us/pricing/details/managed-disks/).
- [Azure Blob: precios y unidades binarias](https://azure.microsoft.com/en-us/pricing/details/storage/blobs/).
- [AWS Object Lock](https://aws.amazon.com/s3/features/object-lock/) y [Azure WORM](https://learn.microsoft.com/en-us/azure/storage/blobs/immutable-storage-overview): configuración de inmutabilidad, no despliegue demostrado.

## Pendientes para cerrar A-06

Reconciliar el DDL y los tamaños de B con C-05; medir CPU/RAM/IOPS/red y definir cuántas celdas/regiones requiere la operación mundial; cotizar servicios auxiliares y guardia real; reconfirmar gp3 por región y completar una cotización reproducible del proveedor. Después se actualizan las cifras y se revisa la decisión económica con los mismos requisitos de disponibilidad y retención.
