const project = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "";
const firestoreEmulator = process.env.FIRESTORE_EMULATOR_HOST || "";

if (!project.startsWith("demo-") || !firestoreEmulator) {
  console.error(
    "Refusing Functions tests: run them with Firebase Emulator Suite and a demo-* project.",
  );
  process.exit(1);
}

console.log(
  `Functions tests target Firestore Emulator ${firestoreEmulator} (${project}).`,
);
