local AutoItem = {}

local function nowMillis()
  if g_clock and type(g_clock.millis) == 'function' then
    return g_clock.millis()
  end
  return os.time() * 1000
end

function AutoItem.normalizeId(value)
  if type(value) == 'number' or type(value) == 'string' then
    return math.max(0, tonumber(value) or 0)
  end

  if value and (type(value) == 'table' or type(value) == 'userdata') then
    local ok, itemId = pcall(function() return value:getId() end)
    if ok then return math.max(0, tonumber(itemId) or 0) end
  end

  return 0
end

local function readBuffField(buff, fieldName)
  if type(buff) ~= 'table' and type(buff) ~= 'userdata' then return nil end
  local ok, value = pcall(function() return buff[fieldName] end)
  return ok and value or nil
end

function AutoItem.makeBuffSnapshot(buffs, receivedAtMs)
  local snapshot = {}
  receivedAtMs = tonumber(receivedAtMs) or nowMillis()

  if type(buffs) ~= 'table' then return snapshot end

  for _, buff in ipairs(buffs) do
    local name = readBuffField(buff, 'name')
    if type(name) == 'string' and name ~= '' then
      local remainingMs = math.max(0,
        tonumber(readBuffField(buff, 'endTime')) or
        tonumber(readBuffField(buff, 'remainingMs')) or 0)
      snapshot[name] = {
        remainingMs = remainingMs,
        value = readBuffField(buff, 'value'),
        receivedAtMs = receivedAtMs
      }
    end
  end

  return snapshot
end

function AutoItem.wasItemConsumed(beforeCount, currentCount)
  beforeCount = tonumber(beforeCount)
  currentCount = tonumber(currentCount)
  return beforeCount and currentCount and currentCount < beforeCount or false
end

function AutoItem.snapshotRemainingMs(entry, currentTimeMs)
  if type(entry) == 'number' then
    return math.max(0, entry)
  end
  if type(entry) ~= 'table' then return 0 end

  currentTimeMs = tonumber(currentTimeMs) or nowMillis()
  local remainingMs = tonumber(entry.remainingMs) or tonumber(entry.endTime) or 0
  local receivedAtMs = tonumber(entry.receivedAtMs)
  if receivedAtMs then
    remainingMs = remainingMs - math.max(0, currentTimeMs - receivedAtMs)
  end
  return math.max(0, remainingMs)
end

function AutoItem.changedBuffNames(before, after, currentTimeMs)
  local changed = {}
  before = type(before) == 'table' and before or {}
  after = type(after) == 'table' and after or {}
  currentTimeMs = tonumber(currentTimeMs) or nowMillis()

  for name, current in pairs(after) do
    local previous = before[name]
    local currentRemaining = AutoItem.snapshotRemainingMs(current, currentTimeMs)
    local previousRemaining = AutoItem.snapshotRemainingMs(previous, currentTimeMs)
    local valueChanged = previous and current.value ~= previous.value
    if not previous or currentRemaining > previousRemaining or valueChanged then
      table.insert(changed, name)
    end
  end

  table.sort(changed)
  return changed
end

function AutoItem.maxBuffRemainingMs(buffNames, getRemainingMs)
  if type(buffNames) ~= 'table' or type(getRemainingMs) ~= 'function' then
    return 0
  end

  local maximum = 0
  for _, name in ipairs(buffNames) do
    local remaining = tonumber(getRemainingMs(name)) or 0
    maximum = math.max(maximum, remaining)
  end
  return maximum
end

function AutoItem.dispatch(itemId, gameApi)
  itemId = AutoItem.normalizeId(itemId)
  if itemId <= 0 then return false, 'invalid-item-id' end

  gameApi = gameApi or g_game
  if not gameApi or type(gameApi.findPlayerItem) ~= 'function' then
    return false, 'find-player-item-unavailable'
  end
  if type(gameApi.use) ~= 'function' then
    return false, 'use-item-unavailable'
  end

  local found, item = pcall(function()
    return gameApi.findPlayerItem(itemId, -1)
  end)
  if not found then
    return false, tostring(item)
  end
  if not item or AutoItem.normalizeId(item) ~= itemId then
    return false, 'item-not-in-inventory'
  end

  local ok, errorMessage = pcall(function()
    gameApi.use(item, true)
  end)
  if not ok then return false, tostring(errorMessage) end

  return true
end

return AutoItem
