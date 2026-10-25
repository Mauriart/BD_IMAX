from pathlib import Path
import re
RAIZ=Path(__file__).resolve().parent.parent
ARCHIVOS=[
 'docs/compa\u00f1eroA/instalacion_completa_A.sql',
 'docs/compa\u00f1eroC/sql_C-01.sql',
 'docs/compa\u00f1eraB/sql_20_ventas_tablas.sql',
 'docs/compa\u00f1eraB/sql_21_ventas_logs.sql',
 'docs/compa\u00f1eraB/sql_22_ventas_funciones.sql',
 'docs/compa\u00f1eroC/sql_C-03.sql',
 'docs/compa\u00f1eroC/sql_C-02.sql',
 'docs/compa\u00f1eroC/integracion_C-01_B.sql',
 'docs/integracion/operaciones_compartidas.sql',
 'docs/compa\u00f1eroA/proteccion_salas_A04.sql',
 'docs/compa\u00f1eroC/c04_reportes.sql']

def generar():
    partes=['-- Instalacion completa en una base vacia. No elimina ni reemplaza tablas existentes.','BEGIN;']
    for archivo in ARCHIVOS:
        texto=(RAIZ/archivo).read_text(encoding='utf-8-sig')
        texto=re.sub(r'(?m)^(BEGIN|COMMIT);\s*$','',texto)
        partes.extend(['-- Fuente: '+archivo,texto.strip()])
    partes.append('COMMIT;')
    return '\n\n'.join(partes)+'\n'

def generar_actualizacion():
    partes=["-- Actualizacion de una base con A y C-01, todavia sin tablas de B. Conserva sus datos.","BEGIN;", """DO $$
DECLARE tabla text;
BEGIN
    FOREACH tabla IN ARRAY ARRAY['cine','pelicula','sala','zona','asiento','funcion','tarifa','promocion_dia','promocion_zona','promocion_categoria','usuario','rol_permiso','solicitud_reembolso','solicitud_reembolso_detalle','acceso_puerta_log','admin_operacion_audit'] LOOP
        IF NOT EXISTS(SELECT 1 FROM pg_tables WHERE schemaname=current_schema() AND tablename=tabla) THEN
            RAISE EXCEPTION 'Falta %. La actualizacion requiere A y C-01 completos.',tabla;
        END IF;
    END LOOP;
    FOREACH tabla IN ARRAY ARRAY['compra','compra_detalle','reserva','boleto','pago','inventario_funcion','reembolso','reembolso_detalle','transaccion_log','asiento_auditoria_log'] LOOP
        IF EXISTS(SELECT 1 FROM pg_tables WHERE schemaname=current_schema() AND tablename=tabla) THEN
            RAISE EXCEPTION 'La tabla % de B ya existe. No se reemplaza ni se reinstala sobre datos existentes.',tabla;
        END IF;
    END LOOP;
END $$;
ALTER TABLE solicitud_reembolso ALTER COLUMN id_compra TYPE bigint;
ALTER TABLE solicitud_reembolso_detalle ALTER COLUMN id_boleto TYPE bigint;
ALTER TABLE acceso_puerta_log ALTER COLUMN id_boleto TYPE bigint;
"""]
    for archivo in ARCHIVOS[2:]:
        texto=(RAIZ/archivo).read_text(encoding='utf-8-sig')
        texto=re.sub(r'(?m)^(BEGIN|COMMIT);\s*$','',texto)
        partes.extend(['-- Fuente: '+archivo,texto.strip()])
    partes.extend(["DO $$ DECLARE f record; BEGIN FOR f IN SELECT id_funcion FROM funcion ORDER BY id_funcion LOOP PERFORM preparar_inventario(f.id_funcion); END LOOP; END $$;",'COMMIT;'])
    return '\n\n'.join(partes)+'\n'

if __name__=='__main__':
    destino=RAIZ/'docs'/'integracion'/'instalacion_completa.sql'
    destino.write_text(generar(),encoding='utf-8')
    (RAIZ/'docs'/'integracion'/'actualizar_base_A_C.sql').write_text(generar_actualizacion(),encoding='utf-8')
    print('Instalacion completa generada en docs/integracion/instalacion_completa.sql')
