# Expense policies rollout

## Estado seguro por defecto

`settings/expensePolicies.expensePoliciesEnabled` queda en `false` si el
documento no existe. Con el kill switch apagado no se consume ledger y no hay
autoautorizacion.

## Rutas Firestore preparadas

- `restaurants/{restaurantId}/settings/expensePolicies`
- `restaurants/{restaurantId}/expensePolicies/{policyId}`
- `restaurants/{restaurantId}/expensePolicyUsage/{usageId}`
- `restaurants/{restaurantId}/cashWithdrawalRequests/{requestId}`

## Riesgo antes de activar

Las reglas actuales siguen permitiendo `validUpdate()` generico para clientes
autenticados en `cashWithdrawalRequests` y `expensePolicyUsage`. Eso no basta
para encender autoautorizacion en produccion: una tablet comprometida podria
intentar escribir estados privilegiados.

## Requisito antes de ON

Desplegar una de estas capas:

- Cloud Function callable que haga la transaccion de policy + usage + expense
  y reglas que impidan al cliente escribir `approved`, `autoApproved` o usage.
- O reglas Firestore estrictas con identidad confiable por usuario y permisos
  server-side para bloquear cambios privilegiados desde cliente.

## Activacion sugerida

1. Mantener feature OFF.
2. Desplegar reglas/functions seguras.
3. Crear 2 o 3 politicas piloto.
4. Activar una sola sucursal.
5. Monitorear gastos, usage y diferencias de caja varios dias.
6. Extender por politica/sucursal.
