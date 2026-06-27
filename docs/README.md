# MLXChat Docs

MLXChat is a documentation-first starting point for client tools that test and access the MLXDashboard localhost provider.

Recommended reading order:

1. [Project brief](project-brief.md): purpose, audience, success criteria, and non-goals.
2. [MLXDashboard provider contract](mlxdashboard-provider-contract.md): observed localhost routes, aliases, and compatibility behaviour.
3. [Client tooling roadmap](client-tooling-roadmap.md): first tool ideas and suggested implementation sequence.
4. [Development workflow](development-workflow.md): how future agents should add tools while staying aligned with MLXDashboard.

`../MLXDashboard` is the source of truth for provider behaviour. These docs should be updated whenever MLXDashboard changes its provider routes, model aliases, routing policy, or localhost safety assumptions.

## MVP: Swift Smoke CLI

The first implemented tool is a lightweight Swift command-line smoke tester for provider compatibility.

- Run: `swift run mlxchat`
- Show CLI flags: `swift run mlxchat --help`
- Common options:
  - `--base-url` (default: `http://127.0.0.1:8123`)
  - `--timeout`
  - `--json`
  - `--no-stream`

`--base-url` accepts only local HTTP provider URLs for MLXDashboard, with an optional `/v1` suffix.
