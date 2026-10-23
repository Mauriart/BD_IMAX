# Datos y Operaciones Compartidos - Bloque C

## Identificadores Publicados

Los identificadores son enteros autoincrementables (`SERIAL`). Los componentes de los bloques A y B deben consumir los IDs devueltos por el sistema.

| Dato | Campos compartidos | Uso |
| --- | --- | --- |
| Rol | `id_rol`, `nombre` | Clasificación de acceso del usuario. |
| Usuario | `id_usuario`, `id_rol`, `nombre`, `correo`, `activo` | Actor de las transacciones. `password_hash` es privado de C. |
| Permiso | `id_rol`, `accion` | Matriz de permisos consultada por `autorizar_accion`. |
| Solicitud de reembolso | `id_solicitud_reembolso`, `id_compra`, `id_usuario_actor`, `estado` | B ejecuta la reversión contable/inventario de solicitudes aprobadas. |

## Función Común de Autorización

```sql
autorizar_accion(p_id_usuario INT, p_accion TEXT) → BOOLEAN
```

Devuelve `TRUE` únicamente si el usuario existe, se encuentra con `activo = TRUE` y su rol posee registrada la acción requerida. Devuelve `FALSE` para usuarios inactivos, inexistentes o acciones no mapeadas.

### Matriz de Acciones por Rol

| Acción | Roles Autorizados |
| --- | --- |
| `consultar_cartelera` | cliente, taquillero, operador_puerta, contador, administrador |
| `gestionar_catalogo` | administrador |
| `configurar_tarifas` | administrador |
| `ver_tarifas` | contador, administrador |
| `reservar_comprar` | cliente |
| `venta_presencial` | taquillero |
| `consultar_boletos_propios` | cliente |
| `consultar_boletos_venta` | taquillero |
| `consultar_boletos_admin` | administrador |
| `validar_ingreso` | operador_puerta |
| `solicitar_reembolso` | cliente, taquillero, administrador |
| `resolver_reembolso` | administrador |
| `ver_reportes_financieros` | contador, administrador |
| `ver_auditoria` | contador, administrador |
| `administrar_usuarios` | administrador |

## Registro de Auditoría Administrativa

Todas las transacciones sensibles del sistema realizadas por módulos A o B deben registrar una fila en `admin_operacion_audit` dentro de la **misma transacción de base de datos** en la que se modifica el recurso:

- `id_usuario_actor`
- `rol_al_actuar`
- `ip`
- `accion`
- `entidad`
- `id_entidad`
- `motivo` (Obligatorio, no vacío)
- `cambios` (JSONB)

## Integración Pendiente con Bloque B

- Integración de Foreign Keys hacia `compra` (`id_compra`) y `boleto` (`id_boleto`).
- Consumo del procedimiento `consumir_boleto` para validación de entradas.