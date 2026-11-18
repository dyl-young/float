# Agent question QA

Run these checks on the screenshot-capable Mac. Use Antigravity Gemini 3.8
Flash with thinking set to low. If that model cannot call the question tool,
use the cheapest enabled model that can and record the fallback.

Keep each test to one prompt:

1. **Single select:** `Ask me one required single-select question with two options using your ask-user-question tool, then reply with the option I pick.`
   Select one option, capture Float beside state 6 in
   `design/shell-states.png`, answer it, and confirm in T3 that the same run
   continued with the selected option.
2. **Multi-select:** `Ask me one required multi-select question with three options using your ask-user-question tool, then reply with every option I pick.`
   Select at least two options and capture the multiple tinted rows and
   checkmarks. Answer it and confirm the continuation in T3 names both.
3. **Custom answer:** `Ask me one question that allows a custom answer using your ask-user-question tool, then repeat my answer in one line.`
   Capture custom text typed in Float's composer with the
   `Or type your own answer…` placeholder behavior. Press Return and confirm
   the continuation in T3 repeats the text.
4. **Answered summary:** use the single-select prompt again, answer it, and
   capture the one-line muted `Answered: …` summary under the message. Confirm
   in T3 that the run continued rather than starting a new turn.
5. **Two questions:** `Ask me exactly two required single-select questions in one ask-user-question call, then reply with both choices.`
   Capture the first card showing `1 of 2`, confirm it shows `Next`, answer
   both, and confirm in T3 that one response resumed the run with both choices.

Also verify throughout:

- The header dot is amber and the thinking loader is hidden while a question
  is open; the loader returns after the last answer while the run continues.
- Number keys 1–9 select options only while the question composer is empty.
  Return confirms, Shift–Return inserts a custom-answer newline, and Esc still
  hides Float.
- A fixed-choice question disables the composer and shows
  `Pick an answer above…`.
- Approvals still show `Needs your approval` and Open in T3, never a question
  card.
- Repeat one answer on a linked machine and confirm list, read, and respond all
  target that thread's machine.
