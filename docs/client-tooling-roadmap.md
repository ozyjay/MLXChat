# Client Tooling Roadmap

MLXChat should grow from provider-facing tests into reusable client tools. Keep each step small enough to validate against a running MLXDashboard instance.

## Phase 1: Smoke Tests

Build a command-line smoke tester that checks:

- provider reachability with `GET /health`;
- model discovery with `GET /v1/models`;
- canonical MLXDashboard metadata discovery with `GET /provider/v1/models`;
- canonical alias metadata and Dashboard routing metadata when advertised;
- mode advice with `POST /provider/v1/mode-advice` when Dashboard capability is detected;
- canonical chat completion with `POST /v1/chat/completions`;
- responses compatibility with `POST /v1/responses`;
- streaming chat behaviour with `"stream": true` using the shared stream parser;
- role aliases `mlx-ask`, `mlx-plan`, and `mlx-coding`.

The smoke tester should produce concise pass/fail output and include the request path, selected model, HTTP status, and short failure body when something fails.
`mlx-fast` should remain covered only as a legacy compatibility alias.

## Phase 2: Compatibility Probes

Add targeted probes for compatibility clients:

- Canonical MLXDashboard metadata discovery through `/provider/v1/models`.
- Legacy Android Studio-style discovery through `/api/v0/models`.
- Ollama-style tags and process listing through `/api/tags` and `/api/ps`.
- show metadata through `/api/show`.
- translated generation through `/api/chat` and `/api/generate`.

These probes should report schema drift without assuming MLXDashboard is a production Ollama server.

## Phase 3: Reusable Client Wrapper

Once smoke-test needs are clear, add a small reusable client wrapper around the provider:

- base URL configuration defaulting to `http://127.0.0.1:8123`;
- localhost-only URL validation matching the SwiftUI app;
- health and model listing helpers;
- model capability metadata helpers using `/provider/v1/models`, with legacy `/api/v0/models` fallback for older local providers;
- chat-completion and responses helpers;
- streaming support;
- structured error reporting for connection failures, non-2xx responses, and malformed JSON.

Text diffusion models should be treated as text-generation models when provider metadata marks them as `model_family: "diffusion_text"`. Do not route them through image-generation APIs unless MLXDashboard later defines an image provider contract.

Avoid adding broad SDK abstractions until at least one concrete MLXChat tool needs them.

## Phase 4: Regression Fixtures

When provider behaviour stabilises, add captured response fixtures or contract tests. Fixtures should be small, scrubbed of prompts that reveal private project context, and tied to documented MLXDashboard behaviour.
