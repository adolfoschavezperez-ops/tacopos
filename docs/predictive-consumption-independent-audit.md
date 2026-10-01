# Auditoría independiente: Inteligencia de consumo

Fuente auditada: `main@c0513a292b8f477dc0b716a3817a7f2e2eec7c22`, PR #3. Correcciones: `astra/audit-predictive-consumption`. Fecha: 2026-10-01.

## Alcance y evidencia

Se revisó el código desde las lecturas de Firestore en `TacoPosRepository.getPredictiveConsumptionAudit` y `_predictiveItemsByOrder`, pasando por `buildPredictiveConsumptionAudit`, hasta la pantalla y el CSV. Las pruebas de CI usan datos sintéticos. No se recibió acceso autenticado a Firestore de producción ni inventarios físicos; por tanto, **ningún número de discrepancia real de Aviación ha sido verificado**.

## Bugs confirmados en el commit base

1. **Fuga temporal.** `_trainingCycles` regresaba a ciclos posteriores al 28/09 cuando había menos de tres anteriores. `_selectFeatureKeys` también miraba ambos lados del corte. Una compra excesiva del periodo investigado podía entrar al ajuste de su propio coeficiente. Corrección: solo fechas de consumo cuyo fin sea anterior al inicio de investigación; si faltan datos, no se puntúa.
2. **Atribución histórica doble.** El repositorio unía `kitchenStockItemName` y `recipeItems` del item con la receta *actual*. Si la receta cambió, una misma venta podía atribuirse a carne o tortilla que no contenía entonces. Corrección: la receta actual solo se usa cuando no hay ningún ingrediente registrado en el item. Ese fallback sigue siendo una hipótesis, no evidencia histórica.
3. **Items legacy omitidos.** La consulta `collectionGroup('items').where('branchId', ...)` consideraba completo un pedido si devolvía *algún* item. Otros items del mismo pedido sin `branchId` quedaban invisibles. Corrección: leer todos los items de cada pedido ya filtrado por restaurante y sucursal. Esto mejora completitud y aumenta lecturas.
4. **Cortes de caja perdidos.** El mapa por `businessDate` conservaba solo la sesión más reciente. Corrección: sumar sesiones cerradas de la fecha, usando el valor vigente de cada documento. La corrección histórica del mismo documento no se suma dos veces.
5. **Score contaminado por caja.** `_anomalyScore` añadía diez puntos por faltante y diez por cancelaciones. Así un residual físico pequeño adquiría prioridad alta por señales contextuales. Corrección: el score usa solo Z y residual porcentual; faltante y cancelaciones permanecen en campos distintos.
6. **Falsa precisión.** Una MAD casi cero generaba intervalos estrechísimos y Z enorme. Además la UI llamaba “95%” al intervalo `1.96 * MAD` sin una calibración de cobertura. Corrección: piso heurístico del 10% de la compra media de entrenamiento, rótulo “banda heurística”, y sin alertas para matrices colineales, muestras insuficientes o coeficientes físicamente atípicos.
7. **Bistec laminado.** La coincidencia por substring confundía compras de bistec y bistec laminado. Corrección: claves de compra distintas y prioridad para el ingrediente guardado en la línea de venta.
8. **Orden cancelada con item legacy activo.** Un item marcado pagado en una orden cancelada podía entrar como venta. Corrección: la orden cancelada no aporta ventas; sus items con evidencia de cocina se clasifican aparte como cancelación potencial.

## Riesgos estadísticos

- La ecuación del ajuste es `compra_i = baseline * días_i + Σ(beta_producto * unidades_i) + error_i`. En realidad también intervienen `inventario_final - inventario_inicial`, merma, consumo interno y fechas de captura. Esos términos no son observables con las entradas actuales; los beta **no son identificables causalmente** solo por tener muchos registros.
- Las dos alineaciones (abastecimiento futuro y reposición pasada) se eligen con MAE de entrenamiento. Elegir la menor de dos métricas calculadas en la misma muestra sesga el error reportado a la baja. No hay validación cronológica fuera de muestra.
- Preferir ciclos con faltante de caja <= $20 selecciona una subpoblación. Puede esconder un patrón persistente o correlacionar ruido de caja con compras. No convierte esos ciclos en verdad física.
- `R²`, MAE y “confianza” se calculan en entrenamiento. Una calificación “Alta” es calidad de ajuste dentro de muestra, no probabilidad de acertar fuera de ella.
- El score 35/45/70 es prioridad heurística, no probabilidad de robo ni umbral estadístico calibrado. El piso del 10% también es conservador y heurístico.
- Un producto con nombre distinto pero ingrediente histórico igual, un cambio de porción, y tacos/gringas cuyos volúmenes se mueven juntos hacen difícil separar coeficientes. La rama ahora suprime alertas ante colinealidad marcada, pero eso no garantiza identificabilidad en todos los casos.

## Calidad de datos y falsos positivos

- **Inventario:** 2 kg comprados, 1 kg explicado por ventas y 1 kg guardado para mañana produce residual +1 kg sin pérdida alguna. El mismo registro de compras/ventas admite la explicación alternativa de 1 kg de merma. Ningún algoritmo puede distinguirlas sin medir stock/merma.
- `purchaseDate`, `businessDate` y fechas de captura pueden diferir. Un movimiento tardío altera el ciclo sin cambiar la operación física. Las órdenes legacy sin fechas completas usan varios timestamps; los límites UTC de esas consultas pueden omitir operaciones alrededor de medianoche local.
- Una receta actual aplicada a un item histórico sin snapshot puede atribuirle ingredientes equivocados. La pantalla no identifica por línea qué ventas usaron fallback; **pendiente** de instrumentación.
- Las ventas se toman una vez por item, de modo que un split payment no multiplica su cantidad. Sin embargo, la condición `item.paymentStatus == paid || order.status/paymentStatus == paid` no reconcilia pagos monetarios individuales: un estado legacy obsoleto puede introducir una venta no cobrada. Esto requiere casos reales y una política explícita para descuentos/comidas gratis.
- Las cancelaciones de cocina se reconocen por `sentToKitchenAt`, `cookingAt`, `readyAt` o `kitchenBatchId`. Una cancelación legacy que solo guarde `kitchenStatus` podría quedar fuera; no hay prueba con documentos reales antiguos.
- La clasificación de proveedores por `contains('noe')` o `contains('omar')` acepta variaciones Noé/Noe y nombres más largos, pero también puede aceptar homónimos. Debe contrastarse con IDs de proveedor reales.
- Tortillas compradas en kg producen gramos de compra por taco/gringa; **no** permiten inferir piezas por kilo ni número literal de tortillas sin una medición adicional.
- La conversión cocido = coeficiente crudo × rendimiento configurado/semilla. Solo el coeficiente crudo se ajusta; el cocido depende del perfil elegido, que puede no ser el histórico.
- El “equivalente estadístico” divide residual por una media ponderada de coeficientes. Con mezcla de tacos y gringas no representa un número literal de tacos faltantes.

## Performance y seguridad

- Se leen todas las compras del restaurante, sus items con una consulta por compra, cinco rangos de órdenes con posible solapamiento, los items con una consulta por orden (lotes de 15), recetas, rendimientos y sesiones de caja. Orden de consultas: **O(compras + órdenes)** y memoria proporcional a documentos históricos. No hay paginación ni caché efectiva en este método. Con años de datos puede tardar y costar mucho; debe medirse con conteos reales antes de extenderlo.
- El `collectionGroup('items')` original no tenía una regla/indexación equivalente clara y además era incompleto para documentos sin `branchId`. La rama elimina esa consulta, sin introducir índices nuevos.
- `getPredictiveConsumptionAudit` exige `_requireYieldProfitAdmin`; la vista es de Backoffice y el método solo ejecuta lecturas. No hay escrituras en la ruta del reporte. Las reglas Firestore vigentes permiten leer órdenes, compras, recetas y caja a cualquier usuario autenticado en el restaurante. La restricción de *este reporte* es del cliente, no una frontera de datos admin en Firestore; endurecerla requiere revisar todos los flujos existentes antes de desplegar reglas nuevas.
- La rama de auditoría no despliega Firestore ni publica el Backoffice.

## CSV

La exportación usa `toStringAsFixed` con punto decimal y `_csvCell` escapa comillas, comas y saltos de línea. La rama agrega unidad base y residual frente a ventas pagadas. **Todavía no permite reproducir el ajuste externamente**: faltan las compras y ventas línea a línea, la fuente de cada mapeo, el conjunto exacto de entrenamiento, parámetros efectivos y alternativas de alineación. No usarlo como paquete forense autosuficiente.

## Pruebas

El workflow `.github/workflows/audit-predictive-consumption.yml` ejecuta `flutter analyze`, `flutter test` y `flutter build web --release --base-href "/tacopos/" --no-wasm-dry-run` en cada push de la rama. Las pruebas sintéticas cubren 50 g/taco, compra alta desde 28/09, cancelaciones de cocina frente a ventas, caja contextual, lote abierto, fuga temporal, colinealidad, 300 g/taco, varios productos por carne, compras múltiples en un día, tortilla de maíz frente a harina, reposición pasada y días sin compras. No son sustituto de reconciliación con datos reales ni prueban el comportamiento de Firestore con documentos legacy auténticos.

## Conclusión permitida

En ciclos **cerrados**, con recetas históricas correctas, compras completas, stock inicial/final aproximadamente estable, mermas estables, porciones comparables y una matriz de ventas suficientemente variable, un residual alto sirve para **priorizar una revisión operativa**. La afirmación inicial es parcialmente válida bajo esos supuestos; la confianza se limita a una señal exploratoria, aún sin cobertura fuera de muestra calibrada.

## Conclusión prohibida

No se puede concluir cuántos tacos se vendieron fuera del sistema, cuántos gramos desaparecieron, quién fue responsable, que hubo fraude/robo, ni que un score sea su probabilidad. Tampoco se puede validar el nivel de confianza con el histórico real de Noé/Omar sin extraer y revisar esos datos.
