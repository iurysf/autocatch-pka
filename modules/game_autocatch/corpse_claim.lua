local CorpseClaim = {}
CorpseClaim.__index = CorpseClaim

local function samePosition(left, right)
  return left and right and left.x == right.x and left.y == right.y and left.z == right.z
end

function CorpseClaim.new(ttl, now)
  return setmetatable({
    ttl = math.max(1, tonumber(ttl) or 1),
    now = now or function() return 0 end,
    items = {}
  }, CorpseClaim)
end

function CorpseClaim:cleanup(isPresent)
  local currentTime = self.now()
  for item, data in pairs(self.items) do
    local expired = data and not data.persistent and currentTime > data.expiresAt
    local missing = data and data.persistent and isPresent and not isPresent(item, data)
    if not data or expired or missing then
      self.items[item] = nil
    end
  end
end

function CorpseClaim:isClaimed(item, skipCleanup)
  if not item then return false end
  if not skipCleanup then self:cleanup() end
  return self.items[item] ~= nil
end

function CorpseClaim:isPositionClaimed(position, skipCleanup)
  if not position then return false end
  if not skipCleanup then self:cleanup() end
  for _, data in pairs(self.items) do
    if data and samePosition(data.position, position) then return true end
  end
  return false
end

function CorpseClaim:claim(item, position, itemId, options)
  if not item then return false end
  local skipCleanup = type(options) == 'table' and options.skipCleanup == true
  if self:isClaimed(item, skipCleanup) then return false end
  local persistent = type(options) == 'table' and options.persistent == true
  self.items[item] = {
    position = position,
    itemId = itemId,
    expiresAt = self.now() + self.ttl,
    persistent = persistent
  }
  return true
end

function CorpseClaim:refresh(item)
  if not item then return false end
  self:cleanup()
  local data = self.items[item]
  if not data then return false end
  data.expiresAt = self.now() + self.ttl
  return true
end

function CorpseClaim:release(item)
  if item then self.items[item] = nil end
end

function CorpseClaim:clear()
  self.items = {}
end

return CorpseClaim
