# Guía de Ejecución Local y Evidencia de Validación — Fase 2

## 1. Ejecución local aislada (Firebase Emulator Suite)

```powershell
# 1. Compilar Backoffice 2.0 para ambiente LOCAL
flutter build web --target lib/main_backoffice.dart --dart-define=ENV=local --base-href "/" --no-wasm-dry-run

# 2. Iniciar emuladores en puertos exclusivos (no interfiere con Codex)
firebase emulators:start -c firebase.backoffice-v2.json --project demo-tacopos-backoffice-v2 --only auth,firestore,functions,hosting

# 3. Poblar datos sintéticos multi-tenant (rest_alpha y rest_beta)
node tools/seed_backoffice_v2_emulator.js
```

Abrir: `http://127.0.0.1:5050`  
Usuario sintético `rest_alpha`: `admin.alpha@tacopos-dev.local` / `DevPass2026!`

## 2. Resultados de pruebas ejecutadas

- `flutter analyze lib/main_backoffice.dart lib/backoffice_v2`: **0 errores, 0 warnings**.
- `flutter test test/backoffice_v2/`: **11/11 pruebas pasando** (`environment_guard_test.dart`, `backoffice_v2_ui_test.dart`).
- `flutter test test/canonical_sales_summary_test.dart test/operational_business_date_test.dart test/backoffice_admin_auth_test.dart`: **59/59 pruebas pasando**.
- `firebase emulators:exec -c firebase.backoffice-v2.json --project demo-tacopos-backoffice-v2-rules --only firestore "npx mocha --timeout 30000 test/firestore-rules/backoffice_v2_isolation.rules.test.js"`: **6/6 pruebas pasando** (aislamiento entre `rest_alpha` y `rest_beta`, sucursales `suc_centro` vs `suc_norte`, bloqueo anónimo y bloqueo de `collectionGroup('payments')`).

## 3. Auditoría de navegador (Chrome real)

- **LOCAL (`http://127.0.0.1:5050`):** `50` solicitudes totales, `0` errores de consola, `0` solicitudes a producción (`browser_audit_report.json`).
- **DEV (`https://tacopos-backoffice-dev.web.app`):** `0` errores de consola, `0` solicitudes a `tacopos-renovadev` o `github.io`.

## 4. Capturas de aprobación visual (`screenshots/`)

1. `01_login.png` — Inicio de sesión SaaS (split-screen, selector de tenant, indicador `LOCAL • EMULADOR`).
2. `02_dashboard.png` — Dashboard ejecutivo (KPIs, gráfica de barras, métodos de cobro, comparativo multi-sucursal).
3. `03_sales_list.png` — Listado de ventas con filtros integrados y paginación por cursores.
4. `04_sale_detail.png` — Detalle de venta (partidas, pagos y conciliación canónica).
5. `05_navigation_collapsed.png` — Menú lateral colapsado.
6. `06_dark_mode.png` — Modo oscuro completo.
7. `07_dev_hosting.png` — Despliegue en `https://tacopos-backoffice-dev.web.app` con indicador `DEV • tacopos-backoffice-dev`.
