# Float roadmap

The designs live in `design/`. Work is planned in batches; items move from "Next" into a batch when they're scheduled.

## In progress
- **Batch 2:** an opaque panel with messages scrolling behind the frosted input, plus the input rim; a stop button (⌘.); dragging from the header; scroll bars and follow-while-streaming; alignment fixes; image preview wrapping; error states; smooth resize; Markdown blocks.

## Next
In this order:
1. **Model picker v2 (multi-provider model selection):** see `design/pickers.png`, items 5–8. Favourites, provider tabs, search across providers, an effort control, and disabled providers that explain themselves.
2. **Project selection on this Mac:** see `design/pickers.png`. A Project menu in the context row for new chats, listing the T3 projects on the local machine, with "No project" as the default. The project locks into the header subtitle after the first send. Never a branch or checkout picker.
3. **Machine selection:** the Run on menu in the same context row, for starting a chat on another T3 environment, such as the Mac mini. Comes after local project selection works.

## Later
- **Skills support:** use T3 skills from the composer, as T3's "$ skills" does. This covers a `$` trigger with a skill picker, a skill chip in the input, and sending the skill with the prompt through T3's API. Not scheduled yet.
- Voice input (the mic button in the T3 composer).
