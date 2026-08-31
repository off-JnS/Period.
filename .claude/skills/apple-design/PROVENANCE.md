# Provenance and precedence

## Where this came from

Vendored from <https://github.com/dickwu/apple-design-skill>
at commit `d0bac1e765a27a696839e62962e36330ce72f0b7`.

Only `SKILL.md` and `references/` were copied. `.cursorrules` and `AGENTS.md` were
left behind — they configure other tools and are noise here.

It is committed into this repository rather than installed into `~/.claude/skills/`
because agent containers are ephemeral: a home-directory install does not survive
to the next session, and every future session on this repo needs it.

Reviewed before committing: markdown only. No scripts, no executables, no network
calls, no credential handling.

To update: re-clone the source, diff, bump the commit hash above in the same commit.

## Precedence — CLAUDE.md wins

This skill is third-party guidance. `CLAUDE.md` is this project's contract. Where the
two disagree, **CLAUDE.md wins and the skill's suggestion is dropped**, not negotiated.

The skill is also an *audit* tool — it reviews an existing design against Apple's
Human Interface Guidelines. It does not author screens, and it is not a licence to
add dependencies.

Four conflicts to expect, because nothing enforces them automatically:

- **§1 — one codebase, two platforms.** HIG advice that assumes iOS conventions must
  not quietly become the Android look. The skill's own reference notes say the
  principles are platform-agnostic and the implementation details are not; hold it
  to that.
- **§9 — no colour-only information.** Every calendar and cycle state needs a shape
  or a label as well as a colour. A design suggestion that carries meaning in colour
  alone is rejected.
- **§8 — copy and claims.** No medical claims, no prediction stated as certainty, and
  no hardcoded display strings. All user-facing text comes from the ARB files.
- **§6 — dependencies.** A design suggestion never justifies adding a package. Ask first.
