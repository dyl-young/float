# Project selection QA

Compare each screenshot with states 1, 3 and 4 in `design/pickers.png`.
Use the same 516pt Float panel width. Do not expect a machine control, branch
control, worktree control or checkout control.

## State 1: new chat

1. Start a new chat with no saved project:
   `defaults delete com.dylyoung.float preferredProjectID`
2. Show Float and capture the whole panel.
3. Check that the panel is 30pt taller than the shell and has one context chip
   below it, aligned 8pt from the shell edge.
4. The chip should be 22pt high with a pencil, "No project" and a chevron in
   muted 11.5pt text.

## State 3: filtered menu

1. Press Shift-Command-P.
2. Check that the 250pt-wide menu opens upward, its search field has focus and
   "No project / Scratch chat, no repo" is first.
3. Type `fl` and capture the whole panel and menu.
4. Check that only matching project names or paths remain below No project,
   the shortened paths start with `~`, the current row has an accent checkmark,
   and the footer says `↑↓ move` and `↵ pick`.
5. Check Up, Down, Return and Esc. The first Esc closes the menu. A second Esc
   hides Float.

## State 4: locked project

1. Pick `float`, send one cheap prompt and capture Float after T3 accepts it.
2. Check that the context row is gone. The header subtitle should have a small
   folder followed by `float`.
3. Shift-Command-P must not reopen the project menu for this thread.
4. Command-N should return to a new chat with the context row and the last
   project restored.
5. Open in T3 should open the launched thread.

The launch made by Float must match this payload, with real IDs:

```json
{
  "name": "t3_thread_launch",
  "arguments": {
    "title": "<first prompt line>",
    "projectId": "<selected-project-id>",
    "message": "<prompt>",
    "attachments": [],
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

There must be no `scratch` or `workspaceStrategy` argument.

## Error state

1. Stop T3 Code, start a new chat and open the project menu.
2. Capture the menu with its muted "Couldn't load projects" row and Retry
   button. No project must remain selectable.
3. Restart T3, click Retry and check that the local projects return.
4. If a disposable missing-project fixture is available, choose it, type a
   draft and send. Check for the "Project unavailable" notice card and confirm
   that Float keeps the draft.
