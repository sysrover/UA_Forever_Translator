# Third-party notices

## Dictionaries and morphology

- `Data/GeneralEnUk.lua`, `Data/GeneralUkEn.lua`, and `Data/Linguistics.lua` draw on KOReader Dicts and English Wiktionary data extracted through Kaikki/Wiktextract. The English-to-Ukrainian KOReader source also credits Princeton WordNet 3.0. Wiktionary contributors retain attribution for their material, which was adapted into Lua indexes under CC BY-SA 4.0. [KOReader Dicts](https://github.com/koreader/koreader/wiki/Dictionary-support) · [Wiktionary copyright](https://en.wiktionary.org/wiki/Wiktionary:Copyrights) · [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
- `Data/Apertium.lua` and parts of `Data/Linguistics.lua` adapt word forms and automata from the English and Ukrainian Apertium dictionaries. Credit belongs to the contributors of the respective projects. [apertium-eng COPYING](https://github.com/apertium/apertium-eng/blob/558c36639531061dc34ed3bb1aec0c5ddc258724/COPYING) · [apertium-ukr COPYING](https://github.com/apertium/apertium-ukr/blob/853abb29f8ecad023028dc80a6b954d48e1c9201/COPYING)
- The game dictionary includes the Ukrainian declension of «витратник», adapted from ChatTranslatorUA 1.1.0 under GPL v3. Copyright © 2026 Chat Translator EN ↔ UA contributors (Ukrainian edition). The upstream archive also retains Amahonda’s original MIT notice (© 2026). [ChatTranslatorUA 1.1.0](https://www.curseforge.com/wow/addons/chattranslatorua/files/9681224)
- Selected game terms in the dictionary come from UA Forever 1.0.3 (`5c1cadddc75e18cd569207437e8ebf68ac162da1`). Credit belongs to the UA Forever contributors and their upstream sources, including ClassicUA where applicable. Redistribution terms for the imported terms and for part of the legacy dictionary remain unresolved. [UA Forever source](https://github.com/sysrover/UA_Forever/tree/5c1cadddc75e18cd569207437e8ebf68ac162da1)

## Syntax and tagging

- The Lua dependency parser is based on Parsito from UDPipe 1.4.0, distributed under MPL 2.0. [Parsito source](https://github.com/ufal/udpipe/tree/v1.4.0/src/parsito) · [MPL 2.0](https://www.mozilla.org/MPL/2.0/)
- `Data/UDPipeModels.lua` adapts the English EWT and Ukrainian IU UDPipe 1 models for Universal Dependencies 2.5. `Data/UDPipeEnglishOutput.lua` adapts the English model’s output layer. The upstream models use CC BY-NC-SA 4.0. [UDPipe model terms and credits](https://ufal.mff.cuni.cz/udpipe/1/models#universal_dependencies_25_models) · [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)
- `Data/UDPipeTagWeights.lua` derives tagging features and weights from the English Web Treebank UD 2.5 training data under CC BY-SA 4.0. The English output layer also uses training data from this treebank. [Training data](https://github.com/UniversalDependencies/UD_English-EWT/tree/d66085c1146283328dd503e6cc8da64d72149131) · [Treebank credits](https://universaldependencies.org/treebanks/en_ewt/index.html)

The addon references the World of Warcraft client font `Fonts/FRIZQT___CYR.TTF`. Game assets and names belong to their respective rightsholders.
