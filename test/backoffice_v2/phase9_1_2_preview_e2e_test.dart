import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tacopos/backoffice_v2/core/preview/preview_api_client.dart';
import 'package:tacopos/backoffice_v2/core/read_only_guard.dart';
import 'package:tacopos/backoffice_v2/features/cash/cash_repository.dart';
import 'package:tacopos/backoffice_v2/features/dashboard/dashboard_repository.dart';
import 'package:tacopos/backoffice_v2/features/employees/employees_repository.dart';
import 'package:tacopos/backoffice_v2/features/finance/finance_repository.dart';
import 'package:tacopos/backoffice_v2/features/sales/sales_repository.dart';
import 'package:tacopos/models/branch.dart';

void main() {
  group('Phase 9.1.2 — Real PreviewApiClient Integration (Zero Firestore Fallback)', () {
    PreviewApiClient buildMockPreviewClient({bool failWith503 = false}) {
      final mockHttp = MockClient((req) async {
        if (failWith503) {
          return http.Response(
            jsonEncode({'code': 'PREVIEW_UNAVAILABLE', 'message': 'API caída'}),
            503,
          );
        }
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final col = body['collection'] as String? ?? '';
        final sub = body['subcollection'] as String?;
        final path = req.url.path;

        if (path.endsWith('/v1/preview/doc') && col == 'orders') {
          return http.Response(
            jsonEncode({
              'doc': {
                'id': 'ord_preview_8000',
                'restaurantId': 'rest_alpha',
                'branchId': 'suc_centro',
                'businessDate': '2026-11-27',
                'status': 'paid',
                'paymentStatus': 'paid',
                'total': 8000.0,
                'paidTotal': 8000.0,
                'pendingTotal': 0.0,
                'createdAt': {'__previewTsMs': 1764244800000},
              },
            }),
            200,
          );
        }

        if (col == 'orders' && sub == null) {
          final start = body['startBusinessDate'] as String? ?? '';
          final isCurrent = start.compareTo('2026-11-27') >= 0;
          return http.Response(
            jsonEncode({
              'docs': isCurrent
                  ? [
                      {
                        'id': 'ord_preview_8000',
                        'restaurantId': 'rest_alpha',
                        'branchId': 'suc_centro',
                        'businessDate': '2026-11-27',
                        'status': 'paid',
                        'paymentStatus': 'paid',
                        'total': 8000.0,
                        'paidTotal': 8000.0,
                        'pendingTotal': 0.0,
                        'createdAt': {'__previewTsMs': 1764244800000},
                      },
                    ]
                  : <dynamic>[],
              'nextCursor': null,
              'hasMore': false,
              'isPartial': false,
              'usage': {'dataReads': isCurrent ? 1 : 0},
            }),
            200,
          );
        }

        if (col == 'orders' && sub == 'payments') {
          return http.Response(
            jsonEncode({
              'docs': [
                {
                  'id': 'pay_preview_1',
                  'orderId': 'ord_preview_8000',
                  'method': 'cash',
                  'status': 'paid',
                  'amount': 8000.0,
                  'chargedAmount': 8000.0,
                  'createdAt': {'__previewTsMs': 1764244800000},
                },
              ],
              'nextCursor': null,
              'hasMore': false,
              'isPartial': false,
              'usage': {'dataReads': 1},
            }),
            200,
          );
        }

        if (col == 'orders' && sub == 'items') {
          return http.Response(
            jsonEncode({
              'docs': [
                {
                  'id': 'item_1',
                  'productId': 'prod_1',
                  'productName': 'Orden Pastor',
                  'qty': 40,
                  'unitPrice': 200.0,
                  'total': 8000.0,
                  'status': 'paid',
                },
              ],
              'nextCursor': null,
              'hasMore': false,
              'isPartial': false,
              'usage': {'dataReads': 1},
            }),
            200,
          );
        }

        return http.Response(
          jsonEncode({
            'docs': <dynamic>[],
            'nextCursor': null,
            'hasMore': false,
            'isPartial': false,
            'usage': {'dataReads': 0},
          }),
          200,
        );
      });

      return PreviewApiClient(
        baseUrl: 'https://preview-api.local.test',
        httpClient: mockHttp,
        idTokenProvider: ({bool forceRefresh = false}) async => 'valid_id_token',
      );
    }

    test('Dashboard, Sales, Cash, and Finance compute \$8,000 exclusively from PreviewApiClient', () async {
      final client = buildMockPreviewClient();
      final dashboardRepo = DashboardRepository(previewClient: client);
      final salesRepo = SalesRepository(previewClient: client, isReadOnly: true);
      final cashRepo = CashRepository(previewClient: client, isReadOnly: true);
      final financeRepo = FinanceRepository(previewClient: client, isReadOnly: true);

      const branch = Branch(
        id: 'suc_centro',
        name: 'Centro',
        normalizedName: 'centro',
        address: '',
        phone: '',
        active: true,
        sortOrder: 1,
      );

      final dash = await dashboardRepo.loadDashboard(
        restaurantId: 'rest_alpha',
        startBusinessDate: '2026-11-27',
        endBusinessDate: '2026-11-27',
        branches: const [branch],
        branchId: 'suc_centro',
      );
      expect(dash.summary.netSales, 8000.0);
      expect(dash.summary.cashCollected, 8000.0);

      final salesPage = await salesRepo.fetchSalesPage(
        restaurantId: 'rest_alpha',
        startBusinessDate: '2026-11-27',
        endBusinessDate: '2026-11-27',
        branchId: 'suc_centro',
      );
      expect(salesPage.orders.length, 1);
      expect(salesPage.orders.first.total, 8000.0);

      final detail = await salesRepo.loadSaleDetail(
        restaurantId: 'rest_alpha',
        orderId: 'ord_preview_8000',
      );
      expect(detail, isNotNull);
      expect(detail!.payments.first.amount, 8000.0);

      final cashData = await cashRepo.loadCashDashboard(
        restaurantId: 'rest_alpha',
        startBusinessDate: '2026-11-27',
        endBusinessDate: '2026-11-27',
        branchId: 'suc_centro',
      );
      expect(cashData.sessions, isEmpty);

      final fin = await financeRepo.loadFinanceDashboard(
        restaurantId: 'rest_alpha',
        startDate: DateTime(2026, 11, 27),
        endDate: DateTime(2026, 11, 27),
        branchId: 'suc_centro',
      );
      expect(fin.summary.netSales, 8000.0);
    });

    test('API failure throws PreviewApiException with zero fallback to Firestore', () async {
      final failingClient = buildMockPreviewClient(failWith503: true);
      final dashboardRepo = DashboardRepository(previewClient: failingClient);

      expect(
        () => dashboardRepo.loadDashboard(
          restaurantId: 'rest_alpha',
          startBusinessDate: '2026-11-27',
          endBusinessDate: '2026-11-27',
          branches: const [],
        ),
        throwsA(isA<PreviewApiException>()),
      );
    });

    test('All write repositories reject mutations with BackofficeReadOnlyException when isReadOnly=true', () async {
      final salesRepo = SalesRepository(isReadOnly: true);
      final cashRepo = CashRepository(isReadOnly: true);
      final financeRepo = FinanceRepository(isReadOnly: true);
      final empRepo = EmployeesRepository(isReadOnly: true);

      await expectLater(
        () => salesRepo.cancelCustomerPayment(
          restaurantId: 'rest_alpha',
          orderId: 'o1',
          paymentId: 'p1',
          reason: 'Prueba',
          employeeId: 'e1',
          employeeName: 'Admin',
        ),
        throwsA(isA<BackofficeReadOnlyException>()),
      );
      await expectLater(
        () => cashRepo.addHistoricalCashExpense(
          restaurantId: 'rest_alpha',
          sessionId: 's1',
          amount: 100,
          reason: 'Prueba',
          employeeId: 'e1',
          employeeName: 'Admin',
        ),
        throwsA(isA<BackofficeReadOnlyException>()),
      );
      await expectLater(
        () => financeRepo.savePartner(
          restaurantId: 'rest_alpha',
          name: 'Socio',
          ownershipPercent: 50,
        ),
        throwsA(isA<BackofficeReadOnlyException>()),
      );
      await expectLater(
        () => empRepo.saveEmployee(
          restaurantId: 'rest_alpha',
          existingEmployeeId: null,
          name: 'Nuevo',
          active: true,
          isSuperAdmin: false,
          permissions: const {},
          assignedBranches: const [],
          actorEmployeeId: 'e1',
          actorEmployeeName: 'Admin',
          actorIsSuperAdmin: true,
        ),
        throwsA(isA<BackofficeReadOnlyException>()),
      );
    });
  });
}
