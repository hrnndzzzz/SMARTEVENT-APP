# AI enhancements: one Gemini feature per area

## Why
The thesis panel or adviser wants AI in the system. Each area gets one feature: suggestions, data organization, and financial/event analysis. Each feature sits on a screen people already use, so it is easy to point at in a defense.

## Approaches considered
- **One Gemini feature per area (picked).** Three small features that reuse the existing Gemini call (`ocr._generate`) and the proposal-summary pattern.
- **Statistics only.** Predictable, but a panel asking for "AI" reads it as rules and averages.
- **One chat assistant.** Riskier: the model can invent numbers, answers could leak data across scopes, and it is the biggest build.

## What was built
1. **Budget suggestion on the proposal form.**
   - Route: `POST /recommendations/event-budget/ai`.
   - Gemini compares the new title and description with up to 30 recent approved or completed past events the caller may see, and suggests an amount. It names the past events it compared against.
   - Event-based rather than category-based: events made through the proposal form carry no category, so the older category recommender never fires for them.
2. **Category suggestion on receipt scan.**
   - The existing vision call also picks one of the scanned organization's categories.
   - Only an exact (case-insensitive) match to a listed name becomes `suggested_category_id`.
   - The app presets the category only when it is still empty, or still the AI's earlier pick, and labels it "Suggested by AI".
3. **AI reading of the financial report.**
   - Route: `GET /reports/financial/ai-reading`.
   - Same filters and checks as `/reports/financial`, which it calls directly.
   - Sends a compact digest: totals, the period before, the top 10 events, categories, and income by kind.
   - Shown as a labeled "AI reading" card next to the rule-based "Worth knowing" card.

## Rules all three follow
- **Fail quietly.** No key, too little data, offline, or a Gemini failure means an empty answer with a 200. The screen works without it.
- **Suggest, never save.** Nothing the AI writes is saved without a person acting on it.
- **No people go to Gemini.** No people, emails, remarks, ledger rows or free-text income sources. Event and category names do go, as data, and the prompts say to treat them as data.
- **Cached and capped.** Results are cached with `lru_cache` on their inputs, and model output is cut to a fixed length.
- **No new dependencies or migrations.**

## Builder's calls
- An event title can contain a person's name. That is accepted, since titles are already shown to the same viewers.
- The demo shows fixed stand-ins for all three features.
