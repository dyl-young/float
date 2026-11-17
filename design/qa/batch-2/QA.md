# Float Batch 2 Visual QA Report

Conducted on macOS 14.x with Float debug build at commit `a6389b9 feat: make panel height resizable`.
Screen session status: `CGSSessionScreenIsLocked: 1` (locked). Items requiring live mouse dragging or system modifier shortcuts are marked `Not checked (locked)` per instructions.

| Screenshot | State Shown | Mockup State | Result | Specific Reason |
| --- | --- | --- | --- | --- |
| `qa-01-replied.png` | Replied assistant message | Mockup state 4 | **Pass** | Plain text on tray with no bubble across full width; copy icon and time left-aligned and muted underneath; user message in right-aligned bubble; 12pt gap between turns. |
| `qa-02-header-alignment.png` | Header and footer center alignment (2×) | Mockup state 4 / shared center lines | **Pass** | At 2×: × center x=43.0px vs paperclip center x=42.7px (Δ=0.32px < 1px); Open in T3 center x=987.7px vs send ring center x=986.7px (Δ=0.98px < 1px); New chat sits 6pt (12px at 2x) left of Open in T3. |
| `qa-03-input-side-gap-compact-left.png` | Input left edge in compact mode (2×) | Mockup state 1 | **Pass** | 1pt solid tray strip separates outer shell border from inner input rim hairline; footer ear stays full width. |
| `qa-03-input-side-gap-compact-right.png` | Input right edge in compact mode (2×) | Mockup state 1 | **Pass** | 1pt solid tray strip separates outer shell border from inner input rim hairline; footer ear stays full width. |
| `qa-03-input-side-gap-convo-left.png` | Input left edge with conversation (2×) | Mockup state 4 | **Pass** | 1pt solid tray strip separates outer shell border from inner input rim hairline; footer ear stays full width. |
| `qa-03-input-side-gap-convo-right.png` | Input right edge with conversation (2×) | Mockup state 4 | **Pass** | 1pt solid tray strip separates outer shell border from inner input rim hairline; footer ear stays full width. |
| `qa-04-frost.png` | Message text scrolling behind frosted input | Mockup state 4 / fixed rules | **Pass** | Text under frosted input is blurred but recognisable; solid tray backdrop ensures desktop never shows through. |
| N/A (Item 5) | Image wrapping with eight pasted images | Mockup state 2 / 3 | **Not checked (locked)** | Sending Cmd-V pasteboard events with multiple image file URLs is intercepted/dropped by loginwindow while screen is locked. |
| `qa-06-markdown.png` | Rendered Markdown blocks in assistant reply | Mockup state 4 | **Pass** | Correct heading hierarchy, hanging indents on bullet and numbered lists, accent-coloured link, and 8pt radius monospaced code box with language tag, copy button, and horizontal overflow. |
| `qa-07-error-t3-offline.png` | T3 offline error banner in active conversation | Mockup state 7 | **Pass** | Notice card renders icon, error description "The local T3 server isn't responding.", "Launch T3" button, and dismiss ✕; header status dot muted. |
| `qa-07-error-notice-only.png` | Notice-only tray (T3 offline, no conversation) | Mockup state 7 | **Fail** | Notice text is clipped off under header fade mask because timeline scrolls down by `inputHeight` to `Self.latest`, leaving only the "Launch T3" button visible. Header correctly shows title "Float" with × and no New chat / Open in T3 buttons. |
| N/A (Item 8) | Close button hover tooltip, ⌥Space toggle, menu bar Quit | Mockup state 4 & menu bar | **Not checked (locked)** | WindowServer tooltips, Carbon global hotkey (⌥Space), and status bar menu popups are suppressed while screen is locked. |
| `qa-09-resize-burst-0.png` | Burst capture 0: compact state before send | Mockup state 1 | **Pass** | Initial compact panel height 84pt before first send. |
| `qa-09-resize-burst-1.png` | Burst capture 1: tray opening animation | Mockup state 1 -> 3 | **Pass** | Animated height growth (119pt); input stays firmly anchored at bottom with no vertical jump. |
| `qa-09-resize-burst-2.png` | Burst capture 2: tray expanded with thinking | Mockup state 3 | **Pass** | Animated height growth (178pt) with thinking loader and red stop ring; input remains stationary. Closing on ⌘N is Not checked (locked). |
| `qa-09-resize-burst-3.png` | Burst capture 3: tray steady during stream | Mockup state 3 | **Pass** | Tray height stable at 178pt; composer positioned without jitter. |
| `qa-09-resize-burst-4.png` | Burst capture 4: tray steady before reply arrival | Mockup state 3 | **Pass** | Tray height stable at 178pt; composer positioned without jitter. |
| `qa-10-provider-icon-antigravity.png` | Antigravity icon in model button (2×) | Mockup pickers state 5 | **Pass** | Renders T3's exact multi-color `antigravity.png` asset, not a line drawing. Model popup menu is Not checked (locked). |
| `qa-10-provider-icon-codex.png` | Codex icon in model button (2×) | Mockup pickers state 6 | **Pass** | Renders exact OpenAI mark from `codex.svg`. Model popup menu is Not checked (locked). |
| `qa-11-resize-minimum-240.png` | Panel resized to minimum height (240pt) | Mockup state 4 / panel height rules | **Pass** | Window correctly clamps to exact minimum height of 240pt (header, conversation, composer). Compact state has no resize handle and does not resize. |
| `qa-11-resize-tall-750.png` | Panel resized to tall height (750pt) and persisted | Mockup state 4 / panel height rules | **Pass** | Window expands to 750pt maximum and persists across app restarts via `panelMaximumHeight`. Double-click reset and live resize cursor are Not checked (locked). |
| N/A (Item 12) | Batch 1 shortcut verification and menu bar cloud | Batch 1 checklist | **Not checked (locked)** | Screen is locked by loginwindow; skipped per instructions. |
