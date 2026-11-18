# Third-party notices

Selected Ukrainian game terms and grammatical forms are drawn from [UA Forever](https://github.com/sysrover/UA_Forever), version 1.0.3, [source snapshot](https://github.com/sysrover/UA_Forever/tree/5c1cadddc75e18cd569207437e8ebf68ac162da1). The compiled [dictionary](Data/Dictionary.lua) records provenance for the relevant entries, including the UA Forever UI, zone, and shared grammar catalogs. Credits belong to UA Forever contributors and the upstream contributors identified by that project, including ClassicUA where applicable.

World of Warcraft, client fonts, and game content belong to their respective rights holders. The addon refers to a font already shipped with the client. This repository carries no client binaries, extracted Blizzard resources, or copied font files.

## General Ukrainian–English dictionary

[Data/GeneralUkEn.lua](Data/GeneralUkEn.lua) adapts the [KOReader Dicts Ukrainian → English StarDict dictionary](https://danielgregorini.github.io/koreader-dicts/en/uk-en/) by Daniel Gregorini and contributors, built on 2026-09-21. That dictionary is derived from [the Ukrainian entries of English Wiktionary](https://en.wiktionary.org/wiki/Category:Ukrainian_lemmas) via [Kaikki / Wiktextract](https://kaikki.org/dictionary/Ukrainian/index.html).

The imported Lua data is licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). This adaptation extracts brief English equivalents, filters explanatory prose, normalizes Ukrainian spelling keys, and packs entries and inflected aliases into a lookup index. The downloaded archive has SHA-256 `690c61e8bb7673e0bdeab6f0bd5c5884f648998373dfdd9b04b9c5d4e7bfb76d`.

A separate distribution license has not been selected for the addon's original code.
