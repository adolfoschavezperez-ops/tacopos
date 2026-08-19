#!/usr/bin/env node

const path = require('path');
const readline = require('readline');

let admin;
try {
  admin = require('firebase-admin');
} catch (_) {
  admin = require(path.join('..', 'functions', 'node_modules', 'firebase-admin'));
}

function arg(name) {
  const index = process.argv.indexOf(`--${name}`);
  if (index === -1 || index + 1 >= process.argv.length) return '';
  return process.argv[index + 1].trim();
}

function promptHiddenPassword(message) {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    return Promise.resolve('');
  }

  return new Promise((resolve) => {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
      terminal: true,
    });

    const originalWrite = rl._writeToOutput;
    rl._writeToOutput = function _writeToOutput(stringToWrite) {
      if (rl.stdoutMuted && stringToWrite.trim() !== '') {
        rl.output.write('*');
        return;
      }
      originalWrite.call(rl, stringToWrite);
    };

    rl.stdoutMuted = true;
    rl.question(message, (answer) => {
      rl.history = rl.history.slice(1);
      rl.close();
      process.stdout.write('\n');
      resolve(answer.trim());
    });
  });
}

async function main() {
  const restaurantId = arg('restaurantId') || 'main_restaurant';
  const email = arg('email').toLowerCase();
  const displayName = arg('displayName') || email;
  let password = process.env.BACKOFFICE_ADMIN_PASSWORD || '';

  if (!email) {
    throw new Error('Uso: node tools/provision_backoffice_admin.js --restaurantId main_restaurant --email admin@example.com');
  }

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: process.env.GCLOUD_PROJECT || 'tacopos-renovadev',
  });

  let user;
  let createdAuthUser = false;
  try {
    user = await admin.auth().getUserByEmail(email);
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
    if (!password) {
      password = await promptHiddenPassword(
        'Contraseña temporal para crear el superadmin: ',
      );
    }
    if (!password) {
      throw new Error(
        'El usuario no existe. Define BACKOFFICE_ADMIN_PASSWORD temporalmente o ejecuta el script en una terminal interactiva.',
      );
    }
    user = await admin.auth().createUser({
      email,
      password,
      displayName,
      emailVerified: false,
      disabled: false,
    });
    createdAuthUser = true;
  }

  if (user.disabled) {
    await admin.auth().updateUser(user.uid, {disabled: false});
  }

  const db = admin.firestore();
  const ref = db
    .collection('restaurants')
    .doc(restaurantId)
    .collection('authUsers')
    .doc(user.uid);
  const snapshot = await ref.get();
  const previous = snapshot.exists ? snapshot.data() : {};
  const desiredPermissions = {
    canViewAdmin: true,
    canAuthorizeCashWithdrawals: true,
  };
  const desiredFields = {
    uid: user.uid,
    email,
    displayName,
    active: true,
    isSuperAdmin: true,
    restaurantId,
    permissions: desiredPermissions,
  };
  const needsAuthUserUpdate = !snapshot.exists ||
    previous.uid !== desiredFields.uid ||
    previous.email !== desiredFields.email ||
    previous.displayName !== desiredFields.displayName ||
    previous.active !== desiredFields.active ||
    previous.isSuperAdmin !== desiredFields.isSuperAdmin ||
    previous.restaurantId !== desiredFields.restaurantId ||
    previous.permissions?.canViewAdmin !== desiredPermissions.canViewAdmin ||
    previous.permissions?.canAuthorizeCashWithdrawals !==
      desiredPermissions.canAuthorizeCashWithdrawals;
  const fields = {
    ...desiredFields,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (!snapshot.exists) {
    fields.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }
  if (needsAuthUserUpdate) {
    await ref.set(fields, {merge: true});
  }

  const wroteAudit = createdAuthUser || needsAuthUserUpdate;
  if (wroteAudit) {
    const auditRef = db
      .collection('restaurants')
      .doc(restaurantId)
      .collection('activityLog')
      .doc();
    await auditRef.set({
      type: 'BACKOFFICE_ADMIN_PROVISIONED_LOCAL',
      restaurantId,
      uid: user.uid,
      email,
      createdAuthUser,
      createdAuthUserDoc: !snapshot.exists,
      updatedAuthUserDoc: needsAuthUserUpdate && snapshot.exists,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  console.log(JSON.stringify({
    restaurantId,
    email,
    uid: user.uid,
    createdAuthUser,
    createdAuthUserDoc: !snapshot.exists,
    updatedAuthUserDoc: needsAuthUserUpdate && snapshot.exists,
    wroteAudit,
    authUserPath: `restaurants/${restaurantId}/authUsers/${user.uid}`,
    fields: {
      active: true,
      isSuperAdmin: true,
      permissions: desiredPermissions,
    },
  }, null, 2));
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
