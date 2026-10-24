# Documentación de Entregable: Issue C-02 (#16)
**Módulo:** C — Acceso, Administración y Auditoría  
**Responsable:** Ian David Fernández Aguilar (`IanDavid1406`)  
**Título:** Implementación de Check-in con QR Único y Validación de Función y Horario  
**Reglas atendidas:** RN-14, RN-15, RN-16, RN-17  

---

## 1. Descripción de la Solución

Se ha diseñado e implementado la función almacenada transaccional `validar_y_consumir_ingreso_qr`, la cual permite simular y procesar el escaneo físico de entradas mediante código QR en los tótems o dispositivos de control de acceso a salas.

Esta solución garantiza la integridad transaccional (propiedades ACID) para evitar el ingreso doble, accesos fuera de la ventana de tiempo o uso de boletos anulados, manteniendo trazabilidad completa en la bitácora especializada `acceso_puerta_log`.

---

## 2. Cobertura de Reglas de Negocio

* **RN-14 (Validación única de entrada):** La función utiliza la cláusula `FOR UPDATE` sobre la tabla `boleto` al momento de la lectura. Esto congela la fila durante la transacción. Al otorgar el acceso, el estado del boleto cambia atómicamente de `'emitido'` a `'usado'`. Cualquier intento de escaneo posterior falla inmediatamente retornando el mensaje exacto exigido por la pauta: **"Entrada ya utilizada"**.
* **RN-15 (Verificación de función y horario):** La función valida que la función asociada al boleto coincida exactamente con la función de la sala donde está instalado el dispositivo de control de acceso. Si el usuario intenta usar un boleto para otra película o sala, se rechaza indicando el conflicto.
* **RN-16 (Tolerancia de ingreso):** Se evalúa que la estampa de tiempo (`CURRENT_TIMESTAMP`) se encuentre dentro del rango permitido:
  * **Apertura de puerta:** 30 minutos antes del inicio reprogramado (`inicio - 30 min`).
  * **Cierre de puerta:** 15 minutos después de haber iniciado la función (`inicio + 15 min`).
  * Fuera de este rango, el acceso es denegado y registrado.
* **RN-17 (Control de acceso por roles - RBAC):** Solo usuarios con el permiso `'validar_ingreso'` (por ejemplo, el rol `operador_sala` / ID 3) pueden invocar con éxito esta función.

---

## 3. Manejo de Bitácora y Trazabilidad

Cada intento de escaneo deja una huella inalterable en `acceso_puerta_log`:
* **Aceptado:** Registra fecha/hora, ID del boleto, operador, dispositivo y motivo ("Acceso concedido exitosamente").
* **Rechazado:** Registra fecha/hora, operador, dispositivo, resultado `'rechazado'` y la causa exacta (QR inexistente, entrada ya utilizada, función incorrecta, fuera de horario). Si el QR no existe en la base de datos, el campo `id_boleto` queda como `NULL`, garantizando que la bitácora no falle por restricciones de clave foránea.

---

## 4. Matriz de Pruebas y Casos de Verificación

| ID Caso | Precondición / Escenario | Comando / Invocación | Resultado Esperado | Estado |
| :--- | :--- | :--- | :--- | :--- |
| **CP-C02-01** | Boleto en estado `'emitido'` dentro del rango de tolerancia (-10 min del inicio). | `SELECT * FROM validar_y_consumir_ingreso_qr('4a44fb0a-6aa6-40a3-8210-5c752cf8511c', 1, 5, 'Totem_1');` | `exito = TRUE`, mensaje "Acceso concedido exitosamente". Estado pasa a `'usado'`. | **Aprobado** |
| **CP-C02-02** | Reescaneo inmediato del mismo boleto utilizado en CP-C02-01 (RN-14). | Misma instrucción previa. | `exito = FALSE`, mensaje **"Entrada ya utilizada"**. Intento registrado en log. | **Aprobado** |
| **CP-C02-03** | Escaneo de QR inexistente en la BD. | `SELECT * FROM validar_y_consumir_ingreso_qr('00000000-0000-0000-0000-000000000000', 1, 5, 'Totem_1');` | `exito = FALSE`, mensaje "Código QR no registrado...". | **Aprobado** |
| **CP-C02-04** | Boleto válido pero presentado en la función/sala equivocada (RN-15). | Invocación con `p_id_funcion_solicitada = 99`. | `exito = FALSE`, mensaje "El boleto corresponde a otra función...". | **Aprobado** |
| **CP-C02-05** | Escaneo fuera de la ventana de tolerancia (ej. 2 horas antes de la función) (RN-16). | Invocación sobre función futura fuera del rango. | `exito = FALSE`, mensaje "Ingreso muy temprano...". | **Aprobado** |
| **CP-C02-06** | Intento de validación ejecutado por un usuario cliente sin rol de operador. | Invocación pasando `p_id_usuario_operador = 1` (Cliente). | Excepción de SQL: "El usuario operador no posee permisos...". | **Aprobado** |