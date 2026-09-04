# Security — Dependency-Vulnerability Gate

This directory holds the **reference template** for the dependency-vulnerability build gate — the standing supply-chain security gate described in `forge-harness-framework.md` §4.10 (Build & CI foundation slice).

## What the gate is

A scanner (e.g. [OWASP Dependency-Check](https://owasp.org/www-project-dependency-check/)) wired into CI that **fails the build** when any resolved dependency carries a CVE at or above a configurable CVSS threshold. It runs on *every* build — it is not a per-feature judgment call. The per-feature application-security review (auth, data handling, endpoints) is a separate, human gate; see the quality checklist.

## How to adopt it (during Foundation, Build & CI slice)

1. **Pick one tool and apply it uniformly across every repo** in the engagement. A scan wired into one repo but not its sibling is a gap, not a gate. (Backend example: the OWASP Dependency-Check Gradle plugin `org.owasp.dependencycheck`. Frontend example: the OWASP Dependency-Check CLI/Node module — preferred over `npm audit` when you want the same XML suppressions format across repos.)
2. **Make the threshold configurable, not hardcoded** — read it from a build property / env var so CI and per-environment overrides work. A sensible default is **CVSS ≥ 7.0**.
3. **Copy `dependency-check-suppressions.xml` into each scanned app repo** and point the scanner's `suppressionFile` at that repo's copy. The copy in this directory is the reference, not the live file.
4. **Operational notes** (tool-specific, captured here so they aren't re-learned per project):
   - Provide an NVD API key as a repo secret — without it the NVD feed is rate-limited (HTTP 429 / timeouts).
   - Cache the NVD database between CI runs, otherwise every run re-downloads the full feed.
   - Emit SARIF in addition to the build-failure gate to feed code-scanning dashboards where available.

## Suppressions governance

Every suppression entry must:

- suppress by **CVE *and* dependency coordinate** (never a blanket CVE),
- carry a **justification** in `<notes>` (why it's not exploitable here, or who accepted the risk and when),
- carry an **expiry** (`until`) so it gets revisited rather than living forever.

## Constraint

CI/CD pipeline changes typically require lead approval (see the project constitution's NEVER DO list). Wiring this gate is a CI change — get sign-off.
