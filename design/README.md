# Float design

These mockups are the source of truth for Float's UI. When the app and a mockup disagree, change the app. Any change to the design starts here.

| File | Shows |
| --- | --- |
| `shell-states.png`, `float-mockups.html` | The shell: a solid message tray, the frosted input and a solid footer, with concave corners where they meet. Also every state: summoned, pasted images, working, replied, needs approval, T3 offline, model picker. |
| `pickers.png`, `float-pickers.html` | Choosing a machine and a project (new chats only, never a branch or checkout), and the model picker across providers: favourites, provider tabs, search, disabled provider. |
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
- **Input rim.** As in T3, the frosted input has a 1px hairline ring (foreground at about 9%) that follows its 16pt corners all the way round, so it reads as its own inset card.

- **Corner radius:** 16 for the shell, 12 for your message bubbles, 10 for cards and menus, 6 for chips.
- **Thinking loader:** the 3×3 pixel grid, 4 frames, stepping every 300 ms. It's the only progress indicator.
- **Replies:** show only assistant text. Never show tool calls. Replies have no bubble: plain text on the tray, as in T3. Under each reply sits a muted row with the copy button first, then the time, left-aligned. Only your own messages sit in bubbles.
- **Header:** a close button (×) at the top left, then the status dot, title, and project and machine subtitle, then New chat and Open in T3 on the right. The × hides the panel, the same as Esc; the draft and chat stay. The compact state has no header, so Esc hides it there. Quit Float lives in the menu bar cloud's right-click menu. You can drag the window by the header as well as the footer.
- **Footer:** paperclip on the left; provider icon, model and send/stop on the right.
