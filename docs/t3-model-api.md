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
