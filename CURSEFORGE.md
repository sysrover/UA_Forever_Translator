# CurseForge submission

**Project name:** UA Forever Translator  
**Summary:** Offline English–Ukrainian chat translation and editable English drafts for WoW Forever.  
**Game:** World of Warcraft  
**Class:** Addons  
**Suggested category:** Chat & Communication  
**Game version to select after in-game verification:** Forever, 1.60.1  
**Logo:** [CurseForgeIcon.png](CurseForgeIcon.png)  
**Changelog:** [CHANGELOG.md](CHANGELOG.md)

## Description

UA Forever Translator helps English- and Ukrainian-speaking players communicate in World of Warcraft: Forever. The UA chat tab shows Ukrainian translations. Standard chat tabs show the original messages. Use `/uaft tab` to open or select the UA tab.

Use `/uaft en <Ukrainian text>` to prepare an English draft. You can review and edit it, choose the current chat target, and insert it into the game chat box. You send the message yourself.

The built-in dictionary covers common group, trade, combat, and loot-roll phrases, along with selected regional names and Ukrainian word forms. Partial suggestions are labeled and retain unfamiliar text. The addon works offline and has no required addon dependencies. Use `/uaft config` to choose which chat channels to translate.

## Packaging

After checking the addon's behavior in the supported client, run this from the repository root to create a ZIP from the committed addon files. Match the archive version to the TOC and changelog.

```powershell
git archive --format=zip --prefix=UA_Forever_Translator/ --output=../UA_Forever_Translator-0.1.0.zip HEAD -- Core Data Engine Modules UI UA_Forever_Translator.toc README.md CHANGELOG.md THIRD_PARTY_NOTICES.md
```

The archive root should contain the `UA_Forever_Translator` folder. [`.pkgmeta`](.pkgmeta) provides equivalent packaging metadata for [BigWigs Packager](https://github.com/BigWigsMods/packager). WoW Forever support is available in [version 2.6.0](https://github.com/BigWigsMods/packager/releases/tag/v2.6.0) and later.

Before submitting, choose the project license and review upstream attribution and distribution terms. Follow the [CurseForge project submission guide](https://support.curseforge.com/support/solutions/articles/9000197241-creating-and-submitting-a-project) to create the project and submit the ZIP.
