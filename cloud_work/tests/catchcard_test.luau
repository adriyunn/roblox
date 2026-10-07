--!strict
-- catchcard_test (About Fishing F1 cloud work; Cloud, 2026-10-07)
-- Proves CatchCard: metric and imperial strings for the 0.40 m / 0.704 kg median trout ("40.0 cm",
-- "15.7 in", "0.70 kg", "1 lb 9 oz"), the 2.03 kg -> "4 lb 8 oz" and 0.45 kg -> "1 lb 0 oz" ounce
-- carries, badge order from real CatchLog results (a first catch, a repeat, a double record), the
-- price present and absent, zone and lure name fallbacks, the ordered lines, and negative controls
-- (unknown species, bad units, a zero length).
-- Run from this folder: luau catchcard_test.luau

local Stub = require("./RobloxStub")
local T = Stub.harness("catchcard_test")
local CatchCard = require("../src/Fishing/Client/CatchCard")
local CatchLog = require("../src/Fishing/Shared/CatchLog")

local function join(list: { string }): string
	return table.concat(list, " | ")
end

-- ---------------------------------------------------------------- formatting
T.eq(CatchCard.formatLength(0.40, "metric"), "40.0 cm", "0.40 m metric -> 40.0 cm")
T.eq(CatchCard.formatLength(0.40, "imperial"), "15.7 in", "0.40 m imperial -> 15.7 in")
T.eq(CatchCard.formatLength(1.2, "metric"), "120.0 cm", "1.2 m metric stays in cm")
T.eq(CatchCard.formatLength(0.255, "metric"), "25.5 cm", "one decimal of cm")
T.eq(CatchCard.formatWeight(0.704, "metric"), "0.70 kg", "0.704 kg metric -> 0.70 kg")
T.eq(CatchCard.formatWeight(0.704, "imperial"), "1 lb 9 oz", "0.704 kg imperial -> 1 lb 9 oz (24.8 oz rounds to 25)")
T.eq(CatchCard.formatWeight(2.03, "imperial"), "4 lb 8 oz", "2.03 kg -> 71.6 oz -> 72 oz -> 4 lb 8 oz")
T.eq(CatchCard.formatWeight(0.45, "imperial"), "1 lb 0 oz", "0.45 kg -> 15.87 oz rounds to 16 and carries into a pound")
T.eq(CatchCard.formatWeight(0.2, "imperial"), "7 oz", "under a pound is ounces only")
T.eq(CatchCard.formatWeight(0, "imperial"), "0 oz", "zero weight imperial")
T.eq(CatchCard.formatWeight(1.83, "metric"), "1.83 kg", "two decimals of kg")
T.eq(CatchCard.formatCoins(8), "8 coins", "8 coins plural")
T.eq(CatchCard.formatCoins(1), "1 coin", "1 coin singular")

-- ---------------------------------------------------------------- badges
T.eq(join(CatchCard.badgeOrder), "New species! | New record! | Heaviest yet!", "badgeOrder is the fixed order")
T.eq(join(CatchCard.badgesFor({ isFirst = true, isLengthRecord = true, isWeightRecord = true })), "New species!", "a first catch shows only New species!")
T.eq(join(CatchCard.badgesFor({ isFirst = false, isLengthRecord = true, isWeightRecord = true })), "New record! | Heaviest yet!", "a double record shows both, in order")
T.eq(join(CatchCard.badgesFor({ isFirst = false, isLengthRecord = false, isWeightRecord = true })), "Heaviest yet!", "a weight-only record")
T.eq(join(CatchCard.badgesFor({ isFirst = false, isLengthRecord = true, isWeightRecord = false })), "New record!", "a length-only record")
T.eq(#CatchCard.badgesFor({ isFirst = false, isLengthRecord = false, isWeightRecord = false }), 0, "no badges on an ordinary repeat")

-- ---------------------------------------------------------------- the card from real CatchLog results
local log = CatchLog.new()
local first = { speciesId = "trout", lengthM = 0.40, weightKg = 0.704, zoneId = "reeds", dayN = 1, timeOfDay = 9, lureId = "worm" }
local r1 = CatchLog.record(log, first)
local opts: CatchCard.Opts = { units = "metric", showPrice = true, zoneNames = { reeds = "The Reeds" }, lureNames = {} }
local card = CatchCard.build(first, r1, opts)
T.eq(card.title, "Trout", "title is the species display name")
T.eq(card.lengthText, "40.0 cm", "card lengthText metric")
T.eq(card.weightText, "0.70 kg", "card weightText metric")
T.eq(card.sizeClass, "medium", "0.40 m trout is medium")
T.eq(card.sizeText, "Medium", "sizeText is capitalised")
T.eq(join(card.badges), "New species!", "first catch badge")
T.eq(card.priceText, "8 coins", "price from GameData.priceFor: 11 * 0.704 * 1.0 = 7.74 -> 8 coins")
T.eq(card.zoneText, "The Reeds", "zone name from zoneNames")
T.eq(card.lureText, "Worm", "lure name falls back to GameData.LURES")
T.eq(join(card.lines), "Trout | New species! | Length: 40.0 cm | Weight: 0.70 kg | Size: Medium | Zone: The Reeds | Lure: Worm | Sells for 8 coins", "lines in display order")

local repeatCatch = { speciesId = "trout", lengthM = 0.38, weightKg = 0.60, zoneId = "deep", dayN = 1, timeOfDay = 10, lureId = "mystery" }
local r2 = CatchLog.record(log, repeatCatch)
card = CatchCard.build(repeatCatch, r2, { units = "metric", showPrice = false })
T.eq(#card.badges, 0, "a smaller repeat has no badges")
T.eq(card.priceText, nil, "showPrice false -> no priceText")
T.eq(card.zoneText, "deep", "an unmapped zone shows its id")
T.eq(card.lureText, "mystery", "an unknown lure shows its id")
T.eq(join(card.lines), "Trout | Length: 38.0 cm | Weight: 0.60 kg | Size: Medium | Zone: deep | Lure: mystery", "lines without badges or price")

local record = { speciesId = "trout", lengthM = 0.45, weightKg = 1.0, zoneId = "reeds", dayN = 2, timeOfDay = 6, lureId = "fly" }
local r3 = CatchLog.record(log, record)
card = CatchCard.build(record, r3, { units = "imperial", showPrice = true, lureNames = { fly = "Our Dry Fly" } })
T.eq(join(card.badges), "New record! | Heaviest yet!", "a longer and heavier repeat shows both record badges")
T.eq(card.lengthText, "17.7 in", "0.45 m imperial -> 17.7 in")
T.eq(card.weightText, "2 lb 3 oz", "1.0 kg imperial -> 35 oz -> 2 lb 3 oz")
T.eq(card.lureText, "Our Dry Fly", "lureNames overrides GameData's name")
T.eq(card.lines[2], "New record!", "the first badge is line 2")
T.eq(card.lines[3], "Heaviest yet!", "the second badge is line 3")
T.eq(card.lines[#card.lines], "Sells for " .. card.priceText :: string, "the price is the last line")

card = CatchCard.build(first, r1, nil)
T.eq(card.lengthText, "40.0 cm", "opts nil defaults to metric")
local minTrout = { speciesId = "trout", lengthM = 0.25, weightKg = 0.172, zoneId = "reeds", lureId = "worm" }
card = CatchCard.build(minTrout, { isFirst = false, isLengthRecord = false, isWeightRecord = false }, { showPrice = true })
T.eq(card.priceText, "1 coin", "a minimum trout sells for 1 coin (singular)")
T.eq(card.sizeClass, "small", "0.25 m trout is small")
card = CatchCard.build({ speciesId = "trout", lengthM = 0.50, weightKg = 1.375, zoneId = "reeds", lureId = "worm" }, r2, nil)
T.eq(card.sizeClass, "large", "0.50 m trout is large")

-- ---------------------------------------------------------------- negative controls
T.throws(function() CatchCard.build({ speciesId = "kraken", lengthM = 1, weightKg = 1, zoneId = "deep", lureId = "worm" }, r1, nil) end, "unknown species", "an unknown species errors")
T.throws(function() CatchCard.build(first, r1, { units = "furlongs" :: any }) end, "units", "bad units error")
T.throws(function() CatchCard.build({ speciesId = "trout", lengthM = 0, weightKg = 1, zoneId = "deep", lureId = "worm" }, r1, nil) end, "lengthM", "a zero length errors")
T.throws(function() CatchCard.formatWeight(-1, "metric") end, "weightKg", "a negative weight errors")

T.finish()
