import * as assert from "assert";
import * as admin from "firebase-admin";
import {backofficePinLoginCore, listBackofficeUsersCore} from "../index";

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

  it("PIN string correcto conserva la semantica original", async () => {
    await seedEmployee("admin", {pin: "1234", canViewAdmin: true});

    const result = await login({pin: "1234"});

    assert.equal(result.uid, "bo_pin-restaurant_admin");
    assert.equal(result.customToken, "token:bo_pin-restaurant_admin");
  });

  it("PIN con ceros iniciales no se convierte a numero", async () => {
    await seedEmployee("admin", {pin: "0123", canViewAdmin: true});

    const result = await login({pin: "0123"});

    assert.equal(result.uid, "bo_pin-restaurant_admin");
    await assert.rejects(() => login({pin: "123"}), /Usuario o PIN incorrectos/);
  });

  it("PIN numerico legacy replica modelo original y no autentica", async () => {
    await seedEmployee("admin", {pin: 1234, canViewAdmin: true});

    await assert.rejects(() => login({pin: "1234"}), /Usuario o PIN incorrectos/);
    assert.equal(auth.createdUids.length, 0);
  });

  it("dos usuarios validan solo su propio PIN", async () => {
    await seedEmployee("admin", {pin: "1111", canViewAdmin: true});
    await seedEmployee("caja", {pin: "2222", canAuthorizeCashWithdrawals: true});

    const adminResult = await login({employeeId: "admin", pin: "1111"});
    const cajaResult = await login({employeeId: "caja", pin: "2222"});

    assert.equal(adminResult.uid, "bo_pin-restaurant_admin");
    assert.equal(cajaResult.uid, "bo_pin-restaurant_caja");
    await assert.rejects(
      () => login({employeeId: "admin", pin: "2222"}),
      /Usuario o PIN incorrectos/,
    );
  });

  it("usuario escrito puede resolver empleado por nombre desde backend", async () => {
    await seedEmployee("adolfo", {
      name: "Adolfo",
      pin: "1234",
      canViewAdmin: true,
    });

    const result = await login({employeeId: undefined, usuario: "Adolfo"});

    assert.equal(result.uid, "bo_pin-restaurant_adolfo");
    assert.equal(result.customToken, "token:bo_pin-restaurant_adolfo");
  });

  it("usuario escrito no requiere id exacto si coincide en minusculas", async () => {
    await seedEmployee("adolfo", {pin: "1234", canViewAdmin: true});

    const result = await login({employeeId: "Adolfo"});

    assert.equal(result.uid, "bo_pin-restaurant_adolfo");
  });

  it("PIN incorrecto no genera token", async () => {
    await seedEmployee("admin", {pin: "1234", canViewAdmin: true});

    await assert.rejects(() => login({pin: "0000"}), /Usuario o PIN incorrectos/);
    assert.equal(auth.createdUids.length, 0);
    const authUsers = await restaurant().collection("authUsers").get();
    assert.equal(authUsers.size, 0);
  });

  it("usuario inexistente no revela detalle", async () => {
    await assert.rejects(() => login(), /Usuario o PIN incorrectos/);
    assert.equal(auth.createdUids.length, 0);
  });

  it("usuario inactivo no entra", async () => {
    await seedEmployee("admin", {pin: "1234", active: false, canViewAdmin: true});

    await assert.rejects(() => login(), /Usuario o PIN incorrectos/);
    assert.equal(auth.createdUids.length, 0);
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

  it("diagnostico no registra PINs en texto", () => {
    const source = require("fs").readFileSync("src/index.ts", "utf8") as string;

    assert.equal(source.includes("receivedPinValue"), false);
    assert.equal(source.includes("storedPinValue"), false);
    assert.equal(source.includes("pin: raw.pin"), false);
    assert.equal(source.includes("pin: employee.pin"), false);
  });
});

describe("listBackofficeUsers", () => {
  beforeEach(async () => {
    await admin.firestore().recursiveDelete(restaurant());
  });

  it("devuelve unicamente usuarios elegibles y activos", async () => {
    await seedEmployee("admin", {name: "Admin", pin: "1234", canViewAdmin: true});
    await seedEmployee("cash", {name: "Caja", pin: "2222", canAuthorizeCashWithdrawals: true});
    await seedEmployee("waiter", {name: "Mesero", pin: "3333", canTakeOrders: true});
    await seedEmployee("inactive", {name: "Inactivo", pin: "4444", active: false, canViewAdmin: true});

    const result = await listUsers();

    assert.deepEqual(result.users, [
      {id: "admin", displayName: "Admin"},
      {id: "cash", displayName: "Caja"},
    ]);
  });

  it("employeeId de la lista es el document id que consume login", async () => {
    await seedEmployee("empleado-A", {name: "Usuario A", pin: "1212", canViewAdmin: true});

    const result = await listUsers();
    const selected = result.users.find((user) => user.displayName === "Usuario A");
    assert.equal(selected?.id, "empleado-A");

    const loginResult = await login({employeeId: selected?.id, pin: "1212"});
    assert.equal(loginResult.uid, "bo_pin-restaurant_empleado-a");
  });

  it("no devuelve PIN hash email authUid ni permisos", async () => {
    await seedEmployee("admin", {
      name: "Admin",
      pin: "1234",
      pinHash: "hash",
      email: "admin@example.com",
      authUid: "uid",
      canViewAdmin: true,
    });

    const result = await listUsers();
    const serialized = JSON.stringify(result);

    assert.equal(serialized.includes("1234"), false);
    assert.equal(serialized.includes("hash"), false);
    assert.equal(serialized.includes("admin@example.com"), false);
    assert.equal(serialized.includes("uid"), false);
    assert.equal(serialized.includes("canViewAdmin"), false);
    assert.deepEqual(Object.keys(result.users[0]).sort(), ["displayName", "id"]);
  });

  it("rechaza restaurant invalido", async () => {
    await assert.rejects(
      () => listBackofficeUsersCore(db, {restaurantId: "bad/path"}, "127.0.0.1"),
      /Restaurante invalido/,
    );
  });

  it("rate limit funciona", async () => {
    await restaurant()
      .collection("backofficeUserListRateLimits")
      .doc("list_127_0_0_1")
      .set({
        attempts: 60,
        windowStartedAt: admin.firestore.Timestamp.now(),
      });

    await assert.rejects(() => listUsers(), /Demasiados intentos/);
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

function listUsers(overrides: Record<string, unknown> = {}) {
  return listBackofficeUsersCore(db, {
    restaurantId,
    ...overrides,
  }, "127.0.0.1") as Promise<{users: Array<{id: string; displayName: string}>}>;
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
