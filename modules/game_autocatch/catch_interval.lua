local Interval = {}

Interval.DEFAULT_MINIMUM = 220
Interval.DEFAULT_MAXIMUM = 260
Interval.LOWER_LIMIT = 50
Interval.UPPER_LIMIT = 2000
Interval.PING_BUFFER = 30

function Interval.validate(minimum, maximum)
  minimum, maximum = tonumber(minimum), tonumber(maximum)
  if not minimum or not maximum or minimum ~= math.floor(minimum) or maximum ~= math.floor(maximum) then
    return nil, "limits-must-be-integers"
  end
  if minimum < Interval.LOWER_LIMIT or minimum > Interval.UPPER_LIMIT or
      maximum < Interval.LOWER_LIMIT or maximum > Interval.UPPER_LIMIT then
    return nil, "limits-out-of-range"
  end
  if minimum > maximum then return nil, "minimum-greater-than-maximum" end
  return minimum, maximum
end

function Interval.calculate(ping, minimum, maximum)
  local validMinimum, validMaximum = Interval.validate(minimum, maximum)
  if not validMinimum then
    validMinimum, validMaximum = Interval.DEFAULT_MINIMUM, Interval.DEFAULT_MAXIMUM
  end
  ping = math.max(0, tonumber(ping) or 0)
  return math.min(validMaximum, math.max(validMinimum, ping + Interval.PING_BUFFER))
end

return Interval
