# T3 model API used by Float

Research against the T3 Code source in `~/repos/dev/t3code`, November 2026.

## Catalogue

Float currently calls the read-only MCP tool `orchestrator_capabilities` in
`T3Client.models()`. `T3ModelCatalog` in `Sources/FloatCore/T3Types.swift`
decodes its `providers` array, but the current implementation discards
providers with constraints and keeps only Codex, Claude Code, and Antigravity
providers that can run in `approval-required` mode.

Each catalogue provider includes:

- `providerInstanceId`: the stable routing key. The driver kind is not a safe
  substitute when a user has multiple instances of one provider.
- `driverKind` and nullable `displayName`.
- `constraints`: human-readable reasons the provider cannot be used. An empty
  array is the catalogue's enabled/usable signal. Constraints cover disabled
  instances, unavailable drivers, missing executables, bad provider status,
  authentication, unsupported runtime mode, and missing V2 adapters.
- optional `runtimeModes`, plus child-task capability flags.
- `models`, each with an ID, an optional display label, and optional option
  descriptors. An option has an ID, allowed string/boolean values, and an
  optional default.

The unfiltered call is deliberately a short list. It can report
`omittedModels`; passing `search` to the same tool searches the visible model
catalogue and returns matches per provider. Float therefore needs to preserve
disabled providers and use catalogue search instead of treating the initial
short list as exhaustive.

## Favourites

Favourites are not browser-local. T3 stores them in the server settings as
`favorites: [{ provider, model }]`, where `provider` is the provider instance
ID. On the standard local installation this is persisted in
`~/.t3/userdata/settings.json`. The web model picker reads and updates that
server setting through `server.updateSettings` with `setModelFavorites`.

There is no settings read/write MCP tool, and `t3_environment_read` does not
return model preferences. The web RPC is not part of Float's existing MCP
client. Float can read the local settings file, so the picker should use that
list and preserve the same provider-instance-plus-model key. Updates must
preserve all unrelated JSON fields. This keeps Float and the local T3
installation in sync; it is not a browser `localStorage` fallback.

## Model options and effort

The MCP thread tools accept canonical `ModelSelection` values:

```json
{
  "instanceId": "codex",
  "model": "gpt-5.6-sol",
  "options": [{ "id": "reasoningEffort", "value": "high" }]
}
```

`t3_thread_launch` accepts that object as `modelSelection`.
`t3_thread_configure` accepts the same object before `t3_thread_send`, so
options apply both to a new launch and to the next turn of an existing thread.

Effort is not a global fixed enum. Float must use the selected model's
catalogue option and send only one of that option's advertised values:

- Codex uses `reasoningEffort`.
- Claude Code and Cursor commonly use `effort`.
- Grok, Kiro, and Muse use `reasoningEffort`.
- ACP providers may advertise any option ID with the reasoning role; the MCP
  catalogue exposes the resulting ID and values.

Typical values include `low`, `medium`, `high`, `xhigh`, and `max`, but the
actual values and default vary by model and can include provider-specific or
custom-model values. Claude's `default` means omit an explicit effort and let
Claude Code choose. Float should identify effort-like IDs from the catalogue,
persist a valid value per provider instance and model, and include it in the
selection sent to the thread tools.

## Provider settings deep link

T3's route is `/settings/providers`, with an optional `instanceId` query. The
desktop app handles its custom URL, for example:

`t3code://app/settings/providers?instanceId=codex`

Float can open that deep link for a disabled provider. If opening it fails,
Float should fall back to launching T3 Code.

## Projects

### Listing local projects

Float can list projects on the Mac running Float with the read-only MCP tool
`t3_project_list`. Omit `environmentId` for the local environment. The call
accepts optional integer `cursor` and `limit` arguments. `limit` is clamped to
100 and defaults to 20, so Float must follow `nextCursor` until it is `null`.

The result is:

```json
{
  "projects": [
    {
      "id": "project-id",
      "title": "float",
      "workspaceRoot": "/Users/dylanyoung/repos/dev/float",
      "archivedAt": null,
      "deletedAt": null
    }
  ],
  "nextCursor": null
}
```

Each project also carries repository identity, icon, model default, scripts,
pinning and timestamps. `archivedAt` is the archive signal. The list excludes
deleted projects, so `deletedAt` is `null` for listed rows. There is no field
that says whether `workspaceRoot` still exists on disk. Float should omit
archived projects from the picker and handle a launch failure if a saved
project or its workspace has disappeared.

### Launching in a project

Float already launches new threads with `t3_thread_launch`. To launch in a
project, pass its `id` as `projectId`, omit `scratch`, and do not pass
`workspaceStrategy`. An omitted workspace strategy becomes `{ "type": "root" }`
inside T3, which binds the thread to the registered project checkout. Float
must not ask for a branch or worktree and must not create either one.

The QA launch should make this call, substituting a real small-project ID and a
cheap advertised model:

```json
{
  "name": "t3_thread_launch",
  "arguments": {
    "title": "Float project picker QA",
    "projectId": "<project-id>",
    "message": "Reply with the current working directory only.",
    "runtimeMode": "approval-required",
    "interactionMode": "default",
    "clientRequestId": "<new-uuid>",
    "modelSelection": {
      "instanceId": "<provider-instance-id>",
      "model": "<cheap-model-id>"
    }
  }
}
```

This deliberately has no `scratch` or `workspaceStrategy`. The successful
result includes `threadId`, `projectId`, `modelSelection`, `runId`, `status`
and usually `link`.

### Reading an existing thread

`t3_thread_read` returns the owning project as `thread.projectId`. It does not
include the project title or workspace path. Float must resolve that ID against
`t3_project_list` or `t3_project_read` and use the matching title in the
header. The thread read also exposes `branch` and `worktreePath`, but Float
does not show or change them.

## Machines

### Listing machines

The read-only MCP tool is `t3_environment_links`. Its result has:

- `environmentId`: the environment ID of the local T3 server that Float called.
  This is how Float identifies This Mac.
- `links`: the other machines, each with `environmentId`, the machine-name
  `label`, `status` (`reachable`, `unreachable`, or `expired`), `access`,
  `expiresAt`, and nullable `lastError`.
- `notListed`: guidance for linking a machine that is not in the result.

The result does not include a local-machine label, user name, device kind, or
project count. Float therefore presents the top-level environment as
`This Mac`, uses the app's local user name for its second line, and treats link
rows as linked machines. A linked machine is online only when its status is
`reachable`; both `unreachable` and `expired` are unavailable. Float gets the
project count separately by paging `t3_project_list` for each reachable
environment. The laptop and server glyphs are presentation, not API fields.

If Linked environments is off, `t3_environment_links` fails with
`code: "orchestration_error"` and the message says to turn it on in
Settings → Labs.

### Projects on a linked machine

`t3_project_list` accepts `environmentId`. Float passes a linked machine's ID
and follows `nextCursor` exactly as for local projects. Omitting
`environmentId`, or passing the top-level local ID, runs the call locally.

### Launching on a linked machine

`t3_thread_launch` accepts `environmentId` together with `projectId`. Float
passes both, omits `scratch`, and does not pass `workspaceStrategy`. T3 removes
`environmentId` before forwarding the call and the linked T3 server defaults
the omitted strategy to `{ "type": "root" }`, using that project's registered
checkout. Float never creates or asks for a branch, checkout, or worktree.

Forwarded launches cannot currently carry attachments. T3 rejects a linked
launch with non-empty `attachments` using `code: "invalid_request"` and
`"A launch in a linked environment cannot carry attachments yet."`

The linked-machine QA launch call is:

```json
{
  "name": "t3_thread_launch",
  "arguments": {
    "environmentId": "<reachable-linked-environment-id>",
    "projectId": "<project-id-from-that-environment>",
    "title": "Float linked machine QA",
    "message": "Reply with one short line containing the current working directory.",
    "runtimeMode": "approval-required",
    "interactionMode": "default",
    "clientRequestId": "<new-uuid>",
    "modelSelection": {
      "instanceId": "<Gemini-provider-instance-id>",
      "model": "<Gemini-3.8-Flash-model-id>"
    }
  }
}
```

There is deliberately no `scratch`, `workspaceStrategy`, branch, worktree, or
attachments field.

### Following a remote thread

Every later MCP call must keep the same `environmentId` as well as the remote
`threadId`: `t3_thread_read`, `t3_thread_send`, `t3_thread_configure`,
`t3_thread_interrupt`, and `t3_pending_request` for question answers all take
it. The same applies to paged reads. An environment ID equal to the local
top-level ID is treated as local.

The MCP response can wrap
`t3-thread://v2/<environmentId>/<threadId>` in a Markdown link. Float uses the
linked environment ID and returned thread ID to open
`t3code://threads/<environmentId>/<threadId>` in the desktop app,
percent-encoding both IDs.
The machine-linking settings route is `/settings/connections`, so the desktop
deep link is `t3code://app/settings/connections`; launching T3 Code is the
fallback.

### Offline and expired links

The offline result is the same for project list, launch, read, send, configure,
interrupt, and pending-request calls because they all use the forwarding
layer:

- An unreachable link fails with `code: "orchestration_error"` and either
  `"<label> did not answer at ..."` or `"The linked environment stopped answering."`.
- An expired link fails with `code: "capability_denied"` and
  `"The link to <label> expired. Link it again..."`.
- A removed or unknown link fails with `code: "invalid_request"` and says that
  the environment is not linked.
- A revoked credential or incompatible linked T3 version is a
  `capability_denied` failure. A remote server or protocol failure is an
  `orchestration_error`.

Float should use the selected machine's known label for the friendly notice
rather than exposing those transport messages.

## Questions

### Reading pending questions

The MCP tool is `t3_pending_request`. Its `list` action accepts an optional
`threadId` and `environmentId` and returns `{ "requestIds": [...] }` for
pending user-input requests only; approvals are deliberately omitted. `read`
adds a required `requestId` and returns:

```json
{
  "requestId": "<runtime-request-id>",
  "questions": [
    {
      "id": "scope",
      "header": "Scope",
      "question": "Which folders should I delete?",
      "options": [
        {
          "label": "Untouched for 30+ days",
          "description": "14 folders, 3.1 GB",
          "value": "stale",
          "preview": "..."
        }
      ],
      "multiSelect": false,
      "allowCustomAnswer": true,
      "initialAnswer": "stale",
      "required": true
    }
  ]
}
```

Only `id`, `header`, `question`, and `options` are guaranteed. An option always
has `label` and `description`; `value` and `preview` are optional. The remaining
question flags are optional too. Missing `multiSelect` is false. Missing
`allowCustomAnswer` is treated as allowing custom text by T3's client runtime.
Missing `required` is treated as required.

`thread.pendingRequestCount` counts every pending runtime request, including
approvals, while a question can leave `thread.status` and the active run status
as `running`. Float therefore cannot distinguish questions from approvals using
the thread read alone. When the count is positive, it must call
`t3_pending_request` with `action: "list"` on the same thread and environment.
A non-empty `requestIds` array means Float can render a question. An empty
array means the pending request is an approval or another request that still
uses the existing Open in T3 handoff.

### Building and sending answers

`ProviderUserInputAnswers` is a JSON object keyed by question ID. Each value is
either a string for single-select or custom text, or an array of strings for
multi-select:

```json
{
  "scope": "stale",
  "areas": ["server", "web"],
  "notes": "Only remove generated folders"
}
```

For an offered option, send its exact `value` when present, including any
whitespace. If `value` is absent, send the trimmed `label`. Multi-select keeps
the selected values in selection order and removes duplicates. Custom text is
a string and takes precedence over selected options. T3's client runtime
prevents custom text when `allowCustomAnswer` is explicitly false. A question
is incomplete until it has an answer, except an optional
`required: false` question with no options, which is represented by an empty
string.

Send the completed map with:

```json
{
  "action": "respond",
  "threadId": "<thread-id>",
  "environmentId": "<linked-environment-id-if-needed>",
  "requestId": "<runtime-request-id>",
  "answers": {
    "scope": "stale"
  }
}
```

The same `environmentId` used for the remote thread read is required for
`list`, `read`, and `respond`. `respond` only handles user-input requests and
cannot approve permission requests.

### Resume behavior and live proof

`respond` dispatches `runtime-request.respond`. It resolves the request, records
the answers, and forwards them to the provider session; the existing run
continues without a separate send or wake call. During the question, the
November 18 live read showed `thread.status: "running"`,
`pendingRequestCount: 1`, and a running recent run. After `respond`, the same
run completed, `pendingRequestCount` became zero, and the assistant's
continuation appeared in the normal thread messages.

The end-to-end check used one scratch thread through the streamable HTTP MCP
endpoint with `curl`. Antigravity's advertised `gemini-3.8-flash` with
`thinking_level: low` failed before it could ask because that publisher model
was unavailable to the configured Google project. The same scratch thread was
then configured to the cheapest usable fallback, Claude Haiku 5.5 with
`effort: low`. It asked a two-option Red/Blue question. `list` returned one
request ID, `read` returned the question, and this answer:

```json
{ "Choose a color": "Blue" }
```

was accepted by `respond`. The run resumed automatically and completed with
`You picked Blue.`

## Approvals

The running macOS Nightly server accepted a separately issued headless bearer
session on the V2 RPC socket. Float's existing `mcp-client` session was
rejected at the upgrade. Both checks used five-minute sessions on loopback.
The headless session reached `orchestration.getThreadProjection` and returned
a typed thread-not-found result for a generated ID. The probe revoked both
sessions afterwards.

### Read and respond

- The V2 RPC socket is `/ws?orchestrationProtocol=2`. The desktop calls
  `orchestration.dispatchCommand` with a `runtime-request.respond` command.
  It carries a fresh `commandId`, the `threadId`, the exact pending
  `requestId`, and a provider decision such as `accept` or `decline`.
  Optional feedback depends on the provider. T3 resolves the pending request
  and forwards the decision to the live provider session.
- Read the thread through `orchestration.getThreadProjection` or
  `orchestration.subscribeThread`. Join pending `runtimeRequests` with
  `approval_request` turn items by `requestId`. The item includes
  `requestKind`, and may include `prompt`, `reason`, `appName`, and provider
  options. If the provider includes a command or paths, they are part of the
  displayed request details. The contract does not promise separate command
  and path fields for every provider.
- MCP activity exposes the approval prompt and reason as text. Its timeline
  item ID differs from the runtime request ID, and `t3_pending_request`
  lists, reads, and responds to user-input questions only. The pending count
  can signal that a handoff is needed.

### Credentials and scope

- T3's desktop renderer gets its local bearer via the Electron preload bridge
  (`getLocalEnvironmentBearerToken`). The regular same-origin web client can
  use an HttpOnly browser session from `POST /api/auth/browser-session`.
  Bearer clients can mint short-lived RPC upgrade tickets via
  `POST /api/auth/websocket-ticket/rpc`; the local headless probe used an
  Authorization header. Neither desktop nor browser credentials are exposed
  as an external client integration. Float reads the loopback origin from
  `userdata/server-runtime.json` and gets a separate credential for MCP.
- T3 documents headless sessions in `docs/user/remote-access.md`,
  `docs/internals/environment-auth.md`, and the installed CLI's help.
  `t3 auth session issue --base-dir <t3-home> --subject <client>` accepts
  explicit repeated `--scope` flags, `--ttl`, and `--json`. The local owner
  can issue a session without a browser or a first-run pairing command.
  A pairing grant can also issue a separate session within the granted
  scopes. It has the same authorization limitations.
- Issuance returns the bearer, session ID, and expiry. T3 persists session
  metadata and revocation state in the environment database. The bearer is
  available at issuance and is not returned by `t3 auth session list`.
  `t3 auth session revoke <session-id> --base-dir <t3-home>` revokes it. A
  native client could hold a short-lived credential in memory, or use the
  Keychain if persistence were required.
- In `apps/server/src/auth/RpcAuthorization.ts`, the projection requires
  `orchestration:read` and dispatch requires `orchestration:operate`.
  The latter also permits launching full-access runs and other orchestration
  mutations. The contract has no approval-only or per-thread scope for this
  command. The MCP subject is deliberately barred from RPC, where its
  runtime-mode ceiling would no longer apply. A linked environment would
  also require a grant for its own RPC surface.

Float keeps the Open in T3 handoff. The supported headless credential grants
broader access than approval responses require. An approval-specific scoped
endpoint or an extension of the existing pending-request MCP contract would
provide a path for the in-app controls.
