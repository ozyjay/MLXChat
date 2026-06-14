# MLXChat

MLXChat contains client-side tools for checking and exercising the MLXDashboard localhost provider. It is the sister project to `../MLXDashboard`, which remains the source of truth for provider behaviour, model management, and runtime setup.

The current implemented tool is a Swift command-line smoke tester for the local OpenAI-compatible provider.

## Quick Start

From this repository:

```sh
swift test
swift run mlxchat --help
swift run mlxchat
```

By default, the CLI targets:

```text
http://127.0.0.1:8123
```

Use `--base-url` only for another local MLXDashboard provider endpoint:

```sh
swift run mlxchat --base-url http://127.0.0.1:8123 --json
```

## What It Checks

The smoke tester verifies the current compatibility surface documented for MLXDashboard:

- `GET /health`
- `GET /v1/models`
- `POST /v1/chat/completions`
- `POST /v1/responses`
- optional streaming chat completions

It expects the role aliases `mlx-ask`, `mlx-plan`, and `mlx-fast` to appear in the model listing.

## Localhost Safety

MLXChat should default to localhost-only access. Do not expose MLXDashboard, its provider server, or `mlx_lm.server` beyond localhost unless MLXDashboard first has a deliberate secured remote-access design.

## Documentation

Read the project docs in this order:

1. [Project brief](docs/project-brief.md)
2. [MLXDashboard provider contract](docs/mlxdashboard-provider-contract.md)
3. [Client tooling roadmap](docs/client-tooling-roadmap.md)
4. [Development workflow](docs/development-workflow.md)

When provider behaviour changes, update [docs/mlxdashboard-provider-contract.md](docs/mlxdashboard-provider-contract.md) and link the change back to the relevant MLXDashboard source or test.
