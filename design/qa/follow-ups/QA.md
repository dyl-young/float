# Panel sizing and follow-up QA

## Sizing

The baseline saved dimensions after each synthetic AppKit drag. The top edge changed height only, and the left and right corners also saved width. A packaged relaunch restored the 591 × 632 pt tray but opened compact at the default 516 pt shell width. The same width jump occurred on ⌘N.

The fix restored a resized 666 × 704 pt tray after quitting and relaunching. ⌘N left a 666 pt shell and a 159 pt compact window height. The compact window frame was 718 pt wide including the transparent context-strip margins. The standalone `swift run` process had no bundle ID and restored the same dimensions using the explicit Float defaults suite.

- [Resized tray](size-resized.png)
- [After ⌘N](size-command-n.png)
- [Tray after relaunch](size-relaunched.png)

The synthetic upward drags reached the screen’s visible top edge, where AppKit moved the frame down to keep it onscreen. The captures verify dimension persistence.

## State 3b

The [typed footer](mock-steer-footer.png) shows the blue steer ring directly left of Stop. The red Stop ring and Open in T3 share their centre line. The [waiting state](mock-steer-waiting-queued.png) shows the muted steer label, the dimmed dashed queue bubble with its ×, and the thinking timer. The [read state](mock-steer-read.png) shows the shorter label after the simulated T3 endpoint changed the same user item from `pending` to `completed`. Float sent `mode: steer` on Return and `mode: queue` on ⌘Return to that endpoint. The panel stayed at 666 × 704 pt through these changes.

The [live queued message](live-gemini-queued.png) and [delivered turn](live-gemini-delivered.png) are from the Float project on this Mac. The selected model was Antigravity Gemini 3.8 Flash with low thinking. Float queued the follow-up, T3 started it after the first turn, and the model replied. In a separate run, the same cancellation action used by × removed a queued follow-up and T3 recorded its run as cancelled.

Live steering was unavailable on Gemini 3.8 Flash. T3’s Claude Code adapter supports steering. The provider was disabled on both environments. The linked HP also had no Float project in its project list. The steer captures exercise real Float keyboard, dispatch, and rendering code against a local simulated T3 endpoint. No live model received those simulated prompts.

Float reads `followUpBehavior` from T3’s local client settings and defaults to steer. The image send endpoint uses T3’s automatic attachment handling. Explicit queueing with images and linked-machine image uploads are unavailable through the current MCP attachment endpoint. Live attachment follow-ups were outside these checks.
