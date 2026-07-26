# Auditoria de seguridad Firestore TacoPOS

Fecha: 2026-07-25
Proyecto Firebase: `tacopos-renovadev`

## Resumen ejecutivo

La app inicia siempre con Firebase Authentication anonima (`main.dart`) y despues valida la sesion operativa en cliente mediante empleados y PIN (`AppSession`, `employees`, `LivePresenceService`). Hoy no existe un documento confiable que vincule `request.auth.uid` con un empleado autorizado. Por eso las reglas incluidas en `firestore.rules` son una capa intermedia segura: exigen autenticacion, limitan el acceso a rutas conocidas dentro de `restaurants/{restaurantId}`, protegen `restaurantId` y `branchId` contra cambios en updates y cierran rutas desconocidas.

Para reglas definitivas por permisos se requiere agregar un vinculo servidor-verificable entre Auth UID y empleado.

## Inventario de accesos reales

Archivo principal: `lib/services/taco_pos_repository.dart`.
Servicios adicionales: `lib/services/live_presence_service.dart`, `lib/services/demo_seed_service.dart`, `lib/widgets/branded_scaffold.dart`.

| Ruta | Lecturas | Altas | Updates | Deletes | Batch/Tx | Collection group |
| --- | --- | --- | --- | --- | --- | --- |
| `restaurants` | `watchRestaurants`, marca visual | seed/default | default setup | no | batch | no |
| `restaurants/{r}/branches` | watch/list | `ensureDefaultRestaurant`, `saveBranch` | `toggleBranch` | no | batch | no |
| `restaurants/{r}/employees` | login, catalogo, permisos, descuentos | seed/admin/save | save/toggle/admin migration | reset operativo puede borrar | batch | no |
| `users` | no se encontro uso real en `lib` | no | no | no | no | no |
| `products` | menu, cocina, reportes | seed/save | save/toggle/stock links | reset puede borrar | batch | no |
| `productCategories` | menu/catalogo | seed/save/ensure | save | reset puede borrar | batch | no |
| `tables` | mesas, catalogo, estado operativo | seed/create | currentOrderId/status/cleanup/toggle | no | batch | no |
| `orderPlatforms` | pedidos para llevar/catalogo | seed/save | save/toggle | reset puede borrar | batch | no |
| `orders` | ventas, cocina, dashboard, reportes | abrir mesa/takeout | estados, totales, cancelaciones, pagos | reset puede borrar | batch/transaction | no |
| `orders/{id}/items` | orden/cocina/reportes | agregar items | cocina, cancelaciones, pagos | reset puede borrar | batch | no |
| `orders/{id}/payments` | pagos/reportes/cortes | cobrar | cancelar pago | no | batch | `collectionGroup('payments')` |
| `orders/{id}/kitchenBatches` | cocina | enviar cocina | no identificado | no | batch | no |
| `cashSessions` | caja, dashboard, historico | abrir caja | cerrar/recalcular | no | no | no |
| `cashWithdrawalRequests` | autorizaciones/caja | solicitar gasto | autorizar/rechazar | no | no | no |
| `kitchenStockItems` | control cocina/productos | crear | editar/stock link | no | batch | no |
| `kitchenSessions` | cocina/control/reportes | abrir cocina | cerrar cocina/entradas | no | batch | no |
| `kitchenSessions/{id}/items` | cierre/reportes | abrir cocina | cierre/entradas | no | batch | no |
| `kitchenSessions/{id}/additionalEntries` | control cocina | registrar entrada | no | no | batch | no |
| `activeSessions` | visor operativo | presencia | heartbeat/cleanup/logout | no | batch | no |
| `activityLog` | backoffice/visor | auditoria | no | no | batch/transaction | no |
| `suppliers` | compras/finanzas | guardar proveedor | editar proveedor | no | no | no |
| `purchaseItems` | compras | guardar concepto | editar concepto | no | no | no |
| `supplierPurchases` | compras/cxp | registrar compra | editar/cancelar/pagar | no | batch | no |
| `supplierPurchases/{id}/items` | compras/reportes | items compra | editar items | borrar en edicion | batch | no |
| `supplierPayments` | compras/cxp | pago proveedor | cancelar/editar ligas | no | batch | no |
| `partners` | socios/descuentos/finanzas | guardar socio | editar socio | no | batch | no |
| `partnerContributions` | finanzas | aportaciones | no identificado | no | no | no |
| `discountUsage` | descuentos | registrar uso | cancelar/deshacer uso | no | batch | no |
| `discountAuthorizationRequests` | autorizaciones/descuentos | crear solicitud | aprobar/rechazar/usar/deshacer | no | batch | no |
| `productStockOuts` | reportes cocina | crear agotado | liberar agotado | no | batch | no |
| `settings/discounts` | configuracion descuentos | set | set | no | no | no |

## Modelo de autorizacion actual

- `request.auth.uid`: existe porque `main.dart` hace `signInAnonymously()`.
- `employeeId`: se elige en login con PIN desde documentos `employees`.
- `AppSession`: mantiene empleado actual en memoria y aplica permisos por sucursal con `branchAccess`.
- `activeSessions`: registra presencia, pantalla y sucursal; lo escribe el cliente, por lo tanto no debe usarse como fuente de autorizacion de reglas.
- `restaurantId` y `branchId`: se guardan en la mayoria de documentos operativos y se filtran en repositorio.

No existe hoy un documento tipo `users/{uid}` o `restaurants/{r}/authUsers/{uid}` que asocie `request.auth.uid` con `employeeId`, permisos y sucursales. Sin ese vinculo, Firestore Rules no pueden distinguir un anonimo autorizado de otro anonimo autenticado.

## Cambio minimo requerido para reglas definitivas

Agregar una ruta escrita solo por un backend/admin confiable:

`restaurants/{restaurantId}/authUsers/{uid}`

Campos sugeridos:

- `employeeId`
- `active`
- `restaurantId`
- `branchAccess`: lista de sucursales permitidas
- `permissions`: mapa booleano con las mismas llaves de `Employee.currentPermissionsMap`
- `isSuperAdmin`
- `createdAt`, `updatedAt`

La app podria seguir usando PIN, pero despues de validar PIN debe existir o actualizarse ese vinculo mediante Cloud Function/Admin SDK, no directamente desde cliente.

## Reglas intermedias incluidas

Archivo: `firestore.rules`.

Garantias:

- `request.auth != null` para toda lectura/escritura.
- Solo rutas bajo `restaurants/{restaurantId}`.
- Rutas desconocidas bloqueadas.
- `restaurantId` en create debe coincidir con la ruta si el campo existe.
- `branchId` debe ser string si existe.
- `restaurantId` y `branchId` existentes no pueden cambiarse en updates.
- Deletes bloqueados salvo casos donde la app actual hace borrados operativos (`employees`, `orders/items`, `supplierPurchases/items`).
- Compatible con Auth anonimo actual.

Limitacion consciente:

- Todavia no aplica permisos por empleado porque no hay vinculo verificable `auth.uid -> employee`.

## Propuesta definitiva por permisos

Cuando exista `authUsers/{uid}`, las funciones de reglas deberian ser:

```rules
function profile(restaurantId) {
  return get(/databases/$(database)/documents/restaurants/$(restaurantId)/authUsers/$(request.auth.uid)).data;
}

function isEmployeeActive(restaurantId) {
  return request.auth != null && profile(restaurantId).active == true;
}

function can(restaurantId, permission) {
  return isEmployeeActive(restaurantId) &&
    (profile(restaurantId).isSuperAdmin == true ||
     profile(restaurantId).permissions[permission] == true);
}

function canBranch(restaurantId, branchId) {
  return isEmployeeActive(restaurantId) &&
    (profile(restaurantId).isSuperAdmin == true ||
     branchId in profile(restaurantId).branchAccess);
}
```

Matriz propuesta:

| Modulo | Lectura | Escritura |
| --- | --- | --- |
| Login empleados/branches | autenticado | solo admin backend o `canManageEmployees` |
| Mesero ordenes/items | `canTakeOrders` o `canCharge` en sucursal | `canTakeOrders` |
| Pagos | `canCharge` | `canCharge` |
| Cocina | `canViewKitchen` | `canOpenKitchen`, `canCloseKitchen`, `canApproveKitchenCancellations` |
| Caja | `canManageCash` | `canManageCash` |
| Retiros | `canManageCash` o `canAuthorizeCashWithdrawals` | solicitar: `canManageCash`; autorizar: `canAuthorizeCashWithdrawals` |
| Productos/categorias | lectura operativa autenticada | `canManageProducts` |
| Mesas/plataformas | lectura operativa autenticada | `canManageTables`, `canManagePlatforms` |
| Empleados | admin/manager | `canManageEmployees` o super admin |
| Compras/proveedores | `canViewPurchases`, `canViewAccountsPayable`, `canViewPurchaseReports` | `canRegisterPurchases`, `canManageSuppliers`, `canPaySuppliers` |
| Finanzas/socios | `canViewAdmin` o permisos financieros | admin/finanzas |
| Reportes | `canViewAdmin`, `canViewKitchenReports`, `canViewPurchaseReports` | sin escritura excepto activityLog |
| ActivityLog | lectura admin | create autenticado, update/delete denegado |

## Pruebas de reglas

Archivo: `test/firestore-rules/tacopos.rules.test.js`.

Casos cubiertos:

- no autenticado rechazado
- autenticado permitido en ruta conocida
- ruta desconocida rechazada
- `restaurantId` alterado rechazado
- cambio de `branchId` rechazado
- orden y pago validos permitidos
- caja y cocina validas permitidas
- caso documentado de permiso por empleado pendiente de vinculo UID

Ejecutar:

```powershell
npm install
npx firebase emulators:exec --only firestore "npm run test:rules"
```

## Despliegue manual

No se desplego automaticamente.

Para desplegar manualmente despues de revisar:

```powershell
firebase use tacopos-renovadev
firebase deploy --only firestore:rules,firestore:indexes
```

## Riesgos encontrados

- Auth anonimo autentica dispositivos, no empleados.
- PIN y permisos viven en cliente; Firestore Rules no pueden confiar en `AppSession`.
- `activeSessions` no debe autorizar porque el cliente lo escribe.
- Las reglas intermedias evitan Test Mode abierto, pero cualquier anonimo autenticado de la app conserva acceso amplio a rutas conocidas.
- Para seguridad granular real hace falta el vinculo `authUsers/{uid}` mantenido por backend/Admin SDK.
