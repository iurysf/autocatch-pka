local source = debug.getinfo(1, "S").source
local testDirectory = source:sub(1, 1) == "@" and source:sub(2):match("^(.*)[/\\]") or "."
local Interval = dofile((testDirectory or ".") .. "/../catch_interval.lua")
local CorpseClaim = dofile((testDirectory or ".") .. "/../corpse_claim.lua")
local CorpseSelection = dofile((testDirectory or ".") .. "/../corpse_selection.lua")
local CatchDispatch = dofile((testDirectory or ".") .. "/../catch_dispatch.lua")
local CorpseTarget = dofile((testDirectory or ".") .. "/../corpse_target.lua")
local AutoItem = dofile((testDirectory or ".") .. "/../auto_item.lua")

local passed, failed = 0, 0

local function check(name, fn)
  local ok, message = pcall(fn)
  if ok then
    passed = passed + 1
    print("PASS " .. name)
  else
    failed = failed + 1
    print("FAIL " .. name .. ": " .. tostring(message))
  end
end

local function equal(actual, expected)
  if actual ~= expected then error("expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

check("preserves current default limits", function()
  local minimum, maximum = Interval.validate(220, 260)
  equal(minimum, 220)
  equal(maximum, 260)
end)

check("clamps ping plus buffer between configured limits", function()
  equal(Interval.calculate(20, 100, 400), 100)
  equal(Interval.calculate(200, 100, 400), 230)
  equal(Interval.calculate(500, 100, 400), 400)
end)

check("accepts only integer limits from 50 through 2000", function()
  equal(Interval.validate(50, 2000), 50)
  equal(Interval.validate(49, 2000), nil)
  equal(Interval.validate(50, 2001), nil)
  equal(Interval.validate(100.5, 200), nil)
end)

check("rejects minimum greater than maximum", function()
  local minimum, reason = Interval.validate(300, 200)
  equal(minimum, nil)
  equal(reason, "minimum-greater-than-maximum")
end)

check("claims stacked corpse objects independently", function()
  local now = 1000
  local claims = CorpseClaim.new(6000, function() return now end)
  local topCorpse = {}
  local bottomCorpse = {}

  equal(claims:claim(topCorpse, { x = 10, y = 20, z = 6 }, 24349), true)
  equal(claims:isClaimed(topCorpse), true)
  equal(claims:isPositionClaimed({ x = 10, y = 20, z = 6 }), true)
  equal(claims:isClaimed(bottomCorpse), false)
  equal(claims:claim(bottomCorpse, { x = 10, y = 20, z = 6 }, 24349), true)
  equal(claims:isClaimed(bottomCorpse), true)
end)

check("expires an individual corpse claim without using position and ID", function()
  local now = 1000
  local claims = CorpseClaim.new(6000, function() return now end)
  local corpse = {}

  equal(claims:claim(corpse, { x = 10, y = 20, z = 6 }, 24349), true)
  now = 7001
  equal(claims:isClaimed(corpse), false)
end)

check("keeps a persistent claim until the exact corpse leaves the tile", function()
  local now = 1000
  local topCorpse = {}
  local claims = CorpseClaim.new(6000, function() return now end)

  equal(claims:claim(topCorpse, { x = 10, y = 20, z = 6 }, 24349, { persistent = true }), true)
  now = 7001
  claims:cleanup(function(item) return item == topCorpse end)
  equal(claims:isClaimed(topCorpse), true)
  claims:cleanup(function() return false end)
  equal(claims:isClaimed(topCorpse), false)
  equal(claims:isPositionClaimed({ x = 10, y = 20, z = 6 }), false)
end)

check("selects the newly created corpse when IDs are equal", function()
  local oldCorpse = { id = 24349 }
  local newCorpse = { id = 24349 }
  local beforeItems = { [oldCorpse] = true }
  local selected, index, hasMatch = CorpseSelection.pick({ newCorpse, oldCorpse }, {
    expectedId = 24349,
    beforeItems = beforeItems,
    preferNew = true,
    topItem = newCorpse,
    isClaimed = function() return false end
  })

  equal(selected, newCorpse)
  equal(index, 1)
  equal(hasMatch, true)
end)

check("does not select the pre-existing body while waiting for a new corpse", function()
  local oldCorpse = { id = 24349 }
  local selected, _, hasMatch = CorpseSelection.pick({ oldCorpse }, {
    expectedId = 24349,
    beforeItems = { [oldCorpse] = true },
    preferNew = true,
    isClaimed = function() return false end
  })

  equal(selected, nil)
  equal(hasMatch, true)
end)

check("retries a rejected dispatch before the deadline", function()
  equal(CatchDispatch.decide(1200, 6000, true, false), "retry")
  equal(CatchDispatch.retryDelay(1200, 6000, 400), 400)
end)

check("drops a rejected dispatch at the deadline", function()
  equal(CatchDispatch.decide(6000, 6000, true, false), "drop")
end)

check("accepts fire-and-forget dispatch without boolean result", function()
  equal(CatchDispatch.decide(1200, 6000, true, nil), "sent")
  equal(CatchDispatch.decide(1200, 6000, true, true), "sent")
  equal(CatchDispatch.decide(1200, 6000, true, false), "retry")
end)

check("matches only the configured corpse IDs", function()
  equal(CorpseTarget.hasConfigured(3552, 6076, 0, 0), true)
  local matched, label, ball = CorpseTarget.resolve(6076, 3552, 6076, 0, 0)
  equal(matched, true)
  equal(label, "Corpo 1 (ID 6076)")
  equal(ball, 3552)
  local unrelated = CorpseTarget.resolve(12345, 3552, 6076, 0, 0)
  equal(unrelated, false)
end)

check("resolves any number of body cards without using Pokemon names", function()
  local entries = {
    { id = 1, name = "Pokemon 1", ballId = 3552, corpseId = 6076 },
    { id = 2, name = "Pokemon 2", ballId = 2392, corpseId = 12345 },
    { id = 3, name = "Pokemon 3", ballId = 0, corpseId = 99999 }
  }

  equal(CorpseTarget.hasConfigured(entries), true)
  local matched, name, ball = CorpseTarget.resolve(12345, entries)
  equal(matched, true)
  equal(name, "Pokemon 2")
  equal(ball, 2392)

  local incomplete = CorpseTarget.resolve(99999, entries)
  equal(incomplete, false)
end)

check("resolves body IDs through the ball index", function()
  local entries = {
    { id = 1, ballId = 3552, corpseId = 6076 },
    { id = 2, ballId = 2392, corpseId = 12345 }
  }
  local index = CorpseTarget.buildBallIndex(entries)
  local matched, label, ball = CorpseTarget.resolveIndexed(12345, index)

  equal(matched, true)
  equal(label, "Corpo ID 12345")
  equal(ball, 2392)
  equal(CorpseTarget.resolveIndexed(99999, index), false)
end)

check("normalizes the selected inventory item ID", function()
  local item = { getId = function() return 1234 end }
  equal(AutoItem.normalizeId(item), 1234)
  equal(AutoItem.normalizeId("5678"), 5678)
  equal(AutoItem.normalizeId(0), 0)
end)

check("uses the selected item through the confirmed right-click path", function()
  local selectedItem = { getId = function() return 4321 end }
  local usedItem = nil
  local confirmed = nil
  local fakeGame = {
    findPlayerItem = function(itemId, subType)
      equal(itemId, 4321)
      equal(subType, -1)
      return selectedItem
    end,
    use = function(item, isConfirmed)
      usedItem = item
      confirmed = isConfirmed
    end
  }

  equal(AutoItem.dispatch(4321, fakeGame), true)
  equal(usedItem, selectedItem)
  equal(confirmed, true)
end)

check("rejects direct use without an item or inventory API", function()
  local ok, reason = AutoItem.dispatch(0, {})
  equal(ok, false)
  equal(reason, "invalid-item-id")

  local unavailable, unavailableReason = AutoItem.dispatch(4321, {})
  equal(unavailable, false)
  equal(unavailableReason, "find-player-item-unavailable")

  local noUse, noUseReason = AutoItem.dispatch(4321, {
    findPlayerItem = function() return { getId = function() return 4321 end } end
  })
  equal(noUse, false)
  equal(noUseReason, "use-item-unavailable")

  local missing, missingReason = AutoItem.dispatch(4321, {
    findPlayerItem = function() return nil end,
    use = function() end
  })
  equal(missing, false)
  equal(missingReason, "item-not-in-inventory")
end)

check("creates a buff snapshot and discovers new or extended buffs", function()
  local before = AutoItem.makeBuffSnapshot({
    { name = "loot", endTime = 10000, value = 10 },
    { name = "experience", endTime = 7000, value = 5 }
  }, 1000)
  local after = AutoItem.makeBuffSnapshot({
    { name = "loot", endTime = 12000, value = 10 },
    { name = "experience", endTime = 5000, value = 5 },
    { name = "SweetAroma", endTime = 18000, value = 0 }
  }, 2000)
  local changed = AutoItem.changedBuffNames(before, after, 2000)
  equal(#changed, 2)
  equal(changed[1], "SweetAroma")
  equal(changed[2], "loot")
end)

check("subtracts elapsed time from a buff snapshot", function()
  equal(AutoItem.snapshotRemainingMs({ remainingMs = 5000, receivedAtMs = 1000 }, 2500), 3500)
  equal(AutoItem.snapshotRemainingMs({ remainingMs = 5000, receivedAtMs = 7000 }, 2500), 5000)
  equal(AutoItem.snapshotRemainingMs({ remainingMs = 5000, receivedAtMs = 1000 }, 7000), 0)
end)

check("waits for every buff linked to an item", function()
  local remaining = { loot = 1200, SweetAroma = 4800 }
  equal(AutoItem.maxBuffRemainingMs({ "loot", "SweetAroma" }, function(name)
    return remaining[name] or 0
  end), 4800)
end)

check("correlates a buff change only with the consumed learning item", function()
  equal(AutoItem.wasItemConsumed(3, 2), true)
  equal(AutoItem.wasItemConsumed(3, 3), false)
  equal(AutoItem.wasItemConsumed(3, 4), false)
end)

check("keeps standalone UI anchors independent of later siblings", function()
  local otuiPath = (testDirectory or ".") .. "/../autocatch.otui"
  local file = assert(io.open(otuiPath, "r"))
  local otui = file:read("*a")
  file:close()

  equal(otui:find("anchors.centerIn: entriesList", 1, true), nil)
  equal(otui:find("anchors.right: addPokemon.left", 1, true), nil)
  equal(otui:find("anchors.right: enabled.left", 1, true), nil)
  equal(otui:find("anchors.right: autoItemEnabled.left", 1, true), nil)
  equal(otui:find("AutoCatchWindow < NewOpaqueWindow", 1, true), nil)
  equal(otui:find("  NewRedCloseButton", 1, true), nil)
  equal(otui:find("AutoCatchEntryRow < AutoCatchCard\n  height: 104\n  anchors.left:", 1, true), nil)
  equal(otui:find("AutoCatchEntryRow < AutoCatchCard\n  height: 104\n  anchors.right:", 1, true), nil)
  local rowPosition = assert(otui:find("AutoCatchEntryRow < AutoCatchCard", 1, true))
  local utilsPosition = assert(otui:find("id: tabUtilsContent", 1, true))
  if rowPosition <= utilsPosition then
    error("AutoCatchEntryRow must be declared after the AutoCatchPanel contents")
  end
  equal(otui:find("id: clearEntry", 1, true), nil)
  equal(otui:find("id: deleteEntry", 1, true) ~= nil, true)
  equal(otui:find("text: Excluir", 1, true) ~= nil, true)
  equal(otui:find("AutoCatchPrimaryButton\n        id: presetSafe", 1, true), nil)
  equal(otui:find("AutoCatchOptionButton\n        id: presetSafe", 1, true) ~= nil, true)
  equal(otui:find("text: Selecionar Slot", 1, true), nil)
  equal(otui:find("text: Selecionar Item", 1, true) ~= nil, true)
  equal(otui:find("+ Add novo Item", 1, true) ~= nil, true)
  equal(otui:find("AutoCatchAutoItemRow < AutoCatchCard", 1, true) ~= nil, true)
  equal(otui:find("id: autoItemsList", 1, true) ~= nil, true)
  equal(otui:find("id: itemEnabled", 1, true) ~= nil, true)
  equal(otui:find("id: deleteItem", 1, true) ~= nil, true)
  equal(otui:find("tooltip: Arraste um item real da mochila para este card", 1, true) ~= nil, true)
  equal(otui:find("virtual: false", 1, true) ~= nil, true)
  equal(otui:find("selectable: true", 1, true) ~= nil, true)
  equal(otui:find("id: autoItemSlotEdit", 1, true), nil)
  equal(otui:find("id: autoItemIntervalEdit", 1, true), nil)
  equal(otui:find("text: Intervalo (minutos):", utilsPosition, true), nil)
end)

check("persists the direct item and uses no action bar executor", function()
  local luaPath = (testDirectory or ".") .. "/../autocatch.lua"
  local file = assert(io.open(luaPath, "r"))
  local lua = file:read("*a")
  file:close()

  equal(lua:find("g_settings.set(SETTINGS.AUTO_ITEMS", 1, true) ~= nil, true)
  equal(lua:find("g_settings.getString(SETTINGS.AUTO_ITEMS", 1, true) ~= nil, true)
  equal(lua:find("AUTO_ITEM_NEXT_ID", 1, true) ~= nil, true)
  equal(lua:find("local okExec, errorMessage = AutoItem.dispatch(card.itemId)", 1, true) ~= nil, true)
  equal(lua:find("onPlayerBuffsReceived = onAutoItemBuffsReceived", 1, true) ~= nil, true)
  equal(lua:find("AUTO_ITEM_RETRY_MS = 15000", 1, true) ~= nil, true)
  equal(lua:find("AutoItem.wasItemConsumed", 1, true) ~= nil, true)
  equal(lua:find("table.remove(autoItems", 1, true) ~= nil, true)
  equal(lua:find("executeSlot", 1, true), nil)
  equal(lua:find("nao encontrado na mochila", 1, true) ~= nil, true)
  equal(lua:find("Configure um item da mochila antes de ativar o card.", 1, true) ~= nil, true)
end)

check("exports the server buff timer API", function()
  local luaPath = (testDirectory or ".") .. "/../../game_buffs/playerbuffs.lua"
  local file = assert(io.open(luaPath, "r"))
  local lua = file:read("*a")
  file:close()

  equal(lua:find("modules.game_buffs.getBuffRemainingMs", 1, true) ~= nil, true)
  equal(lua:find("modules.game_buffs.getBuffSnapshot", 1, true) ~= nil, true)
  equal(lua:find("receivedAtMs", 1, true) ~= nil, true)
end)

check("does not use the Action Bar API for Auto Item", function()
  local luaPath = (testDirectory or ".") .. "/../auto_item.lua"
  local file = assert(io.open(luaPath, "r"))
  local lua = file:read("*a")
  file:close()

  equal(lua:find("useInventoryItem", 1, true), nil)
  equal(lua:find("gameApi.use(item, true)", 1, true) ~= nil, true)
end)

check("reuses card labels after all cards are deleted", function()
  local entries = {
    { id = 1, name = "Pokemon 1" },
    { id = 2, name = "Pokemon 2" }
  }
  table.remove(entries, 1)
  table.remove(entries, 1)
  local nextLabel = string.format("Pokemon %d", #entries + 1)
  equal(nextLabel, "Pokemon 1")
end)

check("allows the lower corpse after the upper corpse leaves", function()
  local now = 1000
  local topCorpse = {}
  local lowerCorpse = {}
  local claims = CorpseClaim.new(6000, function() return now end)

  equal(claims:claim(topCorpse, { x = 10, y = 20, z = 6 }, 24349, { persistent = true }), true)
  claims:cleanup(function(item) return item == topCorpse end)
  equal(claims:isPositionClaimed({ x = 10, y = 20, z = 6 }), true)
  claims:cleanup(function(item) return item == lowerCorpse end)
  equal(claims:isPositionClaimed({ x = 10, y = 20, z = 6 }), false)
  equal(claims:claim(lowerCorpse, { x = 10, y = 20, z = 6 }, 24349, { persistent = true }), true)
end)

print(string.format("RESULT %d passed, %d failed", passed, failed))
if failed > 0 then error("Auto Catch interval tests failed") end
