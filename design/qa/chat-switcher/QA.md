# Chat switcher QA

| Capture | Comparison with [picker states 12 and 13](../../pickers.png) |
| --- | --- |
| [01 · Switcher](01-switcher.png) | State 12. The selection pill covers the full crumb and chevron. The 320 × 321pt picker starts 6pt below the crumb and shows Working, Pinned and Active, with the current thread selected. Working shows the pixel grid and elapsed time. |
| [02 · Search](02-search.png) | State 12. Searching for `history` leaves one Active result. The picker kept its window ID, origin and 320 × 321pt size. The Down event carried the macOS function and numeric-pad flags. Esc dismissed the picker and kept the conversation open. |
| [03 · Crumb hover](03-crumb-hover.png) | State 13. Only the project, slash, title and chevron have the 6% text tint with a 6pt corner radius. The harness set the crumb’s hover state for this capture. |
| [04 · Earlier messages](04-resumed-history.png) | State 13. The Float test thread opened with its latest 10 user and assistant messages. The centered “Earlier messages · Open in T3” line is at the top of the tray. The Float project and Gemini 3.8 Flash remain visible, and the context row is hidden. |
| [05 · Running thread](05-resumed-running.png) | State 13 with a live run. Switching from the pinned test thread showed the new user message, the thinking grid and the Stop button. The Float panel stayed 516 × 560pt at the same origin. |
| [06 · Compact shortcut](06-compact-shortcut.png) | State 12 adapted to compact Float. ⌘K opened a 320pt picker 6pt above the input without changing the compact window. ⌘N cleared the resumed chat and restored the compact context row. |

Window captures used the verified worktree app’s window IDs with `screencapture -x -o -l<windowID>`. The Mac was locked. The temporary AppKit harness kept the windows visible, routed keyboard and click events, and bypassed the picker’s key-window guard. The search field became first responder in that harness. The physical shortcut and hover delivery still need an unlocked-screen check.

The live QA thread and its follow-up ran in the Float project on Antigravity Gemini 3.8 Flash with low thinking. The running test requested 12 short lines. Float displayed the streamed reply and delivered a one-line follow-up on the same model. Relaunching restored the resumed thread, the 10-message history and the T3 desktop URL. The temporary pin was removed and verified in T3. The reachable linked HP returned zero eligible threads. After the running capture, ⌘. stopped the resumed run and T3 reported it interrupted. Live questions, approvals and T3 foreground navigation remain unverified.
