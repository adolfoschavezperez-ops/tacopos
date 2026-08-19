import * as assert from "assert";
import * as admin from "firebase-admin";
import {backofficePinLoginCore} from "../index";

const db = admin.firestore();
const restaurantId = "pin-restaurant";
let auth: FakeAuth;

describe("backoffice PIN login", () => {
  beforeEach(async () => {
    auth = new FakeAuth();
    await admin.firestore().recursiveDelete(restaurant());
  });

  it("usuario valido con PIN valido y admin genera custom token", async () => {
    await seedEmployee("admin", {pin: "1234", canViewAdmin: true});

    const result = await login();

    assert.equal(result.uid, "bo_pin-restaurant_admin");
    assert.equal(result.customToken, "token:bo_pin-restaurant_admin");
    assert.equal(auth.createdUids.length, 1);
    const authUser = await restaurant().collection("authUsers").doc(result.uid).get();
    assert.equal(authUser.data()?.active, true);
    assert.equal(authUser.data()?.permissions.canViewAdmin, true);
    assert.equal(authUser.data()?.pin, undefined);
  });

  it("PIN incorrecto no genera token", async () => {
    await seedEmployee("admin", {pin: "1234", canViewAdmin: true});

    await assert.rejects(() => login({pin: "0000"}), /Usuario o PIN incorrectos/);
    assert.equal(auth.createdUids.length, 0);
  });

  it("usuario inexistente no revela detalle", async () => {
    await assert.rejects(() => login(), /Usuario o PIN incorrectos/);
  });

  it("usuario inactivo no entra", async () => {
    await seedEmployee("admin", {pin: "1234", active: false, canViewAdmin: true});

    await assert.rejects(() => login(), /Usuario o PIN incorrectos/);
  });

  it("usuario sin Backoffice no recibe sesion admin", async () => {
    await seedEmployee("waiter", {pin: "1234", canTakeOrders: true});

    await assert.rejects(
      () => login({employeeId: "waiter"}),
      /No tienes permisos para acceder al Backoffice/,
    );
  });

  it("UID es estable y login repetido no duplica auth user", async () => {
    await seedEmployee("admin", {pin: "1234", canViewAdmin: true});

    const first = await login();
    const second = await login();

    assert.equal(second.uid, first.uid);
    assert.deepEqual(auth.createdUids, [first.uid]);
    const snapshot = await restaurant().collection("authUsers").get();
    assert.equal(snapshot.size, 1);
  });

  it("rol no puede falsificarse desde cliente", async () => {
    await seedEmployee("waiter", {pin: "1234", canTakeOrders: true});

    await assert.rejects(
      () => login({employeeId: "waiter", isSuperAdmin: true}),
      /No tienes permisos para acceder al Backoffice/,
    );
  });

  it("cross-restaurant queda bloqueado", async () => {
    await db.collection("restaurants").doc("other").collection("employees").doc("admin").set({
      name: "Admin",
      active: true,
      pin: "1234",
      canViewAdmin: true,
    });

    await assert.rejects(() => login(), /Usuario o PIN incorrectos/);
  });

  it("rate limiting bloquea despues de fallos repetidos", async () => {
    await seedEmployee("admin", {pin: "1234", canViewAdmin: true});

    for (let index = 0; index < 5; index += 1) {
      await assert.rejects(() => login({pin: "bad"}), /Usuario o PIN incorrectos/);
    }
    await assert.rejects(() => login({pin: "bad"}), /Demasiados intentos/);
  });

  it("PIN nunca aparece en respuesta ni authUsers", async () => {
    await seedEmployee("admin", {pin: "9876", canViewAdmin: true});

    const result = await login({pin: "9876"});
    const serialized = JSON.stringify(result);
    const authUser = await restaurant().collection("authUsers").doc(result.uid).get();

    assert.equal(serialized.includes("9876"), false);
    assert.equal(JSON.stringify(authUser.data()).includes("9876"), false);
  });
});

function login(overrides: Record<string, unknown> = {}) {
  return backofficePinLoginCore(db, auth, {
    restaurantId,
    employeeId: "admin",
    pin: "1234",
    ...overrides,
  }, "127.0.0.1") as Promise<Record<string, string>>;
}

async function seedEmployee(employeeId: string, data: Record<string, unknown>) {
  await restaurant().collection("employees").doc(employeeId).set({
    name: employeeId === "admin" ? "Admin" : "Mesero",
    active: true,
    ...data,
  });
}

function restaurant() {
  return db.collection("restaurants").doc(restaurantId);
}

class FakeAuth {
  readonly createdUids: string[] = [];
  private readonly users = new Set<string>();

  async getUser(uid: string) {
    if (!this.users.has(uid)) {
      const error = new Error("not found") as Error & {code?: string};
      error.code = "auth/user-not-found";
      throw error;
    }
    return {uid, disabled: false, displayName: "Admin"} as admin.auth.UserRecord;
  }

  async createUser(properties: admin.auth.CreateRequest) {
    const uid = properties.uid ?? "";
    this.users.add(uid);
    this.createdUids.push(uid);
    return {uid, disabled: false, displayName: properties.displayName} as admin.auth.UserRecord;
  }

  async updateUser(uid: string) {
    this.users.add(uid);
    return {uid, disabled: false, displayName: "Admin"} as admin.auth.UserRecord;
  }

  async createCustomToken(uid: string) {
    return `token:${uid}`;
  }
}
