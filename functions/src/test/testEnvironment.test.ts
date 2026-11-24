import "../testEnvironment";
import * as assert from "assert";
import {assertSafeFunctionsTestEnvironment} from "../testEnvironment";

const validEnvironment = {
  GCLOUD_PROJECT: "demo-tacopos-tests",
  GOOGLE_CLOUD_PROJECT: "demo-tacopos-tests",
  FIREBASE_CONFIG: JSON.stringify({projectId: "demo-tacopos-tests"}),
  FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
  FIREBASE_AUTH_EMULATOR_HOST: "localhost:9099",
};

describe("Functions Admin SDK test environment guard", () => {
  it("accepts one demo project and local Firestore/Auth emulators", () => {
    assert.doesNotThrow(() => assertSafeFunctionsTestEnvironment(validEnvironment));
  });

  it("rejects a production project even when Firestore points locally", () => {
    assert.throws(
      () => assertSafeFunctionsTestEnvironment({...validEnvironment, GCLOUD_PROJECT: "tacopos-renovadev"}),
      /same demo-\* project/i,
    );
  });

  it("rejects a remote Firestore endpoint", () => {
    assert.throws(
      () => assertSafeFunctionsTestEnvironment({...validEnvironment, FIRESTORE_EMULATOR_HOST: "firestore.googleapis.com:443"}),
      /local HTTP emulator/i,
    );
  });

  it("requires the Auth emulator so Admin Auth cannot fall through to Google", () => {
    assert.throws(
      () => assertSafeFunctionsTestEnvironment({...validEnvironment, FIREBASE_AUTH_EMULATOR_HOST: ""}),
      /FIREBASE_AUTH_EMULATOR_HOST is required/i,
    );
  });

  it("rejects a FIREBASE_CONFIG that names a different project", () => {
    assert.throws(
      () => assertSafeFunctionsTestEnvironment({
        ...validEnvironment,
        FIREBASE_CONFIG: JSON.stringify({projectId: "tacopos-renovadev"}),
      }),
      /same demo-\* project/i,
    );
  });
});
