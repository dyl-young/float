# Float roadmap

The designs live in `design/`. Work is planned in batches; items move from "Next" into a batch when they're scheduled.

## In progress
- **Batch 2:** an opaque panel with messages scrolling behind the frosted input, plus the input rim; a stop button (⌘.); dragging from the header; scroll bars and follow-while-streaming; alignment fixes; image preview wrapping; error states; smooth resize; Markdown blocks.

## Next
In this order:
1. **Model picker v2 (multi-provider model selection):** see `design/pickers.png`, items 5–8. Favourites, provider tabs, search across providers, an effort control, and disabled providers that explain themselves.
2. **Project selection on this Mac:** see `design/pickers.png`. A Project menu in the context row for new chats, listing the T3 projects on the local machine, with "No project" as the default. The project locks into the header subtitle after the first send. Never a branch or checkout picker.
3. **Machine selection:** the Run on menu in the same context row, for starting a chat on another T3 environment, such as the Mac mini. Comes after local project selection works.
4. **UI polish against T3 Code:** run the same workflows side by side in Float and in T3 Code (a quick question, a long streamed reply, pasting images, stopping a run, a failed run, switching models, an approval, reopening a thread) and note where T3 feels better. Decide which of those details are worth porting so Float feels as native as possible, such as T3's shimmering "Thinking" text next to the pixel loader. Each port gets a mockup in `design/` first; a change to a fixed rule in `design/README.md`, like "the loader is the only progress indicator", is Dylan's call.
5. **Answer questions in Float:** when an agent calls T3's ask-user-question tool, show the question and its options in Float and send the answer back through T3's API, so you don't have to switch to T3 Code to reply. See state 6 in `design/shell-states.png` and the "Questions and approvals" rule. Tool approvals still hand off to T3.
6. **Resizable height:** drag the panel's top edge to set how tall the conversation can grow. Height only, never width, within sensible limits. See "Panel height" in `design/README.md`. Small enough to ride along with an earlier batch.

## Later
- **Skills support** (after item 5): use T3 skills from the composer, as T3's "$ skills" does. This covers a `$` trigger with a skill picker, a skill chip in the input, and sending the skill with the prompt through T3's API. Not scheduled yet.
- Voice input (the mic button in the T3 composer).
