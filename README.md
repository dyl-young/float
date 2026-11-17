<img src="assets/icon.svg" width="64" height="64" alt="">

# Float

Float is a native macOS menu bar app for quick chats and agent tasks in local T3 Code. It opens as a compact composer and expands to show the conversation.

## Build and open

You’ll need macOS 14 or newer, Swift 6, and a local T3 Code build with the thread and attachment MCP tools. Float uses the T3 CLI at `~/.t3/bin/t3`. Enable Codex or Claude Code in T3’s provider settings and sign in before sending your first prompt.

```sh
./App/build.sh
open dist/Float.app
```

## Use Float

- Press **Option–Space** to show or hide Float. **Esc** hides it. If another app has that shortcut, use **Show or Hide Float** in the menu bar.
- Drag the empty space in the composer’s footer to move Float.
- Press **Return** to send and **Shift–Return** for a new line. Paste a screenshot with **Command–V** or use the paperclip to attach images. Each message can include up to eight images of 10 MB each.
- Use the model menu to pick an enabled Codex or Claude Code model. A model change applies to your next prompt, and Float remembers your choice for new chats. **Default** restores automatic selection. On a Codex-only device, Float defaults to GPT-6.1 Sol when T3 offers it.
- Float starts chats in T3’s **No project** workspace. The active chat and draft stay in place when you hide Float. Float remembers the last thread and unsent text across relaunches.
- Replies appear in chunks while the model is running. The top buttons start a new chat and open the current thread in T3. Runs continue in T3 while Float is hidden. Open the thread in T3 to handle agent approvals and questions.
- If the local server is unavailable, **Launch T3** starts the app and leaves your draft ready to send. Float reconnects to reload the current conversation after a brief interruption.

## Development

`swift test` checks MCP framing, timestamps, attachment URL validation, and T3 desktop links. `./App/build.sh debug` builds a debug app bundle.

Float uses AppKit for the panel and paste handling, and SwiftUI for the composer and conversation. The T3 client follows the local discovery, scoped authentication, and streamable HTTP patterns in T3’s `cli/thread.ts` and `mcp/AcpMcpStdioBridge.ts`. T3 owns thread execution and history. Float uses its scratch launch, attachment upload, and timeline APIs on loopback with an in-memory bearer session. Runs use T3’s approval-required mode.
