"""Recalcular el escenario económico A-06 con datos locales; no consulta ni modifica la BD."""
import csv
import json
from decimal import Decimal, getcontext
from pathlib import Path

getcontext().prec = 32
D = Decimal
CARPETA = Path(__file__).resolve().parent.parent / 'docs' / 'compañeroA' / 'costos'


def cargar(nombre):
    return json.loads((CARPETA / nombre).read_text(encoding='utf-8'))


def almacenamiento(base, mes, crecimiento):
    sup = {r['nombre']: D(r['valor']) for r in base['tmp_sup']}
    factor = lambda m: (D(1) + crecimiento) ** ((m-1)//12)
    acumulado = sum((factor(m) for m in range(1,mes+1)), D(0))
    caliente = sum((factor(m) for m in range(max(1,mes-int(sup['meses_calientes'])+1),mes+1)), D(0))
    datos = sum((D(r['eventos_mes'])*D(r['b_heap']) for r in base['tmp_tab']),D(0)) / D(2**30)
    indices = sum((D(r['eventos_mes'])*D(r['b_idx']) for r in base['tmp_tab']),D(0)) / D(2**30)
    archivables = sum((D(r['eventos_mes'])*D(r['b_heap']) for r in base['tmp_tab'] if r['archivable']),D(0)) / D(2**30)
    primario = (datos+indices)*caliente*sup['factor_espacio_operativo']
    archivo = archivables*acumulado/sup['compresion_archivo']*sup['copias_archivo']
    backup = primario/sup['compresion_backup']*sup['fulls_retenidos']
    backup += (datos+indices)*factor(mes)*(D(1)+sup['multiplicador_wal'])/sup['compresion_backup']
    return {'primario_gib':primario, 'archivo_gib':archivo, 'backups_gib':backup,
            'replicas_gib':primario*sup['copias_calientes_extra']}


def tarifa(registros, clave):
    r=registros[clave]
    if 'precio' in r:
        return D(r['precio'])
    valor=r['registro']
    if 'retailPrice' in valor:
        return D(str(valor['retailPrice']))
    if 'pricePerUnit' in valor:
        return D(valor['pricePerUnit']['USD'])
    return D(valor['price'])


def calcular(base, parametros, registros, proveedor, crecimiento, multiplicador_reserva=D(1)):
    p=parametros
    horas=D(p['horas_mes'])
    n_db,n_app,n_proxy=(int(p[k]) for k in ('db_instancias','app_instancias','proxy_waf_instancias'))
    assert (n_db,n_app,n_proxy)==(3,4,2), 'Revisar también la distribución regional al cambiar la topología.'
    n_total=n_db+n_app+n_proxy
    if proveedor=='AWS':
        db,db_dr=tarifa(registros,'aws_m6i.4xlarge'),tarifa(registros,'aws_dr_m6i.4xlarge')
        app,app_dr=tarifa(registros,'aws_m6i.xlarge'),tarifa(registros,'aws_dr_m6i.xlarge')
        proxy,proxy_dr=tarifa(registros,'aws_m6i.large'),tarifa(registros,'aws_dr_m6i.large')
        datos_disco=D(p['datos_gib_por_db'])*3*tarifa(registros,'aws_datos')
        arranque=D(n_total*p['boot_gib'])*tarifa(registros,'aws_datos')
        obj,obj_dr=tarifa(registros,'aws_objeto'),tarifa(registros,'aws_objeto_dr')
    else:
        db,db_dr=tarifa(registros,'azure_db'),tarifa(registros,'azure_db_dr')
        app,app_dr=tarifa(registros,'azure_app'),tarifa(registros,'azure_app_dr')
        proxy,proxy_dr=tarifa(registros,'azure_proxy'),tarifa(registros,'azure_proxy_dr')
        datos_disco=D(p['datos_gib_por_db'])*horas*(2*tarifa(registros,'azure_datos')+tarifa(registros,'azure_datos_dr'))
        arranque=6*tarifa(registros,'azure_boot')+3*tarifa(registros,'azure_boot_dr')
        obj,obj_dr=tarifa(registros,'azure_objeto'),tarifa(registros,'azure_objeto_dr')
    computo=horas*(2*db+db_dr+3*app+app_dr+proxy+proxy_dr)
    inicial=D(p['implementacion_horas'])*D(p['implementacion_usd_hora'])+D(p['capacitacion_migracion_inicial'])
    sup={r['nombre']:D(r['valor']) for r in base['tmp_sup']}
    pagadas_mes=sup['boletos_mes']/sup['boletos_por_compra']
    creadas_mes=pagadas_mes/sup['conversion_reserva_a_pago']
    filas=[]
    for mes in range(1,int(p['meses'])+1):
        a=almacenamiento(base,mes,crecimiento)
        assert a['primario_gib'] <= D(p['datos_gib_por_db']), 'El disco de datos ya no alcanza.'
        factor=(1+crecimiento)**((mes-1)//12)
        objetos=a['archivo_gib']/2*(obj+obj_dr)+a['backups_gib']*obj_dr
        reserva=D(p['reserva_variable_mensual'])*factor*multiplicador_reserva
        nube=computo+datos_disco+arranque+objetos+reserva
        contingencia=nube*D(p['contingencia_nube'])
        personal=D(p['operacion_horas_mes'])*D(p['operacion_usd_hora'])
        filas.append(dict(proveedor=proveedor,mes=mes,crecimiento=str(crecimiento),
                          **a,computo=computo,
                          discos_datos=datos_disco,arranque=arranque,objetos=objetos,
                          reserva_variable=reserva,contingencia=contingencia,
                          operacion=personal,opex=nube+contingencia+personal,
                          compras_creadas=creadas_mes*factor,compras_pagadas=pagadas_mes*factor))
    opex=sum(r['opex'] for r in filas)
    creadas=sum(r['compras_creadas'] for r in filas)
    pagadas=sum(r['compras_pagadas'] for r in filas)
    tco=inicial+opex
    roi=[]
    for porcentaje in p['recuperacion_escenarios']:
        beneficios=pagadas*D(porcentaje)*D(p['margen_por_compra_recuperada'])
        roi.append({'fraccion_recuperada':D(porcentaje),'beneficio':beneficios,'roi_pct':100*(beneficios-tco)/tco})
    resumen=dict(proveedor=proveedor,crecimiento=str(crecimiento),inicial=inicial,
                 opex_36_meses=opex,tco_36_meses=tco,
                 costo_opex_por_millon_compras_creadas=opex/(creadas/D(1000000)),
                 costo_total_por_millon_compras_creadas=tco/(creadas/D(1000000)),
                 costo_total_por_millon_compras_pagadas=tco/(pagadas/D(1000000)),
                 recuperacion_equilibrio_pct=100*tco/(pagadas*D(p['margen_por_compra_recuperada'])),
                 roi=roi,
                 anios=[sum(r['opex'] for r in filas if (r['mes']-1)//12==i) for i in range(3)])
    return filas,resumen


def ejecutar():
    base,parametros,precios=cargar('base_C05.json'),cargar('parametros_A06.json'),cargar('precios_consultados_A06.json')['registros']
    # Verificación independiente contra R4 de C-05 al mes 60.
    for crecimiento,escenario in [(D(0),'A sin crecimiento'),(D('.1'),'B crecimiento anual')]:
        esperado=[r for r in base['tmp_res'] if r['escenario']==escenario]
        real=almacenamiento(base,60,crecimiento)
        for clave,fuentes in [
            ('primario_gib',['caliente_primario']),('replicas_gib',['caliente_replicas']),
            ('archivo_gib',['archivo_comprimido_copias']),
            ('backups_gib',['backup_fulls','backup_incrementales_30d','backup_wal_30d'])]:
            valor=sum((D(r[f]) for r in esperado for f in fuentes),D(0))
            assert abs(real[clave]-valor)<D('.00001'),(clave,real[clave],valor)
    filas,resumenes=[],[]
    for crecimiento in (D(0),D(parametros['crecimiento_anual'])):
        for proveedor in ('AWS','Azure'):
            mensual,resumen=calcular(base,parametros,precios,proveedor,crecimiento)
            _,estres=calcular(base,parametros,precios,proveedor,crecimiento,D(2))
            resumen['tco_reserva_variable_doble']=estres['tco_36_meses']
            assert estres['tco_36_meses']>resumen['tco_36_meses']
            filas.extend(mensual);resumenes.append(resumen)
    def formato(v):
        return format(v.quantize(D('.01')),'f') if isinstance(v,D) else v
    with (CARPETA/'proyeccion_mensual_A06.csv').open('w',encoding='utf-8',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(filas[0]))
        writer.writeheader()
        writer.writerows({k:formato(v) for k,v in fila.items()} for fila in filas)
    (CARPETA/'resumen_A06.json').write_text(json.dumps(resumenes,ensure_ascii=False,indent=2,default=lambda v:format(v,'.8f'))+'\n',encoding='utf-8')
    lineas=['# Resultados del escenario económico A-06','',
            'USD; [hipótesis y límites](../costos_A06.md). No es una cotización global.','',
            '| Escenario | Proveedor | Inicial | Año 1 OPEX | Año 2 OPEX | Año 3 OPEX | Total 36 meses |',
            '| --- | --- | ---: | ---: | ---: | ---: | ---: |']
    for r in resumenes:
        lineas.append('| '+('Sin crecimiento' if r['crecimiento']=='0' else '+10 % anual')+' | '+r['proveedor']+' | '+
                      ' | '.join(f'{v:,.2f}' for v in [r['inicial'],*r['anios'],r['tco_36_meses']])+' |')
    lineas += ['','Verificación: 2 escenarios a mes 60 coinciden con las cuatro magnitudes de R4 de C-05.',
               'Se calcularon 144 filas mensuales: 2 proveedores × 2 escenarios × 36 meses.','']
    (CARPETA/'resultados_A06.md').write_text('\n'.join(lineas),encoding='utf-8')
    print('\n'.join(lineas))


if __name__=='__main__':
    ejecutar()
