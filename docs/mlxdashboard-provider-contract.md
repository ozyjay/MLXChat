# MLXDashboard Provider Contract

This document records the currently observed MLXDashboard provider behaviour for MLXChat clients. Treat it as compatibility guidance derived from the sibling project, not as a permanent external API guarantee.

## Default Endpoint

MLXDashboard's provider server defaults to:

```text
Base URL: http://127.0.0.1:8123
```

Clients should use localhost by default. Do not document or implement remote binding as a normal MLXChat workflow.

MLXDashboard also manages an upstream `mlx_lm.server` process. Its runtime notes keep that server bound to `127.0.0.1`; MLXChat should preserve that safety assumption.

## Health

```http
GET /health
```

Observed success response:

```json
{"status":"ok"}
```

The health route does not require a bearer token.

## OpenAI-Style Routes

Observed OpenAI-style routes:

- `GET /v1/models`
- `GET /v1/models/{model}`
- `POST /v1/chat/completions`
- `POST /v1/completions`
- `POST /v1/responses`

The provider accepts requests without a bearer token for local use. If a client library requires an API key field, use a harmless local value such as `local`.

`POST /v1/responses` is translated by MLXDashboard into a chat-completions request before proxying upstream.

`POST /v1/chat/completions` supports OpenAI-style streaming when the request body includes `"stream": true`. MLXDashboard proxies streamed responses as server-sent events with `content-type: text/event-stream`. MLXChat consumes `data:` frames, reads assistant text from `choices[0].delta.content`, and treats `data: [DONE]` as stream completion.

Observed chat streaming frame shape:

```text
data: {"choices":[{"delta":{"content":"Hel"},"finish_reason":null}]}

data: {"choices":[{"delta":{"content":"lo"},"finish_reason":null}]}

data: [DONE]
```

## Model Listing and Aliases

When an active model is configured, `GET /v1/models` advertises role aliases followed by the active model:

```text
mlx-ask
mlx-plan
mlx-fast
<active MLX model id>
```

Observed alias intent:

| Alias | Role |
| --- | --- |
| `mlx-ask` | Ask |
| `mlx-plan` | Planning |
| `mlx-fast` | Coding |

MLXDashboard may route aliases to role-specific upstream endpoints when configured. When no role-specific endpoint is available, aliases can resolve to the active model.

## Compatibility Routes

MLXDashboard also exposes MLXDashboard-specific provider metadata routes:

- `GET /provider/v1/models`
- `GET /provider/v1/models/{model}`

These are the canonical metadata and capability routes for MLXChat. They may include known non-runnable models so clients can show unavailable states, but `/v1/models` remains the runnable OpenAI-compatible allowlist.

MLXDashboard also exposes Android Studio/Ollama-style compatibility routes:

- `GET /api/v0/models`
- `GET /api/v0/models/{model}`
- `GET /api/tags`
- `GET /api/ps`
- `GET /api/version`
- `POST /api/show`
- `POST /api/chat`
- `POST /api/generate`

Observed compatibility behaviour:

- `/provider/v1/models` returns model metadata with fields such as `id`, `object`, `type`, `publisher`, `compatibility_type`, `state`, and `max_context_length`.
- `/api/v0/models` is a legacy alias for older local clients. MLXChat uses it only as a fallback when `/provider/v1/models` returns 404 or is unavailable.
- `/api/tags` and `/api/ps` advertise the aliases and active model in Ollama-style response shapes.
- `/api/version` returns version `0.0.0`.
- `/api/chat` and `/api/generate` are translated to chat completions.

MLXChat understands these provider metadata fields for text model selection:

- `generation_type: "text"` marks a model as producing text.
- `model_family: "chat"` marks normal chat models.
- `model_family: "diffusion_text"` marks text diffusion models that still return text through chat-completions-compatible routes.
- `state: "unsupported"` plus `unsupported_reason` marks a listed model that should not be used for chat requests.
- `state: "not_installed"` plus `not_installed_reason` marks a listed model that is known but unavailable in the local cache.

These fields are compatibility guidance for MLXChat clients. They do not add image diffusion support; image generation requires a separate provider contract.

MLXChat treats `GET /v1/models` as the runnable model allowlist. When `/provider/v1/models` or legacy `/api/v0/models` contains metadata for models that are not advertised by `/v1/models`, MLXChat ignores those extra rows in the sidebar and uses metadata only to label advertised models.

Runnable text diffusion models should appear in `/v1/models`, be labelled as `generation_type: "text"` and `model_family: "diffusion_text"` in `/provider/v1/models`, and respond through `/v1/chat/completions` with the same `choices[0].message.content` shape as normal chat models. MLXChat does not route text diffusion models to image-generation endpoints or render image payloads.

## Path Normalisation

MLXDashboard normalises several client path variants before routing. Observed examples include:

- `/models` to `/v1/models`
- `/chat/completions` to `/v1/chat/completions`
- `/completions` to `/v1/completions`
- `/responses` to `/v1/responses`
- `/chat` to `/api/chat`
- `/generate` to `/api/generate`

MLXChat tools should still prefer the canonical paths listed above so failures are easier to interpret.

## Source of Truth

Before changing this contract, inspect the current MLXDashboard implementation and tests:

- `../MLXDashboard/Sources/MLXProviderServer/NIOProviderServer.swift`
- `../MLXDashboard/Sources/MLXProviderServer/ProviderRouter.swift`
- `../MLXDashboard/Tests/MLXProviderServerTests/ProviderRouterTests.swift`
- `../MLXDashboard/docs/notes/mlx-lm-runtime-and-model-planning.md`
