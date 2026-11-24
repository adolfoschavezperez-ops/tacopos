#!/usr/bin/env node
"use strict";

const {execFileSync} = require("node:child_process");

function inspectReleaseWorktree(runGit = defaultGit) {
  const branch = runGit(["branch", "--show-current"]).trim();
  const sha = runGit(["rev-parse", "HEAD"]).trim();
  const status = runGit(["status", "--porcelain", "--untracked-files=all"]);
  if (!branch) return {ok: false, reason: "detached HEAD"};
  if (status.trim()) return {ok: false, reason: "worktree has modified or untracked files"};
  if (!/^[0-9a-f]{40}$/i.test(sha)) return {ok: false, reason: "invalid HEAD SHA"};
  const remote = runGit(["ls-remote", "--heads", "origin", `refs/heads/${branch}`])
    .trim()
    .split(/\s+/)[0];
  if (!remote) return {ok: false, reason: `origin has no branch ${branch}`};
  if (remote !== sha) {
    return {ok: false, reason: `remote SHA ${remote} does not match HEAD ${sha}`};
  }
  return {ok: true, branch, sha, remote};
}

function defaultGit(args) {
  return execFileSync("git", args, {encoding: "utf8", stdio: ["ignore", "pipe", "pipe"]});
}

if (require.main === module) {
  try {
    const result = inspectReleaseWorktree();
    if (!result.ok) {
      console.error(`RELEASE BLOCKED: ${result.reason}`);
      process.exitCode = 1;
    } else {
      console.log(`RELEASE SOURCE VERIFIED: ${result.branch} ${result.sha}`);
    }
  } catch (error) {
    console.error(`RELEASE BLOCKED: Git provenance check failed: ${error.message}`);
    process.exitCode = 1;
  }
}

module.exports = {inspectReleaseWorktree};
