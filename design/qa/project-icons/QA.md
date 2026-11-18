# Project icon QA

| Mockup in [pickers.png](../../pickers.png) | Window capture | Comparison |
| --- | --- | --- |
| 1b | [Context chip](01-context-chip.png) | The 12pt favicon sits beside the muted `float` label in the compact context strip, below the composer. The real checkout favicon has a dark tile and a light cloud. The mockup uses a blue tile. The window capture preserves transparency, so it does not show the light wallpaper in the mockup. |
| 3 | [Live project picker](02-project-picker.png) | The 13pt slots show T3’s actual favicons for `no-stack` and `pi-durable-lab`, the cyan `images` override for `gallery-ops`, and the green `DV` monogram for `dev`. The pencil remains on the first row. |
| 3 | [Filtered picker with a fixture](02b-project-picker-mockup-fixture.png) | Filtering on `fl` shows the real `float` favicon and a purple `FR` tile for a temporary `flow-reports` fixture in the picker. The 250 × 270pt picker kept the same screen origin while filtering and reopening. The 13 × 13 favicon crop was pixel-identical on the first capture after reopening. |
| 4 | [Local thread header](03-local-thread-header.png) | An existing Float project thread shows the 11pt favicon, muted project name and slash, and brighter thread title. The context strip is absent. |
| 4 | [Remote header fixture](04-remote-thread-header-fixture.png) | The 11pt monogram is followed by `flow-reports · dylans-hp`, a muted slash, and the thread title. The live HP responded to T3, but its only project was `No project`, so there was no live remote project crumb to capture. |

The Mac captures use T3’s live project catalog and existing thread data in an isolated Float build. Window IDs were captured with `screencapture -x -o -l<windowID>`. The locked screen prevented a key window, so the isolated picker harness bypassed its key-window gate and set the search binding directly. The live keyboard shortcut and search focus were unverified. No prompts were sent.

Float fetches local favicons through T3’s read-only `assets.createUrl` V2 RPC and downloads the resulting signed asset from the same loopback origin. T3’s linked-machine MCP tools return project metadata. The asset RPC needs a separate connection to the target environment with read authorization, which Float’s MCP link does not supply. Linked projects use the reported override or the derived monogram. Lucide overrides use a small SF Symbols mapping, with monograms for unmapped names. Emoji use macOS emoji glyphs.

`swift build` and all 78 tests passed.
