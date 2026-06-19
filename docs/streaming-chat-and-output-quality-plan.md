# Streaming Chat and Output Quality Plan

## Goal

Enable first-class streaming replies in the MLXChat SwiftUI app while improving the readability of assistant output and aligning the client contract with current MLXDashboard provider behaviour.

The user-facing target is simple: after the user sends a message, the assistant bubble should appear immediately, grow as tokens arrive, preserve readable paragraph/list/code formatting, and finish cleanly without logging full prompts or full replies.

## Current Behaviour

MLXChat currently sends chat requests through the buffered `ProviderClient.completeChat(model:messages:)` path. The app waits for the full response, then appends one assistant message to the transcript.

The current UI can therefore look like a single dense block of text for rich answers. Recent local output showed paragraph breaks, numbered sections, and inline emphasis collapsing into a hard-to-read response. Streaming should not make that worse: partial output must still preserve newlines, Markdown list spacing, and code-block readability as the message grows.

MLXDashboard already has provider-side support for streamed chat-completions responses, so this work should mostly add client-side streaming consumption, transcript mutation, and formatting polish.

## Non-Goals

- Do not add image-generation support.
- Do not expose non-local provider URLs.
- Do not log full prompt text or full assistant replies.
- Do not remove buffered chat support; keep it as a fallback and for tests.

## Provider Contract Alignment

Before or alongside streaming, align MLXChat with current MLXDashboard role aliases.

Current Dashboard behaviour uses these canonical role aliases:

- `mlx-ask`
- `mlx-plan`
- `mlx-coding`

`mlx-fast` is a legacy accepted alias on the Dashboard side, but the smoke tester and docs should not require it as the canonical coding alias.

Planned client updates:

- Change smoke-test required aliases from `mlx-fast` to `mlx-coding`.
- Keep compatibility documentation noting that older providers or clients may still mention `mlx-fast`.
- Update tests that currently construct catalogues or responses with `mlx-fast` when the test is meant to represent current Dashboard behaviour.
- Keep explicit legacy tests only where they prove fallback compatibility.

## Streaming Client Design

Add a streaming API to `MLXChatCore` rather than overloading the buffered API.

Suggested shape:

```swift
public struct ChatStreamDelta: Equatable, Sendable {
    public let model: String?
    public let content: String
    public let isDone: Bool
}

public func streamChat(
    model: String,
    messages: [ChatTranscriptMessage]
) async throws -> AsyncThrowingStream<ChatStreamDelta, Error>
```

Implementation notes:

- Send `POST /v1/chat/completions` with `stream: true`.
- Use `URLSession.bytes(for:)` for the real transport.
- Buffer partial lines because network chunks may split SSE events.
- Parse OpenAI-style `data: {json}` events.
- Finish cleanly on `data: [DONE]`.
- Extract `choices[0].delta.content` as the primary streaming token source.
- Tolerate local-provider fallback shapes where practical, such as `choices[0].message.content` or `choices[0].text`.
- Return clear errors for non-2xx responses, invalid stream frames, or request failures.
- Keep response-body snippets only for failures and do not log successful streamed content.

## SwiftUI Transcript Design

Update `ChatAppViewModel.sendMessage()` so the transcript updates incrementally.

Planned flow:

1. Validate provider URL, selected model, and sendability as today.
2. Resolve mode advice before sending.
3. Append the user message.
4. Append an empty assistant message with a stable ID and a streaming state.
5. Consume `streamChat(...)` in an async loop.
6. Append each content delta to the assistant message.
7. Mark the assistant message complete when the stream finishes.
8. If an error occurs after partial output, keep the partial reply visible, mark it incomplete, and show the error banner.

`ChatDisplayMessage` will need to become mutable enough for content updates. One option:

```swift
struct ChatDisplayMessage: Equatable, Identifiable {
    let id: UUID
    let role: String
    var content: String
    var isStreaming: Bool
    var didFail: Bool
}
```

## Output Readability Requirements

The current dense output is a quality bug, not just a streaming concern. Treat readable rendering as part of the streaming feature.

Requirements:

- Preserve paragraph breaks in assistant messages.
- Preserve Markdown list spacing during and after streaming.
- Preserve fenced code block line breaks and monospaced rendering.
- Avoid collapsing headings, list items, and bold text into adjacent words.
- Auto-scroll when message content changes, not only when a new message is appended.
- Show `Streaming reply...` only until useful text appears, then let the growing assistant bubble carry the interaction.
- Keep user prompts literal; only render assistant Markdown.

Suggested UI updates:

- Add a `contentRevision` or last-message-content observer so `TranscriptView` scrolls as deltas arrive.
- Use the existing `ChatMessagePresentation.renderedContent(role:content:)` path, but add tests with streamed-style partial Markdown.
- Add snapshot-like unit tests for common response shapes: paragraphs, numbered lists, bullets, fenced code, and bold text next to plain text.

## Test Plan

Core tests:

- Streaming parser emits deltas for normal SSE chunks.
- Parser handles chunks split across line boundaries.
- Parser handles multiple `data:` events in one chunk.
- Parser finishes on `[DONE]`.
- Parser throws a useful error on non-2xx responses.
- Parser tolerates empty keep-alive lines.
- Parser ignores or reports malformed JSON consistently.

App/view-model tests:

- Sending appends user message and assistant placeholder immediately.
- Streaming deltas mutate the same assistant message.
- A completed stream clears `isSending` and marks the assistant message complete.
- A failed stream preserves partial content and sets `errorMessage`.
- Auto-scroll state changes when assistant content grows.
- Markdown rendering preserves paragraph/list/code readability.

Smoke tests:

- Required aliases are `mlx-ask`, `mlx-plan`, and `mlx-coding`.
- Optional streaming check remains available in the CLI.
- A live Dashboard provider returns SSE-like streamed content for `stream: true`.

## Implementation Tasks

- [ ] Add streaming transport abstractions to `MLXChatCore`.
- [ ] Add a streaming chat API to `ProviderClient`.
- [ ] Add an SSE parser with unit tests.
- [ ] Update `ChatAppViewModel.sendMessage()` to append and mutate an assistant placeholder.
- [ ] Update transcript auto-scroll to track content changes.
- [ ] Improve assistant Markdown rendering tests for readable paragraphs, lists, and code blocks.
- [ ] Change current alias expectations from `mlx-fast` to `mlx-coding`.
- [ ] Keep legacy `mlx-fast` coverage only as compatibility coverage.
- [ ] Update README and provider-contract docs after behaviour changes.
- [ ] Run `swift test` and a live `swift run mlxchat --base-url http://127.0.0.1:8123 --json` smoke test.

## Manual Verification

1. Start MLXDashboard and its provider.
2. Run `swift test` in MLXChat.
3. Run `swift run mlxchat` and confirm the optional streaming check passes.
4. Run `swift run mlxchat-app`.
5. Send a prompt that produces headings, lists, bold text, and code.
6. Confirm the assistant bubble streams incrementally and remains readable.
7. Confirm logs include model/status/counts but not full prompt or reply bodies.
