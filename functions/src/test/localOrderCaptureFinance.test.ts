import * as assert from "assert";
import * as fs from "fs";
import * as path from "path";
import {computeOrderAggregates} from "../localOrderCapture";

interface FinanceCase {
  name: string;
  itemTotals: number[];
  payments: Array<Record<string, unknown>>;
  expected: Record<string, unknown>;
}

describe("local capture aggregate parity fixtures", () => {
  const fixturePath = path.resolve(process.cwd(), "../test/fixtures/local_capture_finance_cases.json");
  const cases = JSON.parse(fs.readFileSync(fixturePath, "utf8")) as FinanceCase[];

  for (const testCase of cases) {
    it(testCase.name, () => {
      const result = computeOrderAggregates(
        testCase.itemTotals.map((total) => ({qty: 1, total, unitPrice: total, status: "active"})),
        testCase.payments,
      ) as Record<string, unknown>;
      for (const [key, expected] of Object.entries(testCase.expected)) {
        assert.equal(result[key], expected, `${testCase.name}: ${key}`);
      }
    });
  }
});
