pico-8 cartridge // http://www.pico-8.com
version 42
__lua__

tile_size = 8
cursor_sprite = 32
laser_sprite_map = {
    E = 16,
    v = 17,
    h = 18,
    da = 19,
    db = 20,
    vs = 22,
    hs = 23,
    dsa = 24,
    dsb = 25,
  }
tool_sprite_map = {
    reset = 33,
    mirror = 17,
    splitter = 22
  }
target_sprite_map = {
    -- {off, on}
    test = {21,38}
  }
field_offset = {3,3}
tool_ui_offset = {7,14}
field = {}
targets = {} -- fx:fy = { ... }
tools = {} -- type: {max, num}
selected_tool = ""
level = {
  name = "DEV",
  field = {
    {type = "E", fx = 3, fy = 3, dx = 1, dy = 0},
    {type = "T", sprites = "test", fx = 5, fy = 5},
    {type = "T", sprites = "test", fx = 10, fy = 5},
    {type = "T", sprites = "test", fx = 1, fy = 2}
    },
  tools = { { type = "mirror", max = 2 }, { type = "splitter", max = 2 }}
  }
laser_plot = {}
laser_plot_tool_chain = {} -- "gx:dx:gy:dy"
input = {
    cursor = {0, 0},
    lmb = {
        just_pressed = false,
        was_pressed = false,
        down = false
      }
  }

function _init()
  poke(0x5f2d, 1)
  load_level(level)
end

function _update()
  update_input()
  if input.lmb.just_pressed then
    local mx,my = unpack(input.cursor)
    local gx,gy = unpack(pos_to_grid(mx,my))
    toggle_cell(gx, gy)
  end
  update_lasers()
  update_targets()
  update_ui()
end

function _draw()
	cls()
	draw_field() -- should be draw_map()
  draw_laser()
  draw_targets()
  draw_tools()
  draw_ui()
  if check_win() then
    rect(0,0,8,8,12)
  end
end

function load_level(level_data)
  targets = {}
  tools = {}
  field = {
  {"","","","","","","","","",""},
  {"","","","","","","","","",""},
  {"","","","","","","","","",""},
  {"","","","","","","","","",""},
  {"","","","","","","","","",""},
  {"","","","","","","","","",""},
  {"","","","","","","","","",""},
  {"","","","","","","","","",""},
  {"","","","","","","","","",""},
  {"","","","","","","","","",""}
  }

  for _, obj in ipairs(level_data.field) do
    if obj.type == "T" then
      targets[join_str(obj.fx, obj.fy)] = {fx = obj.fx, fy = obj.fy, sprites = obj.sprites, is_active = false}
    end
    field[obj.fy][obj.fx] = obj.type
  end

  for i, tool in ipairs(level_data.tools) do
    add(tools, {type = tool.type, max = tool.max, current = 0})
  end
  add(tools, { type = "" })
  add(tools, { type = "reset"})

  selected_tool = tools[1].type

  level = level_data
end

function update_input()
  local mb = stat(34)
  input.cursor = {stat(32)-1, stat(33)-1}
  input.lmb.down = mb == 1

  if input.lmb.down then
    if not input.lmb.was_pressed then
      input.lmb.just_pressed = true
      input.lmb.was_pressed = true
    else
      input.lmb.just_pressed = false
    end
  else
    input.lmb.just_pressed = false
    input.lmb.was_pressed = false
  end
end

function update_targets()
  for _, target in pairs(targets) do
    target.is_active = false
  end

  for _, segment in ipairs(laser_plot) do
    _, _, x, y = unpack(segment)
    gx,gy = unpack(pos_to_grid(x, y))
    target = targets[join_str(gx,gy)]
    if target then
      target.is_active = true
    end
  end
end

function check_win()
  for _, target in pairs(targets) do
    if not target.is_active then
      return false
    end
  end

  return true
end

function update_lasers()
  laser_plot = {}
  laser_plot_tool_chain = {}

  local emitters = {}
  for _, cell in ipairs(level.field) do
    if cell.type == "E" then
      add(emitters, cell)
    end
  end

  for _, cell in ipairs(emitters) do
    plot_laser(cell.fx, cell.fy, cell.dx, cell.dy)
  end
end

function plot_laser(gx, gy, dx, dy)
  local c = get_cell(gx + dx, gy + dy)
  local chain_key = join_str(gx,dx,gy,dy)

  if c == nil or laser_plot_tool_chain[chain_key] then
    return
  end

  local ox, oy = unpack(field_offset)
  local x1, y1 = (gx + ox - 1) * tile_size + tile_size/2, (gy + oy - 1) * tile_size + tile_size/2
  local x2, y2 = (gx + ox + dx - 1) * tile_size + tile_size/2, (gy + oy + dy - 1) * tile_size + tile_size/2

  add(laser_plot, {x1,y1,x2,y2})
  if c != "" then
    laser_plot_tool_chain[chain_key] = true
  end

  local directions = reflect(dx, dy, c)

  for i = 1, #directions do
    local next_dx, next_dy = unpack(directions[i])
    if next_dx != 0 or next_dy != 0 then
      plot_laser(gx + dx, gy + dy, next_dx, next_dy)
    end
  end
end

function toggle_cell(gx, gy)
  local cell = get_cell(gx, gy)

  if cell == nil or cell == "E" or cell == "T" or selected_tool == "" then
    return
  end

  local new_cell = ""

  if cell == "" and remaining_tool_count(selected_tool) <= 0 then
    return
  end

  if selected_tool == "splitter" then
    if cell == "" then
      new_cell = "vs"
      use_tool("splitter")
    elseif cell == "vs" then
      new_cell = "dsa"
    elseif cell == "dsa" then
      new_cell = "hs"
    elseif cell == "hs" then
      new_cell = "dsb"
    elseif is_mirror(cell) then
      new_cell = "vs"
      use_tool("splitter")
      restore_tool("mirror")
    else
      new_cell = ""
      restore_tool("splitter")
    end
  else
    if cell == "" then
      use_tool("mirror")
      new_cell = "v"
    elseif cell == "v" then
      new_cell = "da"
    elseif cell == "da" then
      new_cell = "h"
    elseif cell == "h" then
      new_cell = "db"
    elseif is_splitter(cell) then
      new_cell = "v"
      use_tool("mirror")
      restore_tool("splitter")
    else
      new_cell = ""
      restore_tool("mirror")
    end
  end

  field[gy][gx] = new_cell
end

function toggle_cell_deprecated(gx, gy)
  local value = get_cell(gx, gy)
  local new_value = ""

  if value == nil or value == "E" then
    return
  elseif value == "" then
    new_value = "v"
  elseif value == "v" then
    new_value = "da"
  elseif value == "da" then
    new_value = "h"
  elseif value == "h" then
    new_value = "db"
  end

  field[gy][gx] = new_value
end

function is_tool(cell)
  return cell != "" and cell != "E"
end

function is_splitter(cell)
  return cell == "vs" or cell == "hs" or cell == "dsa"
end

function get_cell(gx, gy)
  if gy > 0 and gy <= #field and gx > 0 and gx <= #field[1] then
    return field[gy][gx]
  end

  return nil
end

function reflect(dx, dy, cell)
  if cell == "v" then
    if dx == 0 then
      return {{0,0}}
    end
    return {{dx * -1, dy}}
  elseif cell == "h" then
    if dy == 0 then
      return {{0,0}}
    end
    return {{dx, dy * -1}}
  elseif cell == "da" then
    if dx != 0 and dy != 0 then
      if dx == dy then
        return {{0,0}}
      else
        return {{-dx, -dy}}
      end
    end
    if dx != 0 and dy == 0 then
      if dx > 0 then
        return {{0, 1}}
      else
        return {{0, -1}}
      end
    end
    if dx == 0 and dy != 0 then
      if dy > 0 then
        return {{1, 0}}
      else
        return {{-1, 0}}
      end
    end
  elseif cell == "db" then
    if dy != 0 and dx != 0 then
      if dx == dy then
        return {{0,0}}
      else
        return {{-dx, -dy}}
      end
    end
    if dy != 0 and dx == 0 then
      if dy > 0 then
        return {{-1, 0}}
      end
      return {{1, 0}}
    end
    if dy == 0 and dx != 0 then
      if dx > 0 then
        return {{0, -1}}
      else
        return {{0, 1}}
      end
    end
  elseif cell == "vs" then
    if dx == 0 then
      return {{0,0}}
    end
    return {{0,-1}, {0,1}}
  elseif cell == "hs" then
    if dy == 0 then
      return {{0,0}}
    end
    return {{-1,0}, {1,0}}
  elseif cell == "dsa" then
    if (dx != 0 and dy == 0) or (dx == 0 and dy != 0) or (dx != dy) then
      return {{-1, -1}, {1,1}}
    end
    return {{0,0}}
  elseif cell == "dsb" then
    if (dx != 0 and dy == 0) or (dx == 0 and dy != 0) or (dx == dy) then
      return {{-1, 1}, {1,-1}}
    end
    return {{0,0}}
  else
    return {{dx,dy}}
  end
end

function draw_field()
  map(0, 0, 0, 0)
end

function draw_tools()
  local mx,my = unpack(input.cursor)
  local gx,gy = unpack(pos_to_grid(mx,my))
  local ox,oy = unpack(field_offset)
  for i, row in ipairs(field) do
    for j, cell in ipairs(row) do
      local left = (j+ox-1)*tile_size
      local top = (i+oy-1)*tile_size
      local sprite = laser_sprite_map[cell]
      if sprite then
        spr(sprite, left, top)
      end
      if j == gx and i == gy then
        rect(left,top,left+tile_size,top+tile_size,12)
      end
    end
  end
end

function draw_laser()
  local prev_color = color()
  color(8)

  for _, segment in ipairs(laser_plot) do
    local x1,y1,x2,y2 = unpack(segment)
    line(x1,y1,x2,y2)
  end

  color(prev_color)
end

function draw_targets()
  for _, target in pairs(targets) do
    local x, y = unpack(grid_to_pos(target.fx, target.fy))
    local sprites = target_sprite_map[target.sprites]
    spr(target.is_active and sprites[2] or sprites[1], x, y)
  end
end

function update_ui()
  if not input.lmb.just_pressed then
    return
  end

  local mx, my = unpack(input.cursor)
  local tx, ty = unpack(tool_ui_offset)
  local gx, gy = unpack(pos_to_grid(mx, my))

  for i, tool in ipairs(tools) do
    local x, y = (i-1+tx) * tile_size, ty * tile_size
    local tool_gx, tool_gy = unpack(pos_to_grid(x,y))

    if tool_gx == gx and tool_gy == gy then
      if tool.type == "reset" then
        load_level(level)
      else
        selected_tool = tool.type
      end
    end
  end
end

function draw_ui()
  local mx,my = unpack(input.cursor)
  local tx, ty = unpack(tool_ui_offset)
  local gx, gy = unpack(pos_to_grid(mx, my))

  for i, tool in ipairs(tools) do
    if tool.type != "" then
      local x, y = (i-1+tx) * tile_size, ty * tile_size
      local tool_gx, tool_gy = unpack(pos_to_grid(x,y))
      local text = tool.type == "reset" and "r" or tostr(tool.max - tool.current)
      local text_color = text == "r" and 8 or 7
      print(text, x + tile_size/2 - 2, y - tile_size/2 - 2, text_color)

      if selected_tool == tool.type then
        rectfill(x, y, x + tile_size - 1, y + tile_size - 1, 6)
      end

      spr(tool_sprite_map[tool.type], x, y)

      if tool_gx == gx and tool_gy == gy then
        rect(x, y, x + tile_size - 1, y + tile_size, 12)
      end
    end
  end

  spr(cursor_sprite, mx-1, my-1)
end

function is_mirror(cell)
  return cell == "v" or cell == "h" or cell == "da" or cell == "db"
end

function is_splitter(cell)
  return cell == "vs" or cell == "hs" or cell == "dsa" or cell == "dsb"
end

function remaining_tool_count(type)
  for _, tool in ipairs(tools) do
    if tool.type == type then
      return tool.max - tool.current
    end
  end
  return 0
end

function use_tool(type)
  for _, tool in ipairs(tools) do
    if tool.type == type then
      tool.current = tool.current + 1
    end
  end
end

function restore_tool(type)
  for _, tool in ipairs(tools) do
    if tool.type == type then
      tool.current = tool.current - 1
    end
  end
end

function pos_to_grid(x, y)
  return {flr(x/tile_size) - field_offset[1] + 1, flr(y/tile_size) - field_offset[2] + 1}
end

function grid_to_pos(c, r)
  return {(c + field_offset[1] - 1) * tile_size, (r + field_offset[2] - 1) * tile_size}
end

function join_str(...)
  local args = {...}
  local result = ""
  for i, v in pairs(args) do
    result = result .. tostr(v) .. (i < #args and ":" or "")
  end

  return result
end

__gfx__
00000000707070077777777770000000777777777000000000000000000000000000000000000000000000000000000000000000000000000777777000000000
00000000077777707000000070000000000000000000000000000000000000000000000000000000000000000000000000000000070707707070707700000000
00700700077007777000000070000000000000000000000000000000000000000000000000000000000000000000000000000000070000007707770700000000
00077000770770707000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000707077777700000000
00077000070770777000000070000000000000000000000000000000000000000000000000000000000000000000000000000000070000007777770700000000
00700700777007707000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000707077707700000000
00000000077777707000000070000000000000000000000000000000000000000000000000000000000000000000000000000000077070707707070700000000
00000000700707077000000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000777777000000000
05577550000cc00000000000cc000000000000cc0660066000555500000000000550000000000550000000000000000000000000000005880000000000000000
55688655000cc00000000000ccc0000000000ccc6556655600555500000000005550000000000555000000000000000000000000000055580000000000000000
56688665000cc000000000000ccc00000000ccc065755756000c50005505505555c5500000055c55000000000000000000000000000555550005500000000000
57888875000cc000cccccccc00ccc000000ccc0006577560005cc500555ccc55005cc500005cc500000000000000000000000000005885000058850000000000
57888875000cc000cccccccc000ccc0000ccc00006577560005cc50055ccc555005cc500005cc500000000000000000000000000005885000558855000000000
56688665000cc000000000000000ccc00ccc0000657557560005c0005505505500055c5555c55000000000000000000000000000000555555555555500000000
55688655000cc0000000000000000cccccc000006556655600555500000000000000055555500000000000000000000000000000000055588550055800000000
05577550000cc00000000000000000cccc0000000660066000555500000000000000055005500000000000000000000000000000000005888850058800000000
08888000008888880000000000000000000000007777777703300330000000000000000000000000000000000000000000000000000000000000000000000000
8777780088807008000000000000000000000000788888873bb33bb3000000000000000000000000000000000000000000000000000000000000000000000000
8777800080070700000000000000000000000000787777873babbab3000000000000000000000000000000000000000000000000000000000000000000000000
87777800080880800000000000000000000000007878878703baab30000000000000000000000000000000000000000000000000000000000000000000000000
87877780080880800000000000000000000000007878878703baab30000000000000000000000000000000000000000000000000000000000000000000000000
0808780008088080000000000000000000000000787777873babbab3000000000000000000000000000000000000000000000000000000000000000000000000
0000800008088080000000000000000000000000788888873bb33bb3000000000000000000000000000000000000000000000000000000000000000000000000
00000000080880800000000000000000000000007777777703300330000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0101010101010101010101010101010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0100000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0100000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0100000202020202020202020203000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0100000202020202020202020203000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0100000202020202020202020203000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0100000202020202020202020203000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0100000202020202020202020203000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0100000202020202020202020203000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0100000202020202020202020203000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0100000202020202020202020203000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0100000202020202020202020203000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0100000202020202020202020203000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0100000404040404040404040405000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0100000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010101010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
