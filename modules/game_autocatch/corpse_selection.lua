local CorpseSelection = {}

local function containsItem(items, expected)
  for index, item in ipairs(items or {}) do
    if item == expected then return index end
  end
  return nil
end

local function isPreexisting(beforeItems, item)
  return beforeItems and beforeItems[item] == true
end

function CorpseSelection.pick(items, options)
  options = options or {}
  local getId = options.getId or function(item) return item and item.id end
  local matcher = options.matcher or function(item)
    return options.expectedId ~= nil and getId(item) == options.expectedId
  end
  local beforeItems = options.beforeItems
  local preferNew = options.preferNew == true and beforeItems ~= nil
  local isClaimed = options.isClaimed or function() return false end
  local topItem = options.topItem
  local topIndex = topItem and containsItem(items, topItem) or nil
  local hasMatch = false
  local hasNewMatch = false

  local function eligible(item, requireNew)
    if not item or not matcher(item) then return false end
    hasMatch = true
    if isPreexisting(beforeItems, item) then
      if requireNew then return false end
    else
      hasNewMatch = true
      if requireNew or not preferNew then
        return not isClaimed(item)
      end
    end
    return not requireNew and not isClaimed(item)
  end

  if topItem and topIndex and eligible(topItem, preferNew) then
    return topItem, topIndex, hasMatch, hasNewMatch
  end

  if preferNew then
    for index = #items, 1, -1 do
      local item = items[index]
      if item ~= topItem and eligible(item, true) then
        return item, index, hasMatch, hasNewMatch
      end
    end
    if hasNewMatch or hasMatch then
      return nil, nil, hasMatch, hasNewMatch
    end
    return nil, nil, false, false
  end

  for index = #items, 1, -1 do
    local item = items[index]
    if item ~= topItem and eligible(item, false) then
      return item, index, hasMatch, hasNewMatch
    end
  end

  return nil, nil, hasMatch, hasNewMatch
end

return CorpseSelection
