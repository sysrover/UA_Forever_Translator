# CurseForge submission

**Project name:** UA Forever Translator  
**Summary:** Offline English–Ukrainian chat translation and editable English drafts for WoW Forever.  
**Game:** World of Warcraft  
**Class:** Addons  
**Suggested category:** Chat & Communication  
**Target game version:** Forever 1.60.1 (`Interface: 16001`, `camelot`)  
**Release type:** Release  
**File display name:** UA Forever Translator 0.5.0  
**Archive:** `UA_Forever_Translator-0.5.0.zip`  
**Logo:** [CurseForgeIcon.png](CurseForgeIcon.png)  
**Changelog:** [CHANGELOG.md](CHANGELOG.md)

## Description

UA Forever Translator helps English- and Ukrainian-speaking players communicate in World of Warcraft: Forever. It translates English messages in selected channels into Ukrainian and keeps the originals visible. Use `/uaft tab` to open the UA tab and `/uaft config` to choose channels and where translations appear.

Use `/uaft` to open the composer or `/uaft en <Ukrainian text>` to prepare an English draft. You can edit the draft, choose a chat target, and insert it into the game chat box. You send the message yourself.

The built-in dictionaries and grammar cover common group, trade, combat, and loot phrases. Partial translations are labeled and retain unfamiliar text. Translation runs offline without addon dependencies. An optional local journal can record translations and draft previews. The journal is off by default.

## Packaging

From the addon Git repository root, create the ZIP from the commit tagged `0.5.0`. Use the same ZIP as the GitHub Release asset and the CurseForge file.

```powershell
git archive --format=zip --prefix=UA_Forever_Translator/ --output=../UA_Forever_Translator-0.5.0.zip 0.5.0 -- Core Data Engine Modules UI UA_Forever_Translator.toc README.md CHANGELOG.md THIRD_PARTY_NOTICES.md
```

The archive root should contain the `UA_Forever_Translator` folder. [`.pkgmeta`](.pkgmeta) provides equivalent packaging metadata for [BigWigs Packager](https://github.com/BigWigsMods/packager). WoW Forever support is available in [version 2.6.0](https://github.com/BigWigsMods/packager/releases/tag/v2.6.0) and later.

Before publishing, settle the project license and the redistribution terms for the components listed in the [third-party notices](THIRD_PARTY_NOTICES.md), and confirm the supported game version in the client. Follow the [CurseForge project submission guide](https://support.curseforge.com/support/solutions/articles/9000197241-creating-and-submitting-a-project) to create the project and submit the ZIP.
