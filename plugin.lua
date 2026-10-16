-- Selective Outline Studio -- Aseprite extension entry point.
-- The pixel maths live in outline.lua; this file reads cels, runs the core and writes the result back.

local core = nil
local LITE = true -- the Lite build flips this to true (see build_bundles.py)

local function load_core(dir)
  if not core then core = dofile(app.fs.joinPath(dir, "outline.lua")) end
  return core
end

-- Cel -> sprite-sized core image (0 = transparent). Indexed colours are stored as index+1.
local function cel_to_core(spr, cel)
  local S = core
  local im = S.new(spr.width, spr.height)
  if not cel then return im end
  local px = app.pixelColor
  local mode = spr.colorMode
  local tc = spr.transparentColor
  local cx, cy = cel.position.x, cel.position.y
  for it in cel.image:pixels() do
    local v = it()
    local x, y = it.x + cx, it.y + cy
    if mode == ColorMode.INDEXED then
      if v ~= tc then S.set(im, x, y, v + 1) end
    elseif mode == ColorMode.GRAY then
      if px.grayaA(v) > 0 then S.set(im, x, y, v) end
    else
      if px.rgbaA(v) > 0 then S.set(im, x, y, v) end
    end
  end
  return im
end

-- Core image -> Image in the sprite's colour mode.
local function core_to_image(spr, im)
  local img = Image(im.w, im.h, spr.colorMode)
  local indexed = spr.colorMode == ColorMode.INDEXED
  local tc = spr.transparentColor
  if indexed then img:clear(tc) end
  for y = 0, im.h - 1 do for x = 0, im.w - 1 do
    local v = im.d[y * im.w + x + 1]
    if v ~= 0 then img:drawPixel(x, y, indexed and (v - 1) or v) end
  end end
  return img
end


-- value <-> r,g,b for the sprite's colour mode (core values: indexed = index+1)
local function rgb_of(spr)
  local px = app.pixelColor
  if spr.colorMode == ColorMode.INDEXED then
    local pal = spr.palettes[1]
    return function(v) local c = pal:getColor(v - 1); return c.red, c.green, c.blue end
  elseif spr.colorMode == ColorMode.GRAY then
    return function(v) local g = px.grayaV(v); return g, g, g end
  end
  return function(v) return px.rgbaR(v), px.rgbaG(v), px.rgbaB(v) end
end

-- Palette entries usable as outline colours (sel-out never leaves the palette).
local function candidates(spr)
  local list = {}
  if spr.colorMode == ColorMode.GRAY then
    for g = 0, 255, 1 do list[#list + 1] = { value = app.pixelColor.graya(g, 255), r = g, g = g, b = g } end
  else
    local pal = spr.palettes[1]
    local seen = {}
    for i = 0, #pal - 1 do
      local c = pal:getColor(i)
      if c.alpha > 0 and not (spr.colorMode == ColorMode.INDEXED and i == spr.transparentColor) then
        local v = spr.colorMode == ColorMode.INDEXED and (i + 1) or app.pixelColor.rgba(c.red, c.green, c.blue, 255)
        if not seen[v] then seen[v] = true; list[#list + 1] = { value = v, r = c.red, g = c.green, b = c.blue } end
      end
    end
  end
  return list
end

local function value_of_color(spr, color)
  if spr.colorMode == ColorMode.INDEXED then
    -- nearest palette entry, so the result stays inside the palette
    local pal = spr.palettes[1]
    local best, bd = 0, math.huge
    for i = 0, #pal - 1 do
      local c = pal:getColor(i)
      if c.alpha > 0 and i ~= spr.transparentColor then
        local d = (c.red - color.red) ^ 2 + (c.green - color.green) ^ 2 + (c.blue - color.blue) ^ 2
        if d < bd then bd, best = d, i end
      end
    end
    return best + 1
  elseif spr.colorMode == ColorMode.GRAY then
    return app.pixelColor.graya(math.floor(0.299 * color.red + 0.587 * color.green + 0.114 * color.blue), 255)
  end
  return app.pixelColor.rgba(color.red, color.green, color.blue, 255)
end

-- Outline one cel. place = "replace" | "layer". Returns true if something was written.
local function apply(spr, layer, fn, opts, place)
  local S = core
  local cel = layer:cel(fn)
  if not cel then return false end
  local im = cel_to_core(spr, cel)
  local has = false
  for i = 1, #im.d do if im.d[i] ~= 0 then has = true; break end end
  if not has then return false end
  local img = core_to_image(spr, S.outline(im, opts))
  if place == "layer" then
    local nl = spr:newLayer()
    nl.name = layer.name .. " (outline)"
    spr:newCel(nl, fn, img, Point(0, 0))
  else
    spr:newCel(layer, fn, img, Point(0, 0))
  end
  return true
end

local function frame_list(spr)
  local list = {}
  local r = app.range
  if r and r.frames and #r.frames > 0 and not LITE then
    for _, f in ipairs(r.frames) do list[#list + 1] = f.frameNumber end
    table.sort(list)
  else
    list[1] = app.frame and app.frame.frameNumber or 1
  end
  return list
end

local function show_dialog(plugin)
  local spr = app.sprite
  if not spr then app.alert("Open a sprite first."); return end
  local layer = app.layer
  if not layer or layer.isGroup then app.alert("Select a normal layer first."); return end
  load_core(plugin.path)
  local prefs = plugin.preferences
  local dlg = Dialog(LITE and "Selective Outline Studio (Lite)" or "Selective Outline Studio")
  dlg:combobox { id = "mode", label = "Style", option = LITE and "Flat outer outline" or (prefs.mode or "Selective (sel-out)"),
    options = LITE and { "Flat outer outline", "Flat inner outline" }
      or { "Selective (sel-out)", "Flat outer outline", "Flat inner outline" } }
  dlg:color { id = "color", label = "Flat colour", color = Color { r = 0, g = 0, b = 0 } }
  dlg:check { id = "diag", label = "Corners", text = "8-neighbour (include diagonals)", selected = prefs.diag == true, enabled = not LITE }
  dlg:check { id = "cleanup", label = "Cleanup", text = "Pixel-perfect corners", selected = prefs.cleanup ~= false }
  dlg:check { id = "usel", label = "Light", text = "Light from a direction (lit side lighter)", selected = prefs.usel == true, enabled = not LITE }
  dlg:slider { id = "angle", label = "Light angle (deg)", min = 0, max = 359, value = prefs.angle or 90, enabled = not LITE }
  dlg:slider { id = "dark", label = "Shade %", min = 20, max = 90, value = prefs.dark or 45, enabled = not LITE }
  dlg:combobox { id = "place", label = "Result", option = prefs.place or "Replace cel", options = { "Replace cel", "New layer" } }
  dlg:separator()
  dlg:button { id = "ok", text = "Apply", focus = true }
  dlg:button { id = "cancel", text = "Cancel" }
  if LITE then
    dlg:separator()
    dlg:label { text = "Full version: selective outline (sel-out) with palette-locked colours, light direction, 8-neighbour, frame ranges." }
  end
  dlg:show()
  local d = dlg.data
  if not d.ok then return end
  prefs.mode, prefs.diag, prefs.cleanup, prefs.usel = d.mode, d.diag, d.cleanup, d.usel
  prefs.angle, prefs.dark, prefs.place = d.angle, d.dark, d.place

  local mode = d.mode
  if LITE and mode == "Selective (sel-out)" then mode = "Flat outer outline" end
  local opts = { diag = d.diag and not LITE, cleanup = d.cleanup, inner = (mode == "Flat inner outline") }
  if mode == "Selective (sel-out)" then
    local rgb = rgb_of(spr)
    opts.sel = core.make_mapper(candidates(spr), rgb)
    opts.shade = d.dark / 100
    opts.lit_shade = math.min(0.98, opts.shade + 0.35)
    if d.usel then
      local rad = math.rad(d.angle)
      opts.light = { math.cos(rad), -math.sin(rad) } -- 0 deg = right, 90 deg = up
    end
  else
    opts.color = value_of_color(spr, d.color)
  end
  local place = (d.place == "New layer") and "layer" or "replace"
  local frames = frame_list(spr)
  local done = 0
  app.transaction("Selective Outline Studio", function()
    for i = #frames, 1, -1 do
      if apply(spr, layer, frames[i], opts, place) then done = done + 1 end
    end
  end)
  if done == 0 then
    app.alert { title = "Selective Outline Studio", text = "The selected frame has no drawing on this layer." }
  end
  app.refresh()
end

function init(plugin)
  local id = LITE and "OutlineStudioLite" or "OutlineStudio"
  local title = LITE and "Selective Outline Studio (Lite)..." or "Selective Outline Studio..."
  plugin:newCommand { id = id, title = title, group = "cel_popup_properties", onclick = function() show_dialog(plugin) end }
  plugin:newCommand { id = id .. "Edit", title = title, group = "edit_fx", onclick = function() show_dialog(plugin) end }
end

function exit(plugin) end

return { load_core = load_core, apply = apply, cel_to_core = cel_to_core, core_to_image = core_to_image,
         rgb_of = rgb_of, candidates = candidates, value_of_color = value_of_color }
