Written by Cloud (session roblox-9d) on 2026-10-07 from public Roblox documentation fetched today; limits change, re-check before relying on a number.
Written without the project files: the SaveData check in section 2 reads `cloud_work/src/Fishing/Server/SaveData.lua` (the cloud draft), not the real `src/`. Three pages we wanted were unreachable today (help.roblox.com returned 403: Experience Guidelines, Community Standards, DevEx FAQ); each fact below comes from a page that did open, and the gaps are named.

# ROBLOX platform constraints for GameOne (About Fishing mechanics on Roblox)

What this covers: the Roblox facts that decide how bloody filleting can be, who can play, how often we may save, how big meshes and sounds may be, what text we must filter, and what we may copy from About Fishing. One section per topic, a table of facts with the page each came from, then one "what it means for GameOne" line. Section 7 is the list of decisions this forces.

## 1. Content and age ratings (as of 2026-10-07)

Roblox rates each experience with a Content Maturity label from a questionnaire the creator answers; the label decides which age tier can see it. There is no "Crime" descriptor on today's questionnaire; a murder in a story is rated through Violence (death) and Fear.

| Fact | Value today | Source |
|---|---|---|
| Labels and audiences | "Games rated Minimal or Mild are eligible for Roblox Kids (ages 5–8) and Roblox Select (ages 9–15). Games rated Moderate are eligible for Roblox Select (ages 9–15) and standard Roblox (16+). Games rated Restricted are only accessible to age-verified Roblox users 18 and older." | [Experience guidelines](https://create.roblox.com/docs/production/promotion/experience-guidelines) |
| Minimal | "May contain occasional mild violence and/or light unrealistic blood." | same |
| Mild | "May contain repeated mild violence, heavy unrealistic blood, mild fear-based content, and/or mild crude humor." | same |
| Moderate | "May contain moderate violence, light realistic blood, moderate fear-based content, moderate crude humor, and/or unplayable gambling content." | same |
| Restricted | "May contain strong violence, heavy realistic blood, moderate crude humor, romantic themes, unplayable gambling content, the presence of alcohol, and/or strong language." | same |
| Blood: unrealistic vs realistic | Unrealistic = "pixelated or having a different color or shape"; realistic = "the same color, shape, and splatter properties as blood in the real world". Light realistic = "blood spatter from a distance"; heavy realistic = "pools of blood, gushing blood, and up-close blood spatter" (Restricted, 18+). | same |
| Violence and death | Mild = "implied or unrealistic depictions of violence, such as bodies disappearing the moment their health reaches zero"; Moderate = "non-graphic, realistic-looking depictions of violence and/or death"; Restricted = "graphic and realistic-looking depictions of violence and/or death" (beheading, impalement, dismemberment, organs shown). | same |
| Fear | Mild = "jump scares, ominous music, and/or gameplay that builds suspense"; Moderate = "lack of flesh with realistic-looking connective tissues, organs, and/or blood vessels visible". | same |
| No questionnaire | "If an experience does not have accurate or all content maturity information, Roblox restricts the playability of the experience on the platform for all players." | [Content maturity and compliance](https://create.roblox.com/docs/production/promotion/content-maturity) (page dated 2026-10-06) |
| Restricted workflow | "it must first receive a Restricted maturity label so that its content is restricted to age-verified players who are at least 18 years old. You must not add any restricted content to your experience before adding content maturity information." The creator must "confirm you are at least 18 years old by verifying your account". | same |
| Never allowed, any label | "extreme violence or serious physical or psychological abuse ... animal abuse and torture, realistic depictions of extreme gore, or the depiction, support, or glorification of war crimes". | same |
| Community Standards on gore | "we do not allow content that contains extreme violence or serious physical or psychological abuse, including ... Realistic or real-world depictions of extreme gore, graphic violence, or death"; Restricted games follow a separate Restricted Content Policy (help-center page, 403 today). | [Community Standards](https://about.roblox.com/community-standards) |
| Illegal activity | "We do not allow users to discuss or engage in illegal activities on Roblox, or to encourage others to do so." (about real conduct; a fictional murder story is rated by the Violence and Fear descriptors). | same |
| Verification history | 17+ tier launched 2023-06-20 with "a selfie and a photo of your government-issued ID"; the live docs now say 18+. The GitHub mirror of the guidelines page still shows the older All ages/9+/13+/17+ table, so re-check the live page before filling the questionnaire. | [Roblox newsroom 2023-06](https://about.roblox.com/newsroom/2023/06/introducing-experiences-for-people-17-and-older) |

What it means for GameOne: realistic red fish blood up close in the filleting minigame is "heavy realistic blood" = Restricted = age-verified 18+ only, which drops Roblox Kids, Roblox Select and unverified 16+ players, i.e. most of the audience. Pixelated or off-colour (dark, desaturated, PS1-dithered) blood is "unrealistic" and even "heavy" unrealistic blood stays Mild. Visible fish guts with realistic organs is Moderate fear. A murder that is told, not shown (evidence board, newspaper, a body under a sheet) is at most "non-graphic ... death" = Moderate (Select 9–15 plus 16+); a shown corpse with wounds pushes to Restricted. The questionnaire must be filled before publishing or the game is restricted for everyone.

## 2. DataStores and MemoryStores (as of 2026-10-07)

| Fact | Value today | Source |
|---|---|---|
| Server request budget, standard store | Read `60 + numPlayers × 40` per minute; Write the same; List `5 + numPlayers × 2`; Remove `60 + numPlayers × 40`. Experience-wide: Read `300 + concurrentUsers × 40`, Write `300 + concurrentUsers × 20`. | [Error codes and limits](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits) |
| Per-key throughput | Read 25 MB per minute, Write 4 MB per minute per key (60-second window); exceeding it shows as `DatastoreThrottled` or `KeyThrottled`. (The old "one write per key per 6 s" rule is not on today's page.) | same |
| Value and key size | Key value 4,194,304 bytes; key name, scope and store name 50 characters each; metadata value 250 characters. | same |
| Queue and drop | "Each queue has a limit of 30 requests. When the limit of a queue is reached, requests fail with an error code in the 301-306 range, indicating that the requests have been dropped entirely." 301 GetAsync, 302 SetAsync, 304 UpdateAsync, 306 RemoveAsync dropped. | same |
| Error codes to match | 502 `RequestRejected` "API Services rejected the request with error X."; 403 Studio API access disabled; 105 serialized value too big; 501/503/504 internal; experience-level `StandardWriteExperienceThrottled` etc.; server-level `...GameServerThrottled`. | same |
| UpdateAsync vs SetAsync | UpdateAsync "Reads the current key value from the server that last updated it before making any changes" and "Counts against both the read and write limits"; "If the callback returns nil, the write operation is cancelled". | [Data stores](https://create.roblox.com/docs/cloud-services/data-stores) |
| Best practice | "Prefer UpdateAsync() when a write depends on the current value or when multiple servers might write the same key." One key per player under 4 MB. "Wrap requests in pcall() and retry transient failures with exponential backoff. Add random jitter". The sample autosave "uses 180 seconds"; choose intervals "shorter than any session-lock expiration". | [Best practices](https://create.roblox.com/docs/cloud-services/data-stores/best-practices) |
| Studio access | File > Experience Settings > Security > "Enable Studio Access to API Services"; "Studio accesses the same data stores as the client application", so use a test copy of the place. | [Data stores](https://create.roblox.com/docs/cloud-services/data-stores) |
| MemoryStoreService | Item value 32 KB; expiration 0 to 3,888,000 s (45 days); quota "64 KB + 1.2 KB * [number of users]"; "1000 + 120 * [number of concurrent users] request units per minute" per experience; throttle status `PartitionRequestsOverLimit`. | [Memory stores](https://create.roblox.com/docs/cloud-services/memory-stores) |

Check of the cloud SaveData draft (`cloud_work/src/Fishing/Server/SaveData.lua`, defaults `autosaveS = 60`, `maxRetries = 5`, `lockStaleS = 1800`, `budgetFloor = 5`) against these numbers; Dev1 confirms on the real file:
- Budget: autosave every 60 s with 8 players is 8 UpdateAsync per minute, each counted as one read and one write, against a server budget of 380 reads and 380 writes at 8 players (60 + 40 per player). Still fine at the 100-player voice-chat cap (4,060 budget, 100 writes per minute). Keep 60 s; the docs' 180 s sample is for busier stores.
- Size: the per-key write cap is 4 MB per minute, so one profile save must stay well under 4 MB; the draft's `maxBytes` guard should be set in the tens of KB, not near the cap.
- Retries: `maxRetries = 5` with doubling backoff matches "pcall ... exponential backoff", but the draft has no jitter; add `math.random()` to the wait so servers do not retry in step.
- Throttle detection: the draft waits while `GetRequestBudgetForRequestType` is under `budgetFloor = 5`, which is the right guard against 301-306 drops ("dropped entirely", never queued).
- Error strings: a 502 arrives as the pcall error "API Services rejected the request with error X"; `DatastoreThrottled`, `KeyThrottled` and `...GameServerThrottled` are the throttle names. The draft retries every failure five times; a 403 (Studio access off) and a 105 (value too big) should fail fast instead.
- Lock: `lockStaleS = 1800` is longer than the 60 s autosave, as the best-practice page requires. The UpdateAsync transform must stay side-effect free because Roblox may call it more than once; the draft's transform only reads `old` and returns a record, which is right.
- Alternative lock: a MemoryStore hash-map key with a 120 s expiration costs about one request unit per player per minute against "1000 + 120 * users" per minute, so it is the cheaper lock if the DataStore record lock ever proves slow at load.

## 3. Server and client limits (as of 2026-10-07)

| Fact | Value today | Source |
|---|---|---|
| Max players | Set per place on the Creator Dashboard (`Players.MaxPlayers` is read-only in scripts); `PreferredPlayers` is what the matchmaker fills to. No maximum number is stated on today's docs pages; the 700 figure is devforum history, not documentation. | [Players](https://create.roblox.com/docs/reference/engine/classes/Players) |
| Voice chat cap | Voice chat "is only available for places that support a maximum of 100 players". | [Voice chat](https://create.roblox.com/docs/chat/voice-chat) |
| Server memory | "6.4GB + 100MB * (Peak Number of Players)" since 2024-12-04 (was 50 MB per player). Roblox staff announcement, not a docs page. | [DevForum: Even more server memory](https://devforum.roblox.com/t/even-more-server-memory/3293192) |
| Mesh triangles | "Individual meshes can not exceed 20,000 triangles" (the 10k figure in the brief is out of date); "A vertex can not be influenced by more than 4 bones or joints." | [Modeling specifications](https://create.roblox.com/docs/art/modeling/specifications) |
| Textures | "Roblox supports up to 4096×4096 pixel texture resolutions (4K)"; PBR guidance "1024×1024 (maximum)" for 8×8×8 unit assets, 512 for 4×4×4, 256 for 2×2×2; "Roblox supports up to 1024×1024 pixel spaces for texture maps"; the engine "automatically starts with lower quality versions of the texture and ramps up quality based on device resources". Formats .png .jpg .tga .bmp. | [Texture specifications](https://create.roblox.com/docs/art/modeling/texture-specifications) |
| SurfaceAppearance | Five maps (ColorMap, NormalMap, RoughnessMap, MetalnessMap, EmissiveMaskContent); normal maps OpenGL tangent space; no size limit on that page beyond the texture spec above. | [Surface appearance](https://create.roblox.com/docs/art/modeling/surface-appearance) |
| Asset moderation | Human and automated review "generally happens within a few hours after you import the asset"; "If an asset is still in the moderation queue when you publish your game, users cannot see or interact with the asset until Roblox approves it." | [Assets](https://create.roblox.com/docs/projects/assets) |
| Audio uploads | .mp3 .ogg .wav .flac, 20 MB, 7 minutes, 48 kHz max; "2,000 free audio assets per 30 days" ID-verified, "100 free audio assets per 30 days" unverified. | [Audio assets](https://create.roblox.com/docs/sound/assets) |
| Audio privacy | Since 2022-03-22 "all new audio uploaded will be Private"; "The audio assets in your experience will stop working if they were not uploaded by the same user or Group who created the experience." Today the owner grants other experiences or creators access from the asset's Permissions page in the Creator Dashboard; a denied asset prints "a clickable error message ... in the Output window". | [DevForum 2022 audio privacy](https://devforum.roblox.com/t/action-needed-upcoming-changes-to-asset-privacy-for-audio/1701697), [Asset privacy](https://create.roblox.com/docs/projects/assets/privacy) |
| Remote events | "RemoteEvents and UnreliableRemoteEvents both have a limit of approximately 500 requests per second, per client. This limit is shared among all remote events of the same type." UnreliableRemoteEvent: "Events with payloads larger than 1000 bytes are dropped." The often-quoted 50 KB/s per client is not on any page opened today; treat it as folklore. | [RemoteEvent](https://create.roblox.com/docs/reference/engine/classes/RemoteEvent), [UnreliableRemoteEvent](https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent) |

What it means for GameOne: the fishing net (FishingNet v2, RequestGuard) must stay far under 500 messages per second per client in both directions, which it does at a few per second; the per-frame rod delta must never become a remote. Trout, rod and town props can use up to 20k triangles each but PS1 style wants hundreds, so the budget is not the constraint, texture memory on phones is (keep 256 to 512 px, 1024 only for the terrain splat). Every generated sound must be uploaded by the account or group that owns the place, or granted to the experience, and uploaded hours before a playtest so moderation clears. Keep `MaxPlayers` at or under 100 so voice chat is never silently disabled.

## 4. Players and devices (as of 2026-10-07)

| Fact | Value today | Source |
|---|---|---|
| Scale | Q2 2026: 123M average DAUs, 29B hours engaged (deck gives DAUs and hours by region only, no device split). | [Roblox Q2 2026 Supplemental Materials (PDF)](https://s27.q4cdn.com/984876518/files/doc_financials/2026/q2/Roblox-Q2-2026-Supplemental-Materials.pdf) |
| Revenue through phone stores | FY2025: "29% of our revenue was attributable to Robux sales through the Apple App Store" and "15% ... through the Google Play Store" (FY2024: 30% and 16%). | [Roblox 10-K FY2025](https://www.sec.gov/Archives/edgar/data/1315098/000131509826000024/rblx-20251231.htm), [10-K FY2024](https://www.sec.gov/Archives/edgar/data/1315098/000131509825000033/rblx-20241231.htm) |
| Users by device | Press summary of Roblox's 2024 annual report: 80% of users on mobile, 17% PC, 3% console; mobile = 46% of Robux revenue. We did not find these percentages in the 10-K text we scanned, so treat as secondary. | [PocketGamer.biz, 2025-04-23](https://www.pocketgamer.biz/80-of-roblox-users-are-on-mobile-contributing-46-of-robux-revenue/) |
| Platforms | The client "operates on iOS, Android, Windows, Mac, Xbox, PlayStation, Chromebook, and select virtual reality hardware"; Xbox was "less than 2% of our total quarterly DAUs". | [10-K FY2025](https://www.sec.gov/Archives/edgar/data/1315098/000131509826000024/rblx-20251231.htm) |
| Device setting | "Playable Devices: Lets you enable each applicable device that supports your game." The publishing page: "Each applicable device type that you want to support. The default options are practical for most new creators." | [Experience settings](https://create.roblox.com/docs/studio/experience-settings), [Publish experiences](https://create.roblox.com/docs/production/publishing/publish-experiences-and-places) |
| "Must be playable on every device" rule | Not found in those words on any page opened today. The nearest rules: the Community Standards ban on "Deceptive, sensational, duplicative, or otherwise misleading content or metadata", and the questionnaire rule that inaccurate maturity information restricts playability. Practical reading: tick only devices the game is tested on. | [Community Standards](https://about.roblox.com/community-standards) |

What it means for GameOne: with roughly four of five players on phones and tablets and 44% of revenue through phone stores, a mouse-only game reaches a fifth of Roblox. `design/WSI_touch_gamepad.md` puts touch and gamepad in R1; this note says the touch profile belongs in the F1 to R1 window and the Phone and Tablet boxes stay unticked until it passes the AF1 playtest on a phone. Console (3%) can wait; VR stays unticked.

## 5. Text, voice and names (as of 2026-10-07)

| Fact | Value today | Source |
|---|---|---|
| What must be filtered | "you are responsible for filtering any displayed text that you don't have explicit control over": TextBox input, random or generated text, text fetched from the web, and "Stored user data like pet names retrieved from data stores". | [Text filtering](https://create.roblox.com/docs/ui/text-filtering) |
| How | Server-side `TextService:FilterStringAsync(text, userId)` then `GetNonChatStringForBroadcastAsync()` (shown to everyone) or `GetNonChatStringForUserAsync()` (per viewer); filter on submit, "Do not filter text in real time 'per character entered'". | same |
| Penalty | "If Roblox receives reports or automatically detects that your game doesn't apply text filtering, then the system removes the game until you add filtering." | same |
| Display names | `Player.DisplayName`: "display names are non-unique names a player displays to others" and "may have unicode characters"; `UserId` "will never change for the same account" and is what to key saves on. | [Player](https://create.roblox.com/docs/reference/engine/classes/Player) |
| Voice chat | "all 13+ age-verified users in a specific set of countries"; on by default "for verified 13+ users on all new games with a maximum of 100 players"; toggle in File > Experience Settings > Communication. | [Voice chat](https://create.roblox.com/docs/chat/voice-chat) |

What it means for GameOne: the catch log, evidence board, NPC lines, fish names and shop text are developer text sent by the server, so no filtering. The moment a player can type anything another player sees (naming an aquarium fish, a note pinned to the evidence board, a boat name) that string goes through FilterStringAsync on the server before it is stored or replicated, and it is filtered again when shown if it came from a DataStore. Show `DisplayName`, key everything on `UserId`. Voice chat needs nothing from us except a `MaxPlayers` of 100 or less.

## 6. Monetization and legal (as of 2026-10-07)

| Fact | Value today | Source |
|---|---|---|
| Ideas vs expression | "Copyright does not protect facts or ideas, but it may protect the specific expression of a fact or idea." Infringement stands even if you "Didn't monetize your content", "Credited the original creator", or "Purchased a physical copy"; copies count "even if it has been modified, including by AI tools". | [IP guidelines](https://create.roblox.com/docs/production/publishing/ip-guidelines) |
| DMCA | "Roblox prohibits the unauthorized use of intellectual property, and removes from the Roblox platform content that violates this policy"; repeat or egregious infringers get accounts "suspended or terminated"; a knowingly false notice is itself illegal (DMCA 512(f)). | [DMCA guidelines](https://create.roblox.com/docs/production/publishing/dmca-guidelines) |
| Look-alike content | Community Standards ban "content that is confusingly similar to that of other creators" and "Impersonating individuals, groups, or entities". | [Community Standards](https://about.roblox.com/community-standards) |
| Off-platform links | "You may not link to, share, or display URLs of any external websites or services except by using the Social Links feature on the Game, Group, or User detail pages." (exceptions: DevForum, Talent Hub, approved ads). | same |
| DevEx | "minimum of 30,000 Earned Robux"; rate 0.0038 USD per Robux since 2025-09-05 ($114 per 30,000), 0.0054 on eligible purchases by age-verified 18+ US players; one completed request per calendar month; 13+, Roblox-verified email, W-9 or W-8 on file, in compliance with the Terms. | [Developer Exchange](https://create.roblox.com/docs/production/monetization/developer-exchange) |

What it means for GameOne: the project rule "copy how it plays, never its assets" is exactly the line Roblox draws. Cast, sink, nip, hook-set, fight, fillet, sell, upgrade, day/night, weather, NPC routines, an evidence board and an aquarium are mechanics and are free to copy; About Fishing's title, fish names, dialogue, item names, icons, music, sound effects, fonts, models and the specific wording of its story are expression and must not appear, nor may the store page call the game "About Fishing on Roblox" or link to Steam. Any text or sound generated for us must be ours to upload. Charging Robux only matters once 30,000 earned Robux (about $114) is in play.

## Not verified today (do not quote these as facts)

| Claim | Status on 2026-10-07 |
|---|---|
| 700 players per server maximum | Devforum history only; no docs page opened today states a cap. `MaxPlayers` is set on the Creator Dashboard. |
| 50 KB/s per client before replication throttles | Not on the RemoteEvent, UnreliableRemoteEvent or remote-events pages today; the only documented rate is ~500 requests per second per client. |
| 10,000-triangle mesh limit | Superseded: the specifications page says 20,000. |
| SurfaceAppearance 1024 cap | The texture page gives 1024×1024 as the PBR "maximum" for 8×8×8 unit assets and the UV map space; the engine accepts up to 4096 for plain textures. |
| "An experience must be playable on every device it is published to" | Not found in those words; the nearest rules are the misleading-content clause and the questionnaire playability rule. |
| 80% mobile / 17% PC / 3% console | Press summary attributed to Roblox's 2024 annual report; not found in the 10-K text scanned today. The sourced number is 44% of FY2025 revenue through the Apple and Google stores. |
| Restricted Content Policy wording, Community Standards wording on death, DevEx FAQ | help.roblox.com returned 403 today; substitutes are the create.roblox.com and about.roblox.com pages cited above. |

## 7. Decisions this forces

1. The maturity label decides filleting: fish blood is dark, pixelated or off-colour (never red, never pooling or gushing, never an up-close spatter) so the game can hold Mild; realistic-red blood or shown organs moves it to Moderate; up-close realistic blood moves it to Restricted (18+). Owner: Coordinator rules the label target; Dev2 builds the minigame to it.
2. The murder is told, not shown: evidence board, newspaper, witness lines; no corpse with wounds. Owner: Coordinator (story), WordAgent (text).
3. The Maturity & Compliance Questionnaire is answered before the first public publish, by an account verified 18+ if anything mature is ever intended. Owner: Adrian.
4. Four in five Roblox players are on phones: the touch profile in `WSI_touch_gamepad.md` is F1 to R1 work, and Phone/Tablet are ticked in Playable Devices only after a phone playtest; console later, VR never. Owner: Dev2 (InputMap), Dev3 (phone playtest), Coordinator (ruling 1 of WS-I).
5. DataStore budget at 8 players (380 writes per minute) allows the 60 s autosave with room to spare; keep 60 s, add jitter to the retry wait, do not retry 403 or 105, keep profiles well under 4 MB. Owner: Dev1 (SaveData integration).
6. `MaxPlayers` stays at or below 100 so voice chat is never disabled; the F1 default of a small server (8 to 12) stands. Owner: Dev1.
7. Every generated sound and every texture is uploaded under the game owner's account or group, at least a day before a playtest so moderation clears, and no asset from About Fishing or from another creator's upload is ever referenced by id. Owner: Adrian (uploads), WordAgent (SFX_ART_LIST ids).
8. Every player-typed string shown to another player goes through `FilterStringAsync` on the server before it is stored or replicated; server-authored text (catch log, evidence board, shop) does not. Owner: Dev1.
9. The net stays well under 500 messages per second per client in each direction; per-frame input never becomes a remote; an UnreliableRemoteEvent payload stays under 1,000 bytes. Owner: Dev1, Dev3 (guard tests).
10. Phone texture budget: props 256 to 512 px, terrain at most 1024, PBR only where the camera gets close (held fish, rod). Owner: Dev2.
11. Store page and in-game text never name About Fishing, Steam or any external site; the only outside link is the Social Links box on the game page. Owner: WordAgent.
12. Re-check sections 1, 2 and 4 before publishing; the guideline page changed its age tiers between the GitHub mirror and the live page, so the numbers here have a short shelf life. Owner: Coordinator.
