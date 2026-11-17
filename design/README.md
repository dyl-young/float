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
- **Thinking loader:** the 3×3 pixel grid, 4 frames, stepping every 300 ms. It's the only progress indicator.
- **Replies:** show only assistant text. Never show tool calls. Replies have no bubble: plain text on the tray, as in T3. Under each reply sits a muted row with the copy button first, then the time, left-aligned. Only your own messages sit in bubbles.
- **Header:** a close button (×) at the top left, then the status dot, title, and project and machine subtitle, then New chat and Open in T3 on the right. The × hides the panel, the same as Esc; the draft and chat stay. The compact state has no header, so Esc hides it there. Quit Float lives in the menu bar cloud's right-click menu. You can drag the window by the header as well as the footer.
- **Questions and approvals:** when an agent asks you something through T3's ask-user-question tool, Float shows a question card in the tray: the header in small caps, "1 of N" when there are several, the question, and the options with their descriptions. Number keys pick, Return confirms, and typing in the input answers in your own words when the question allows it. The answer goes back through T3. Tool approvals still hand off to T3 with Open in T3.
- **Footer:** paperclip on the left; provider icon, model and send/stop on the right.
- **Panel height:** the width is fixed. The tray grows with the conversation up to a maximum height, and you can drag the panel's top edge to change that maximum: a 4pt grab zone along the top with the up-down resize cursor. The input stays anchored at the bottom, so dragging moves only the top. Limits: at least 240pt (header, a few lines and the composer), at most 85% of the screen's visible height. Float remembers the height. Double-clicking the top edge resets it to the default 560pt. The compact state, with no tray, never resizes.
- **Shared centre lines:** the header's × sits on the same vertical centre line as the footer's paperclip, and Open in T3 on the same line as the send ring, 21pt in from each inner edge of the shell.
