# Third-party notices

`Data/Linguistics.lua` adapts lexical data from [KOReader Dicts EN → UK](https://danielgregorini.github.io/koreader-dicts/en/en-uk/) and inflection data from [Kaikki’s Ukrainian Wiktionary extract](https://kaikki.org/dictionary/Ukrainian/index.html), based on the English Wiktionary dump dated 2026-10-01. The Wiktionary-derived portion is adapted under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). The source articles are credited to [Wiktionary contributors](https://en.wiktionary.org/wiki/Wiktionary:Copyrights). Source hashes are recorded in the generated file manifest.

`Data/Linguistics.lua` also adapts inflected forms from [apertium-eng](https://github.com/apertium/apertium-eng/tree/558c36639531061dc34ed3bb1aec0c5ddc258724) and [apertium-ukr](https://github.com/apertium/apertium-ukr/tree/853abb29f8ecad023028dc80a6b954d48e1c9201). `Data/Apertium.lua` contains compiled analysis and generation transitions from the same Apertium dictionaries. These forms are credited to the Apertium contributors. Source terms are GPL v3, as stated in [eng COPYING](https://github.com/apertium/apertium-eng/blob/558c36639531061dc34ed3bb1aec0c5ddc258724/COPYING) and [ukr COPYING](https://github.com/apertium/apertium-ukr/blob/853abb29f8ecad023028dc80a6b954d48e1c9201/COPYING). The generated manifest records the hashes of both expanded dictionaries.

The pre-existing `Data/GeneralUkEn.lua` and `Data/GeneralEnUk.lua` snapshots identify KOReader Dicts, dated `2026.09.21`, with CC BY-SA 4.0 declared in their headers. Their attribution identifies English Wiktionary via Kaikki/Wiktextract and, for EN → UK, Princeton WordNet 3.0. Sources: https://danielgregorini.github.io/koreader-dicts/en/uk-en/ and https://danielgregorini.github.io/koreader-dicts/en/en-uk/. No re-import was performed for the structural pipeline.

`legacy-curated` / `unresolved` records retain their original sourceRefs; their exact origin and redistribution terms are unknown. The analysis and transfer code was written in Lua for this addon.

Selected Ukrainian game terms and grammatical forms are drawn from [UA Forever](https://github.com/sysrover/UA_Forever), version 1.0.3, [source snapshot](https://github.com/sysrover/UA_Forever/tree/5c1cadddc75e18cd569207437e8ebf68ac162da1). The compiled [dictionary](Data/Dictionary.lua) records provenance for the relevant entries, including the UA Forever UI, zone, and shared grammar catalogs. Credits belong to UA Forever contributors and the upstream contributors identified by that project, including ClassicUA where applicable.

World of Warcraft, client fonts, and game content belong to their respective rights holders. The addon refers to a font already shipped with the client. This repository carries no client binaries, extracted Blizzard resources, or copied font files.

## UDPipe model weights

`Data/UDPipeModels.lua` adapts the Parsito dependency weights from the English EWT and Ukrainian IU Universal Dependencies 2.5 models. The models are published by the Institute of Formal and Applied Linguistics at Charles University under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). The converter extracts the dependency component and changes its storage encoding while preserving the float32 weights. The Lua dependency algorithm follows the upstream Parsito implementation. [Model sources](https://ufal.mff.cuni.cz/udpipe/1/models) · [Parsito source and license](https://github.com/ufal/udpipe/tree/v1.4.0/src/parsito)

## General Ukrainian–English dictionary

[Data/GeneralUkEn.lua](Data/GeneralUkEn.lua) adapts the [KOReader Dicts Ukrainian → English StarDict dictionary](https://danielgregorini.github.io/koreader-dicts/en/uk-en/) by Daniel Gregorini and contributors, built on 2026-09-21. That dictionary is derived from [the Ukrainian entries of English Wiktionary](https://en.wiktionary.org/wiki/Category:Ukrainian_lemmas) via [Kaikki / Wiktextract](https://kaikki.org/dictionary/Ukrainian/index.html).

The imported Lua data is licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). This adaptation extracts brief English equivalents, filters explanatory prose, normalizes Ukrainian spelling keys, and packs entries and inflected aliases into a lookup index. The downloaded archive has SHA-256 `690c61e8bb7673e0bdeab6f0bd5c5884f648998373dfdd9b04b9c5d4e7bfb76d`.

A separate distribution license has not been selected for the addon's original code.

## General English–Ukrainian dictionary

[Data/GeneralEnUk.lua](Data/GeneralEnUk.lua) adapts the [KOReader Dicts English → Ukrainian StarDict dictionary](https://danielgregorini.github.io/koreader-dicts/ru/en-uk/) by Daniel Gregorini and contributors, built on 2026-09-21 from [English Wiktionary](https://en.wiktionary.org/) via [Kaikki / Wiktextract](https://kaikki.org/) and [Princeton University WordNet 3.0](https://wordnet.princeton.edu/).

The adaptation is licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). It selects a short Ukrainian gloss per English headword, drops ambiguously mapped aliases, and packs single-token keys and their inflected forms into a lookup index. The downloaded archive has SHA-256 `2e5dfd0b86e5d9a8dd3d5f6eff932285829a5d3ef8d2cc6e8c6558d7e06583e3`.

## WoW chat abbreviations and slang

The Ukrainian chat glosses were written for this addon. The `wow-community` references in the compiled dictionary identify sources for the English terms and their usage. Ukrainian client names and loot button labels follow UA Forever.

- `forum` and `classic` — [WoW abbreviation guide](https://us.forums.blizzard.com/en/wow/t/wow-guide-acronyms-and-abbreviations/1387957) and [Classic glossary discussion](https://us.forums.blizzard.com/en/wow/t/what-is-ptr-and-how-about-a-glossary/97130).
- `strategy` and `wiki` — [WoW strategy guide glossary](https://media.battle.net/documents/wow/WoW-BradyGAMES-enUS-Guide.pdf), [Warcraft Wiki abbreviation guide](https://warcraft.wiki.gg/wiki/Abbreviation_guide), and its linked terminology pages.
- `loot`, `dkp`, and `loot-council` — [Classic raid loot abbreviations](https://us.forums.blizzard.com/en/wow/t/dst-hr-1-sr-per-raid/2325303), [DKP and GDKP](https://us.forums.blizzard.com/en/wow/t/what-is-gdkp-and-what-does-it-stand-for/921617), and [Vanilla loot terminology in use](https://us.forums.blizzard.com/en/wow/t/warmongers-are-recruiting/353453).
- `craft` and `dungeons` — [Example crafting advertisement](https://us.forums.blizzard.com/en/wow/t/suspended-for-week-for-advertising/2281741?page=3) and [Classic dungeon abbreviations](https://us.forums.blizzard.com/en/wow/t/lfg-terms-explained/408615).
