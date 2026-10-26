from datetime import datetime
from decimal import Decimal, InvalidOperation
from flask import Blueprint, abort, redirect, render_template, request, url_for
import psycopg
from psycopg.rows import dict_row
from modulos.conexion import obtener_conexion
from modulos.salas import entero_positivo
from modulos.seguridad import autorizar_cambio, auditar, leer_registro

precios_bp = Blueprint('precios', __name__)
DIAS = [(1, 'Lunes'), (2, 'Martes'), (3, 'Miércoles'), (4, 'Jueves'),
        (5, 'Viernes'), (6, 'Sábado'), (7, 'Domingo')]


def tarifa_unica(tarifas):
    if not tarifas:
        raise ValueError('No hay tarifa vigente para esa función, zona y categoría, o la función ya no está disponible.')
    if len(tarifas) != 1:
        raise ValueError('Hay varias tarifas vigentes; se debe corregir la configuración antes de cotizar.')
    return tarifas[0]


def consultar_tarifas(id_funcion, id_zona, id_categoria_entrada, instante):
    """Devuelve exactamente una tarifa vigente; falla si falta o es ambigua."""
    if instante.tzinfo is None or instante.utcoffset() is None:
        raise ValueError('El instante debe incluir zona horaria.')
    with obtener_conexion() as conexion:
        with conexion.cursor(row_factory=dict_row) as cursor:
            cursor.execute('''
                SELECT t.*, c.nombre AS categoria, c.requiere_acreditacion, z.nombre AS zona
                FROM tarifa t
                INNER JOIN funcion f ON f.id_funcion = t.id_funcion
                INNER JOIN zona z ON z.id_zona = t.id_zona AND z.id_sala = f.id_sala
                INNER JOIN categoria_entrada c ON c.id_categoria_entrada = t.id_categoria_entrada
                WHERE t.id_funcion = %s AND t.id_zona = %s AND t.id_categoria_entrada = %s
                  AND t.vigente_desde <= %s AND %s < t.vigente_hasta
                  AND f.activa = TRUE AND f.inicio > %s
            ''', (id_funcion, id_zona, id_categoria_entrada, instante, instante, instante))
            tarifas = cursor.fetchall()
    return tarifa_unica(tarifas)


def consultar_promociones(id_funcion, instante, id_zona=None, id_categoria_entrada=None):
    """2x1 vigentes al cotizar y aplicables al día local de la función."""
    if instante.tzinfo is None or instante.utcoffset() is None:
        raise ValueError('El instante debe incluir zona horaria.')
    with obtener_conexion() as conexion:
        with conexion.cursor(row_factory=dict_row) as cursor:
            cursor.execute('''
                SELECT p.*,
                    ARRAY(SELECT dia_semana FROM promocion_dia WHERE id_promocion=p.id_promocion ORDER BY dia_semana) AS dias,
                    ARRAY(SELECT pz.id_zona FROM promocion_zona pz INNER JOIN zona z ON z.id_zona=pz.id_zona
                          WHERE pz.id_promocion=p.id_promocion AND z.id_sala=f.id_sala ORDER BY pz.id_zona) AS zonas,
                    ARRAY(SELECT id_categoria_entrada FROM promocion_categoria WHERE id_promocion=p.id_promocion ORDER BY id_categoria_entrada) AS categorias
                FROM promocion p
                INNER JOIN funcion_promocion fp ON fp.id_promocion=p.id_promocion
                INNER JOIN funcion f ON f.id_funcion=fp.id_funcion
                INNER JOIN sala s ON s.id_sala=f.id_sala
                INNER JOIN cine c ON c.id_cine=s.id_cine
                WHERE fp.id_funcion=%s AND p.activa=TRUE AND p.tipo='2x1'
                  AND p.vigente_desde <= %s AND %s < p.vigente_hasta
                  AND f.activa=TRUE AND f.inicio > %s
                  AND EXISTS (SELECT 1 FROM promocion_dia pd WHERE pd.id_promocion=p.id_promocion
                              AND pd.dia_semana=EXTRACT(ISODOW FROM f.inicio AT TIME ZONE c.zona_horaria))
                  AND EXISTS (SELECT 1 FROM promocion_zona pz INNER JOIN zona z ON z.id_zona=pz.id_zona
                              WHERE pz.id_promocion=p.id_promocion AND z.id_sala=f.id_sala
                                AND (%s::int IS NULL OR z.id_zona=%s))
                  AND EXISTS (SELECT 1 FROM promocion_categoria pc WHERE pc.id_promocion=p.id_promocion
                                AND (%s::int IS NULL OR pc.id_categoria_entrada=%s))
                ORDER BY p.id_promocion
            ''', (id_funcion, instante, instante, instante, id_zona, id_zona,
                  id_categoria_entrada, id_categoria_entrada))
            return cursor.fetchall()


def contexto_funcion(id_funcion):
    with obtener_conexion() as conexion:
        with conexion.cursor(row_factory=dict_row) as cursor:
            cursor.execute('''
                SELECT f.*, p.titulo, s.nombre AS sala, c.nombre AS cine, c.ubicacion,
                       c.zona_horaria, f.inicio AT TIME ZONE c.zona_horaria AS inicio_local
                FROM funcion f INNER JOIN pelicula p ON p.id_pelicula=f.id_pelicula
                INNER JOIN sala s ON s.id_sala=f.id_sala INNER JOIN cine c ON c.id_cine=s.id_cine
                WHERE f.id_funcion=%s
            ''', (id_funcion,))
            funcion = cursor.fetchone()
            if funcion is None:
                abort(404)
            cursor.execute('SELECT id_zona,nombre FROM zona WHERE id_sala=%s ORDER BY nombre', (funcion['id_sala'],))
            zonas = cursor.fetchall()
            cursor.execute('SELECT * FROM categoria_entrada ORDER BY id_categoria_entrada')
            categorias = cursor.fetchall()
    return funcion, zonas, categorias


def fechas_locales(formulario):
    try:
        desde = datetime.fromisoformat(formulario.get('vigente_desde', ''))
        hasta = datetime.fromisoformat(formulario.get('vigente_hasta', ''))
        if desde.tzinfo or hasta.tzinfo or 'T' not in formulario.get('vigente_desde', '') or 'T' not in formulario.get('vigente_hasta', ''):
            raise ValueError()
        if hasta <= desde:
            raise ValueError()
    except ValueError:
        raise ValueError('Introduce una vigencia válida: desde debe ser anterior a hasta, en hora local del cine.')
    return desde, hasta


def registrar_tarifa(id_funcion, funcion, zonas, categorias):
    id_zona = entero_positivo(request.form.get('id_zona', ''))
    id_categoria = entero_positivo(request.form.get('id_categoria_entrada', ''))
    if id_zona not in {z['id_zona'] for z in zonas} or id_categoria not in {c['id_categoria_entrada'] for c in categorias}:
        raise ValueError('Selecciona una zona de esta sala y una categoría existente.')
    try:
        monto = Decimal(request.form.get('monto', ''))
        if not monto.is_finite() or monto < 0 or monto > Decimal('9999999999.99') or monto != monto.quantize(Decimal('0.01')):
            raise ValueError()
    except (InvalidOperation, ValueError):
        raise ValueError('El monto debe ser positivo o cero, con un máximo de dos decimales.')
    desde, hasta = fechas_locales(request.form)
    with obtener_conexion() as conexion:
        actor = autorizar_cambio(conexion, 'configurar_tarifas')
        fila = conexion.execute('''
            INSERT INTO tarifa(id_funcion,id_zona,id_categoria_entrada,monto,moneda,vigente_desde,vigente_hasta)
            VALUES (%s,%s,%s,%s,'USD',%s::timestamp AT TIME ZONE %s,%s::timestamp AT TIME ZONE %s)
            RETURNING id_tarifa
        ''', (id_funcion, id_zona, id_categoria, monto, desde, funcion['zona_horaria'], hasta, funcion['zona_horaria'])).fetchone()
        auditar(conexion, actor, 'configurar_tarifas', 'tarifa', fila[0],
                despues=leer_registro(conexion, 'tarifa', fila[0]))


def registrar_promocion(id_funcion, funcion, zonas, categorias):
    nombre = request.form.get('nombre', '').strip()
    condicion = request.form.get('condicion', '').strip()
    if not nombre or len(nombre) > 100 or not condicion:
        raise ValueError('Introduce un nombre de hasta 100 caracteres y la descripción de la promoción.')
    dias = set(request.form.getlist('dias'))
    zonas_elegidas = set(request.form.getlist('zonas'))
    categorias_elegidas = set(request.form.getlist('categorias'))
    if not dias or not dias.issubset({str(d) for d, _ in DIAS}):
        raise ValueError('Selecciona al menos un día válido para la función.')
    if not zonas_elegidas or not zonas_elegidas.issubset({str(z['id_zona']) for z in zonas}):
        raise ValueError('Selecciona al menos una zona de esta sala.')
    if not categorias_elegidas or not categorias_elegidas.issubset({str(c['id_categoria_entrada']) for c in categorias}):
        raise ValueError('Selecciona al menos una categoría existente.')
    desde, hasta = fechas_locales(request.form)
    with obtener_conexion() as conexion:
        actor = autorizar_cambio(conexion, 'configurar_tarifas')
        with conexion.cursor() as cursor:
            cursor.execute('''
                INSERT INTO promocion(nombre,tipo,condicion,vigente_desde,vigente_hasta,activa)
                VALUES (%s,'2x1',%s,%s::timestamp AT TIME ZONE %s,%s::timestamp AT TIME ZONE %s,TRUE)
                RETURNING id_promocion
            ''', (nombre, condicion, desde, funcion['zona_horaria'], hasta, funcion['zona_horaria']))
            identificador = cursor.fetchone()[0]
            cursor.execute('INSERT INTO funcion_promocion VALUES (%s,%s)', (id_funcion, identificador))
            cursor.executemany('INSERT INTO promocion_dia VALUES (%s,%s)', [(identificador, int(d)) for d in sorted(dias)])
            cursor.executemany('INSERT INTO promocion_zona VALUES (%s,%s)', [(identificador, int(z)) for z in sorted(zonas_elegidas)])
            cursor.executemany('INSERT INTO promocion_categoria VALUES (%s,%s)', [(identificador, int(c)) for c in sorted(categorias_elegidas)])
        despues = leer_registro(conexion, 'promocion', identificador)
        despues.update(id_funcion=id_funcion, dias=sorted(int(d) for d in dias),
                       zonas=sorted(int(z) for z in zonas_elegidas),
                       categorias=sorted(int(c) for c in categorias_elegidas))
        auditar(conexion, actor, 'configurar_tarifas', 'promocion', identificador, despues=despues)


@precios_bp.route('/funciones/<int:id_funcion>/precios', methods=['GET', 'POST'])
def configurar_precios(id_funcion):
    funcion, zonas, categorias = contexto_funcion(id_funcion)
    error = None
    if request.method == 'POST':
        try:
            accion = request.form.get('accion')
            if accion == 'tarifa':
                registrar_tarifa(id_funcion, funcion, zonas, categorias)
            elif accion == 'promocion':
                registrar_promocion(id_funcion, funcion, zonas, categorias)
            elif accion == 'categoria':
                nombre = request.form.get('nombre_categoria', '').strip()
                if not nombre or len(nombre) > 50:
                    raise ValueError('Introduce un nombre de categoría de hasta 50 caracteres.')
                with obtener_conexion() as conexion:
                    actor = autorizar_cambio(conexion, 'configurar_tarifas')
                    fila = conexion.execute('INSERT INTO categoria_entrada(nombre,requiere_acreditacion) VALUES (%s,%s) RETURNING id_categoria_entrada',
                                            (nombre, request.form.get('requiere_acreditacion') == 'on')).fetchone()
                    auditar(conexion, actor, 'configurar_tarifas', 'categoria_entrada', fila[0],
                            despues=leer_registro(conexion, 'categoria_entrada', fila[0]))
            else:
                raise ValueError('Selecciona una operación válida.')
            return redirect(url_for('precios.configurar_precios', id_funcion=id_funcion))
        except ValueError as ex:
            error = str(ex)
        except psycopg.errors.CheckViolation:
            error = 'No se pudo guardar: comprueba la vigencia y que no se superponga otra tarifa de esa zona y categoría.'
        except psycopg.errors.UniqueViolation:
            error = 'Ese nombre de categoría ya existe.'
        except (psycopg.IntegrityError, psycopg.DataError):
            error = 'No se pudo guardar. Revisa los datos y las referencias seleccionadas.'
        except (psycopg.errors.DeadlockDetected, psycopg.errors.SerializationFailure):
            error = 'Otra operación cambió la configuración. Inténtalo de nuevo.'
    with obtener_conexion() as conexion:
        with conexion.cursor(row_factory=dict_row) as cursor:
            cursor.execute('''
                SELECT t.*, z.nombre AS zona, c.nombre AS categoria,
                       t.vigente_desde AT TIME ZONE %s AS desde_local,
                       t.vigente_hasta AT TIME ZONE %s AS hasta_local
                FROM tarifa t INNER JOIN zona z ON z.id_zona=t.id_zona
                INNER JOIN categoria_entrada c ON c.id_categoria_entrada=t.id_categoria_entrada
                WHERE t.id_funcion=%s ORDER BY z.nombre,c.nombre,t.vigente_desde
            ''', (funcion['zona_horaria'], funcion['zona_horaria'], id_funcion))
            tarifas = cursor.fetchall()
            cursor.execute('''
                SELECT p.*, p.vigente_desde AT TIME ZONE %s AS desde_local,
                       p.vigente_hasta AT TIME ZONE %s AS hasta_local,
                       ARRAY(SELECT dia_semana FROM promocion_dia WHERE id_promocion=p.id_promocion ORDER BY dia_semana) AS dias,
                       ARRAY(SELECT z.nombre FROM promocion_zona pz INNER JOIN zona z ON z.id_zona=pz.id_zona WHERE pz.id_promocion=p.id_promocion ORDER BY z.nombre) AS zonas,
                       ARRAY(SELECT c.nombre FROM promocion_categoria pc INNER JOIN categoria_entrada c ON c.id_categoria_entrada=pc.id_categoria_entrada WHERE pc.id_promocion=p.id_promocion ORDER BY c.nombre) AS categorias
                FROM promocion p INNER JOIN funcion_promocion fp ON fp.id_promocion=p.id_promocion
                WHERE fp.id_funcion=%s ORDER BY p.id_promocion
            ''', (funcion['zona_horaria'], funcion['zona_horaria'], id_funcion))
            promociones = cursor.fetchall()
    return render_template('precios.html', funcion=funcion, zonas=zonas, categorias=categorias,
                           tarifas=tarifas, promociones=promociones, dias=DIAS, error=error,
                           datos=request.form), 400 if error else 200


@precios_bp.route('/cartelera/<int:id_funcion>/precios')
def ver_precios(id_funcion):
    funcion, zonas, categorias = contexto_funcion(id_funcion)
    with obtener_conexion() as conexion:
        instante, consultado = conexion.execute(
            "SELECT CURRENT_TIMESTAMP, CURRENT_TIMESTAMP AT TIME ZONE %s", (funcion['zona_horaria'],)
        ).fetchone()
        with conexion.cursor(row_factory=dict_row) as cursor:
            cursor.execute('''
                SELECT t.* FROM tarifa t
                INNER JOIN zona z ON z.id_zona=t.id_zona
                WHERE t.id_funcion=%s AND z.id_sala=%s
                  AND t.vigente_desde <= %s AND %s < t.vigente_hasta
            ''', (id_funcion, funcion['id_sala'], instante, instante))
            tarifas = cursor.fetchall()
    if not funcion['activa'] or funcion['inicio'] <= instante:
        abort(404)
    matriz = []
    for zona in zonas:
        fila = []
        for categoria in categorias:
            try:
                tarifa = tarifa_unica([t for t in tarifas if t['id_zona'] == zona['id_zona']
                                       and t['id_categoria_entrada'] == categoria['id_categoria_entrada']])
                fila.append({'tarifa': tarifa, 'error': None})
            except ValueError as ex:
                fila.append({'tarifa': None, 'error': str(ex)})
        matriz.append({'zona': zona, 'celdas': fila})
    promociones = consultar_promociones(id_funcion, instante)
    return render_template('precios_publicos.html', funcion=funcion, categorias=categorias,
                           zonas=zonas, matriz=matriz, promociones=promociones, dias=DIAS,
                           consultado=consultado.strftime('%d/%m/%Y %H:%M') + ' · ' + funcion['zona_horaria'])


@precios_bp.route('/tarifas')
def listar_precios():
    with obtener_conexion() as conexion:
        with conexion.cursor(row_factory=dict_row) as cursor:
            cursor.execute("""
                SELECT f.id_funcion,p.titulo,s.nombre AS sala,c.nombre AS cine,
                       f.inicio AT TIME ZONE c.zona_horaria AS inicio_local
                FROM funcion f INNER JOIN pelicula p ON p.id_pelicula=f.id_pelicula
                INNER JOIN sala s ON s.id_sala=f.id_sala
                INNER JOIN cine c ON c.id_cine=s.id_cine ORDER BY f.inicio DESC
            """)
            funciones = cursor.fetchall()
    return render_template('tarifas_funciones.html', funciones=funciones)
