# MLXChat

MLXChat contains client-side tools for checking and exercising the MLXDashboard localhost provider. It is the sister project to `../MLXDashboard`, which remains the source of truth for provider behaviour, model management, and runtime setup.

The current implemented tools are a Swift command-line smoke tester and a lightweight macOS SwiftUI chat front-end for the local OpenAI-compatible provider.

## Quick Start

From this repository:

```sh
swift test
swift run mlxchat
swift run mlxchat-app
```

Or use the project scripts:

```sh
./scripts/build.sh
./scripts/run.sh cli --help
./scripts/run.sh app
./scripts/install.sh
```

`scripts/install.sh` builds release binaries and installs `mlxchat` and `mlxchat-app` to `$HOME/.local/bin` by default. Set `PREFIX=/path/to/prefix` or `BIN_DIR=/path/to/bin` to choose another user-local install location.

Both tools default to:

```text
http://127.0.0.1:8123
```

Start MLXDashboard's provider server first, then use either the CLI smoke tester or the app.

## Tools

### SwiftUI Chat App

Run the macOS SwiftUI front-end:

```sh
swift run mlxchat-app
```

The app:

- checks provider health with `GET /health`;
- lists models with `GET /v1/models`;
- overlays richer capability metadata from `GET /provider/v1/models` when available, falling back to legacy `GET /api/v0/models` for older local providers, while only showing models advertised by `GET /v1/models`;
- selects `mlx-ask` by default when it is advertised, otherwise the first model;
- sends normal chat and text diffusion chat requests to `POST /v1/chat/completions`;
- labels normal chat, text diffusion, and unsupported models in the sidebar;
- persists the last local base URL and selected model;
- accepts only localhost provider URLs such as `http://127.0.0.1:8123`, `http://localhost:8123`, or `http://[::1]:8123`.

If MLXDashboard is not running, the app should show a disconnected state rather than crash.
Image diffusion is not supported by MLXChat yet. Text diffusion models must be advertised by MLXDashboard in `GET /v1/models`, labelled with `model_family: "diffusion_text"` in canonical `GET /provider/v1/models` metadata, and returned as plain text chat-completion responses.

The app and core provider client emit concise logs to Application Support:

```sh
tail -f "$HOME/Library/Application Support/MLXChat/logs/mlxchat.log"
```

They also emit Unified Logging entries under the `MLXChat` subsystem. Use Console.app or:

```sh
log stream --predicate 'subsystem == "MLXChat"'
```

Default-visible logs include provider health, model counts, selected model IDs, chat send start/finish, request failures, status codes, and response snippets for failures. Debug logs add lower-level request start/finish details. Logs do not include full prompts, full assistant replies, or raw successful response bodies.

### CLI Smoke Tester

Run the command-line smoke tester:

```sh
swift run mlxchat
```

Show CLI options:

```sh
swift run mlxchat --help
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
