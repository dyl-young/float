# Float roadmap

The designs live in `design/`. Work is planned in batches. Items move from "Next" into a batch when they're scheduled. Testing rules for agents are in `docs/testing.md`.

## Done (2026-11-17 to 2026-11-18)
- **Shell:**
  - opaque panel with a frosted input and rim
  - stop (⌘.)
  - header crumb `<project> / <title>`, the ×, and Quit
  - drag strip
  - fixed-size panel with top-edge and corner resize
  - knob-only scroll bars
  - error and offline cards
  - T3's thinking shimmer
- **Replies:**
  - no bubble, one copy-and-time row per turn
  - `send_to_user` messages
  - T3-style code blocks
  - full GitHub-flavoured Markdown with tables, in replies and your own messages
- **Model picker v2:**
  - favourites from T3
  - provider tabs and search across providers
  - effort for every provider
  - disabled providers that explain themselves
  - ↑↓ and Return
- **Context row:** project selection (⇧⌘P) and machine selection (Run on, ⇧⌘H) for new chats. Never a branch or checkout picker.
- **Answering agent questions in Float** (state 6).
- **Approvals in Float:** opt-in, with a revocable Keychain credential. Allow (⌘↵) and Deny for threads on this Mac. Threads on other machines hand off to T3.
- **Auto mode:** new threads on this Mac start in T3's Auto mode, or the broadest mode the provider offers below it. Float gets Auto by signing in through T3's MCP app sign-in, which it approves itself with a five-minute session from the local `t3` CLI. Threads on linked machines start Supervised.
- Editing keys behave like any macOS text field.

## Next
In this order:
1. **Fixes from Dylan's testing:**
   - chat titles show raw Markdown (for example backticks)
   - one failing Markdown test (`providesWebAutolinksAndImageLinksAndDisplaysHTMLLiterally`)
   - anything else found in use
2. **UI polish against T3 Code:** run the same workflows side by side in Float and in T3 Code and note where T3 feels better:
   - a quick question
   - a long streamed reply
   - pasting images
   - stopping a run
   - a failed run
   - switching models
   - an approval
   - reopening a thread

   Then decide which of those details are worth porting. Each port gets a mockup in `design/` first. A change to a fixed rule in `design/README.md` is Dylan's call.
3. **Auto mode on linked machines:** today they start Supervised, because the link caps Float's access. Find out whether a linked machine can grant Auto the same way, and if so, use it.

## In progress
- **Skills and commands (`$` and `/`):** see `design/pickers.png` states 9–11 and the "Skills and commands" rule in `design/README.md`.

## Later
- **Voice input:** the mic button in the T3 composer.
