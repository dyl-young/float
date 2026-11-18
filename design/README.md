# Float design

These mockups are the source of truth for Float's UI. When the app and a mockup disagree, change the app. Any change to the design starts here.

| File | Shows |
| --- | --- |
| `shell-states.png`, `float-mockups.html` | The shell: a solid message tray, the frosted input and a solid footer, with concave corners where they meet. Also every state: summoned, pasted images, working, replied, needs approval, asks a question, T3 offline, model picker. |
| `pickers.png`, `float-pickers.html` | Choosing a machine and a project (new chats only, never a branch or checkout), and the model picker across providers: favourites, provider tabs, search, disabled provider. |
| `assets/providers/` | T3's own provider icons, copied from the T3 repo: `codex.svg` (T3 uses the OpenAI mark for Codex, in the text colour), `claude.svg` (`#D97757`), `cursor.svg` (`#EDECEC` on dark), and `antigravity.png` (T3 ships it as a 128px PNG). Float uses these exact assets, never redrawn approximations. |
| `logo.png`, `float-*.svg` | The cloud logo: app icon, template glyph for the menu bar, and the filled variant. |

Open the HTML files in a browser to inspect sizes. Their CSS variables map to `Sources/Float/Theme.swift`:

| CSS variable | Theme |
| --- | --- |
| `--card` | `surface` / `tray` |
| `--popover` | `raised` |
| `--primary` | `accent` |
| `--muted-foreground` | `muted` |
| `--border` | `border` |
| `--success` | `success` |
| `--warning` | `warning` |
| `--destructive` | `error` |

The colours come from Dylan's nordbones T3 theme. So do the pixel thinking loader and the composer layout.

## Fixed rules

- **Opaque panel, frosted input.** The panel is opaque, so the desktop never shows through. The conversation scrolls up *behind* the frosted input, and the input blurs the message text under it, as in T3's composer. The solid footer tucks under the input with concave corners. The input's top corners are drawn as solid concave ears over the scrolling content.
- **Input rim.** As in T3, the frosted input has a 1px hairline ring (foreground at about 9%) that follows its 16pt corners all the way round, so it reads as its own inset card. The input is inset 1pt from the shell's left and right edges, so a 1pt strip of solid tray separates the shell border from the rim and the two lines never merge.

- **Corner radius:** 16 for the shell, 12 for your message bubbles, 10 for cards and menus, 6 for chips.
- **Thinking loader:** the 3×3 pixel grid, 4 frames, stepping every 300 ms, followed by T3's shimmering "Thinking" text and the elapsed time. The shimmer copies T3's `live-activity-focus` (`apps/web/src/index.css`): the word in the muted colour, with a 4.5rem band of the text colour sweeping left to right every 2.2 s in 30 steps, fading in and out at 12% → 55% → 100% → 55% → 12%. With Reduce Motion, no sweep. These two are the only progress indicators.
- **Replies:** show only assistant text. Never show tool calls, with one exception: text an agent shows you through T3's `send_to_user` tool is part of the reply, in order, rendered as Markdown like any other reply text (T3 shows it the same way). Code blocks copy T3's `MarkdownCodeBlock`: radius 8, the input colour at 32% on dark, a header row with the language's file icon from T3's icon set on the left (or the language name when there's no icon) and wrap and copy buttons on the right, then the code in monospaced text in the text colour, wrapped by default. No syntax highlighting. Replies have no bubble: plain text on the tray, as in T3. Under each reply sits a muted row with the copy button first, then the time, left-aligned. Only your own messages sit in bubbles.
- **Header:** a close button (×) at the top left, then a crumb as T3 shows a thread: the project's icon (T3's project icon when it has one, otherwise a folder) and name in the muted colour, plus " · <machine>" when the thread isn't on this Mac, then a muted slash, then the title in the text colour. A chat with no project shows just the title. No status dot, except a grey one while T3 or the thread's machine is disconnected. New chat and Open in T3 sit on the right. The × hides the panel, the same as Esc; the draft and chat stay. The compact state has no header, so Esc hides it there. Quit Float lives in the menu bar cloud's right-click menu. You can drag the window by the header as well as the footer.
- **Questions and approvals:** when an agent asks you something through T3's ask-user-question tool, Float shows a question card in the tray: the header in small caps, "1 of N" when there are several, the question, and the options with their descriptions. Number keys pick, Return confirms, and typing in the input answers in your own words when the question allows it. The answer goes back through T3. Tool approvals are answered in Float too (state 5): the approval card shows what the agent wants to do, with Allow (primary, ⌘↵), Deny, and a small Open in T3 link for the full request, so the run keeps going without opening T3.
- **Footer:** paperclip on the left; provider icon, model and send/stop on the right.
- **Panel size:** once a chat has a tray, the panel opens straight to its full size, even for the first message, and never grows or shrinks as messages stream in. You set that size yourself: drag the top edge to change the height, or either top corner to change the height and the width together. The bottom edge and the input stay anchored, so dragging moves only the top (and the dragged side). Grab zones: 4pt along the top edge with the up-down cursor, 10×10pt at the top corners with the diagonal cursor. Limits: height 240pt to 85% of the screen's visible height; width 420pt to 900pt. Float remembers the size. Double-clicking the top edge resets it to the default (560pt tall, today's width). The compact state, with no tray, keeps its width and never resizes.
- **Dragging:** you can drag the window by the header, the footer's empty space, and a thin strip along the top edge of the input (6pt, arrow cursor), which matters in the compact state where there's no header.
- **Pickers:** the model, project and Run on pickers keep one size and one anchor while open, whatever tab or query is showing, so they never jump. The model picker is a fixed 300×360pt and its bottom-right corner stays pinned above the model button; the list scrolls inside it. The current item sits in a filled pill in nordbones `secondary` (`#1C3349`, radius 8), as T3 marks a selected chip, with no checkmark. Hover and the keyboard highlight use the text colour at 6%. Trailing status dots line up in one column.
- **Keyboard:** ⌥Space toggles Float, Esc hides it (or closes an open picker first), Return sends, ⇧Return adds a new line, the standard editing keys work in the input (⌘A, ⌘C, ⌘X, ⌘V, ⌘Z, ⇧⌘Z), ⌘V also pastes images, ⌘N starts a new chat, ⇧⌘M opens the model picker, ⇧⌘P the project picker, ⌘H the Run on picker, ⌘. stops a run.
- **Shared centre lines:** the header's × sits on the same vertical centre line as the footer's paperclip, and Open in T3 on the same line as the send ring, 21pt in from each inner edge of the shell.
