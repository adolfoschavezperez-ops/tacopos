const http = require("http");
const {spawn} = require("child_process");
const path = require("path");
const admin = require("../functions/node_modules/firebase-admin");

const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "";
if (!projectId.startsWith("demo-") ||
    process.env.FIRESTORE_EMULATOR_HOST !== "127.0.0.1:8080" ||
    process.env.FIREBASE_AUTH_EMULATOR_HOST !== "127.0.0.1:9099") {
  throw new Error(
    `Refusing Android integration test: project=${projectId || "unset"}, ` +
      `firestore=${process.env.FIRESTORE_EMULATOR_HOST || "unset"}, ` +
      `auth=${process.env.FIREBASE_AUTH_EMULATOR_HOST || "unset"}. ` +
      "Run inside Firebase Emulator Suite with a demo-* project.",
  );
}

admin.initializeApp({projectId});
const db = admin.firestore();
const auth = admin.auth();
const restaurantId = "local-capture-demo";
const branchId = "branch-demo";
const orderId = "android-order";
const uid = "local-capture-android-test";
const employeeId = "waiter-demo";
const root = db.collection("restaurants").doc(restaurantId);

async function seed() {
  await db.recursiveDelete(root);
  try {
    await auth.deleteUser(uid);
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
  }
  await auth.createUser({
    uid,
    email: "capture-test@example.invalid",
    password: "emulator-only-password",
  });
  await Promise.all([
    root.collection("devices").doc(uid).set({
      active: true,
      restaurantId,
      branchId,
      branchName: "Demo",
      employeeId,
    }),
    root.collection("employees").doc(employeeId).set({
      name: "Mesero Demo",
      active: true,
      canTakeOrders: true,
      branchAccess: [],
    }),
    root.collection("products").doc("taco-demo").set({
      name: "Taco demo",
      categoryId: "tacos",
      categoryName: "Tacos",
      active: true,
      sendToKitchen: true,
      affectsKitchenStock: false,
      price: 12,
      recipeItems: [],
    }),
    root.collection("branches").doc(branchId).set({name: "Demo"}),
    root.collection("tables").doc("table-demo").set({
      name: "Mesa demo",
      status: "occupied",
      currentOrderId: orderId,
      branchId,
    }),
    root.collection("orders").doc(orderId).set({
      restaurantId,
      restaurantName: "Demo",
      branchId,
      branchName: "Demo",
      tableId: "table-demo",
      tableName: "Mesa demo",
      tableIds: ["table-demo"],
      tableNames: ["Mesa demo"],
      orderType: "dine_in",
      status: "open",
      kitchenStatus: "pending",
      paymentStatus: "pending",
      total: 0,
      grossSubtotal: 0,
      netTotal: 0,
      paidTotal: 0,
      pendingTotal: 0,
      captureRevision: 0,
      businessDate: "2026-11-24",
    }),
  ]);
}

async function main() {
  await seed();
  let droppedSubmitResponses = 0;
  const proxy = http.createServer((incoming, outgoing) => {
    if (incoming.url === "/__status") {
      outgoing.writeHead(200, {"content-type": "application/json"});
      outgoing.end(JSON.stringify({droppedSubmitResponses}));
      return;
    }
    const chunks = [];
    incoming.on("data", (chunk) => chunks.push(chunk));
    incoming.on("end", () => {
      const body = Buffer.concat(chunks);
      const dropResponse = incoming.method === "POST" &&
        incoming.url.includes("/submitLocalOrderCapture") &&
        droppedSubmitResponses === 0;
      const upstream = http.request({
        hostname: "127.0.0.1",
        port: 5001,
        path: incoming.url,
        method: incoming.method,
        headers: incoming.headers,
      }, (response) => {
        if (dropResponse) {
          response.resume();
          response.on("end", () => {
            droppedSubmitResponses++;
            outgoing.destroy();
          });
          return;
        }
        outgoing.writeHead(response.statusCode || 502, response.headers);
        response.pipe(outgoing);
      });
      upstream.on("error", (error) => {
        if (!outgoing.destroyed) {
          outgoing.writeHead(502, {"content-type": "text/plain"});
          outgoing.end(error.message);
        }
      });
      upstream.end(body);
    });
  });

  await new Promise((resolve, reject) => {
    proxy.once("error", reject);
    proxy.listen(5002, "0.0.0.0", resolve);
  });

  const flutter = spawn("flutter", [
    "test",
    "integration_test/local_capture_android_emulator_test.dart",
    "-d",
    "emulator-5554",
    "--dart-define=TACOPOS_EMULATOR_PROJECT_ID=demo-tacopos-local-capture",
    "--dart-define=TACOPOS_EMULATOR_HOST=10.0.2.2",
    "--dart-define=TACOPOS_FUNCTIONS_EMULATOR_PORT=5002",
  ], {
    cwd: path.resolve(__dirname, ".."),
    stdio: "inherit",
    shell: true,
  });
  const exitCode = await new Promise((resolve, reject) => {
    flutter.once("error", reject);
    flutter.once("exit", (code) => resolve(code ?? 1));
  });
  proxy.close();
  if (exitCode !== 0) process.exit(exitCode);
  if (droppedSubmitResponses !== 1) {
    throw new Error(`Expected one committed callable response to be dropped, got ${droppedSubmitResponses}.`);
  }
  console.log("Android integration verified one committed callable response loss and same-ID recovery.");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
