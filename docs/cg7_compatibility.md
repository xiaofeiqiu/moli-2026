# CGMSV / CrossGate 7.1 compatibility findings

## Scope and conclusion

This is a read-only analysis of the supplied installation. The user's correction makes **7.1** the target version, and permits choosing any candidate. The requested filename remains `cg7_compatibility.md`.

Installation under discussion: **`D:\Games\CrossGate`**. The relevant server tables, configuration, and selected animation/index files match the original workspace at `D:\Program Files (x86)\SOFTSTAR\魔力寶貝`; the startup configuration differs because of the earlier locale fix. Paths below are relative to the English installation unless linked explicitly.

The package itself describes its server DATA as Taiwan **5.5** and its client as Taiwan **7.1**. Those versions refer to different components. A newer client asset collection does not automatically create newer pet definitions in the server. Evidence: [installation notes, lines 11–12](D:/Games/CrossGate/安装说明.txt:11).

**Selected candidate: appearance/animation ID `104866`, working name `CG71_POC_104866`.** It exists in the supplied Joy EX animation and graphic banks, has the usual creature movement/combat actions, and is absent from the supplied server DATA references. Its official species name and first release version have not been established. Calling it “7.1-only” or “7.0-only” would exceed the available evidence.

The smallest proposed addition uses the already supplied client assets, clones a known server pet definition, and introduces two server table rows. A temporary appearance swap on an existing test pet is the preceding rendering check. Neither proposal has been executed. Only this report is being created; game assets, server DATA, configuration, and executables are unchanged by this analysis.

## 1. Character, pet, and NPC ID representation

There are several independent numeric namespaces. Similar-looking numbers are not interchangeable.

| Value | Meaning | Local evidence / example |
| --- | --- | --- |
| Object index (`charIndex`, `petIndex`, `npcIndex`) | Runtime handle for an instance; not an asset ID | `Char.GetData`, `Char.SetData`, and the return from `Char.GivePet` |
| Current appearance | Integer held in object field `CONST.对象_形象 = 4` | Used for players, pets/enemies, and NPC appearance changes |
| Base/original appearance | Separate object field `CONST.对象_原形 = 5` | Existing pet-variation Lua changes this alongside the current appearance |
| Original graphic field | Another documented field, `CONST.对象_原始图档 = 264` | Its exact native lifecycle is unverified; do not assume it is synonymous with field 5 |
| EnemyBase ID | Species/stat template key, also exposed as `CONST.对象_EnemyBaseId = 61` | Base ID `1` in `enemybase.txt` has appearance `101000` |
| Pet ID | Persistent pet identity in `CONST.宠物_PETID = 72` / `CONST.PET_PetID = 72`; use this for pet lookup/cleanup rather than field 61 | POC pet key 30000 |
| Enemy ID | Encounter/enemy template key referencing an EnemyBase ID | Enemy ID `1` in `enemy.txt` references base ID `1` |
| Animation serial / appearance ID | Logical client animation lookup key | `104866` in an `AnimeInfo` record |
| Graphic index | Identifier for a single sprite frame within an asset bank | Candidate frames use indices `7125`–`7636` |
| Graphic serial | Separate final field in `GraphicInfo`; useful for static graphics and palette lookup | Graphic index `7118` has serial `104866` and carries an embedded palette |

The appearance fields are documented as Lua numeric values; text DATA stores decimal integers. Client index fields are little-endian 32-bit values. The inspected examples exceed 65,535, so truncating an appearance to 16 bits would be incorrect. The engine's internal C types, wire encoding, validation bounds, and maximum allowed ID are not established by the supplied Lua stubs or this file inspection.

References: [object constants](D:/Games/CrossGate/lua参考/CONST.lua:660), [EnemyBase object key](D:/Games/CrossGate/lua参考/CONST.lua:719), [original graphic field](D:/Games/CrossGate/lua参考/CONST.lua:761), [object get/set API](D:/Games/CrossGate/lua参考/Char.lua:3).

Pet appearance is distinct from species identity and stats. The local variation script sets both current and base appearance, supporting an appearance-only rendering test: [LvOnePet.lua, lines 64–69](D:/Games/CrossGate/gmsv/lua/Module/LvOnePet.lua:64). NPC creation takes an `Image` number explicitly: [NL.CreateArgNpc](D:/Games/CrossGate/lua参考/NL.lua:28); the supplied [NPC module](D:/Games/CrossGate/gmsv/lua/libs/Module/Parts/Npc.lua:36) passes that appearance through.

## 2. Animation-to-graphics mapping

The mapping is:

```text
server object appearance = 104866
    -> AnimeInfo_Joy_EX_9: animation serial 104866
    -> Anime_Joy_EX_9: action selected by direction and action type
    -> frame.GraphicIndex, e.g. 7125
    -> GraphicInfo_Joy_EX_9: sprite offset, length, size, placement
    -> Graphic_Joy_EX_9: compressed RD sprite + required palette
```

The bank/family is part of frame lookup. A frame number alone does not identify a sprite across all banks. The first GraphicInfo field is the stored graphic index; do not substitute its physical row number without checking that they agree. The candidate happens to have matching index/row positions.

### Observed layouts

All offsets below are byte offsets within a record; integers are little-endian.

| Record | Layout |
| --- | --- |
| `AnimeInfo`, 12 bytes | `+0 u32 animation serial`, `+4 u32 Anime byte offset`, `+8 u16 action-entry count`, `+10 two trailing bytes` |
| Basic action header, 12 bytes | `+0 u16 direction`, `+2 u16 action type`, `+4 u32 cycle time`, `+8 u32 frame count` |
| Extended action header, 20 bytes | Basic header plus two 16-bit values at `+12/+14` and `FFFFFFFF` at `+16`; candidate uses extended headers |
| Frame, 10 bytes | `+0 u32 graphic index`, `+4/+6 i16 frame offsets`, `+8 u16 sound/effect flag` |
| `GraphicInfo`, 40 bytes | `+0 u32 index`, `+4 u32 Graphic offset`, `+8 u32 length`, `+12/+16 i32 placement offsets`, `+20/+24 u32 width/height`, `+28..35 occupancy/flags/reserved bytes`, `+36 u32 graphic serial` |

The layouts and bank-based frame lookup are corroborated by the primary parser implementations [CGTool Anime.cs](https://github.com/HonorLee-cn/CGTool/blob/master/CrossgateToolkit/Anime.cs) and [GraphicInfo.cs](https://github.com/HonorLee-cn/CGTool/blob/master/CrossgateToolkit/GraphicInfo.cs). The original client's exact implementation and duplicate precedence remain unverified. The AnimeInfo trailing bytes have observed values including 0, 1, and 64; this report does not assign them an unsupported meaning.

### Supplied animation banks

The following counts were computed directly from the files. Suffix numbers such as `_91` and `_9` are asset revision names, not species IDs or proof of game version.

| AnimeInfo path | Records | Distinct serials | Observed serial range | Matching animation file |
| --- | ---: | ---: | --- | --- |
| `bin/AnimeInfo_4.bin` | 3,186 | 806 | 100000–120000 | `Anime_4.bin` |
| `bin/AnimeInfoEx_1.Bin` | 827 | 827 | 105000–110204 | `AnimeEx_1.Bin` |
| `bin/AnimeInfoV3_8.bin` | 342 | 342 | 110350–114224 | `AnimeV3_8.bin` |
| `bin/Puk2/AnimeInfo_PUK2_4.bin` | 343 | 343 | 110300–113688 | `Anime_PUK2_4.bin` |
| `bin/Puk3/AnimeInfo_PUK3_2.bin` | 155 | 149 | 110505–113406 | `Anime_PUK3_2.bin` |
| `bin/AnimeInfo_Joy_91.bin` | 831 | 785 | 104000–120003 | `Anime_Joy_91.bin` |
| `bin/AnimeInfo_Joy_CH1.Bin` | 70 | 68 | 104854–120155 | `Anime_Joy_CH1.bin` |
| `bin/AnimeInfo_Joy_EX_9.bin` | 59 | 57 | 104854–111100 | `Anime_Joy_EX_9.bin` |

The corresponding graphic indices include base `_66` (252,824 records), Ex `_5` (343,875), V3 `_19` (20,032), PUK2 `_2` (11,033), PUK3 `_1` (4,592), Joy `_125` (493,947), Joy CH1 (54,030), and Joy EX `_9` (11,663). UI indices under `bin/cgmsv` are separate assets. These files are under `bin`, whereas client `data` contains other resources such as maps and update/load metadata.

Duplicate animation serials occur within and between banks. For example, `104856` has repeated entries in the CH1 and EX indices. Appending records or merging banks requires an explicit duplicate policy and a verified loader order. Candidate `104866` has exactly one occurrence across the supplied AnimeInfo files, avoiding that particular ambiguity.

### Candidate `104866`: verified dependency chain

| Check | Measured result |
| --- | --- |
| AnimeInfo row | Zero-based row 14, byte offset 168 (`0xA8`) in `AnimeInfo_Joy_EX_9.bin` |
| Entry | `(serial=104866, offset=100160, actionCount=72, trailing=1)` |
| Animation byte span | `[100160, 107120)`, exactly 6,960 bytes; next animation starts at 107120 |
| Direction/action coverage | Directions 0–7; action types `{0,1,2,3,5,6,8,9,10}` for each direction |
| Frames | 552 frame references, 512 distinct graphic indices, range 7125–7636 |
| Extended header values | Raw 16-bit values `2067, 0`, followed by `FFFFFFFF`, for all 72 actions |
| Frame flags | 536 references with 0; eight with 10131; eight with 10213 |
| Dependency resolution | All 512 distinct indices resolve in `GraphicInfo_Joy_EX_9.bin`; all sprite blocks stay within `Graphic_Joy_EX_9.bin` |
| Sprite decoding | All 512 referenced compressed sprite blocks decode to their expected pixel dimensions; each has RD version 1 |
| Palette dependency | Graphic index 7118, serial 104866; offset 95872243, length 10091; RD version 3, embedded palette 768 bytes / 256 BGR entries |
| Palette decoding | Palette carrier decodes to `140 × 162` indexed pixels plus exactly 768 palette bytes |
| Server registration | No base row uses appearance 104866; no standalone occurrence found anywhere under supplied `gmsv/data` |

CGTool names these action numbers idle (0), walk (1), before-run (2), run (3), attack (5), magic (6), hurt (8), defence (9), and dead (10); those names help interpret the observed coverage, but do not prove native runtime behavior. Its decoder also preserves palette and frame-effect data. See [Anime.cs](https://github.com/HonorLee-cn/CGTool/blob/master/CrossgateToolkit/Anime.cs) and [GraphicData.cs](https://github.com/HonorLee-cn/CGTool/blob/master/CrossgateToolkit/GraphicData.cs).

A concrete first-frame lookup: the first action is direction 0 / action 5 / cycle 1000 / ten frames. Its first frame references index 7125. That GraphicInfo record points to offset **95921357**, length **9321**, dimensions **140 × 162**, placement **(-60, -126)**. The palette carrier at index 7118 is a separate dependency; copying only the visible frame blocks can lose the intended colors.

### Present files versus active client loading

[Client update metadata](D:/Games/CrossGate/data/argument.ini:1) names the base, Ex, V3, PUK2, PUK3, Joy, and Joy EX revisions. Its Joy EX fields repeat `animebin_joy_ex:9` and do not include a distinct `animeinfobin_joy_ex` field. This is an observed metadata irregularity, not a demonstrated loading failure.

The stock `cg.exe` contains a literal `Graphic_Joy_CH1.bin` and references `CGLoadSpr.dbf`. The configured modified client `cgmsv.exe` is packed, so absence of these names in a raw string search is inconclusive. A bank existing on disk, or appearing in update metadata, does **not** establish that the configured executable loads it. This remains the first runtime check for the POC. No executable was launched for this analysis.

## 3. Server DATA references

[setup.cf](D:/Games/CrossGate/gmsv/setup.cf:107) explicitly selects `enemybase.txt`, `enemy.txt`, `group.txt`, and `encount.txt`; it also selects NPC and optional appearance tables. [cgmsv.cf](D:/Games/CrossGate/gmsv/cgmsv.cf:323) selects headcover and pet-style paths.

| Server file | Reference role | Required for the proposed new pet? |
| --- | --- | --- |
| `gmsv/data/enemybase.txt` | Direct species-to-appearance mapping. Physical column **2** is base ID; physical column **31** is appearance, with the name in column 1 | **Yes**, one new cloned row |
| `gmsv/data/enemy.txt` | Enemy ID in physical column **3**, EnemyBase ID in column **4**; encounter level/AI/capture/drop settings | **Yes**, one new cloned row |
| `gmsv/data/group.txt` | Enemy-group definitions reference enemy templates, not sprite-frame indices | Only for a new encounter |
| `gmsv/data/encount.txt` | Encounter settings select groups for maps/regions | Only for a new encounter |
| `gmsv/data/npc.txt` | Contains NPC appearances. Observed appearance position is physical column **21** (zero-based 20), e.g. `103012` on line 5; native parser schema is not supplied | Only if adding a display/spawn NPC |
| `gmsv/data/npc/*.txt` | NPC argument/script files can test appearance via `BBImage`; e.g. `5atest01.txt`, lines 220 onward | Not needed for a direct pet grant |
| `gmsv/data/ridepet.txt` | Header explicitly identifies first column as `SPRID`; riding speed bounds keyed by appearance | Only to enable/test riding |
| `gmsv/data/petStyle.yml` | Header explicitly keys attack-style overrides by **EnemyBaseId**, not appearance | Optional; retain donor behavior initially |
| `gmsv/data/guildmonster.txt` | Header distinguishes direct `graph` field from `enemy` field; includes `110600`, etc. | Only for guild-monster use |
| `gmsv/data/headcover.txt` | `ItemID -> HeadImageID`, including 114170; `useheadcoverlist=0` in current config | Unrelated to ordinary pet addition |
| `gmsv/data/morph.txt`, `guise.txt`, `q_morph.txt`, `morphpuk2.txt` | Transformation/disguise-related appearance candidates. Older rows contain 12xxx/14xxx values; PUK2 rows include 110300 onward | Optional; legacy conversion semantics need confirmation |
| `gmsv/data/tobossnpc.txt` | NPC/boss-related candidate appearance column includes 14059 and 101800 | Optional; header/native schema unavailable |
| `gmsv/data/itemset.txt`, `profile.txt`, map tables | Other image/icon/map references belong to separate uses/namespaces | Do not treat matching integers as pet appearances |

All physical column numbers above are **one-based**. `EnemyBase_形象 = 29` is a numeric engine field index, not physical text column 30: the name is stored separately by the API. Row 1 demonstrates the distinction: name `虎人`, base ID `1`, appearance `101000` at zero-based text index 30. Constants: [EnemyBase fields](D:/Games/CrossGate/lua参考/CONST.lua:1199), [compatibility constants](D:/Games/CrossGate/gmsv/lua/Const.lua:496).

The current base table has **1,587 records, 1,583 distinct base IDs, and 664 distinct appearances**, spanning 100002–120007. Duplicate base IDs already exist; file row position is not a safe species identifier. The enemy table has 4,433 records. The supplied [DataEx.lua](D:/Games/CrossGate/gmsv/lua/libs/Gmsv/DataEx.lua:3) explicitly resolves `Enemy ID -> EnemyBase ID -> EnemyBase data index`.

Some legacy values in optional files are not modern AnimeInfo serials as written. No universal `+100000` or similar conversion was verified. Do not apply an assumed offset to every image field.

## 4. Compatibility differences and actual blockers

The original request mentioned a “7.0-only” pet; the later correction specifies 7.1. No separately identified 7.0 donor dataset or original 7.1 server species dataset was supplied. Consequently this analysis cannot establish a release-to-release species difference, a first-introduced version, or a native 7.0/7.1 format incompatibility. It can establish the following local integration gaps:

| Gap | Evidence / consequence | Smallest response |
| --- | --- | --- |
| Client assets without server species | 104866 exists and resolves completely in client assets, but has no server base definition | Clone a valid base row and enemy row |
| Wrong numeric namespace | Base ID 1 maps to appearance 101000, which maps to many graphic frames | Keep Enemy ID, EnemyBase ID, appearance, and graphic index separate |
| Bank activation unknown | Joy EX exists and is mentioned in metadata; configured client is packed | Test appearance 104866 before importing or rewriting assets |
| Missing palette/frame metadata after an import | Candidate uses a separate palette carrier and extended animation headers | Preserve bank relationships, palette, durations, offsets, and effect flags |
| Duplicate serial precedence | Several supplied banks repeat serials | Verify actual loader precedence; avoid collisions for any future import |
| Animation action coverage | Existing files expose explicit direction/action entries, not just an idle picture | Test movement and combat actions, not merely a portrait |
| Species behavior missing | No verified canonical stats, race, skills, album entry, capture rules, or riding behavior for the candidate | Use cloned donor stats for POC; research actual species separately |
| Text encoding differs | `enemybase.txt` strictly decodes as GBK; `enemy.txt` and `npc.txt` do not strictly decode as UTF-8, GBK, or CP950 as whole files | Preserve existing bytes/tabs; edit only targeted ASCII numeric fields or use an explicit per-record conversion |

The screenshot's garbled text concerns character encoding. It does not by itself demonstrate a graphic-ID or animation incompatibility. Names/UI text and sprite lookup should be diagnosed independently.

## 5. Smallest proposed proof of concept

### Stage A: validate rendering with an existing disposable pet

Use a test account and an existing pet. Record its original current/base appearance. In a temporary administrator callback, change only object fields **4 and 5** to `104866`, then call `Pet.UpPet(playerIndex, petIndex)`. The Lua API documents that this sends pet status and recalculates pet information: [Pet.lua](D:/Games/CrossGate/lua参考/Pet.lua:28).

Illustrative callback logic, **not installed or run**:

```lua
-- petIndex is an existing disposable pet instance, not a species ID.
local oldImage = Char.GetData(petIndex, 4)
local oldBase = Char.GetData(petIndex, 5)
assert(Char.SetData(petIndex, 4, 104866) == 1)
assert(Char.SetData(petIndex, 5, 104866) == 1)
Pet.UpPet(playerIndex, petIndex)
-- Refresh visible/map state through the normal follow/battle transition.
-- On completion, restore oldImage and oldBase and refresh again.
```

Check visible pet/follow state, all eight directions, walking, and a simple battle including attack, magic, hurt, defence, and death. Check colors and placement. Missing sprites would first require confirming Joy EX loading; wrong colors would first require checking its palette carrier. This proves an appearance path, not a new species or persistence.

### Stage B: add one distinct server pet definition

After Stage A passes, make backups and propose precisely these two additions:

1. **`enemybase.txt`:** clone row 1 (`虎人`, base ID 1, appearance 101000). Rename only the cloned row to ASCII `CG71_POC_104866`; replace its base ID with **30000** and its appearance with **104866**. Preserve all other fields, including empty fields, donor stats, skills, and capture settings.
2. **`enemy.txt`:** clone row 1 (Enemy ID 1 -> base ID 1). Rename the cloned row to the same ASCII working name; set Enemy ID to **30000** and EnemyBase reference to **30000**. Preserve the AI string and all remaining values.

`30000` was absent from the ID columns of both inspected tables. It is a **provisional test key**, not an established engine limit or a permanent reserved ID; recheck uniqueness and native acceptance at implementation time. Using the same new number in both tables avoids a base/enemy-key mismatch while the native `GivePet` argument semantics are verified.

Do not replace the whole files through a lossy decode/re-encode operation. The existing enemy row contains non-ASCII bytes and empty tab-delimited fields. A byte-preserving cloned row with an ASCII name is the smallest safe edit.

Reload these tables through a supported mechanism or restart the test server. Confirm at runtime:

```text
EnemyGetDataIndex(30000) resolves
EnemyGetData(enemyIndex, DATA_ENEMY_TEMPNO) == 30000
EnemyBaseGetDataIndex(30000) resolves
EnemyBaseGetData(baseIndex, DATA_ENEMYBASE_IMGNUMBER) == 104866
```

Then grant the disposable test pet through `Char.GivePet(playerIndex, 30000, 1)` and verify the returned object index is nonnegative, its EnemyBase ID is 30000, and its current/base appearances are 104866. Call `Pet.UpPet` if a refresh is needed.

The installed administrator modules expose `/getPet <number>` and `/dolua <file>` under an admin permission check: [module loading](D:/Games/CrossGate/gmsv/lua/ModuleConfig.lua:4), [pet grant](D:/Games/CrossGate/gmsv/lua/Modules/adminCommands.lua:35), [dispatch](D:/Games/CrossGate/gmsv/lua/Modules/adminCommands.lua:217). The API describes the argument only as `PetID`; its native implementation is not supplied. This report therefore does not assert that every CGMSV build interprets it identically. The runtime checks above make the proposed grant test explicit. Official reference: [Char.GivePet](https://lua.cgmsv.com/char.givepet.html).

**Initial change budget:** two appended server DATA rows, no client asset changes. No encounter, NPC, shop, album, riding, or attack-style integration is needed for the direct-grant POC. The resulting pet is a new server key with a supplied 7.1 appearance and cloned donor behavior; it is not yet a faithful recreation of an officially named species.

Acceptance requires correct field values, correct colors and movement/combat rendering, no client/server errors, and survival of logout/login with the same species/appearance values. If the native engine rejects the key, resets appearance, or does not load the EX bank, record that result before expanding the change. Roll back by removing the two new rows, restoring the test pet's appearances, and removing any temporary callback/test pet before reloading.

## 6. If a future donor really is missing from this client

That is a larger task than this POC. Collect the donor's matching AnimeInfo/Anime, GraphicInfo/Graphic, and palette dependencies. Allocate collision-free animation and graphic indices; copy the required graphic blocks and palette carrier; rewrite graphic offsets and frame references; preserve extended headers, placement, timing, and sound/hit markers; then connect the new bank to a verified client loader. Merely adding a server appearance number cannot create missing client pixels.

No standalone 7.0 donor was identified here, so these are requirements for a possible import rather than evidence that such an import is currently needed. Candidate 104866 needs no asset import to establish its on-disk dependency chain.

## 7. Verification limits and reproducibility

Performed: byte-level table inspection; decimal ID extraction without relying on name decoding; 12-byte animation-index and 40-byte graphic-index parsing; all 72 candidate action headers and 552 frame references; bounds checks; decompression of all 512 referenced sprites and the palette carrier; selected SHA-256 comparison between the original and English installations. All analysis helpers ran from memory.

Not performed: game/server launch, live packet capture, native loader tracing, POC execution, persistence testing, or donor-species identification. No source defining the native engine's ID bounds, packet fields, table reload behavior, or bank precedence was supplied. Binary structural validity alone is not a runtime compatibility guarantee.

Selected English-installation SHA-256 values:

| File | SHA-256 |
| --- | --- |
| `gmsv/data/enemybase.txt` | `a28025d168828815adb884b073ca5cfa5100518bb19c060ce321c17368bba165` |
| `gmsv/data/enemy.txt` | `b3dc7d207cae7f6a63ccba6562b6af9a10b94acffff84b314e689bb874b5ff10` |
| `bin/AnimeInfo_Joy_EX_9.bin` | `4b71188c3a6f341e25c84552865f2bc01874eceae700d0d35f3e749aa76f9374` |
| `bin/Anime_Joy_EX_9.bin` | `728f129b4fa8be288ca48e0081c01eb6bc0785d573c929359c8cd26486fdacab` |
| `bin/GraphicInfo_Joy_EX_9.bin` | `79a772a3db4e120b31b7f3edae30d3668157e44ada3f260ba0c147541b15dc5a` |
| `bin/Graphic_Joy_EX_9.bin` | `935dd2deacad7bd4e17e604b658bd65b6389c69facb27e19797502d180711d10` |

These hashes identify the examined files. The original and English startup configurations already differed before this analysis; no startup change is part of the report.

## 8. Implementation follow-up

After the user authorized starting the POC, two cloned rows were deployed to the English installation: EnemyBase 30000 -> appearance 104866 and Enemy 30000 -> base 30000. The original table bytes are preserved as backups; existing rows were not re-encoded. The native engine loaded both keys in an isolated copy, returning `enemyIndex=4433 baseIndex=1587 baseId=30000 appearance=104866`. The helper compiled and ran its lookup check under the native Lua runtime.

The administrator helper is on-demand only. Client rendering, grant behavior, battle, and persistence still need an in-game check; the Windows UI tool could not initialize. Stage B definitions are prepared, while the actual grant is deferred until the Stage A appearance check passes. No client asset or startup configuration change was made.

Instructions: [cg71_pet_poc.md](D:/Games/CrossGate/docs/cg71_pet_poc.md). Native validation: [cg71_pet_poc_validation.json](D:/Games/CrossGate/docs/cg71_pet_poc_validation.json). Backup directory: `D:\Games\CrossGate\backups\cg71_pet_poc_b3b51de9`. The earlier hashes above describe the pre-implementation analysis snapshot; current table hashes are in the validation record.

## 9. User-confirmed runtime result

The user first supplied an in-game `DEFINITIONS_OK enemy=30000 base=30000 image=104866 indexes=4433,1587` response. They then explicitly reported creating the pet with the native `nr makepet 30000` command and validating that its appearance is usable in the supplied 7.1 client. This confirms native creation through makepet and client rendering of the selected appearance. No client asset import was needed.

The prototype retains cloned tiger-template stats and behavior. The Lua `grant` path was not separately tested, and full battle action coverage and logout/login persistence have not been confirmed by the user. The earlier read-only limitations and pre-implementation hashes remain historical snapshots; the validation JSON records the subsequent results.

## 10. Pet identity correction

The original helper used object EnemyBaseId field 61 for pet identity; a user-reported cleanup failure exposed that error. The documented pet identity is `CONST.宠物_PETID = 72` ([reference](D:/Games/CrossGate/lua参考/CONST.lua:1115)), also `CONST.PET_PetID = 72` in the supplied compatibility constants. The helper now uses field 72 for pet identity, lists all runtime pet slots read-only, and permits cleanup only when PETID is 30000 and both appearance fields are 104866. Earlier helper snippets mentioning a pet identity check at field 61 are superseded by this correction. The reported failed cleanup stopped before any deletion.

Cleanup guard safety tests passed under the native Lua runtime using simulated pets: ordinary pets, cosmetic donors, mismatched appearances and empty slots were protected; only PETID 30000 with both appearances 104866 was accepted. No live pets were deleted by the assistant.

After the PETID-field correction and list/remove instructions, the user reported cleanup complete. The one-pet POC has user-confirmed creation, usable client appearance, and cleanup; battle-action coverage and logout/login persistence remain outside the confirmed results.

## 11. User-confirmed battle and persistence acceptance

The user reported that the battle test passed, then explicitly confirmed that the pet was retained and its appearance remained normal after logout/login and a server restart. Together with the earlier native creation and appearance checks, the one-pet minimum compatibility POC has passed. These in-game results were performed and reported by the user; the assistant did not independently observe exhaustive coverage of all 72 animation entries.

The on-demand GM helper [gm_encount.lua](D:/Games/CrossGate/gmsv/lua/tests/cg71_pet_poc/gm_encount.lua) supports `poc` mode (one level-1 Enemy 30000 through `Battle.PVE`) and `here` mode (normal encounters at the current location through `Battle.Encount`). It is read by `/dolua` on each invocation, without startup registration or encounter-table edits.

The POC is now accepted for native creation, supplied-client appearance, battle use and persistence across both relogging and a server restart. Earlier pending-verification paragraphs describe their historical stage and are superseded by these user-confirmed results. The prototype still retains the cloned tiger-template stats and behavior; production naming, growth/stats, skills and acquisition rules are a separate next step. No claim about the official species identity or exhaustive animation coverage is added.

## 12. Test-script organization

Both POC helpers now reside in `D:\Games\CrossGate\gmsv\lua\tests\cg71_pet_poc`; the old Lua-root files were moved. Commands and documentation use the new paths. The folder [README](D:/Games/CrossGate/gmsv/lua/tests/cg71_pet_poc/README.md) lists entry points and cleanup steps. The rollback manifest and script now verify and remove both known Lua files plus this README, removing the directory only when empty. No rollback was executed and no game DATA was changed by this organization.

## 13. Permanent custom-pet configuration

The user accepted the default configuration: custom name 异界兽, Enemy/EnemyBase 30000 and appearance 104866, with all tiger-template numeric fields, AI and skills retained. Only each DATA row’s name column changed, preserving GBK and all unrelated table bytes. The official donor species name remains unknown. Acquisition uses the existing GM makepet command; no public encounter/NPC distribution was added.

An isolated native server verified GBK name loading, runtime activation using name field 4000, retained stats/elements/skills, refusal of test deletion, and restoration after a simulated partial update failure. The running main server was not interrupted; activate the name with `/dolua lua/tests/cg71_pet_poc/cg71_pet_poc.lua activate` or a normal restart. Existing saved pet names are retained.

The test helper’s remove action is now disabled. The earlier POC DATA rollback is retired because 30000 is permanent. [Cleanup-CG71Tests.ps1](D:/Games/CrossGate/tools/Cleanup-CG71Tests.ps1) removes only verified test files and retains pet DATA and saved pets. Current configuration: [cg71_pet_30000.md](D:/Games/CrossGate/docs/cg71_pet_30000.md), [machine-readable record](D:/Games/CrossGate/docs/cg71_pet_30000.json). Earlier removal instructions are historical.

## 14. Full batch of eligible missing creature appearances

The user authorized completing the full batch. Eight client resource banks were scanned: 2706 unique appearances were absent from the prior EnemyBase table; all 403 appearances satisfying the conservative eight-direction action, sprite decompression and palette-dependency criteria were added as Enemy/EnemyBase/PETID **30001–30403**. The other 2303 appearances did not satisfy this batch's eligibility rules; their detailed reasons remain in the scan snapshot. These rules do not recover every official species or prove all excluded appearances are non-pets.

Names are custom aliases consisting of 异界兽 plus the appearance ID. Numeric fields, skills, AI, capture and drop settings inherit the accepted default template. Existing species 30000/104866 is unchanged. Each DATA table gained 403 appended rows while retaining all prior bytes. Client assets and the live character database were not modified.

The isolated native engine passed all 403 pet creations and 403 PVE enemy constructions, with ID/appearance mappings, GBK names, inherited fields and skills verified. Temporary pets/dummies were removed and the probe stopped. GM helper guards also passed. This does not claim individual live-client rendering, complete battle turns or save/relogin checks for all 403 species; the user-confirmed one-pet acceptance remains separate.

The files are installed. The running main server was retained; a **normal server restart loads the new definitions**. Then `/dolua lua/tests/cg71_pet_poc/cg71_pet_batch.lua check` should return `ALL_OK count=403 ids=30001..30403`. All four on-demand test Lua files and README remain in the same test folder, and the cleanup manifest now covers all five known files while retaining permanent DATA and saved pets.

See the [batch instructions](D:/Games/CrossGate/docs/cg71_pet_batch.md), [complete mapping](D:/Games/CrossGate/docs/cg71_pet_candidates.md), [per-species native results](D:/Games/CrossGate/docs/cg71_pet_batch_native_validation.tsv), and [machine-readable record](D:/Games/CrossGate/docs/cg71_pet_batch.json). Earlier small-batch proposals are superseded by this completed batch.
