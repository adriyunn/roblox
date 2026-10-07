local TackleBox = require("../src/Fishing/Shared/TackleBox")
-- nextId float trap: a save with nextId = 2^53 (or an id that large)
local box = TackleBox.deserialize({ w = 8, h = 6, nextId = 2^53, items = {} })
local id1 = TackleBox.place(box, { kind = "lure", key = "a", shape = TackleBox.SHAPES.line1 }, 0, 1, 1)
print("id1", id1, "nextId after", box.nextId, "nextId advanced?", box.nextId ~= id1)
print("check after one place:", pcall(TackleBox.check, box))
local id2 = TackleBox.place(box, { kind = "lure", key = "b", shape = TackleBox.SHAPES.line1 }, 0, 2, 1)
print("id2", id2, "same as id1?", id1 == id2, "items", #TackleBox.items(box), "freeCells", TackleBox.freeCells(box))
print("check after two places:", pcall(TackleBox.check, box))
-- same via a huge item id
local ok, err = pcall(TackleBox.deserialize, { w = 8, h = 6, nextId = 1, items = { { id = 2^53, kind = "lure", key = "a", shape = { { 0, 0 } }, rot = 0, x = 1, y = 1 } } })
print("deserialize with id 2^53 accepted?", ok, err)
-- items() exposes live references
local b2 = TackleBox.new()
TackleBox.place(b2, { kind = "lure", key = "a", shape = TackleBox.SHAPES.line2 }, 0, 1, 1)
TackleBox.items(b2)[1].item.shape[2][1] = 5
print("mutating items()[1].item.shape breaks check:", pcall(TackleBox.check, b2))
