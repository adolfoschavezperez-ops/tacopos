import * as assert from "assert";
import {readFileSync} from "fs";
import {resolve} from "path";
import {computeOrderAggregates} from "../localOrderCapture";

interface FinanceCase {
  name: string;
  itemTotals: number[];
  payments: Array<Record<string, unknown>>;
  expected: Record<string, unknown>;
}

describe("local capture aggregate parity with the canonical Dart fixtures", () => {
  const fixturePath = resolve(__dirname, "../../../test/fixtures/local_capture_finance_cases.json");
  const cases = JSON.parse(readFileSync(fixturePath, "utf8")) as FinanceCase[];

  for (const testCase of cases) {
    it(testCase.name, () => {
      const result = computeOrderAggregates(
        testCase.itemTotals.map((total) => ({
          qty: 1,
          unitPrice: total,
          total,
          status: "active",
          kitchenStatus: "sent",
          paymentStatus: "pending",
          cancelStatus: "none",
        })),
        testCase.payments,
      );

      for (const field of [
        "total",
        "grossSubtotal",
        "netTotal",
        "discountAmount",
        "totalLiquidated",
        "paidTotal",
        "pendingTotal",
        "paymentStatus",
      ]) {
        assert.equal(result[field as keyof typeof result], testCase.expected[field], `${testCase.name}: ${field}`);
      }
    });
  }
});
