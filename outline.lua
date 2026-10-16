-- Selective Outline Studio core. Pure Lua, palette-locked: every output colour is a colour already in the
-- palette (or the colour you pick). Images are {w=,h=,d={}} with 0 = transparent.
local M = {}
function M.new(w, h) local d = {} for i = 1, w * h do d[i] = 0 end return { w = w, h = h, d = d } end
function M.get(im, x, y) if x < 0 or y < 0 or x >= im.w or y >= im.h then return 0 end return im.d[y * im.w + x + 1] end
function M.set(im, x, y, v) if x >= 0 and y >= 0 and x < im.w and y < im.h then im.d[y * im.w + x + 1] = v end end
function M.clone(im) local o = M.new(im.w, im.h) for i = 1, #im.d do o.d[i] = im.d[i] end return o end

local N4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local N8 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }

local function lum(r, g, b) return 0.299 * r + 0.587 * g + 0.114 * b end

-- cands: list of { value=, r=, g=, b= } (opaque palette entries). rgb(v) -> r,g,b for a pixel value.
-- Returns mapper(v, f): the palette colour nearest to v*f among those not brighter than v (f<1 darkens).
function M.make_mapper(cands, rgb)
  local cache = {}
  return function(v, f)
    local key = v .. ":" .. f
    if cache[key] then return cache[key] end
    local r, g, b = rgb(v)
    local l0 = lum(r, g, b)
    local tr, tg, tb = r * f, g * f, b * f
    local best, bd, darkest, dl = nil, math.huge, nil, math.huge
    for _, c in ipairs(cands) do
      local l = lum(c.r, c.g, c.b)
      if l < dl then dl, darkest = l, c.value end
      if l <= l0 then
        local d = (c.r - tr) ^ 2 + (c.g - tg) ^ 2 + (c.b - tb) ^ 2
        if d < bd then bd, best = d, c.value end
      end
    end
    local out = best or darkest or v
    cache[key] = out
    return out
  end
end

-- opts: diag (8-neighbour), cleanup, inner (recolour edge pixels of the drawing instead of drawing outside),
--       color (flat value) OR sel = mapper (sel-out: colour from the neighbouring fill pixel),
--       light = {x,y} unit vector pointing toward the light, strength/lit_strength = darkening factors.
function M.outline(src, o)
  local out = M.clone(src)
  local nb = o.diag and N8 or N4
  local shade, lit = o.shade or 0.45, o.lit_shade or 0.8
  local function colour_for(fill, ox, oy)
    if not o.sel then return o.color end
    local f = shade
    if o.light then
      local len = math.sqrt(ox * ox + oy * oy)
      if len > 0 and (ox * o.light[1] + oy * o.light[2]) / len > 0.01 then f = lit end
    end
    return o.sel(fill, f)
  end
  if o.inner then
    for y = 0, src.h - 1 do for x = 0, src.w - 1 do
      local v = M.get(src, x, y)
      if v ~= 0 then
        for _, d in ipairs(nb) do
          if M.get(src, x + d[1], y + d[2]) == 0 then M.set(out, x, y, colour_for(v, d[1], d[2])); break end
        end
      end
    end end
    return out
  end
  local placed = {}
  for y = -1, src.h do for x = -1, src.w do
    if M.get(src, x, y) == 0 and x >= 0 and y >= 0 and x < src.w and y < src.h then
      for _, d in ipairs(nb) do
        local v = M.get(src, x + d[1], y + d[2])
        if v ~= 0 then
          M.set(out, x, y, colour_for(v, -d[1], -d[2])) -- offset from fill pixel to the outline pixel
          placed[y * src.w + x] = true
          break
        end
      end
    end
  end end
  if o.cleanup and not o.diag then
    -- remove the middle pixel of an L-shaped corner: its two outline neighbours already touch diagonally
    local function isout(x, y) return placed[y * src.w + x] and x >= 0 and y >= 0 and x < src.w and y < src.h end
    for y = 0, src.h - 1 do for x = 0, src.w - 1 do
      if isout(x, y) then
        local hx = (isout(x - 1, y) and -1) or (isout(x + 1, y) and 1) or 0
        local vy = (isout(x, y - 1) and -1) or (isout(x, y + 1) and 1) or 0
        local n = (isout(x - 1, y) and 1 or 0) + (isout(x + 1, y) and 1 or 0) + (isout(x, y - 1) and 1 or 0) + (isout(x, y + 1) and 1 or 0)
        if n == 2 and hx ~= 0 and vy ~= 0 then
          placed[y * src.w + x] = nil; M.set(out, x, y, 0)
        end
      end
    end end
  end
  return out
end
return M
