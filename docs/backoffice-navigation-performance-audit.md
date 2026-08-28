# Backoffice: navigation and performance audit

Date: 2026-08-28

This audit covers the current Flutter Backoffice implementation. Part A is
implemented in the existing route and tab structure. Part B is read-only: no
query rewrite, pagination, index, cache, or Firestore change was made.

## Navigation result

The Backoffice opens feature screens with normal `Navigator.push` routes. The
purchase area keeps its tab states alive inside `TabBarView`; purchase and
payment details are dialogs, so closing them returns to the same tab state.
Filters are held by the state object of each tab, not in global storage.

| Area | Current behavior | Context after detail |
| --- | --- | --- |
| Cortes | One `businessDate` query after Buscar | Date and result remain; previous/next uses exactly one calendar day |
| Difference audit | Rendered from the selected Backoffice report | Parent report date range remains while the report is open |
| Compras | Tabs and details stay in the purchase screen | Supplier, dates, status, text filters and tab remain |
| CXP | Stateful tab with explicit search | Supplier, dates, status and results remain |
| Pagos | Stateful tab with explicit search | Supplier, dates, method and results remain |
| Supplier statement | Stateful tab, provider required for search | Selected provider remains |
| Suppliers | Stateful tab, details are dialogs | Text/status/payment filters remain |
| Finance | Stateful report screen | Date range and supplier remain while opening dashboard |

Long list tabs use `PageStorageKey`, preserving scroll position while the
screen remains in the current navigation session. No permanent persistence was
introduced. Explicit Buscar/Actualizar actions continue to create a fresh
request where the existing screen already did so.

### Cuts navigation

`CashAdminScreen` now has one date selector and these actions:

- opening the screen: 0 cut queries;
- selecting a date: 0 cut queries;
- Buscar: one stream filtered by `businessDate == selectedBusinessDate`;
- Dia anterior/siguiente: updates the date by exactly one day and starts only
  that exact-date stream;
- Limpiar: clears the selected date and result without querying;
- no match: `No se encontro corte para esta fecha.`;
- no automatic jump to a neighboring existing cut.

## Performance audit

The following counts describe Firestore operations implied by the code. A
document count is not guessed because it depends on production data; `N` means
the number of returned documents.

| Screen/action | Reads/listeners observed | Query shape | Risk |
| --- | --- | --- | --- |
| Dashboard principal open | Several live streams plus report futures | Orders/payments/products and cash data for the current date/range | High |
| Finance open | 7 live streams plus report and canonical-sales futures | Suppliers, purchases, supplier payments, partners, contributions, cash sessions and withdrawals; date filters only on some report/session queries | Critical |
| Cortes open | 0 | No stream until Buscar | Low |
| Cortes Buscar | 1 live listener per visible tab | `cashSessions.where(businessDate == date)` and withdrawals with the same date | Low |
| Compras open | 4 live catalog listeners | Suppliers, kitchen stock, partners, partner contributions; no limit | High |
| Compras/CXP/Pagos search | 1-2 live listeners plus local filtering | Purchases/payments ordered server-side, branch filtering in Dart | High |
| Estado de cuenta | 2 one-time queries after provider | Purchases and payments for the selected supplier | Medium |
| Purchase detail | 1 item listener/query | Purchase subcollection by purchase id | Low |
| Reports | Cached range bundle when the cache key matches | Orders, payments, sessions and optional items by business-date range | Medium |

### Collection-complete and N+1 findings

- `watchSuppliers`, `watchSupplierPurchases`, `watchSupplierPayments`, and
  catalog streams have no `limit`. They are live collection listeners and can
  grow with the restaurant.
- `getReportDataBundle` uses the report cache and date-keyed loaders, but a
  cache miss still loads the complete requested date range. This is expected
  for reports, not a collection-wide query.
- `activityLog` has collection-wide reads in administrative/repair paths; it
  is a high-growth risk and should receive a bounded, on-demand design later.
- Yield/cost report loaders read catalogs and then fetch purchase item
  subcollections in batches. This is a bounded batch N+1 pattern; it should
  not be changed in this navigation release.
- No new N+1 was introduced by the navigation changes.

### Futures, streams, and rebuilds

- `PurchaseAdminScreen` nests four catalog `StreamBuilder`s around all eight
  tabs. A catalog event rebuilds the tab view, although tab state is retained.
- `FinanceAdminScreen` nests streams and creates report futures from its build
  tree. Date or supplier changes intentionally refresh the report, but an
  unrelated rebuild can recreate the future and deserves measurement before
  changing it.
- `BackofficeScreen` uses section-dependent report builders. Its large tables
  rebuild with the active report state; this is a medium-to-high UI cost on
  large ranges.
- Most long lists are `ListView`-based. The purchase tabs now preserve their
  viewport, but they do not yet paginate.

### Catalogs and indexes

There is no shared global cache for suppliers, partners, employees, or kitchen
stock listeners. Report bundles and the cash schedule have local keyed caches.
The existing `firestore.indexes.json` contains supplier purchase indexes for
supplier/folio, supplier/createdAt, supplier/dueDate, supplier/purchaseDate,
and supplier payment indexes for supplier/paymentDate and purchase/paymentDate.
No index was added or deployed.

## Prioritized Phase 2 recommendations

1. Make Finance on-demand and retain a stable future per query key. Impact:
   highest read reduction; risk: medium; complexity: medium.
2. Split the purchase catalog scope from the active tab and load catalogs once
   per screen. Impact: fewer rebuilds/listener churn; risk: medium; complexity:
   medium.
3. Add server-side pagination for supplier purchases and supplier payments.
   Impact: high growth protection; risk: medium; complexity: medium.
4. Bound ActivityLog queries and load them only from an explicit audit action.
   Impact: high growth protection; risk: high because audit semantics matter;
   complexity: medium.
5. Measure and then isolate large Backoffice report tables. Impact: UI
   responsiveness; risk: medium; complexity: medium.

Do not change financial formulas, Firestore Rules, indexes, Android, or
production data as part of this audit.
