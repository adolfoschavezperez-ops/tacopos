"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {inspectReleaseWorktree} = require("./verify_release_worktree");

const sha = "3ef05a81700f4934347b52760be1d3fed5e9a499";

function gitMock({branch = "feature/durable-local-order-capture", head = sha,
  status = "", remote = sha} = {}) {
  return (args) => {
    if (args[0] === "branch") return `${branch}\n`;
    if (args[0] === "rev-parse") return `${head}\n`;
    if (args[0] === "status") return status;
    if (args[0] === "ls-remote") return remote ? `${remote}\trefs/heads/${branch}\n` : "";
    throw new Error(`unexpected git command ${args.join(" ")}`);
  };
}

test("release source requires a clean branch whose remote SHA matches", () => {
  assert.deepEqual(inspectReleaseWorktree(gitMock()), {
    ok: true,
    branch: "feature/durable-local-order-capture",
    sha,
    remote: sha,
  });
});

test("release source rejects dirty worktrees and untracked files", () => {
  assert.equal(inspectReleaseWorktree(gitMock({status: " M pubspec.yaml\n"})).ok, false);
  assert.equal(inspectReleaseWorktree(gitMock({status: "?? secret.tmp\n"})).ok, false);
});

test("release source rejects detached, unbacked, or divergent branches", () => {
  assert.equal(inspectReleaseWorktree(gitMock({branch: ""})).reason, "detached HEAD");
  assert.equal(inspectReleaseWorktree(gitMock({remote: ""})).ok, false);
  assert.equal(inspectReleaseWorktree(gitMock({remote: "a".repeat(40)})).ok, false);
});
