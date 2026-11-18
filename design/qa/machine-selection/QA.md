# Machine selection QA

Run these checks on a Mac with at least one linked T3 machine. Do not add a
branch, checkout, or worktree at any point.

1. **State 1 — new chat:** Open a new chat while at least one linked machine is
   known. Confirm the context row has Run on before Project, both chips match
   the mockup, and the Run on chip disappears when T3 reports only This Mac.
2. **State 2 — Run on menu:** Open it by click and by ⇧⌘R. Confirm it opens
   upward, This Mac is first, linked machines follow, online rows have green
   dots, and any offline row is dimmed and cannot be selected. Check ↑, ↓,
   Return, and Esc. Confirm “Link machines in T3” opens Connections settings.
3. **State 3 — linked project:** Pick an online linked machine. Open Project
   and confirm its header says `On <machine name>`, only that machine's projects
   appear, and a project with the same ID is retained while a missing one
   resets to No project.
4. **State 4 — real linked launch:** Pick a small project on the linked machine,
   select Gemini 3.8 Flash, and send one short line. Confirm the thread starts
   in the registered project checkout without creating a branch or worktree.
   Confirm the context row disappears and the header shows the folder icon and
   `<project> · <machine>`. Send a follow-up, stop a run, reopen Float, and use
   Open in T3; all actions must address that same remote thread.
5. **Offline notice:** If it is safe, disconnect the linked machine while its
   thread is open. Confirm Float shows `<machine> is offline`, the notice fits
   between the header and input, and typed draft text remains. Reconnect and
   confirm the thread can continue.
