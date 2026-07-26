# Rendimiento de reportes del backoffice

## Alcance

La carga compartida usa la clave:

`restaurantId|branchId|startBusinessDate|endBusinessDate|detailLevel`

El nivel `summary` carga ordenes y pagos. El nivel `full` agrega articulos y
construye el mismo resumen canonico que ya usaban los reportes.

La cache es solo de memoria, dura 60 segundos, comparte solicitudes simultaneas
y nunca conserva errores. Las correcciones de auditoria, cancelaciones de pago,
ediciones de compras y correcciones historicas de caja invalidan la cache
relacionada.

## Diagnostico anterior

Para un rango con `N` ordenes, Dashboard ejecutaba al menos:

- una lectura de todo el historial para el contenedor;
- otra lectura de todo el historial y `N` lecturas secuenciales de pagos;
- otra lectura de todo el historial, `N` lecturas secuenciales de articulos y
  `N` de pagos para el resumen canonico;
- `N` lecturas secuenciales adicionales de articulos para productos destacados.

Eso equivale a `3 + 4N` consultas, ademas de transferir el historial completo
tres veces. Con 115 ordenes son al menos 463 consultas.

La ruta nueva ejecuta cinco consultas de ordenes acotadas por campos de fecha
para conservar los fallbacks historicos, seguidas por `N` consultas de pagos y,
solo cuando el reporte lo necesita, `N` consultas de articulos. Ambas
subcolecciones se procesan en lotes de 15 y comparten un Future. Para 115
ordenes son 235 consultas en carga fria y cero en cache.

## Medicion

En modo debug cada carga imprime un bloque `REPORT_PERF` con:

- pantalla, sucursal y rango;
- documentos de ordenes, pagos y articulos;
- consultas Firestore;
- numero de ejecucion;
- uso de cache o Future compartido;
- milisegundos por fase y total.

La consulta comienza inmediatamente. El widget de carga conserva el umbral
visual de 300 ms y no impone una duracion minima.

## Tabla de referencia

El 25 de julio de 2026 se intento medir el proyecto con autenticacion anonima
de Firebase, igual que la aplicacion. Firestore respondio `403 Forbidden`, por
lo que este entorno no tuvo una sesion autorizada para consultar los datos. No
se incluyen tiempos inventados. Los conteos son deterministas a partir del
flujo anterior y el nuevo, donde `N` es la cantidad de ordenes del rango.

| Pantalla | Antes | Despues | Consultas antes | Consultas despues |
| --- | ---: | ---: | ---: | ---: |
| Dashboard de un dia | 30-50 s reportados | pendiente `REPORT_PERF` | `3 + 4N`, mas pendientes | `5 + 2N`; pendientes reutilizan bundle |
| Dashboard del mes | 30-50 s reportados | pendiente `REPORT_PERF` | `3 + 4N`, mas pendientes | `5 + 2N`; 0 en cache |
| Caja de un dia | 30-50 s reportados | pendiente `REPORT_PERF` | historial y N+1 de cancelaciones | `5 + 2N`; 0 en cache |
| Ventas por articulo del mes | 30-50 s reportados | pendiente `REPORT_PERF` | `3 + 3N` | `5 + 2N`; 0 en cache |
| Comparativo por hora | 30-50 s reportados | pendiente `REPORT_PERF` | historial y `N` pagos secuenciales | `5 + N`; 0 en cache |
| Finanzas del mes | 30-50 s reportados | pendiente `REPORT_PERF` | `3 + 3N`, mas catalogos financieros | `5 + 2N`, mas catalogos; 0 en cache |
| Auditoria del mes | 30-50 s reportados | pendiente `REPORT_PERF` | carga base mas `2N` secuenciales | `5 + 2N` en lotes; 0 en cache |
| Descuentos por dia | 30-50 s reportados | pendiente `REPORT_PERF` | `3 + 3N` | `5 + 2N`; 0 en cache |

Con 115 ordenes, Dashboard pasa de al menos 463 consultas a 235 en carga fria
y cero durante los siguientes 60 segundos.

La diferencia importante en Ventas no es el numero nominal de consultas, sino
que deja de transferir todo el historial y las 115 subconsultas ya no esperan
una a la otra.

## Captura obligatoria en ambiente conectado

1. Ejecutar `flutter run -d chrome`.
2. Abrir cada pantalla con los mismos filtros antes y despues.
3. Copiar los bloques `REPORT_PERF` de la consola.
4. Comparar Dashboard dia/mes, Caja dia, Ventas por articulo, comparativo por
   hora, Finanzas, Auditoria y Descuentos por dia.
5. Verificar que los totales y el CSV coincidan con los snapshots previos.
