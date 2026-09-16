local CatchInterval = dofile('/modules/game_autocatch/catch_interval.lua')
local CorpseClaim = dofile('/modules/game_autocatch/corpse_claim.lua')
local CorpseSelection = dofile('/modules/game_autocatch/corpse_selection.lua')
local CatchDispatch = dofile('/modules/game_autocatch/catch_dispatch.lua')
local CorpseTarget = dofile('/modules/game_autocatch/corpse_target.lua')
local AutoItem = dofile('/modules/game_autocatch/auto_item.lua')

local function debugLog(msg)
  pcall(function()
    local timeStr = os and os.date and os.date("%Y-%m-%d %H:%M:%S") or "time"
    local text = string.format("[%s] %s\n", timeStr, tostring(msg))
    local f1 = io.open("autocatch_debug.log", "a")
    if f1 then
      f1:write(text)
      f1:close()
    end
    local tempDir = os and os.getenv and os.getenv("TEMP")
    if tempDir then
      local f2 = io.open(tempDir .. "\\autocatch_debug.log", "a")
      if f2 then
        f2:write(text)
        f2:close()
      end
    end
  end)
  pcall(function() print("[AutoCatch] " .. tostring(msg)) end)
end

local ui = {
  window = nil,
  panel = nil,
  button = nil,
  statusCard = nil,
  statusIndicator = nil,
  statusTitle = nil,
  statusLabel = nil,
  enabledCheckBox = nil,
  navTabCatch = nil,
  navTabSafety = nil,
  navTabUtils = nil,
  tabCatchContent = nil,
  tabSafetyContent = nil,
  tabUtilsContent = nil,
  presetSafeBtn = nil,
  presetNormalBtn = nil,
  presetTurboBtn = nil,
  addPokemonBtn = nil,
  entriesList = nil,
  entriesEmpty = nil,
  entriesCountHint = nil,
  shinyBall1Btn = nil,
  shinyBall2Btn = nil,
  shinyCheckBox = nil,
  autoItemsList = nil,
  autoItemsEmpty = nil,
  autoItemsCountHint = nil,
  addAutoItemBtn = nil,
  catchIntervalMinEdit = nil,
  catchIntervalMaxEdit = nil
}

local corpseEntries = {}
local nextCorpseEntryId = 0
local corpseBallIndex = {}
local shinyLookTypes = {}
local shinyBallChoice = 1
local catchAllShiny = false
local enabled = false
local updatingInterface = false
local sessionThrows = 0
local recentBurstThrows = 0
local dyingTargets = {}
local observedTargets = {}
local retryEvents = {}
local catchVerificationEvents = {}
local catchQueue = {}
local catchQueueEvent = nil
local queuedTargets = {}
local activeCatchJob = nil
local nextCatchJobId = 0
local ballRefreshEvent = nil
local corpseSelectGrabber = nil
local ballSelectGrabber = nil
local selectingCorpseEntryId = nil
local selectingBallEntryId = nil
local lastThrowTime = 0
local catchIntervalMinimum = CatchInterval.DEFAULT_MINIMUM
local catchIntervalMaximum = CatchInterval.DEFAULT_MAXIMUM

local function rebuildCorpseBallIndex()
  corpseBallIndex = CorpseTarget.buildBallIndex(corpseEntries)
end

local function resolveCorpseTarget(itemId)
  return CorpseTarget.resolveIndexed(itemId, corpseBallIndex)
end

local autoItems = {}
local nextAutoItemCardId = 0
local autoItemTimerEvent = nil
local autoItemSelectionGrabber = nil
local autoItemLearningCardId = nil
local autoItemBuffSnapshot = nil
local updatingAutoItemInterface = false

local SETTINGS = {
  BALL1_ID = 'autoCatchBall1Id',
  BALL2_ID = 'autoCatchBall2Id',
  BALL_ID_LEGACY = 'autoCatchBallId',
  CORPSE1_ID = 'autoCatchCorpse1Id',
  CORPSE2_ID = 'autoCatchCorpse2Id',
  CORPSE_ID_LEGACY = 'autoCatchCorpseId',
  CORPSE_ENTRIES = 'autoCatchCorpseEntries',
  TARGETS1 = 'autoCatchPokemonNames1',
  TARGETS2 = 'autoCatchPokemonNames2',
  TARGETS_LEGACY = 'autoCatchPokemonNames',
  SHINY_BALL_CHOICE = 'autoCatchShinyBallChoice',
  CATCH_ALL_SHINY = 'autoCatchAllShiny',
  SHINY_LOOKTYPES = 'autoCatchShinyLookTypes',
  AUTO_ACTION_SLOT = 'autoCatchActionSlot',
  AUTO_ITEMS = 'autoCatchAutoItems',
  AUTO_ITEM_NEXT_ID = 'autoCatchAutoItemNextId',
  AUTO_ITEM_ID = 'autoCatchAutoItemId',
  AUTO_ITEM_ENABLED = 'autoCatchAutoItemEnabled',
  AUTO_ITEM_INTERVAL = 'autoCatchAutoItemInterval',
  CATCH_INTERVAL_MIN = 'autoCatchQueueIntervalMin',
  CATCH_INTERVAL_MAX = 'autoCatchQueueIntervalMax',
  LEGACY_TARGET_NAME = 'autoCatchPokemonName'
}

local CORPSE_RETRY_DELAY = 100
local CORPSE_RETRY_LIMIT = 50
local MAX_CATCH_DISTANCE = 10
local VISIBLE_SCAN_RADIUS_X = 10
local VISIBLE_SCAN_RADIUS_Y = 5
local CORPSE_CLAIM_TTL = 6000
local CATCH_DISPATCH_RETRY_WINDOW = 5000
local CATCH_RESULT_CHECK_DELAY = 1800
local MAX_CATCH_SEND_ATTEMPTS = 2
local corpseClaims = CorpseClaim.new(CORPSE_CLAIM_TTL, function() return g_clock.millis() end)

local function trim(value)
  return (value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function normalizedName(value)
  local text = trim(value):lower()
  text = text:gsub('%s*%b[]%s*$', '')
  text = text:gsub('%s*%(.-%)%s*$', '')
  return trim(text)
end

local function loadShinyLookTypes()
  shinyLookTypes = {}
  local raw = g_settings.getString(SETTINGS.SHINY_LOOKTYPES, '')
  if raw ~= '' then
    local ok, decoded = pcall(function() return json.decode(raw) end)
    if ok and type(decoded) == 'table' then
      for _, id in ipairs(decoded) do
        id = tonumber(id)
        if id and id > 0 then
          shinyLookTypes[id] = true
        end
      end
      for k, _ in pairs(decoded) do
        local id = tonumber(k)
        if id and id > 0 then
          shinyLookTypes[id] = true
        end
      end
    end
  end
end

local function saveShinyLookTypes()
  local list = {}
  for id, _ in pairs(shinyLookTypes) do
    if type(id) == 'number' and id > 0 then
      table.insert(list, id)
    end
  end
  table.sort(list)
  g_settings.set(SETTINGS.SHINY_LOOKTYPES, json.encode(list))
  g_settings.save()
end

local function registerShinyLookType(lookTypeId, name)
  if not lookTypeId or lookTypeId <= 0 then return end
  if not shinyLookTypes[lookTypeId] then
    shinyLookTypes[lookTypeId] = true
    saveShinyLookTypes()
    local display = name and tostring(name) or 'Pokemon'
    print(string.format('[AutoCatch] Sprite de Shiny aprendida e salva via Look: %s (LookType %d).', display, lookTypeId))
    if setStatus then
      setStatus(string.format('Shiny memorizado: %s (Sprite ID %d).', display, lookTypeId), '#62d985')
    end
  end
end

local function isCreatureShiny(creature)
  if not creature then return false end
  if type(creature) == 'userdata' or type(creature) == 'table' then
    if creature.isShiny and type(creature.isShiny) == 'function' then
      local ok, isSh = pcall(creature.isShiny, creature)
      if ok and isSh == true then return true end
    end
    if creature.shinyIcon and (creature.shinyIcon == 1 or creature.shinyIcon == true) then
      return true
    end
    local okIcon, icon = pcall(function() return creature:getShinyIcon() end)
    if okIcon and icon and (icon == 1 or icon == true) then return true end
    local okName, name = pcall(function() return creature:getName() end)
    if okName and type(name) == 'string' and normalizedName(name):match('^shiny%s+') then
      return true
    end
    local okOutfit, outfit = pcall(function() return creature:getOutfit() end)
    if okOutfit and type(outfit) == 'table' then
      local lookType = tonumber(outfit.type or outfit.lookType) or 0
      if lookType > 0 and shinyLookTypes[lookType] then
        return true
      end
    end
  end
  return false
end

local function getShinyBallId()
  local entry = corpseEntries[shinyBallChoice] or corpseEntries[1]
  return entry and (tonumber(entry.ballId) or 0) or 0
end

local function getShinyCorpseId()
  local entry = corpseEntries[shinyBallChoice] or corpseEntries[1]
  return entry and (tonumber(entry.corpseId) or 0) or 0
end

local function hasConfiguredCorpseTarget()
  return next(corpseBallIndex) ~= nil
end

local function getTargetBallForCreature(value, creature, isShinyOverride)
  if not hasConfiguredCorpseTarget() then return false, 0, nil end
  local nameStr = type(value) == 'string' and value or (value and value.getName and value:getName() or '')
  return true, 0, (nameStr ~= '' and nameStr or 'Pokemon')
end

local function normalizeCorpseEntry(rawEntry, index)
  if type(rawEntry) ~= 'table' then return nil end
  local entryId = tonumber(rawEntry.id) or index
  if entryId <= 0 then entryId = index end
  nextCorpseEntryId = math.max(nextCorpseEntryId, entryId)
  return {
    id = entryId,
    name = string.format('Pokemon %d', index),
    ballId = math.max(0, tonumber(rawEntry.ballId) or 0),
    corpseId = math.max(0, tonumber(rawEntry.corpseId) or 0)
  }
end

local function loadCorpseEntries()
  corpseEntries = {}
  nextCorpseEntryId = 0

  local raw = g_settings.getString(SETTINGS.CORPSE_ENTRIES, '')
  if raw ~= '' then
    local ok, decoded = pcall(function() return json.decode(raw) end)
    if ok and type(decoded) == 'table' then
      for index, rawEntry in ipairs(decoded) do
        local entry = normalizeCorpseEntry(rawEntry, index)
        if entry then table.insert(corpseEntries, entry) end
      end
    end
  end

  if #corpseEntries == 0 then
    local legacy = {
      { ballId = g_settings.getNumber(SETTINGS.BALL1_ID, 0), corpseId = g_settings.getNumber(SETTINGS.CORPSE1_ID, 0) },
      { ballId = g_settings.getNumber(SETTINGS.BALL2_ID, 0), corpseId = g_settings.getNumber(SETTINGS.CORPSE2_ID, 0) }
    }
    local legacyBall = g_settings.getNumber(SETTINGS.BALL_ID_LEGACY, 0)
    local legacyCorpse = g_settings.getNumber(SETTINGS.CORPSE_ID_LEGACY, 0)
    if legacy[1].ballId <= 0 then legacy[1].ballId = legacyBall end
    if legacy[1].corpseId <= 0 then legacy[1].corpseId = legacyCorpse end

    for index, rawEntry in ipairs(legacy) do
      if rawEntry.ballId > 0 or rawEntry.corpseId > 0 then
        nextCorpseEntryId = nextCorpseEntryId + 1
        table.insert(corpseEntries, {
          id = nextCorpseEntryId,
          name = string.format('Pokemon %d', index),
          ballId = math.max(0, rawEntry.ballId),
          corpseId = math.max(0, rawEntry.corpseId)
        })
      end
    end
  end

  rebuildCorpseBallIndex()
end

local function setStatus(text, color)
  if not ui.statusLabel then return end
  ui.statusLabel:setText(text)
  ui.statusLabel:setColor(color or '#b8b8b8')
end

local function saveSettings()
  g_settings.set(SETTINGS.CORPSE_ENTRIES, json.encode(corpseEntries))

  local first = corpseEntries[1] or {}
  local second = corpseEntries[2] or {}
  g_settings.set(SETTINGS.BALL1_ID, tonumber(first.ballId) or 0)
  g_settings.set(SETTINGS.BALL2_ID, tonumber(second.ballId) or 0)
  g_settings.set(SETTINGS.CORPSE1_ID, tonumber(first.corpseId) or 0)
  g_settings.set(SETTINGS.CORPSE2_ID, tonumber(second.corpseId) or 0)
  g_settings.set(SETTINGS.TARGETS1, json.encode({}))
  g_settings.set(SETTINGS.TARGETS2, json.encode({}))
  g_settings.set(SETTINGS.SHINY_BALL_CHOICE, shinyBallChoice)
  g_settings.set(SETTINGS.CATCH_ALL_SHINY, catchAllShiny)
  local persistedAutoItems = {}
  for _, card in ipairs(autoItems) do
    table.insert(persistedAutoItems, {
      cardId = tonumber(card.cardId) or 0,
      itemId = tonumber(card.itemId) or 0,
      buffNames = card.buffNames or {},
      enabled = card.enabled == true,
      state = card.state or (#(card.buffNames or {}) > 0 and 'active' or 'learning')
    })
  end
  g_settings.set(SETTINGS.AUTO_ITEMS, json.encode(persistedAutoItems))
  g_settings.set(SETTINGS.AUTO_ITEM_NEXT_ID, nextAutoItemCardId)
  local firstAutoItem = autoItems[1] or {}
  g_settings.set(SETTINGS.AUTO_ITEM_ID, tonumber(firstAutoItem.itemId) or 0)
  g_settings.set(SETTINGS.AUTO_ITEM_ENABLED, firstAutoItem.enabled == true)
  g_settings.set(SETTINGS.CATCH_INTERVAL_MIN, catchIntervalMinimum)
  g_settings.set(SETTINGS.CATCH_INTERVAL_MAX, catchIntervalMaximum)
  saveShinyLookTypes()

  g_settings.set(SETTINGS.BALL_ID_LEGACY, tonumber(first.ballId) or 0)
  g_settings.set(SETTINGS.CORPSE_ID_LEGACY, tonumber(first.corpseId) or 0)
  g_settings.set(SETTINGS.TARGETS_LEGACY, json.encode({}))
  g_settings.set(SETTINGS.LEGACY_TARGET_NAME, '')
  g_settings.save()
end

local function updateCatchIntervalInputColors(valid)
  local color = valid and '#dbe5ec' or '#ff7676'
  if ui.catchIntervalMinEdit then ui.catchIntervalMinEdit:setColor(color) end
  if ui.catchIntervalMaxEdit then ui.catchIntervalMaxEdit:setColor(color) end
end

local function updatePresetButtons(minimum, maximum)
  local isSafe = tonumber(minimum) == 350 and tonumber(maximum) == 700
  local isNormal = tonumber(minimum) == 200 and tonumber(maximum) == 400
  local isTurbo = tonumber(minimum) == 80 and tonumber(maximum) == 180
  if ui.presetSafeBtn then ui.presetSafeBtn:setOn(isSafe) end
  if ui.presetNormalBtn then ui.presetNormalBtn:setOn(isNormal) end
  if ui.presetTurboBtn then ui.presetTurboBtn:setOn(isTurbo) end
end

local function applyCatchIntervalInputs()
  if not ui.catchIntervalMinEdit or not ui.catchIntervalMaxEdit then return end
  local minimum, reason = CatchInterval.validate(
    ui.catchIntervalMinEdit:getText(), ui.catchIntervalMaxEdit:getText())
  if not minimum then
    updateCatchIntervalInputColors(false)
    local messageText = reason == 'minimum-greater-than-maximum' and
      'Intervalo invalido: minimo nao pode ser maior que o maximo.' or
      'Intervalo invalido: use numeros inteiros entre 50 e 2000 ms.'
    setStatus(messageText, '#ff7676')
    return false
  end
  catchIntervalMinimum = minimum
  catchIntervalMaximum = tonumber(ui.catchIntervalMaxEdit:getText())
  updateCatchIntervalInputColors(true)
  updatePresetButtons(catchIntervalMinimum, catchIntervalMaximum)
  saveSettings()
  setStatus(string.format('Intervalo das Balls: %d-%d ms (adaptado ao ping).', catchIntervalMinimum, catchIntervalMaximum), '#62d985')
  return true
end

local setEnabled

local function updateShinyBallButtons()
  if ui.shinyBall1Btn then ui.shinyBall1Btn:setOn(shinyBallChoice == 1) end
  if ui.shinyBall2Btn then ui.shinyBall2Btn:setOn(shinyBallChoice == 2) end
end

local function setShinyBallChoice(choice)
  shinyBallChoice = (choice == 2) and 2 or 1
  saveSettings()
  updateShinyBallButtons()
  local currentShinyBallId = getShinyBallId()
  local ballDesc = string.format('Ball %d (%s)', shinyBallChoice, currentShinyBallId > 0 and ('ID ' .. currentShinyBallId) or 'nao config.')
  setStatus(string.format('Shinys configurados para usar %s.', ballDesc), '#62d985')
end

local refreshCorpseEntries
local startCorpseSelection
local startBallSelection
local getInventoryItemCount

local function configuredEntriesSummary()
  local configured = 0
  for _, entry in ipairs(corpseEntries) do
    if (tonumber(entry.ballId) or 0) > 0 and (tonumber(entry.corpseId) or 0) > 0 then
      configured = configured + 1
    end
  end
  return string.format('%d/%d cards configurados', configured, #corpseEntries)
end

local function entryById(entryId)
  entryId = tonumber(entryId) or 0
  for _, entry in ipairs(corpseEntries) do
    if tonumber(entry.id) == entryId then return entry end
  end
  return nil
end

local function entryIndex(entry)
  for index, current in ipairs(corpseEntries) do
    if current == entry then return index end
  end
  return 0
end

local function renumberCorpseEntries()
  for index, entry in ipairs(corpseEntries) do
    entry.name = string.format('Pokemon %d', index)
  end
end

local function setEntryBall(entry, item)
  if not entry or not item or not item:isItem() then
    setStatus('A Ball selecionada nao e um item valido.', '#ff7777')
    return false
  end

  local id = tonumber(item:getId()) or 0
  if id <= 0 then
    setStatus('A Ball selecionada nao possui um ID valido.', '#ff7777')
    return false
  end

  entry.ballId = id
  rebuildCorpseBallIndex()
  saveSettings()
  refreshCorpseEntries()
  setStatus(string.format('%s configurado com a Ball ID %d.', entry.name, id), '#62d985')
  if enabled then setEnabled(false, 'Ball alterada; ative novamente para confirmar.') end
  return true
end

local function setEntryCorpse(entry, item)
  if not entry or not item or not item:isItem() then return false end
  local id = tonumber(item:getId()) or 0
  if id <= 0 then return false end

  for _, other in ipairs(corpseEntries) do
    if other ~= entry and tonumber(other.corpseId) == id then
      setStatus(string.format('O corpo ID %d ja esta no %s.', id, other.name), '#ffcc66')
      return false
    end
  end

  entry.corpseId = id
  rebuildCorpseBallIndex()
  saveSettings()
  refreshCorpseEntries()
  setStatus(string.format('Corpo do %s configurado: ID %d.', entry.name, id), '#62d985')
  if enabled then setEnabled(false, 'Corpo alterado; ative novamente para confirmar.') end
  return true
end

local function clearEntry(entry)
  if not entry then return end
  entry.ballId = 0
  entry.corpseId = 0
  rebuildCorpseBallIndex()
  saveSettings()
  refreshCorpseEntries()
  setStatus(string.format('%s limpo. O card foi mantido para configurar novamente.', entry.name), '#b8b8b8')
  if enabled then setEnabled(false, 'Um card foi limpo; Auto Catch desativado.') end
end

local function deleteEntry(entry)
  local index = entryIndex(entry)
  if index <= 0 then return false end

  local entryName = entry.name
  if enabled then
    setEnabled(false, 'Um card foi excluido; Auto Catch desativado.')
  end

  table.remove(corpseEntries, index)
  renumberCorpseEntries()
  rebuildCorpseBallIndex()
  saveSettings()
  refreshCorpseEntries()
  setStatus(string.format('%s excluido.', entryName), '#b8b8b8')
  return true
end

local function setSlotItem(slot, itemId)
  if not slot then return end
  slot:setItem(nil)
  slot:setItemId(0)
  if itemId and itemId > 0 then
    local visual = Item.create(itemId, 1)
    if visual then slot:setItem(visual) else slot:setItemId(itemId) end
  end
  slot:setItemVisible(true)
  slot:setShowCount(false)
end

local function refreshCorpseEntryRow(row, entry, index)
  local ballSlot = row:recursiveGetChildById('ballSlot')
  local ballInfo = row:recursiveGetChildById('ballInfo')
  local corpseInfo = row:recursiveGetChildById('corpseInfo')
  local nameLabel = row:recursiveGetChildById('pokemonLabel')
  local entryIndexLabel = row:recursiveGetChildById('entryIndex')

  if nameLabel then nameLabel:setText(entry.name) end
  if entryIndexLabel then entryIndexLabel:setText(string.format('#%d', index)) end
  setSlotItem(ballSlot, tonumber(entry.ballId) or 0)

  local ballId = tonumber(entry.ballId) or 0
  local corpseId = tonumber(entry.corpseId) or 0
  local count = getInventoryItemCount(ballId)
  local countText = count > 0 and string.format('  Qtd: %d', count) or ''
  if ballInfo then
    ballInfo:setText(ballId > 0 and string.format('Ball ID: %d%s', ballId, countText) or 'Ball nao selecionada')
    ballInfo:setColor(ballId > 0 and '#dce9f2' or '#9aaab5')
  end
  if corpseInfo then
    corpseInfo:setText(corpseId > 0 and string.format('Corpo ID: %d', corpseId) or 'Corpo nao selecionado')
    corpseInfo:setColor(corpseId > 0 and '#62d985' or '#9aaab5')
  end

  local selectBall = row:recursiveGetChildById('selectBall')
  if selectBall then
    selectBall.onClick = function() startBallSelection(entry.id) end
    selectBall.onMouseRelease = function(_, _, button)
      if button == MouseLeftButton then startBallSelection(entry.id); return true end
    end
  end
  local selectCorpse = row:recursiveGetChildById('selectCorpse')
  if selectCorpse then
    selectCorpse.onClick = function() startCorpseSelection(entry.id) end
    selectCorpse.onMouseRelease = function(_, _, button)
      if button == MouseLeftButton then startCorpseSelection(entry.id); return true end
    end
  end
  local deleteButton = row:recursiveGetChildById('deleteEntry')
  if deleteButton then
    deleteButton.onClick = function() deleteEntry(entry) end
    deleteButton.onMouseRelease = function(_, _, button)
      if button == MouseLeftButton then deleteEntry(entry); return true end
    end
  end
  if ballSlot then
    ballSlot.onDrop = function(_, draggedWidget)
      local item = draggedWidget and draggedWidget.currentDragThing or nil
      if not item and draggedWidget and draggedWidget.getItem then item = draggedWidget:getItem() end
      local accepted = setEntryBall(entry, item)
      if draggedWidget then draggedWidget.currentDragThing = nil end
      return accepted
    end
  end
end

refreshCorpseEntries = function()
  local root = ui.panel or ui.window
  if root and not ui.entriesList then ui.entriesList = root:recursiveGetChildById('entriesList') end
  if not ui.entriesList then return end

  ui.entriesList:destroyChildren()
  for index, entry in ipairs(corpseEntries) do
    local row = g_ui.createWidget('AutoCatchEntryRow', ui.entriesList)
    refreshCorpseEntryRow(row, entry, index)
  end

  if ui.entriesEmpty then ui.entriesEmpty:setVisible(#corpseEntries == 0) end
  if ui.entriesCountHint then
    ui.entriesCountHint:setText(string.format('%s. A captura usa somente o ID do corpo.', configuredEntriesSummary()))
  end
end

local function addNewPokemon()
  nextCorpseEntryId = nextCorpseEntryId + 1
  local entry = {
    id = nextCorpseEntryId,
    name = string.format('Pokemon %d', #corpseEntries + 1),
    ballId = 0,
    corpseId = 0
  }
  table.insert(corpseEntries, entry)
  saveSettings()
  refreshCorpseEntries()
  setStatus(string.format('%s adicionado. Selecione a Ball e o corpo.', entry.name), '#62d985')
  return entry
end

local function switchTab(tabIndex)
  debugLog('switchTab: captura por cards (pedido=' .. tostring(tabIndex) .. ')')
  refreshCorpseEntries()
end

local function clearBall(legacySlot)
  local entry = corpseEntries[tonumber(legacySlot) or 0]
  if entry then clearEntry(entry) end
end

local floorScanEvent = nil
local floorScanHasPendingCorpses = false
local floorScanHasResult = false

local function cancelFloorScan()
  if floorScanEvent then
    floorScanEvent:cancel()
    floorScanEvent = nil
  end
end

local function cancelCatchVerifications()
  for jobId, verification in pairs(catchVerificationEvents) do
    if verification and verification.event then verification.event:cancel() end
    catchVerificationEvents[jobId] = nil
  end
end

local scheduleFloorScan
local scanFloorForCorpses

local function cancelRetries()
  for token, event in pairs(retryEvents) do
    if event then event:cancel() end
    retryEvents[token] = nil
  end
  if catchQueueEvent then
    catchQueueEvent:cancel()
    catchQueueEvent = nil
  end
  cancelFloorScan()
  cancelCatchVerifications()
  dyingTargets = {}
  observedTargets = {}
  corpseClaims:clear()
  floorScanHasPendingCorpses = false
  floorScanHasResult = false
  catchQueue = {}
  queuedTargets = {}
  activeCatchJob = nil
end

setEnabled = function(value, reason)
  value = value == true
  if value then
    if not hasConfiguredCorpseTarget() then
      value = false
      reason = 'Configure uma Ball e selecione o corpo correspondente antes de ativar.'
    elseif not g_game.isOnline() then
      value = false
      reason = 'Entre no jogo antes de ativar.'
    end
  end

  enabled = value
  updatingInterface = true
  if ui.enabledCheckBox then ui.enabledCheckBox:setChecked(enabled) end
  if ui.statusIndicator then
    ui.statusIndicator:setImageColor(enabled and '#42d392' or '#a85863')
  end
  if ui.statusTitle then
    ui.statusTitle:setText(enabled and 'AUTO CATCH ATIVADO' or 'AUTO CATCH DESATIVADO')
    ui.statusTitle:setColor(enabled and '#62d985' or '#dbe5ec')
  end
  updatingInterface = false

  if not enabled then
    cancelRetries()
    setStatus(reason or 'Auto Catch desativado.', '#b8b8b8')
  else
    floorScanHasPendingCorpses = true
    floorScanHasResult = false
    setStatus(string.format('Ativo por corpos: %s, alcance %d SQM.',
      configuredEntriesSummary(), MAX_CATCH_DISTANCE), '#62d985')
    if type(scheduleFloorScan) == 'function' then scheduleFloorScan() end
  end
end

local function setCatchAllShiny(value)
  catchAllShiny = value == true
  saveSettings()

  if not catchAllShiny and not hasConfiguredCorpseTarget() and enabled then
    setEnabled(false, 'Captura de Shiny desativada e as listas estao vazias.')
    return
  end

  if enabled then
    setEnabled(true)
  elseif catchAllShiny then
    local currentShinyBall = getShinyBallId()
    local ballDesc = string.format('Ball %d (%s)', shinyBallChoice, currentShinyBall > 0 and ('ID ' .. currentShinyBall) or 'nao config.')
    setStatus(string.format('Todos os Shinys serao capturados usando %s ao ativar.', ballDesc), '#62d985')
  else
    setStatus('Captura automatica de todos os Shiny desativada.', '#b8b8b8')
  end
end

getInventoryItemCount = function(itemId)
  if not itemId or itemId <= 0 then return 0 end
  if not g_game or not g_game.isOnline or not g_game.isOnline() then return 0 end
  local player = g_game.getLocalPlayer and g_game.getLocalPlayer()
  if not player then return 0 end
  local ok, count = pcall(function() return player:getItemCount(itemId) end)
  if ok and type(count) == 'number' then
    return count
  end
  return 0
end

local function refreshBallDisplay()
  refreshCorpseEntries()
end

local function cancelBallRefresh()
  if ballRefreshEvent then
    ballRefreshEvent:cancel()
    ballRefreshEvent = nil
  end
end

local function scheduleBallRefresh()
  cancelBallRefresh()
  ballRefreshEvent = scheduleEvent(function()
    ballRefreshEvent = nil
    refreshBallDisplay()
  end, 750)
end

local function useCurrentTarget()
  setStatus('Este modo usa somente o corpo selecionado no mapa; nomes de Pokemon sao ignorados.', '#ffcc66')
end

local function finishCorpseSelection(grabber)
  if not grabber then return end
  g_mouse.popCursor('target')
  grabber:ungrabMouse()
  if grabber == corpseSelectGrabber then corpseSelectGrabber = nil end
  grabber:destroy()
end

local function cancelCorpseSelection()
  if corpseSelectGrabber then
    finishCorpseSelection(corpseSelectGrabber)
  end
end

local function onSelectCorpseRelease(grabber, mousePosition, mouseButton)
  local selectedItem = nil
  if mouseButton == MouseLeftButton or mouseButton == MouseRightButton then
    local rootPanel = modules.game_interface.getRootPanel()
    local clickedWidget = rootPanel and rootPanel:recursiveGetChildByPos(mousePosition, false) or nil
    if clickedWidget and clickedWidget:getClassName() == 'UIGameMap' then
      local tile = clickedWidget:getTile(mousePosition)
      local thing = tile and tile:getTopUseThing() or nil
      if thing and thing:isItem() and not thing:isGround() then
        selectedItem = thing
      end
    end
  end

  local entry = entryById(selectingCorpseEntryId)
  if selectedItem then setEntryCorpse(entry, selectedItem) end

  finishCorpseSelection(grabber)
  if ui.window then
    ui.window:show()
    ui.window:raise()
    ui.window:focus()
  end

  if not selectedItem then
    setStatus('Nenhum corpo valido selecionado. Clique diretamente no corpo no mapa.', '#ffcc66')
  end
  selectingCorpseEntryId = nil
  return true
end

startCorpseSelection = function(entryId)
  if g_ui.isMouseGrabbed() then
    setStatus('Finalize a acao atual do mouse antes de selecionar o corpo.', '#ffcc66')
    return
  end

  if not entryById(entryId) then return end
  selectingCorpseEntryId = entryId

  if enabled then
    setEnabled(false, 'Auto Catch pausado para selecionar o corpo.')
  end
  if ui.window then ui.window:hide() end

  corpseSelectGrabber = g_ui.createWidget('UIWidget')
  corpseSelectGrabber:setVisible(false)
  corpseSelectGrabber:setFocusable(false)
  corpseSelectGrabber.onMouseRelease = onSelectCorpseRelease
  corpseSelectGrabber:grabMouse()
  g_mouse.pushCursor('target')
end

local function itemFromSelectionClick(mousePosition)
  local rootPanel = modules.game_interface.getRootPanel()
  local clickedWidget = rootPanel and rootPanel:recursiveGetChildByPos(mousePosition, false) or nil
  local current = clickedWidget
  while current do
    local className = current:getClassName()
    if className == 'UIGameMap' then
      local tile = current:getTile(mousePosition)
      local thing = tile and tile:getTopMoveThing() or nil
      if thing and thing:isItem() then return thing end
      return nil
    elseif className == 'UIItem' and not current:isVirtual() then
      local item = current:getItem()
      if item and item:isItem() then return item end
      return nil
    end
    current = current:getParent()
  end
  return nil
end

local function finishBallSelection(grabber)
  if not grabber then return end
  g_mouse.popCursor('target')
  grabber:ungrabMouse()
  if grabber == ballSelectGrabber then ballSelectGrabber = nil end
  grabber:destroy()
end

local function cancelBallSelection()
  if ballSelectGrabber then finishBallSelection(ballSelectGrabber) end
  selectingBallEntryId = nil
end

local function onSelectBallRelease(grabber, mousePosition, mouseButton)
  local selectedItem = nil
  if mouseButton == MouseLeftButton then selectedItem = itemFromSelectionClick(mousePosition) end
  local entry = entryById(selectingBallEntryId)
  finishBallSelection(grabber)
  if ui.window then
    ui.window:show()
    ui.window:raise()
    ui.window:focus()
  end
  if selectedItem and entry then
    setEntryBall(entry, selectedItem)
  else
    setStatus('Nenhuma Ball valida selecionada. Clique em um item da mochila.', '#ffcc66')
  end
  selectingBallEntryId = nil
  return true
end

startBallSelection = function(entryId)
  if g_ui.isMouseGrabbed() then
    setStatus('Finalize a acao atual do mouse antes de selecionar a Ball.', '#ffcc66')
    return
  end
  if not entryById(entryId) then return end
  selectingBallEntryId = entryId
  if enabled then setEnabled(false, 'Auto Catch pausado para selecionar a Ball.') end
  if ui.window then ui.window:hide() end
  ballSelectGrabber = g_ui.createWidget('UIWidget')
  ballSelectGrabber:setVisible(false)
  ballSelectGrabber:setFocusable(false)
  ballSelectGrabber.onMouseRelease = onSelectBallRelease
  ballSelectGrabber:grabMouse()
  g_mouse.pushCursor('target')
end

local updateAutoItemLoop = nil
local refreshAutoItemEntries
local setAutoItemEnabled
local startAutoItemSelection
local deleteAutoItem

local AUTO_ITEM_RETRY_MS = 15000

local function getLegacyActionBarItemId(slotIndex)
  if not slotIndex or slotIndex <= 0 then return nil end
  if modules.game_playeractionbar and modules.game_playeractionbar.getSlotInfo then
    local info = modules.game_playeractionbar.getSlotInfo(slotIndex)
    if info and info.itemId then return AutoItem.normalizeId(info.itemId) end
  end
  local rootPanel = modules.game_interface and modules.game_interface.getRootPanel()
  local slot = rootPanel and rootPanel:recursiveGetChildById('ACTION_BAR_' .. slotIndex)
  if slot and slot.item and slot.item.getItemId then
    return AutoItem.normalizeId(slot.item:getItemId())
  end
  return 0
end

local function autoItemNow()
  return g_clock.millis()
end

local function autoItemByCardId(cardId)
  cardId = tonumber(cardId) or 0
  for _, card in ipairs(autoItems) do
    if tonumber(card.cardId) == cardId then return card end
  end
  return nil
end

local function normalizeAutoItemBuffNames(rawNames)
  local names, seen = {}, {}
  if type(rawNames) ~= 'table' then return names end

  for key, value in pairs(rawNames) do
    local name = nil
    if type(value) == 'string' then name = value
    elseif value == true and type(key) == 'string' then name = key end
    if name and name ~= '' and not seen[name] then
      seen[name] = true
      table.insert(names, name)
    end
  end
  table.sort(names)
  return names
end

local function normalizeAutoItemEntry(rawEntry, fallbackCardId)
  if type(rawEntry) ~= 'table' then return nil end
  local cardId = tonumber(rawEntry.cardId) or tonumber(fallbackCardId) or 0
  if cardId <= 0 then return nil end

  local buffNames = normalizeAutoItemBuffNames(rawEntry.buffNames or rawEntry.buffs)
  if #buffNames == 0 and type(rawEntry.buffName) == 'string' and rawEntry.buffName ~= '' then
    buffNames = { rawEntry.buffName }
  end

  return {
    cardId = cardId,
    itemId = AutoItem.normalizeId(rawEntry.itemId),
    buffNames = buffNames,
    enabled = rawEntry.enabled == true,
    state = #buffNames > 0 and 'active' or 'learning',
    pending = false,
    retryAt = 0,
    learningBefore = nil,
    learningBeforeItemCount = nil,
    learningStartedAt = 0
  }
end

local function loadAutoItems()
  autoItems = {}
  nextAutoItemCardId = g_settings.getNumber(SETTINGS.AUTO_ITEM_NEXT_ID, 0)
  local migrated = false

  local raw = g_settings.getString(SETTINGS.AUTO_ITEMS, '')
  if raw ~= '' then
    local ok, decoded = pcall(function() return json.decode(raw) end)
    if ok and type(decoded) == 'table' then
      for index, rawEntry in ipairs(decoded) do
        local card = normalizeAutoItemEntry(rawEntry, index)
        if card then
          table.insert(autoItems, card)
          nextAutoItemCardId = math.max(nextAutoItemCardId, card.cardId)
        end
      end
    end
  end

  if #autoItems == 0 then
    local legacyItemId = AutoItem.normalizeId(g_settings.getNumber(SETTINGS.AUTO_ITEM_ID, 0))
    if legacyItemId <= 0 then
      local legacySlot = g_settings.getNumber(SETTINGS.AUTO_ACTION_SLOT, 0)
      legacyItemId = AutoItem.normalizeId(getLegacyActionBarItemId(legacySlot))
    end

    if legacyItemId > 0 then
      nextAutoItemCardId = math.max(nextAutoItemCardId, 1)
      table.insert(autoItems, {
        cardId = 1,
        itemId = legacyItemId,
        buffNames = {},
        enabled = g_settings.getBoolean(SETTINGS.AUTO_ITEM_ENABLED, false),
        state = 'learning',
        pending = false,
        retryAt = 0,
        learningBefore = nil,
        learningBeforeItemCount = nil,
        learningStartedAt = 0
      })
      migrated = true
    end
  end

  if migrated then saveSettings() end
end

local function getCurrentAutoItemBuffSnapshot()
  if modules.game_buffs and type(modules.game_buffs.getBuffSnapshot) == 'function' then
    local ok, snapshot = pcall(modules.game_buffs.getBuffSnapshot)
    if ok and snapshot ~= nil then return snapshot, true end
  end
  return autoItemBuffSnapshot, autoItemBuffSnapshot ~= nil
end

local function getAutoItemBuffRemainingMs(buffName)
  local snapshot, ready = getCurrentAutoItemBuffSnapshot()
  if not ready then return nil, false end

  if modules.game_buffs and type(modules.game_buffs.getBuffRemainingMs) == 'function' then
    local ok, remaining = pcall(modules.game_buffs.getBuffRemainingMs, buffName)
    if ok and type(remaining) == 'number' then
      return math.max(0, remaining), true
    end
  end

  return AutoItem.snapshotRemainingMs(snapshot[buffName], autoItemNow()), true
end

local function getAutoItemCardRemainingMs(card)
  local maximum = 0
  for _, buffName in ipairs(card.buffNames or {}) do
    local remaining, ready = getAutoItemBuffRemainingMs(buffName)
    if not ready then return nil, false end
    maximum = math.max(maximum, remaining or 0)
  end
  return maximum, true
end

local function formatAutoItemBuffNames(card)
  if not card.buffNames or #card.buffNames == 0 then return 'Buff: descobrindo...' end
  return 'Buff: ' .. table.concat(card.buffNames, ', ')
end

local function autoItemStatusText(card)
  if card.itemId <= 0 then return 'Item nao selecionado' end
  if #card.buffNames == 0 then
    if card.pending then return 'Usando item e aguardando o icone...' end
    return 'Buff ainda nao identificado'
  end

  local remaining, ready = getAutoItemCardRemainingMs(card)
  if not ready then return 'Aguardando estado de buffs do servidor...' end
  if remaining > 0 then return 'Restante: ' .. timeFormat(remaining / 1000) end
  if card.pending then return 'Aguardando renovacao...' end
  return 'Buff encerrado; renovando...'
end

local function updateAutoItemRowVisual(row, card, index)
  if not row or not card then return end
  local itemLabel = row:recursiveGetChildById('autoItemLabel')
  local itemIndex = row:recursiveGetChildById('autoItemIndex')
  local itemSlot = row:recursiveGetChildById('itemSlot')
  local itemInfo = row:recursiveGetChildById('itemInfo')
  local buffInfo = row:recursiveGetChildById('buffInfo')
  local timerInfo = row:recursiveGetChildById('timerInfo')
  local enabled = row:recursiveGetChildById('itemEnabled')

  if itemLabel then itemLabel:setText(string.format('Item %d', card.cardId)) end
  if itemIndex then itemIndex:setText(string.format('#%d', index)) end
  if itemSlot then setSlotItem(itemSlot, card.itemId) end

  if itemInfo then
    itemInfo:setText(card.itemId > 0 and string.format('Item ID %d', card.itemId) or 'Item nao selecionado')
    itemInfo:setColor(card.itemId > 0 and '#fde68a' or '#a39882')
  end
  if buffInfo then
    buffInfo:setText(formatAutoItemBuffNames(card))
    buffInfo:setColor(#card.buffNames > 0 and '#b8d8eb' or '#a39882')
  end
  if timerInfo then
    timerInfo:setText(card.enabled and autoItemStatusText(card) or 'Desativado')
    timerInfo:setColor(card.enabled and '#38bdf8' or '#778899')
  end
  if enabled then
    updatingAutoItemInterface = true
    enabled:setChecked(card.enabled == true)
    updatingAutoItemInterface = false
  end
end

local function stopAutoItemTimer()
  if autoItemTimerEvent then
    removeEvent(autoItemTimerEvent)
    autoItemTimerEvent = nil
  end
end

local function hasEnabledAutoItems()
  for _, card in ipairs(autoItems) do
    if card.enabled and card.itemId > 0 then return true end
  end
  return false
end

local function startAutoItemTimer()
  stopAutoItemTimer()
  if updateAutoItemLoop and hasEnabledAutoItems() then
    autoItemTimerEvent = cycleEvent(updateAutoItemLoop, 1000)
  end
end

local function isItemThing(value)
  if not value then return false end
  local ok, result = pcall(function() return value:isItem() end)
  return ok and result == true
end

local function scheduleAutoItemRetry(card, message)
  local now = autoItemNow()
  card.pending = false
  card.retryAt = now + AUTO_ITEM_RETRY_MS
  card.learningBefore = nil
  card.learningBeforeItemCount = nil
  card.learningStartedAt = 0
  card.state = #card.buffNames > 0 and 'waiting' or 'learning'
  if message then
    print(message)
    setStatus(message, '#ffcc66')
  end
end

local function dispatchAutoItem(card)
  if getInventoryItemCount(card.itemId) <= 0 then
    scheduleAutoItemRetry(card, string.format('[Auto Item] Item ID %d nao encontrado na mochila. Tentando em 15s.', card.itemId))
    return false
  end

  local now = autoItemNow()
  if #card.buffNames == 0 then
    local before, ready = getCurrentAutoItemBuffSnapshot()
    if not ready then
      card.retryAt = now + 1000
      card.state = 'waiting-buffs'
      return false
    end
    autoItemLearningCardId = card.cardId
    card.learningBefore = before
    card.learningBeforeItemCount = getInventoryItemCount(card.itemId)
    card.learningStartedAt = now
  end

  local okExec, errorMessage = AutoItem.dispatch(card.itemId)
  if not okExec then
    if autoItemLearningCardId == card.cardId then autoItemLearningCardId = nil end
    scheduleAutoItemRetry(card, string.format('[Auto Item] Falha ao usar item ID %d (%s). Tentando em 15s.',
      card.itemId, tostring(errorMessage or 'erro desconhecido')))
    return false
  end

  card.pending = true
  card.retryAt = now + AUTO_ITEM_RETRY_MS
  card.state = #card.buffNames > 0 and 'waiting' or 'learning'
  local message = #card.buffNames > 0 and
    string.format('[Auto Item] Card %d (item ID %d) enviado; aguardando o buff terminar/atualizar.', card.cardId, card.itemId) or
    string.format('[Auto Item] Card %d (item ID %d) usado; aprendendo o buff correspondente.', card.cardId, card.itemId)
  print(message)
  setStatus(message, '#62d985')
  return true
end

local function updateAutoItemRowHandlers(row, card)
  local selectButton = row:recursiveGetChildById('selectItem')
  local deleteButton = row:recursiveGetChildById('deleteItem')
  local enabled = row:recursiveGetChildById('itemEnabled')
  local itemSlot = row:recursiveGetChildById('itemSlot')

  if selectButton then
    selectButton.onClick = function() startAutoItemSelection(card.cardId) end
    selectButton.onMouseRelease = function(_, _, button)
      if button == MouseLeftButton then startAutoItemSelection(card.cardId); return true end
    end
  end
  if deleteButton then
    deleteButton.onClick = function() deleteAutoItem(card) end
    deleteButton.onMouseRelease = function(_, _, button)
      if button == MouseLeftButton then deleteAutoItem(card); return true end
    end
  end
  if enabled then
    enabled.onCheckChange = function(_, checked)
      if not updatingAutoItemInterface then setAutoItemEnabled(card, checked) end
    end
  end
  if itemSlot then
    itemSlot.onDrop = function(_, draggedWidget) return onDropAutoItem(card, draggedWidget) end
  end
end

refreshAutoItemEntries = function()
  local root = ui.panel or ui.window
  if root and not ui.autoItemsList then ui.autoItemsList = root:recursiveGetChildById('autoItemsList') end
  if not ui.autoItemsList then return end

  ui.autoItemsList:destroyChildren()
  for index, card in ipairs(autoItems) do
    local row = g_ui.createWidget('AutoCatchAutoItemRow', ui.autoItemsList)
    updateAutoItemRowVisual(row, card, index)
    updateAutoItemRowHandlers(row, card)
  end
  if ui.autoItemsEmpty then ui.autoItemsEmpty:setVisible(#autoItems == 0) end
  if ui.autoItemsCountHint then
    ui.autoItemsCountHint:setText(string.format('%d item(ns). Cada card renova pelo tempo real do buff.', #autoItems))
  end
end

local function refreshAutoItemRows()
  if not ui.autoItemsList then return end
  local children = ui.autoItemsList:getChildren()
  for index, row in ipairs(children) do
    updateAutoItemRowVisual(row, autoItems[index], index)
  end
end

local function assignAutoItem(card, itemOrId)
  local itemId = AutoItem.normalizeId(itemOrId)
  if not card or itemId <= 0 then
    setStatus('Item invalido. Arraste um item real da mochila.', '#ff7777')
    return false
  end

  if autoItemLearningCardId == card.cardId then autoItemLearningCardId = nil end
  card.itemId = itemId
  card.buffNames = {}
  card.state = 'learning'
  card.pending = false
  card.retryAt = 0
  card.learningBefore = nil
  card.learningBeforeItemCount = nil
  card.learningStartedAt = 0
  saveSettings()
  refreshAutoItemEntries()
  setStatus(string.format('%s configurado para o item ID %d. O buff sera aprendido ao ativar.',
    string.format('Item %d', card.cardId), itemId), '#62d985')
  if card.enabled then startAutoItemTimer() end
  return true
end

local function onDropAutoItem(card, draggedWidget)
  if not draggedWidget or not draggedWidget.getClassName or draggedWidget:getClassName() ~= 'UIItem' then
    setStatus('Arraste um item diretamente da mochila.', '#ffcc66')
    return false
  end
  if draggedWidget.isVirtual and draggedWidget:isVirtual() then
    setStatus('O item precisa vir de uma mochila aberta.', '#ffcc66')
    return false
  end

  local selectedItem = draggedWidget.currentDragThing
  if not selectedItem and draggedWidget.getItem then selectedItem = draggedWidget:getItem() end
  if not isItemThing(selectedItem) then
    setStatus('Nenhum item valido foi arrastado da mochila.', '#ffcc66')
    return false
  end
  return assignAutoItem(card, selectedItem)
end

local function itemFromInventoryClick(mousePosition)
  local rootPanel = modules.game_interface.getRootPanel()
  local clickedWidget = rootPanel and rootPanel:recursiveGetChildByPos(mousePosition, false) or nil
  local current = clickedWidget
  while current do
    if current:getClassName() == 'UIItem' and not current:isVirtual() then
      local item = current:getItem()
      return isItemThing(item) and item or nil
    end
    current = current:getParent()
  end
  return nil
end

local function finishAutoItemSelection(grabber)
  if not grabber then return end
  g_mouse.popCursor('target')
  grabber:ungrabMouse()
  if grabber == autoItemSelectionGrabber then autoItemSelectionGrabber = nil end
  grabber:destroy()
end

local function cancelAutoItemSelection()
  if autoItemSelectionGrabber then finishAutoItemSelection(autoItemSelectionGrabber) end
end

local function onSelectAutoItemRelease(grabber, mousePosition, mouseButton)
  local selectedItem = mouseButton == MouseLeftButton and itemFromInventoryClick(mousePosition) or nil
  local card = autoItemByCardId(grabber.cardId)
  finishAutoItemSelection(grabber)
  if ui.window then ui.window:show(); ui.window:raise(); ui.window:focus() end

  if card and selectedItem then
    assignAutoItem(card, selectedItem)
  else
    setStatus('Nenhum item valido selecionado. Clique em um item da mochila.', '#ffcc66')
  end
  return true
end

startAutoItemSelection = function(cardId)
  if g_ui.isMouseGrabbed() then
    setStatus('Finalize a acao atual do mouse antes de selecionar o item.', '#ffcc66')
    return
  end
  local card = autoItemByCardId(cardId) or autoItems[1]
  if not card then
    setStatus('Adicione um card de item antes de selecionar.', '#ffcc66')
    return
  end

  if ui.window then ui.window:hide() end
  autoItemSelectionGrabber = g_ui.createWidget('UIWidget')
  autoItemSelectionGrabber.cardId = card.cardId
  autoItemSelectionGrabber:setVisible(false)
  autoItemSelectionGrabber:setFocusable(false)
  autoItemSelectionGrabber.onMouseRelease = onSelectAutoItemRelease
  autoItemSelectionGrabber:grabMouse()
  g_mouse.pushCursor('target')
end

deleteAutoItem = function(card)
  if not card then return false end
  for index, current in ipairs(autoItems) do
    if current == card then
      if autoItemLearningCardId == card.cardId then autoItemLearningCardId = nil end
      table.remove(autoItems, index)
      saveSettings()
      refreshAutoItemEntries()
      if not hasEnabledAutoItems() then stopAutoItemTimer() else startAutoItemTimer() end
      setStatus(string.format('Item %d excluido.', card.cardId), '#b8b8b8')
      return true
    end
  end
  return false
end

local function clearAutoItem(cardId)
  local card = autoItemByCardId(cardId) or autoItems[1]
  if not card then return false end
  card.itemId = 0
  card.buffNames = {}
  card.enabled = false
  card.pending = false
  card.retryAt = 0
  card.learningBefore = nil
  card.learningBeforeItemCount = nil
  card.learningStartedAt = 0
  card.state = 'learning'
  if autoItemLearningCardId == card.cardId then autoItemLearningCardId = nil end
  saveSettings()
  refreshAutoItemEntries()
  if not hasEnabledAutoItems() then stopAutoItemTimer() end
  setStatus(string.format('Item %d desconfigurado.', card.cardId), '#b8b8b8')
  return true
end

setAutoItemEnabled = function(card, value)
  value = value == true
  if not card then return end
  if value and card.itemId <= 0 then
    card.enabled = false
    setStatus('Configure um item da mochila antes de ativar o card.', '#ffcc66')
    refreshAutoItemEntries()
    return
  end
  if value and not g_game.isOnline() then
    card.enabled = false
    setStatus('Entre no jogo antes de ativar o Auto Item.', '#ffcc66')
    refreshAutoItemEntries()
    return
  end

  card.enabled = value
  card.pending = false
  card.retryAt = 0
  card.learningBefore = nil
  card.learningBeforeItemCount = nil
  card.learningStartedAt = 0
  if not value and autoItemLearningCardId == card.cardId then autoItemLearningCardId = nil end
  card.state = #card.buffNames > 0 and 'active' or 'learning'
  saveSettings()
  refreshAutoItemEntries()
  if value then
    startAutoItemTimer()
    setStatus(string.format('Item %d ativado; renovara somente quando o buff terminar.', card.cardId), '#62d985')
  else
    if not hasEnabledAutoItems() then stopAutoItemTimer() end
    setStatus(string.format('Item %d desativado.', card.cardId), '#b8b8b8')
  end
end

local function addNewAutoItem()
  nextAutoItemCardId = nextAutoItemCardId + 1
  table.insert(autoItems, {
    cardId = nextAutoItemCardId,
    itemId = 0,
    buffNames = {},
    enabled = false,
    state = 'learning',
    pending = false,
    retryAt = 0,
    learningBefore = nil,
    learningBeforeItemCount = nil,
    learningStartedAt = 0
  })
  saveSettings()
  refreshAutoItemEntries()
  setStatus(string.format('Item %d adicionado. Selecione o item da mochila.', nextAutoItemCardId), '#62d985')
end

local function onAutoItemBuffsReceived(buffs)
  autoItemBuffSnapshot = AutoItem.makeBuffSnapshot(buffs, autoItemNow())

  local learningCard = autoItemByCardId(autoItemLearningCardId)
  if learningCard and learningCard.pending and learningCard.learningBefore then
    local changed = AutoItem.changedBuffNames(learningCard.learningBefore, autoItemBuffSnapshot, autoItemNow())
    local currentItemCount = getInventoryItemCount(learningCard.itemId)
    local consumed = AutoItem.wasItemConsumed(learningCard.learningBeforeItemCount, currentItemCount)
    if #changed > 0 and consumed then
      learningCard.buffNames = changed
      learningCard.pending = false
      learningCard.retryAt = 0
      learningCard.state = 'active'
      learningCard.learningBefore = nil
      learningCard.learningBeforeItemCount = nil
      learningCard.learningStartedAt = 0
      autoItemLearningCardId = nil
      saveSettings()
      local linkedMessage = string.format('Item %d vinculado ao buff: %s.', learningCard.cardId, table.concat(changed, ', '))
      print('[Auto Item] ' .. linkedMessage)
      setStatus(linkedMessage, '#62d985')
    elseif #changed > 0 then
      print(string.format('[Auto Item] Mudanca de buff ignorada para o card %d: o item ID %d nao foi consumido neste envio.',
        learningCard.cardId, learningCard.itemId))
    end
  end
  refreshAutoItemRows()
end

local function resetAutoItemRuntimeState()
  autoItemBuffSnapshot = nil
  autoItemLearningCardId = nil
  for _, card in ipairs(autoItems) do
    card.pending = false
    card.retryAt = 0
    card.learningBefore = nil
    card.learningBeforeItemCount = nil
    card.learningStartedAt = 0
  end
end

updateAutoItemLoop = function()
  if not g_game.isOnline() then
    refreshAutoItemRows()
    return
  end

  local now = autoItemNow()
  for _, card in ipairs(autoItems) do
    if card.enabled and card.itemId > 0 then
      local remaining, ready = getAutoItemCardRemainingMs(card)
      if not ready then
      elseif card.pending then
        if #card.buffNames > 0 and remaining > 0 then
          card.pending = false
          card.retryAt = 0
          card.state = 'active'
        elseif now >= (card.retryAt or 0) then
          card.pending = false
          if autoItemLearningCardId == card.cardId then autoItemLearningCardId = nil end
          if not autoItemLearningCardId then dispatchAutoItem(card) end
        end
      elseif autoItemLearningCardId and autoItemLearningCardId ~= card.cardId then
      elseif #card.buffNames == 0 then
        if now >= (card.retryAt or 0) then dispatchAutoItem(card) end
      elseif remaining <= 0 and now >= (card.retryAt or 0) then
        dispatchAutoItem(card)
      else
        card.state = 'active'
      end
    end
  end
  refreshAutoItemRows()
end

local function safeItemText(item, methodName)
  local method = item and item[methodName]
  if not method then return '' end
  local ok, value = pcall(function() return method(item) end)
  if not ok or not value then return '' end
  return tostring(value)
end

local function safeItemId(item)
  if not item then return nil end
  local ok, itemId = pcall(function() return item:getId() end)
  return ok and itemId or nil
end

local function snapshotTileItems(position)
  local snapshot = {}
  local tile = g_map.getTile(position)
  local items = tile and tile:getItems() or nil
  if items then
    for _, item in ipairs(items) do snapshot[item] = true end
  end
  return snapshot
end

local function samePosition(left, right)
  return left and right and
         left.x == right.x and left.y == right.y and left.z == right.z
end

local function observationForCreature(token)
  if not token then return nil end
  return observedTargets[token]
end

local function isWildMonster(creature)
  if not creature then return false end
  local okType, cType = pcall(function() return creature:getType() end)
  if okType and cType then
    if cType == 3 or cType == 4 or cType == (CreatureTypeSummonOwn or 3) or cType == (CreatureTypeSummonOther or 4) then
      return false
    end
    if cType == 0 or cType == (CreatureTypePlayer or 0) or cType == 2 or cType == (CreatureTypeNpc or 2) then
      return false
    end
  end
  local okPlayer, isPlay = pcall(function() return creature:isPlayer() end)
  if okPlayer and isPlay then return false end
  local okNpc, isNpc = pcall(function() return creature:isNpc() end)
  if okNpc and isNpc then return false end
  local okMonster, isMon = pcall(function() return creature:isMonster() end)
  if not okMonster or not isMon then return false end
  return true
end

local function rememberTarget(creature, position)
  if not creature or not isWildMonster(creature) then return nil end

  local okId, cid = pcall(function() return creature:getId() end)
  if not okId or not cid then return nil end
  local token = tostring(cid)

  local okName, name = pcall(function() return creature:getName() end)
  name = okName and name or ''

  local isShiny = isCreatureShiny(creature)
  local isTarget, targetBallId, targetName = getTargetBallForCreature(name, creature, isShiny)
  if not isTarget then
    observedTargets[token] = nil
    return nil
  end

  if not position then
    local okPos, cPos = pcall(function() return creature:getPosition() end)
    if okPos and cPos then position = cPos end
  end
  if not position then return nil end

  local remembered = {
    creatureId = cid,
    name = name,
    position = { x = position.x, y = position.y, z = position.z },
    beforeItems = snapshotTileItems(position),
    isShiny = isShiny,
    ballId = targetBallId,
    isTarget = true,
    lastSeen = g_clock.millis()
  }
  observedTargets[token] = remembered
  return remembered
end

local function isClaimPresent(item, data)
  local tile = data and data.position and g_map.getTile(data.position) or nil
  local items = tile and tile:getItems() or nil
  if not items then return false end
  for _, candidate in ipairs(items) do
    if candidate == item then return true end
  end
  return false
end

local function cleanupClaimedCorpses()
  corpseClaims:cleanup(isClaimPresent)
end

local function claimCorpse(position, itemId, item, skipCleanup)
  if not item then return false end
  return corpseClaims:claim(item, position, itemId, {
    persistent = true,
    skipCleanup = skipCleanup == true
  })
end

local function releaseCorpseClaim(item)
  corpseClaims:release(item)
end

local function isCorpseClaimed(position, itemId, item, skipCleanup)
  if not item then return false end
  if not skipCleanup then cleanupClaimedCorpses() end
  return corpseClaims:isClaimed(item, skipCleanup == true)
end

local function topUseThing(tile)
  if not tile or type(tile.getTopUseThing) ~= 'function' then return nil end
  local ok, item = pcall(function() return tile:getTopUseThing() end)
  return ok and item or nil
end

local function catchDistance(position)
  local player = g_game.getLocalPlayer()
  local playerPosition = player and player:getPosition() or nil
  if not playerPosition or not position or playerPosition.z ~= position.z then
    return nil
  end
  return math.max(
    math.abs(playerPosition.x - position.x),
    math.abs(playerPosition.y - position.y)
  )
end

local function isWithinCatchRange(position)
  local distance = catchDistance(position)
  return distance ~= nil and distance <= MAX_CATCH_DISTANCE, distance
end

local function tileContainsItem(tile, expectedItem)
  if not tile or not expectedItem then return false end
  local items = tile:getItems()
  if not items then return false end
  for _, item in ipairs(items) do
    if item == expectedItem then return true end
  end
  return false
end

local SEARCH_OFFSETS = {
  { dx = 0, dy = 0 },
  { dx = 1, dy = 0 }, { dx = -1, dy = 0 }, { dx = 0, dy = 1 }, { dx = 0, dy = -1 },
  { dx = 1, dy = 1 }, { dx = -1, dy = 1 }, { dx = 1, dy = -1 }, { dx = -1, dy = -1 },
  { dx = 2, dy = 0 }, { dx = -2, dy = 0 }, { dx = 0, dy = 2 }, { dx = 0, dy = -2 }
}

local function findCorpseOnTile(target, pos, isOriginalTile)
  local tile = g_map.getTile(pos)
  if not tile then return nil end
  local items = tile:getItems()
  if not items or #items == 0 then return nil end

  local topItem = topUseThing(tile)
  local selectionOptions = {
    beforeItems = isOriginalTile and target.beforeItems or nil,
    preferNew = isOriginalTile,
    topItem = topItem,
    getId = safeItemId,
    isClaimed = function(item)
      return isCorpseClaimed(pos, safeItemId(item), item)
    end
  }

  for _, entry in ipairs(corpseEntries) do
    local corpseId = tonumber(entry.corpseId) or 0
    local ballId = tonumber(entry.ballId) or 0
    if corpseId > 0 and ballId > 0 then
      selectionOptions.expectedId = corpseId
      local item, index = CorpseSelection.pick(items, selectionOptions)
      if item then
        return item, string.format('%s (corpo %d)', entry.name, corpseId), index, pos, corpseId
      end
    end
  end

  return nil
end


local function findCorpse(target, attempt)
  if not target or not target.position then return nil end

  local corpse, mode, index, pos, id = findCorpseOnTile(target, target.position, true)
  if corpse then
    return corpse, mode, index, pos, id
  end

  for i = 2, #SEARCH_OFFSETS do
    local offset = SEARCH_OFFSETS[i]
    local neighborPos = { x = target.position.x + offset.dx, y = target.position.y + offset.dy, z = target.position.z }
    corpse, mode, index, pos, id = findCorpseOnTile(target, neighborPos, false)
    if corpse then
      return corpse, mode .. ' (vizinho)', index, pos, id
    end
  end

  return nil
end

local function describeTile(position)
  local tile = g_map.getTile(position)
  local items = tile and tile:getItems() or nil
  if not items then return 'tile sem itens' end
  local descriptions = {}
  for index, item in ipairs(items) do
    local okId, id = pcall(function() return item:getId() end)
    local okCorpse, isCorpse = pcall(function() return item:isLyingCorpse() end)
      local claimed = isCorpseClaimed(position, okId and id or nil, item)
    table.insert(descriptions, string.format(
      '#%d id=%s nome="%s" descricao="%s" corpse=%s claimed=%s',
      index,
      okId and tostring(id) or '?',
      safeItemText(item, 'getName'),
      safeItemText(item, 'getDescription'),
      okCorpse and tostring(isCorpse) or '?',
      tostring(claimed)
    ))
  end
  return table.concat(descriptions, ' | ')
end

local function finishAttempt(token)
  local event = retryEvents[token]
  if event then event:cancel() end
  retryEvents[token] = nil
  dyingTargets[token] = nil
  observedTargets[token] = nil
end

local processCatchQueue

local function catchQueueInterval()
  local ping = 0
  local ok, value = pcall(function() return g_game.getPing() end)
  if ok then ping = math.max(0, tonumber(value) or 0) end
  return CatchInterval.calculate(ping, catchIntervalMinimum, catchIntervalMaximum)
end

local function scheduleCatchQueue(delay)
  if catchQueueEvent or #catchQueue == 0 then return end
  catchQueueEvent = scheduleEvent(function()
    catchQueueEvent = nil
    processCatchQueue()
  end, delay or 1)
end

local function discardCatchJob(job, reason)
  queuedTargets[job.token] = nil
  releaseCorpseClaim(job.corpse)
  print(string.format('[AutoCatch] Corpo descartado nome=%s pos=%d,%d,%d motivo=%s tentativas=%d.',
    tostring(job.name), job.position.x, job.position.y, job.position.z, tostring(reason), job.sendAttempts or 0))
  return 'drop'
end

local function deferCatchJob(job, reason, apiResult, countAttempt)
  local now = g_clock.millis()
  if countAttempt ~= false then
    job.sendAttempts = (job.sendAttempts or 0) + 1
  end
  local decision = CatchDispatch.decide(now, job.retryDeadline, false, apiResult)
  if decision == 'drop' then
    return discardCatchJob(job, reason)
  end

  job.nextAttemptDelay = CatchDispatch.retryDelay(now, job.retryDeadline, catchQueueInterval())
  table.insert(catchQueue, 1, job)
  print(string.format('[AutoCatch] Tentativa de Ball adiada nome=%s pos=%d,%d,%d motivo=%s tentativa=%d.',
    tostring(job.name), job.position.x, job.position.y, job.position.z, tostring(reason), job.sendAttempts))
  return 'retry'
end

local function recordCatchCommand(job, useBallId)
  local now = g_clock.millis()
  sessionThrows = sessionThrows + 1
  if (now - (lastThrowTime or 0)) > 3000 then
    recentBurstThrows = 0
  end
  recentBurstThrows = (recentBurstThrows or 0) + 1
  lastThrowTime = now
  print(string.format('[AutoCatch] Comando Ball %d enviado ao cliente para %s pos=%d,%d,%d fila=%d sessao=%d.',
    useBallId, tostring(job.name), job.position.x, job.position.y, job.position.z, #catchQueue, sessionThrows))
end

local function scheduleCatchVerification(job)
  if not job or not job.id then return end

  local previous = catchVerificationEvents[job.id]
  if previous and previous.event then previous.event:cancel() end

  local verification = {}
  catchVerificationEvents[job.id] = verification
  verification.event = scheduleEvent(function()
    if catchVerificationEvents[job.id] ~= verification then return end
    catchVerificationEvents[job.id] = nil

    if not enabled or not g_game.isOnline() then
      queuedTargets[job.token] = nil
      releaseCorpseClaim(job.corpse)
      return
    end

    cleanupClaimedCorpses()
    local tile = g_map.getTile(job.position)
    local stillPresent = tile and tileContainsItem(tile, job.corpse)
    if not stillPresent then
      releaseCorpseClaim(job.corpse)
      print(string.format('[AutoCatch] Corpo confirmado removido apos Ball para %s pos=%d,%d,%d.',
        tostring(job.name), job.position.x, job.position.y, job.position.z))
      return
    end

    if (job.sendAttempts or 0) >= MAX_CATCH_SEND_ATTEMPTS then
      discardCatchJob(job, 'corpo permaneceu apos tentativas de Ball')
      return
    end

    queuedTargets[job.token] = true
    job.nextAttemptDelay = catchQueueInterval()
    table.insert(catchQueue, 1, job)
    print(string.format('[AutoCatch] Corpo ainda presente; nova tentativa sem bloquear a fila nome=%s pos=%d,%d,%d tentativa=%d.',
      tostring(job.name), job.position.x, job.position.y, job.position.z, (job.sendAttempts or 0) + 1))
    scheduleCatchQueue(job.nextAttemptDelay)
  end, CATCH_RESULT_CHECK_DELAY)
end

local function executeCatchJob(job)
  cleanupClaimedCorpses()
  local tile = g_map.getTile(job.position)
  if not tile then
    queuedTargets[job.token] = nil
    releaseCorpseClaim(job.corpse)
    return false
  end

  local currentCorpse = job.corpse
  corpseClaims:refresh(currentCorpse)
  local okCorpseId, currentCorpseId = pcall(function() return currentCorpse:getId() end)
  if not okCorpseId or currentCorpseId ~= job.itemId or
     not tileContainsItem(tile, currentCorpse) then
    queuedTargets[job.token] = nil
    releaseCorpseClaim(currentCorpse)
    return false
  end

  local currentTop = topUseThing(tile)
  if not currentTop or currentTop ~= currentCorpse then
    return deferCatchJob(job, 'corpo nao esta no topo utilizavel', nil, false)
  end

  local withinRange, distance = isWithinCatchRange(job.position)
  if not withinRange then
    return deferCatchJob(job, string.format('fora do alcance distancia=%s', tostring(distance)), nil, false)
  end

  local useBallId = job.ballId
  if not useBallId or useBallId <= 0 then
    local matched, _, matchedBall = resolveCorpseTarget(job.itemId)
    useBallId = matched and matchedBall or 0
  end
  if not useBallId or useBallId <= 0 then
    queuedTargets[job.token] = nil
    releaseCorpseClaim(currentCorpse)
    return false
  end

  job.sendAttempts = (job.sendAttempts or 0) + 1
  local ok, result = pcall(function()
    return g_game.useInventoryItemWith(useBallId, currentCorpse)
  end)

  local decision = CatchDispatch.decide(g_clock.millis(), job.retryDeadline, ok, result)
  if decision == 'sent' then
    queuedTargets[job.token] = nil
    recordCatchCommand(job, useBallId)
    scheduleCatchVerification(job)
    scheduleBallRefresh()
    print(string.format('[AutoCatch] Captura aceita pela API para %s.', tostring(job.name)))
    setStatus(string.format('Comando Ball %d enviado para %s. Fila: %d; sessao: %d.',
      useBallId, job.name, #catchQueue, sessionThrows), '#62d985')
    return true
  end

  local reason = ok and 'cliente recusou o comando' or tostring(result)
  return deferCatchJob(job, reason, ok and false or nil, false)
end

processCatchQueue = function()
  if not enabled or not g_game.isOnline() then
    catchQueue = {}
    queuedTargets = {}
    activeCatchJob = nil
    corpseClaims:clear()
    return
  end

  local job = table.remove(catchQueue, 1)
  if not job then
    activeCatchJob = nil
    return
  end

  activeCatchJob = job
  local result = executeCatchJob(job)
  activeCatchJob = nil

  if #catchQueue > 0 then
    local delay = (result == 'retry' and catchQueue[1].nextAttemptDelay) or catchQueueInterval()
    scheduleCatchQueue(delay)
  end
end

local function enqueueCatch(token, target, corpse, detectionMode, corpsePos, corpseIndex, targetBallId, explicitItemId, skipClaimCleanup)
  if queuedTargets[token] then
    finishAttempt(token)
    return false
  end

  local pos = corpsePos or target.position
  local okId, itemId = pcall(function() return corpse:getId() end)
  itemId = explicitItemId or (okId and itemId or nil)
  if not itemId then
    finishAttempt(token)
    return false
  end

  if isCorpseClaimed(pos, itemId, corpse, skipClaimCleanup) then
    finishAttempt(token)
    return false
  end

  local matched, matchedName, matchedBall = resolveCorpseTarget(itemId)
  local ballToUse = matchedBall
  if not ballToUse or ballToUse <= 0 then ballToUse = targetBallId or target.ballId end
  if matched and matchedName then target.name = matchedName end
  if not ballToUse or ballToUse <= 0 then
    print(string.format('[AutoCatch] Ignorado %s: nenhuma Ball configurada.', tostring(target.name)))
    finishAttempt(token)
    return false
  end

  if not claimCorpse(pos, itemId, corpse, skipClaimCleanup) then
    finishAttempt(token)
    return false
  end
  nextCatchJobId = nextCatchJobId + 1
  queuedTargets[token] = true

  table.insert(catchQueue, {
    id = nextCatchJobId,
    token = token,
    name = target.name,
    position = pos,
    corpse = corpse,
    corpseIndex = corpseIndex,
    itemId = itemId,
    ballId = ballToUse,
    isShiny = target.isShiny,
    detectionMode = detectionMode,
    sendAttempts = 0,
    retryDeadline = g_clock.millis() + CATCH_DISPATCH_RETRY_WINDOW
  })
  print(string.format('[AutoCatch] Corpo enfileirado job=%d nome=%s ballId=%d corpoId=%s pos=%d,%d,%d modo=%s fila=%d.',
    nextCatchJobId, tostring(target.name), ballToUse, tostring(itemId),
    pos.x, pos.y, pos.z, tostring(detectionMode), #catchQueue))
  finishAttempt(token)

  local now = g_clock.millis()
  local elapsed = now - lastThrowTime
  local waitTime = math.max(1, catchQueueInterval() - elapsed)
  scheduleCatchQueue(waitTime)
  return true
end

local function isCorpseMatchingTarget(item)
  if not item or not item:isItem() then return false, nil, 0 end
  local id = safeItemId(item)
  if not id then return false, nil, 0 end
  return resolveCorpseTarget(id)
end

scanFloorForCorpses = function()
  if not enabled or not g_game.isOnline() then
    floorScanHasPendingCorpses = false
    floorScanHasResult = true
    return
  end
  cleanupClaimedCorpses()
  local player = g_game.getLocalPlayer()
  if not player then
    floorScanHasPendingCorpses = false
    floorScanHasResult = true
    return
  end
  local playerPos = player:getPosition()
  if not playerPos then
    floorScanHasPendingCorpses = false
    floorScanHasResult = true
    return
  end

  local z = playerPos.z
  local foundPendingCorpse = false

  for dx = -VISIBLE_SCAN_RADIUS_X, VISIBLE_SCAN_RADIUS_X do
    for dy = -VISIBLE_SCAN_RADIUS_Y, VISIBLE_SCAN_RADIUS_Y do
      local pos = { x = playerPos.x + dx, y = playerPos.y + dy, z = z }
      local tile = g_map.getTile(pos)
      if tile and not corpseClaims:isPositionClaimed(pos, true) then
        local item = topUseThing(tile)
        local itemId = safeItemId(item)
        if item and itemId then
          local matches, matchedName, matchedBall = isCorpseMatchingTarget(item)
          if matches and matchedBall and matchedBall > 0 and not isCorpseClaimed(pos, itemId, item, true) then
            foundPendingCorpse = true
            local token = string.format('%d,%d,%d:%d', pos.x, pos.y, pos.z, itemId)
            enqueueCatch(token, {
              name = matchedName,
              position = pos,
              isShiny = false
            }, item, 'varredura de chao', pos, nil, matchedBall, itemId, true)
          end
        end
      end
    end
  end

  floorScanHasPendingCorpses = foundPendingCorpse
  floorScanHasResult = true
end

scheduleFloorScan = function()
  cancelFloorScan()
  if not enabled then return end
  floorScanEvent = scheduleEvent(function()
    floorScanEvent = nil
    scanFloorForCorpses()
    scheduleFloorScan()
  end, 120)
end

local function attemptCatch(token, attempt)
  retryEvents[token] = nil
  local target = dyingTargets[token]
  if not target or not enabled or not g_game.isOnline() then
    finishAttempt(token)
    return
  end

  local corpse, detectionMode, index, pos, id = findCorpse(target, attempt)
  if corpse then
    local withinRange, distance = isWithinCatchRange(pos)
    if not withinRange then
      print(string.format('[AutoCatch] Corpo de %s encontrado, mas fora do limite: distancia=%s, limite=%d.',
        target.name, distance and tostring(distance) or 'outro andar', MAX_CATCH_DISTANCE))
      setStatus(string.format('%s ignorado: corpo fora do limite de %d SQM.',
        target.name, MAX_CATCH_DISTANCE), '#ffcc66')
      finishAttempt(token)
      return
    end
    enqueueCatch(token, target, corpse, detectionMode, pos, index, target.ballId, id)
    return
  end

  if attempt >= CORPSE_RETRY_LIMIT then
    print(string.format('[AutoCatch] Corpo de %s nao identificado em %d,%d,%d: %s',
      target.name, target.position.x, target.position.y, target.position.z, describeTile(target.position)))
    setStatus('O Pokemon desapareceu, mas nenhum corpo valido foi encontrado. Diagnostico no log.', '#ffcc66')
    finishAttempt(token)
    return
  end

  retryEvents[token] = scheduleEvent(function()
    attemptCatch(token, attempt + 1)
  end, CORPSE_RETRY_DELAY)
end

function onCreatureHealthPercentChange(creature, healthPercent)
  if not enabled or not creature then return end
  local okMonster, isMon = pcall(function() return creature:isMonster() end)
  if not okMonster or not isMon then return end

  local okId, cid = pcall(function() return creature:getId() end)
  if not okId or not cid then return end
  local token = tostring(cid)

  local observed = observationForCreature(token)
  local isShiny = (observed and observed.isShiny) or isCreatureShiny(creature)
  local cName = (observed and observed.name) or (pcall(function() return creature:getName() end) and creature:getName() or '')
  local isTarget, targetBallId = getTargetBallForCreature(cName, creature, isShiny)
  if not isTarget then
    observedTargets[token] = nil
    return
  end

  if healthPercent > 0 then
    rememberTarget(creature)
    return
  end

  local position = nil
  local okPos, cPos = pcall(function() return creature:getPosition() end)
  if okPos and cPos then position = cPos else position = observed and observed.position end
  if not position then return end

  dyingTargets[token] = {
    creatureId = cid,
    name = cName,
    isShiny = isShiny,
    ballId = targetBallId,
    position = { x = position.x, y = position.y, z = position.z },
    beforeItems = observed and samePosition(observed.position, position) and
      observed.beforeItems or snapshotTileItems(position)
  }
end

function onCreatureAppear(creature)
  if not enabled then return end
  rememberTarget(creature)
end

function onCreaturePositionChange(creature, newPosition)
  if not enabled then return end
  rememberTarget(creature, newPosition)
end

function onCreatureDisappear(creature)
  if not enabled or not creature or not isWildMonster(creature) then return end

  local okId, cid = pcall(function() return creature:getId() end)
  if not okId or not cid then return end
  local token = tostring(cid)

  local observed = observationForCreature(token)
  local isShiny = (observed and observed.isShiny) or isCreatureShiny(creature)
  local cName = (observed and observed.name) or (pcall(function() return creature:getName() end) and creature:getName() or '')
  local isTarget, targetBallId = getTargetBallForCreature(cName, creature, isShiny)
  if not isTarget then
    observedTargets[token] = nil
    return
  end

  local target = dyingTargets[token]
  local healthPercent = nil
  pcall(function() healthPercent = creature:getHealthPercent() end)

  if not target then
    local position = observed and observed.position
    if not position then
      local okPos, cPos = pcall(function() return creature:getPosition() end)
      if okPos and cPos then position = cPos end
    end
    if not position then return end
    target = {
      creatureId = cid,
      name = cName,
      isShiny = isShiny,
      ballId = targetBallId or (observed and observed.ballId),
      position = { x = position.x, y = position.y, z = position.z },
      beforeItems = observed and samePosition(observed.position, position) and
        observed.beforeItems or snapshotTileItems(position),
      unconfirmedDeath = healthPercent == nil or healthPercent > 0
    }
    dyingTargets[token] = target
  end

  if retryEvents[token] then return end
  retryEvents[token] = scheduleEvent(function()
    attemptCatch(token, 1)
  end, CORPSE_RETRY_DELAY)
end

function onGameEnd()
  cancelCorpseSelection()
  cancelBallSelection()
  cancelAutoItemSelection()
  stopAutoItemTimer()
  resetAutoItemRuntimeState()
  setEnabled(false, 'Auto Catch desativado ao sair do jogo.')
  sessionThrows = 0
  hide()
end

function onGameStart()
  refreshBallDisplay()
  scheduleBallRefresh()
  resetAutoItemRuntimeState()
  refreshAutoItemEntries()
  if hasEnabledAutoItems() then startAutoItemTimer() end
end

local function bindPanelWidgets(rootWidget)
  if not rootWidget then
    debugLog("bindPanelWidgets: rootWidget is nil")
    return
  end
  debugLog("bindPanelWidgets: starting with rootWidget id=" .. tostring(rootWidget:getId()))

  local panelWidget = rootWidget:recursiveGetChildById('autoCatchPanel') or rootWidget
  ui.panel = panelWidget

  ui.entriesList = rootWidget:recursiveGetChildById('entriesList')
  ui.entriesEmpty = rootWidget:recursiveGetChildById('entriesEmpty')
  ui.entriesCountHint = rootWidget:recursiveGetChildById('entriesCountHint')
  ui.addPokemonBtn = rootWidget:recursiveGetChildById('addPokemon')

  ui.enabledCheckBox = rootWidget:recursiveGetChildById('enabled')
  ui.statusLabel = rootWidget:recursiveGetChildById('status')
  ui.statusCard = rootWidget:recursiveGetChildById('statusCard')
  ui.statusIndicator = rootWidget:recursiveGetChildById('statusIndicator')
  ui.statusTitle = rootWidget:recursiveGetChildById('statusTitle')

  ui.navTabCatch = rootWidget:recursiveGetChildById('navTabCatch')
  ui.navTabSafety = rootWidget:recursiveGetChildById('navTabSafety')
  ui.navTabUtils = rootWidget:recursiveGetChildById('navTabUtils')

  ui.tabCatchContent = rootWidget:recursiveGetChildById('tabCatchContent')
  ui.tabSafetyContent = rootWidget:recursiveGetChildById('tabSafetyContent')
  ui.tabUtilsContent = rootWidget:recursiveGetChildById('tabUtilsContent')

  ui.presetSafeBtn = rootWidget:recursiveGetChildById('presetSafe')
  ui.presetNormalBtn = rootWidget:recursiveGetChildById('presetNormal')
  ui.presetTurboBtn = rootWidget:recursiveGetChildById('presetTurbo')

  ui.autoItemsList = rootWidget:recursiveGetChildById('autoItemsList')
  ui.autoItemsEmpty = rootWidget:recursiveGetChildById('autoItemsEmpty')
  ui.autoItemsCountHint = rootWidget:recursiveGetChildById('autoItemsCountHint')
  ui.addAutoItemBtn = rootWidget:recursiveGetChildById('addAutoItem')
  ui.catchIntervalMinEdit = rootWidget:recursiveGetChildById('catchIntervalMinEdit')
  ui.catchIntervalMaxEdit = rootWidget:recursiveGetChildById('catchIntervalMaxEdit')

  debugLog(string.format("bindPanelWidgets: widgets resolved - navTabCatch=%s, entriesList=%s, addPokemon=%s, enabled=%s",
    tostring(ui.navTabCatch ~= nil), tostring(ui.navTabSafety ~= nil),
    tostring(ui.entriesList ~= nil), tostring(ui.addPokemonBtn ~= nil), tostring(ui.enabledCheckBox ~= nil)))

  local function wireButton(widget, onClickFunc)
    if not widget then return end
    widget.onClick = function()
      pcall(onClickFunc)
    end
    widget.onMouseRelease = function(self, mousePos, mouseButton)
      if mouseButton == MouseLeftButton then
        pcall(onClickFunc)
        return true
      end
    end
  end

  wireButton(ui.navTabCatch, function() selectSubTab('catch') end)
  wireButton(ui.navTabSafety, function() selectSubTab('safety') end)
  wireButton(ui.navTabUtils, function() selectSubTab('utils') end)

  wireButton(ui.presetSafeBtn, function() applyPreset(350, 700) end)
  wireButton(ui.presetNormalBtn, function() applyPreset(200, 400) end)
  wireButton(ui.presetTurboBtn, function() applyPreset(80, 180) end)

  if ui.statusIndicator then
    ui.statusIndicator:setImageColor(enabled and '#42d392' or '#a85863')
  end
  if ui.statusTitle then
    ui.statusTitle:setText(enabled and 'AUTO CATCH ATIVADO' or 'AUTO CATCH DESATIVADO')
    ui.statusTitle:setColor(enabled and '#62d985' or '#dbe5ec')
  end

  wireButton(ui.addPokemonBtn, onAddTargetClick)
  wireButton(ui.addAutoItemBtn, onAddAutoItemClick)

  if ui.catchIntervalMinEdit and ui.catchIntervalMaxEdit then
    ui.catchIntervalMinEdit:setText(tostring(catchIntervalMinimum))
    ui.catchIntervalMaxEdit:setText(tostring(catchIntervalMaximum))
    ui.catchIntervalMinEdit.onTextChange = applyCatchIntervalInputs
    ui.catchIntervalMaxEdit.onTextChange = applyCatchIntervalInputs
    updateCatchIntervalInputColors(true)
  end
  updatePresetButtons(catchIntervalMinimum, catchIntervalMaximum)

  if ui.enabledCheckBox then
    ui.enabledCheckBox:setChecked(enabled)
    ui.enabledCheckBox.onCheckChange = function(widget, checked)
      debugLog("CHECK: enabled=" .. tostring(checked))
      if updatingInterface then return end
      setEnabled(checked)
    end
  end

  selectSubTab('catch')
  refreshCorpseEntries()
  refreshAutoItemEntries()
  debugLog("bindPanelWidgets: setup completed")
end

function selectSubTab(tabName)
  debugLog("selectSubTab: " .. tostring(tabName))
  local root = ui.panel or ui.window
  if root then
    if not ui.tabCatchContent then ui.tabCatchContent = root:recursiveGetChildById('tabCatchContent') end
    if not ui.tabSafetyContent then ui.tabSafetyContent = root:recursiveGetChildById('tabSafetyContent') end
    if not ui.tabUtilsContent then ui.tabUtilsContent = root:recursiveGetChildById('tabUtilsContent') end
    if not ui.navTabCatch then ui.navTabCatch = root:recursiveGetChildById('navTabCatch') end
    if not ui.navTabSafety then ui.navTabSafety = root:recursiveGetChildById('navTabSafety') end
    if not ui.navTabUtils then ui.navTabUtils = root:recursiveGetChildById('navTabUtils') end
  end

  local isCatch = (tabName == 'catch')
  local isSafety = (tabName == 'safety')
  local isUtils = (tabName == 'utils')

  if ui.tabCatchContent then ui.tabCatchContent:setVisible(isCatch) end
  if ui.tabSafetyContent then ui.tabSafetyContent:setVisible(isSafety) end
  if ui.tabUtilsContent then ui.tabUtilsContent:setVisible(isUtils) end

  if ui.navTabCatch then ui.navTabCatch:setOn(isCatch) end
  if ui.navTabSafety then ui.navTabSafety:setOn(isSafety) end
  if ui.navTabUtils then ui.navTabUtils:setOn(isUtils) end
end

function applyPreset(minMs, maxMs)
  debugLog(string.format("applyPreset: %d-%d ms", minMs, maxMs))
  local root = ui.panel or ui.window
  if not ui.catchIntervalMinEdit and root then ui.catchIntervalMinEdit = root:recursiveGetChildById('catchIntervalMinEdit') end
  if not ui.catchIntervalMaxEdit and root then ui.catchIntervalMaxEdit = root:recursiveGetChildById('catchIntervalMaxEdit') end

  if ui.catchIntervalMinEdit and ui.catchIntervalMaxEdit then
    ui.catchIntervalMinEdit:setText(tostring(minMs))
    ui.catchIntervalMaxEdit:setText(tostring(maxMs))
  else
    catchIntervalMinimum = minMs
    catchIntervalMaximum = maxMs
    saveSettings()
  end
  updatePresetButtons(minMs, maxMs)
end

local lastAddTargetTime = 0
function onAddTargetClick()
  local now = g_clock.millis()
  if (now - lastAddTargetTime) < 200 then
    return
  end
  lastAddTargetTime = now
  debugLog("onAddTargetClick: adicionando novo card")
  addNewPokemon()
  return true
end

local lastAddAutoItemTime = 0
function onAddAutoItemClick()
  local now = g_clock.millis()
  if (now - lastAddAutoItemTime) < 200 then
    return
  end
  lastAddAutoItemTime = now
  debugLog("onAddAutoItemClick: adicionando novo card")
  addNewAutoItem()
  return true
end

function onCurrentTargetClick()
  debugLog("onCurrentTargetClick called")
  useCurrentTarget()
end

if not modules.game_autocatch then modules.game_autocatch = {} end
modules.game_autocatch.selectSubTab = selectSubTab
modules.game_autocatch.switchTab = switchTab
modules.game_autocatch.onAddTargetClick = onAddTargetClick
modules.game_autocatch.onCurrentTargetClick = onCurrentTargetClick
  modules.game_autocatch.addNewPokemon = addNewPokemon
modules.game_autocatch.startCorpseSelection = startCorpseSelection
modules.game_autocatch.clearBall = clearBall
modules.game_autocatch.setShinyBallChoice = setShinyBallChoice
modules.game_autocatch.applyPreset = applyPreset
modules.game_autocatch.startAutoItemSelection = startAutoItemSelection
modules.game_autocatch.clearAutoItem = clearAutoItem
modules.game_autocatch.addNewAutoItem = addNewAutoItem
modules.game_autocatch.onAddAutoItemClick = onAddAutoItemClick

_G.autoCatchSelectSubTab = selectSubTab
_G.autoCatchSwitchTab = switchTab
_G.autoCatchAddTarget = onAddTargetClick
_G.autoCatchCurrentTarget = onCurrentTargetClick
function init()
  debugLog("init() starting")
  g_ui.importStyle('autocatch.otui')

  catchAllShiny = g_settings.getBoolean(SETTINGS.CATCH_ALL_SHINY, false)
  shinyBallChoice = g_settings.getNumber(SETTINGS.SHINY_BALL_CHOICE, 1)
  if shinyBallChoice ~= 1 and shinyBallChoice ~= 2 then shinyBallChoice = 1 end

  local configuredMinimum = g_settings.getNumber(SETTINGS.CATCH_INTERVAL_MIN, CatchInterval.DEFAULT_MINIMUM)
  local configuredMaximum = g_settings.getNumber(SETTINGS.CATCH_INTERVAL_MAX, CatchInterval.DEFAULT_MAXIMUM)
  local validMinimum, validMaximum = CatchInterval.validate(configuredMinimum, configuredMaximum)
  if validMinimum then
    catchIntervalMinimum, catchIntervalMaximum = validMinimum, validMaximum
  else
    catchIntervalMinimum, catchIntervalMaximum = CatchInterval.DEFAULT_MINIMUM, CatchInterval.DEFAULT_MAXIMUM
  end

  loadCorpseEntries()
  loadShinyLookTypes()
  loadAutoItems()


  function createEmbeddedPanel(parent)
    if not parent then return nil end
    if ui.panel then
      ui.panel:destroy()
      ui.panel = nil
    end
    ui.panel = g_ui.createWidget('AutoCatchPanel', parent)
    bindPanelWidgets(ui.panel)
    return ui.panel
  end

  function getPanel()
    return ui.panel
  end

  function isEnabled()
    return enabled
  end

  function onMasterTabSelected()
    refreshBallDisplay()
    refreshAutoItemEntries()
    updateShinyBallButtons()
    switchTab(1)
  end

  if modules.game_cavebot_pka and modules.game_cavebot_pka.getAutoCatchContainer then
    local container = modules.game_cavebot_pka.getAutoCatchContainer()
    if container then
      createEmbeddedPanel(container)
    end
  end

  if modules.client_topmenu and not ui.button then
    ui.button = modules.client_topmenu.addMiddleGameToggleButton(
      'autoCatchButton',
      tr('Auto Catch'),
      '/modules/game_autocatch/images/icon',
      toggle,
      false,
      17
    )
    if ui.button then
      ui.button:setOn(false)
    end
  end

  connect(Creature, {
    onAppear = onCreatureAppear,
    onHealthPercentChange = onCreatureHealthPercentChange,
    onPositionChange = onCreaturePositionChange,
    onDisappear = onCreatureDisappear,
  })
  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd,
    onPlayerBuffsReceived = onAutoItemBuffsReceived,
  })

  refreshBallDisplay()
  scheduleBallRefresh()
  refreshAutoItemEntries()
  if hasEnabledAutoItems() then startAutoItemTimer() end
  updateShinyBallButtons()
  switchTab(1)
  setEnabled(false, 'Adicione cards com Ball e corpo; o recurso inicia desativado.')
  print(string.format('[AutoCatch] Cards por corpos carregados: %s, AutoItems=%d (enabled=%s), Balls=%d-%dms.',
    configuredEntriesSummary(), #autoItems, tostring(hasEnabledAutoItems()),
    catchIntervalMinimum, catchIntervalMaximum))
  debugLog("init() completed successfully")
end

function terminate()
  disconnect(Creature, {
    onAppear = onCreatureAppear,
    onHealthPercentChange = onCreatureHealthPercentChange,
    onPositionChange = onCreaturePositionChange,
    onDisappear = onCreatureDisappear,
  })
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd,
    onPlayerBuffsReceived = onAutoItemBuffsReceived,
  })
  cancelBallRefresh()
  cancelCorpseSelection()
  cancelBallSelection()
  cancelAutoItemSelection()
  stopAutoItemTimer()
  resetAutoItemRuntimeState()
  cancelRetries()

  if ui.window then
    ui.window:destroy()
    ui.window = nil
    ui.panel = nil
  elseif ui.panel then
    ui.panel:destroy()
    ui.panel = nil
  end
  if ui.button then
    ui.button:destroy()
    ui.button = nil
  end
end

function show()
  debugLog("show() called")
  if modules.game_cavebot_pka and modules.game_cavebot_pka.openTab then
    debugLog("show(): delegating to game_cavebot_pka.openTab('autocatch')")
    modules.game_cavebot_pka.openTab('autocatch')
    if ui.button then ui.button:setOn(true) end
    return
  end
  if not ui.window then
    debugLog("show(): creating AutoCatchWindow standalone")
    local root = modules.game_interface and modules.game_interface.getRootPanel()
    debugLog("show(): rootPanel = " .. tostring(root and root:getId()))
    local okCreate, win = pcall(function()
      return g_ui.createWidget('AutoCatchWindow', root)
    end)
    if not okCreate or not win then
      debugLog("show() FATAL: Failed to create AutoCatchWindow: " .. tostring(win))
      return
    end
    ui.window = win
    debugLog("show(): AutoCatchWindow created successfully")

    local okBind, errBind = pcall(bindPanelWidgets, ui.window)
    if not okBind then
      debugLog("show() ERROR during bindPanelWidgets: " .. tostring(errBind))
      ui.window:destroy()
      ui.window = nil
      ui.panel = nil
      if ui.button then ui.button:setOn(false) end
      return
    else
      debugLog("show(): bindPanelWidgets completed successfully")
    end

    ui.window.onVisibilityChange = function(widget, visible)
      if ui.button then ui.button:setOn(visible) end
    end
    ui.window.onEnter = onAddTargetClick
    ui.window.onEscape = hide
  end
  ui.window:show()
  ui.window:raise()
  ui.window:focus()
  refreshBallDisplay()
  scheduleBallRefresh()
  if ui.button then ui.button:setOn(true) end
  debugLog("show(): window displayed and raised")
end

function hide()
  if modules.game_cavebot_pka and modules.game_cavebot_pka.hide then
    modules.game_cavebot_pka.hide()
    if ui.button then ui.button:setOn(false) end
    return
  end
  if not ui.window then return end
  ui.window:hide()
  if ui.button then ui.button:setOn(false) end
end

function toggle()
  if modules.game_cavebot_pka and modules.game_cavebot_pka.toggleTab then
    modules.game_cavebot_pka.toggleTab('autocatch')
    if ui.button and modules.game_cavebot_pka.isOpen then
      ui.button:setOn(modules.game_cavebot_pka.isOpen())
    end
    return
  elseif modules.game_cavebot_pka and modules.game_cavebot_pka.toggle then
    modules.game_cavebot_pka.toggle()
    if ui.button and modules.game_cavebot_pka.isOpen then
      ui.button:setOn(modules.game_cavebot_pka.isOpen())
    end
    return
  end
  if not ui.window then
    show()
    return
  end
  if ui.window:isVisible() then hide() else show() end
end

local function hasPendingCorpses()
  if not enabled or not g_game.isOnline() then return false end
  if not floorScanHasResult then return true end
  return floorScanHasPendingCorpses
end

function isBusy()
  if not enabled then return false end
  local now = g_clock.millis()
  if activeCatchJob ~= nil or #catchQueue > 0 then return true end
  if next(dyingTargets) ~= nil or next(retryEvents) ~= nil then return true end
  local gracePeriod = ((recentBurstThrows or 0) >= 5) and 1500 or 800
  if (now - lastThrowTime) < gracePeriod then return true end
  if hasPendingCorpses() then return true end
  return false
end

if not modules.game_autocatch then modules.game_autocatch = {} end
modules.game_autocatch.init = init
modules.game_autocatch.terminate = terminate
modules.game_autocatch.show = show
modules.game_autocatch.hide = hide
modules.game_autocatch.toggle = toggle
modules.game_autocatch.createEmbeddedPanel = createEmbeddedPanel
modules.game_autocatch.getPanel = getPanel
modules.game_autocatch.isEnabled = isEnabled
modules.game_autocatch.setEnabled = setEnabled
modules.game_autocatch.isBusy = isBusy
modules.game_autocatch.hasPendingCorpses = hasPendingCorpses
modules.game_autocatch.onMasterTabSelected = onMasterTabSelected
modules.game_autocatch.selectSubTab = selectSubTab
modules.game_autocatch.switchTab = switchTab
modules.game_autocatch.onAddTargetClick = onAddTargetClick
modules.game_autocatch.onCurrentTargetClick = onCurrentTargetClick
modules.game_autocatch.startCorpseSelection = startCorpseSelection
modules.game_autocatch.clearBall = clearBall
modules.game_autocatch.setShinyBallChoice = setShinyBallChoice
modules.game_autocatch.applyPreset = applyPreset
modules.game_autocatch.startAutoItemSelection = startAutoItemSelection
modules.game_autocatch.clearAutoItem = clearAutoItem
modules.game_autocatch.addNewAutoItem = addNewAutoItem
modules.game_autocatch.onAddAutoItemClick = onAddAutoItemClick

_G.autoCatchHide = hide
_G.autoCatchShow = show
_G.autoCatchToggle = toggle
_G.autoCatchSelectSubTab = selectSubTab
_G.autoCatchSwitchTab = switchTab
_G.autoCatchAddTarget = onAddTargetClick
_G.autoCatchCurrentTarget = onCurrentTargetClick

