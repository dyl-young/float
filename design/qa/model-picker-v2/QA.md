# Model picker v2 QA

Run this pass on the screenshot-capable Mac. Compare against states 5–8 in
`design/pickers.png`; capture one screenshot for each state.

## State 5 — Favourites with effort

1. Star models from at least two providers in T3, including the current model.
2. Open Float and press ⇧⌘M.
3. Confirm the picker opens above the model button on Favourites, the search
   field has focus, provider names appear under favourite models, and the
   current model has the accent checkmark.
4. Hover an unstarred row and confirm the star appears. Star it, close and
   reopen the picker, and confirm it remains starred in both Float and T3.
5. Select a model with effort. Confirm its allowed values appear in the footer
   and capture the screenshot with one segment selected.

## State 6 — Provider tab

1. Press ⌘1–⌘9 to select an enabled provider tab.
2. Confirm the selected tab is a raised icon-and-name pill; other tabs are
   icon-only and show provider-name tooltips.
3. Confirm rows use that provider's icon, the current model has an accent
   checkmark, hover reveals the star, and the refresh control is at the right
   edge of the tabs.
4. Capture the screenshot.

## State 7 — Search

1. Reopen with ⇧⌘M, type `son`, then use ↓ and Return to pick a result.
2. Reopen and type `son` again.
3. Confirm results search all providers and are grouped under provider
   headings. A disabled provider remains represented by a muted “No match”
   row with its reason.
4. Also confirm `gpt56` finds `GPT-5.6 Sol`.
5. Capture the `son` screenshot.

## State 8 — Disabled provider

1. Turn off one provider in T3 and reload models in Float.
2. Confirm its tab remains visible but greyed out.
3. Open it and confirm the panel says “<Provider> is turned off in T3.”
4. Confirm “Open T3 settings” opens T3's provider settings for that instance.
5. Capture the screenshot.

## Keyboard, dismissal, and delivery

1. Confirm ⌘1–⌘9 changes tabs, ↑/↓ moves the highlight, Return picks, and Esc
   closes only the picker.
2. Confirm clicking outside closes the picker and composer focus is restored.
3. Confirm the footer model button is unchanged and ⇧⌘M still opens the picker.
4. Pick a cheap model, choose a non-default effort, send one short prompt
   (`Reply with exactly: Float effort QA`), and confirm in T3 that the run used
   the selected provider/model and effort.
