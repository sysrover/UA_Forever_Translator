# Changelog

## 0.5.1

- Improved translation of group rosters, recruitment and enchantment trade messages, chat reactions, and expressions for dates, times, durations, and approximate quantities.
- Expanded the game dictionary and improved how the grammar and UDPipe models use sentence context. Mixed-language chat preserves text in unsupported languages.
- Split incoming translation work across frames and prepare UDPipe models when the addon loads.
- The optional translation journal now records processing time for incoming translations and outgoing draft previews.

## 0.5.0

First release of UA Forever Translator for World of Warcraft: Forever.

- Translate English chat in selected channels. Show Ukrainian translations in the UA tab, the main chat tab, or both, while keeping the original messages visible.
- Compose editable English drafts from Ukrainian text and insert them into the selected chat box for manual sending.
- Look up group recruitment, trade, combat, and loot terms with `/uaft lookup`.
- Translate supported clauses offline using bilingual dictionaries, word forms, and grammar. Partial translations are labeled and preserve unfamiliar text and in-game links.
- Optionally keep a local per-character journal of translations and draft previews. The journal is off by default.
