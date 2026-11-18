# Testing Float with real chats

These rules apply to every agent that tests or QAs Float by sending real prompts, through Float or straight through T3's API.

## Start every test chat in the Float project

Dylan filters test sessions out of T3's sidebar by project, so every test chat must start in the Float project, never as a "No project" scratch chat:

| Machine | Float project ID | Checkout |
| --- | --- | --- |
| Mac mini | `0e51166a-90ec-46ca-a2c2-7dc566d71ce2` | `~/dev/float` |
| Laptop | `5e6632d4-a8a9-4fba-96b6-f11b0778a9de` | `~/repos/dev/float` |

- In Float, pick the Float project in the context row before the first send.
- Through T3's API, pass the project ID to `t3_thread_launch` (no `scratch`, no worktree or branch).
- On another machine, use its Float project if it has one. If it doesn't, skip that check and say so, rather than starting a scratch chat.
- The only exception is a check that's specifically about "No project" chats. Then start one scratch chat, no more, and name it in your report.

## Keep the prompts cheap and harmless

- Send test prompts only to cheap, fast models: Antigravity's Gemini 3.8 Flash with thinking low, or Claude Haiku. Never Codex.
- Keep each prompt to one short line. For a long reply, ask for about 12 short lines.
- Test chats run in the Float checkout, so prompts must not change it. Use prompts like `Reply with exactly: Float QA`. Approval tests may run a harmless command such as `echo float-approval-test`. Never ask an agent to edit, delete or commit anything.

## Leave T3 as you found it

- Don't quit or restart T3. It hosts the agents doing the testing.
- Don't change T3's settings. If a test stars a model or issues a credential, restore or revoke it before you finish.

## Captures

- Capture the Float window by window ID with `screencapture -x -o -l<windowID>`. It works while the screen is locked.
- Save captures under `design/qa/<batch>/` and commit them.
- Never capture or commit secrets such as bearer tokens.
