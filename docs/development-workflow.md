# Development Workflow

## Start With the Sibling Provider

Before adding or changing client behaviour, inspect MLXDashboard's current provider implementation and tests:

- `../MLXDashboard/README.md`
- `../MLXDashboard/AGENTS.md`
- `../MLXDashboard/Sources/MLXProviderServer/ProviderRouter.swift`
- `../MLXDashboard/Tests/MLXProviderServerTests/ProviderRouterTests.swift`

Use `docs/mlxdashboard-provider-contract.md` as the local summary, then verify against MLXDashboard before making behaviour-sensitive changes.

## Python Environment

When Python tooling is introduced:

- use `python3` from the active `pyenv` version;
- create virtual environments with that interpreter;
- avoid assuming the macOS system Python;
- document any new dependency and why it is needed.

Do not add Python package files until there is an actual Python tool to run.

## Adding Future Tools

For the first executable tool, prefer a narrow smoke-test CLI before a general SDK. The first tool should:

- accept a base URL with `http://127.0.0.1:8123` as the default;
- make no attempt to start or configure MLXDashboard;
- fail clearly when MLXDashboard is not running;
- keep request and response logging concise;
- avoid sending prompts larger than needed for provider verification.

## Verification Habits

For documentation-only changes:

- confirm the file tree matches the intended docs set;
- read every changed markdown file after editing;
- check links and sibling-project paths;
- compare documented provider facts with MLXDashboard source or tests.

For future executable tools:

- run unit tests for request construction and response parsing;
- run smoke tests against a live MLXDashboard provider when available;
- include failure cases for connection refused, non-2xx responses, missing active model, invalid JSON, and interrupted streams.

For SwiftUI app verification:

- after launching from Terminal, bring the app window to the front and confirm it is not hidden behind VS Code or the launching terminal;
- click into an editable field, type a short value, and confirm the characters appear in the app rather than in the terminal session that started it;
- verify at least one primary interaction path with real keyboard focus, such as editing the provider URL or typing in the chat composer.

## Localhost Safety

MLXChat clients should default to local-only provider access. Do not add docs, defaults, flags, or examples that expose MLXDashboard or `mlx_lm.server` beyond localhost unless MLXDashboard first has a deliberate secured remote-access mode.
