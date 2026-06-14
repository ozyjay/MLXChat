## Global Response Language Preferences

- Use Australian grammar and spelling.

## Global Development Preferences

- This machine uses `pyenv` for Python. Prefer `python3` from the active `pyenv` version when creating virtual environments, installing packages, or running Python tooling.
- Do not assume the macOS system Python is the intended interpreter.

## MLXChat Project Guidance

- MLXChat is the sister project to `../MLXDashboard`. It exists to create client tools that test and access the MLXDashboard localhost provider.
- Keep this repository docs-first until a specific client tool, SDK, or smoke-test command is chosen.
- Do not add app scaffolding, dependency manifests, package managers, generated fixtures, or executable client code unless the user explicitly asks for that next step.
- Treat `../MLXDashboard` as the source of truth for provider behaviour. Before changing client expectations, inspect:
  - `../MLXDashboard/README.md`
  - `../MLXDashboard/AGENTS.md`
  - `../MLXDashboard/Tests/MLXProviderServerTests/ProviderRouterTests.swift`
  - `../MLXDashboard/Sources/MLXProviderServer/ProviderRouter.swift`
- Default clients to `http://127.0.0.1:8123` and localhost-only access.
- Do not encourage exposing MLXDashboard, its provider server, or `mlx_lm.server` beyond localhost unless a deliberate secured remote-access design exists in MLXDashboard.
- Document observed MLXDashboard behaviour as current compatibility guidance, not as a permanent external API guarantee.

## Documentation Style

- Keep docs concise, practical, and implementation-oriented.
- Prefer concrete endpoint examples, expected behaviours, and verification steps over broad product language.
- When provider behaviour changes, update `docs/mlxdashboard-provider-contract.md` and link the change back to the relevant MLXDashboard source or test.
