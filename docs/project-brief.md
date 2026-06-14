# Project Brief

## Purpose

MLXChat is a sister project for building client-side tools that exercise MLXDashboard's local provider. The first goal is not to build a chat app; it is to capture the provider contract and prepare a clear path for smoke tests, compatibility probes, and later reusable clients.

MLXDashboard owns model installation, active model selection, role aliases, and the local provider process. MLXChat should behave like an external client: connect to the provider, send realistic requests, report compatibility results, and avoid duplicating MLXDashboard's control-plane responsibilities.

## Audience

- Developers validating MLXDashboard provider changes.
- Agents adding command-line smoke tests or client wrappers.
- Future app or tool authors who need a small, local OpenAI-compatible target for MLX models.

## Success Criteria

- A future worker can understand what MLXChat is for without inspecting MLXDashboard from scratch.
- Provider assumptions are documented with enough detail to build a first smoke-test CLI.
- Localhost safety is explicit and preserved.
- The project remains free of runtime scaffolding until the first concrete tool is chosen.

## Non-Goals

- Do not manage MLX models, Hugging Face downloads, Python package setup, or `mlx_lm.server` startup in MLXChat.
- Do not replace MLXDashboard's provider implementation.
- Do not expose remote access to MLXDashboard or `mlx_lm.server`.
- Do not promise that the currently observed provider shape is a stable public API.

## Relationship to MLXDashboard

MLXDashboard currently exposes an OpenAI-compatible localhost provider intended for MLXChat and other tools. MLXChat should verify its expectations against the sibling project before changing client behaviour, especially:

- `../MLXDashboard/README.md`
- `../MLXDashboard/AGENTS.md`
- `../MLXDashboard/Tests/MLXProviderServerTests/ProviderRouterTests.swift`
- `../MLXDashboard/Sources/MLXProviderServer/ProviderRouter.swift`
