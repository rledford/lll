pico-8 cartridge // http://www.pico-8.com
version 42
__lua__

-- constants --

EMPTY = ""
T_SIZE = 8
FIELD_OFFSET = {3,3}
TOOL_UI_OFFSET = {7,14}

LASER_EMIT = "E"
LASER_BLOCK = "B"
LASER_TARGET = "T"
LASER_V = "V"
LASER_H = "H"
LASER_DA = "DA"
LASER_DB = "DB"
LASER_V_SPLIT = "VS"
LASER_H_SPLIT = "HS"
LASER_D_SPLIT_A = "DSA"
LASER_D_SPLIT_B = "DSB"

TOOL_RESET = "RESET"
TOOL_MIRROR = "MIRROR"
TOOL_SPLIT = "SPLIT"

CURSOR_SPRITE = 32

LASER_SPRITES = {
    [LASER_EMIT] = 16,
    [LASER_V] = 17,
    [LASER_H] = 18,
    [LASER_DA] = 19,
    [LASER_DB] = 20,
    [LASER_V_SPLIT] = 22,
    [LASER_H_SPLIT] = 23,
    [LASER_D_SPLIT_A] = 24,
    [LASER_D_SPLIT_B] = 25,
    [LASER_BLOCK] = 26
  }

TOOL_SPRITES = {
    [TOOL_RESET] = 33,
    [TOOL_MIRROR] = 17,
    [TOOL_SPLIT] = 22
  }

TARGET_SPRITES = {
    -- {off, on}
    test = {21,38}
  }

-- globals --

current_level = 25

field = {}
targets = {} -- fx:fy = { ... }
tools = {} -- type: {max, num}

selected_tool = EMPTY
level = {
  name = EMPTY,
  field = {},
  tools = {}
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

-- methods --

function _init()
  poke(0x5f2d, 1)
  load_level(levels[current_level])
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
  {EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY},
  {EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY},
  {EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY},
  {EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY},
  {EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY},
  {EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY},
  {EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY},
  {EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY},
  {EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY},
  {EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY,EMPTY},
  }

  for _, obj in ipairs(level_data.field) do
    if obj.type == LASER_TARGET then
      targets[join_str(obj.fx, obj.fy)] = {fx = obj.fx, fy = obj.fy, sprites = obj.sprites, is_active = false}
    end
    field[obj.fy][obj.fx] = obj.type
  end

  for i, tool in ipairs(level_data.tools) do
    add(tools, {type = tool.type, max = tool.max, current = 0})
  end
  add(tools, { type = EMPTY })
  add(tools, { type = TOOL_RESET})

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
    if cell.type == LASER_EMIT then
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

  local ox, oy = unpack(FIELD_OFFSET)
  local x1, y1 = (gx + ox - 1) * T_SIZE + T_SIZE/2, (gy + oy - 1) * T_SIZE + T_SIZE/2
  local x2, y2 = (gx + ox + dx - 1) * T_SIZE + T_SIZE/2, (gy + oy + dy - 1) * T_SIZE + T_SIZE/2

  add(laser_plot, {x1,y1,x2,y2})
  if c != EMPTY then
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

  if cell == nil or cell == LASER_BLOCK or cell == LASER_EMIT or cell == LASER_TARGET or selected_tool == EMPTY then
    return
  end

  local new_cell = EMPTY

  if cell == EMPTY and remaining_tool_count(selected_tool) <= 0 then
    return
  end

  if selected_tool == TOOL_SPLIT then
    if cell == EMPTY then
      new_cell = LASER_V_SPLIT
      use_tool(TOOL_SPLIT)
    elseif cell == LASER_V_SPLIT then
      new_cell = LASER_D_SPLIT_A
    elseif cell == LASER_D_SPLIT_A then
      new_cell = LASER_H_SPLIT
    elseif cell == LASER_H_SPLIT then
      new_cell = LASER_D_SPLIT_B
    elseif is_mirror(cell) then
      new_cell = LASER_V_SPLIT
      use_tool(TOOL_SPLIT)
      restore_tool(TOOL_MIRROR)
    else
      new_cell = EMPTY
      restore_tool(TOOL_SPLIT)
    end
  else
    if cell == EMPTY then
      use_tool(TOOL_MIRROR)
      new_cell = LASER_V
    elseif cell == LASER_V then
      new_cell = LASER_DA
    elseif cell == LASER_DA then
      new_cell = LASER_H
    elseif cell == LASER_H then
      new_cell = LASER_DB
    elseif is_splitter(cell) then
      new_cell = LASER_V
      use_tool(TOOL_MIRROR)
      restore_tool(TOOL_SPLIT)
    else
      new_cell = EMPTY
      restore_tool(TOOL_MIRROR)
    end
  end

  field[gy][gx] = new_cell
end

function is_tool(cell)
  return cell != EMPTY and cell != LASER_EMIT
end

function is_splitter(cell)
  return cell == LASER_V_SPLIT or cell == LASER_H_SPLIT or cell == LASER_D_SPLIT_A
end

function get_cell(gx, gy)
  if gy > 0 and gy <= #field and gx > 0 and gx <= #field[1] then
    return field[gy][gx]
  end

  return nil
end

function reflect(dx, dy, cell)
  if cell == LASER_BLOCK or cell == LASER_EMIT then
    return {{0,0}}
  end

  if cell == LASER_V then
    if dx == 0 then
      return {{0,0}}
    end
    return {{dx * -1, dy}}
  elseif cell == LASER_H then
    if dy == 0 then
      return {{0,0}}
    end
    return {{dx, dy * -1}}
  elseif cell == LASER_DA then
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
  elseif cell == LASER_DB then
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
  elseif cell == LASER_V_SPLIT then
    if dx == 0 then
      return {{0,0}}
    end
    return {{0,-1}, {0,1}}
  elseif cell == LASER_H_SPLIT then
    if dy == 0 then
      return {{0,0}}
    end
    return {{-1,0}, {1,0}}
  elseif cell == LASER_D_SPLIT_A then
    if (dx != 0 and dy == 0) or (dx == 0 and dy != 0) or (dx != dy) then
      return {{-1, -1}, {1,1}}
    end
    return {{0,0}}
  elseif cell == LASER_D_SPLIT_B then
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
  local ox,oy = unpack(FIELD_OFFSET)
  for i, row in ipairs(field) do
    for j, cell in ipairs(row) do
      local left = (j+ox-1)*T_SIZE
      local top = (i+oy-1)*T_SIZE
      local sprite = LASER_SPRITES[cell]
      if sprite then
        spr(sprite, left, top)
      end
      if j == gx and i == gy then
        rect(left,top,left+T_SIZE,top+T_SIZE,12)
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
    local sprites = TARGET_SPRITES[target.sprites]
    spr(target.is_active and sprites[2] or sprites[1], x, y)
  end
end

function update_ui()
  if not input.lmb.just_pressed then
    return
  end

  local mx, my = unpack(input.cursor)
  local tx, ty = unpack(TOOL_UI_OFFSET)
  local gx, gy = unpack(pos_to_grid(mx, my))

  for i, tool in ipairs(tools) do
    local x, y = (i-1+tx) * T_SIZE, ty * T_SIZE
    local tool_gx, tool_gy = unpack(pos_to_grid(x,y))

    if tool_gx == gx and tool_gy == gy then
      if tool.type == TOOL_RESET then
        load_level(level)
      else
        selected_tool = tool.type
      end
    end
  end
end

function draw_ui()
  local mx,my = unpack(input.cursor)
  local tx, ty = unpack(TOOL_UI_OFFSET)
  local gx, gy = unpack(pos_to_grid(mx, my))

  for i, tool in ipairs(tools) do
    if tool.type != EMPTY then
      local x, y = (i-1+tx) * T_SIZE, ty * T_SIZE
      local tool_gx, tool_gy = unpack(pos_to_grid(x,y))
      local text = tool.type == TOOL_RESET and "r" or tostr(tool.max - tool.current)
      local text_color = text == "r" and 8 or 7

      print(text, x + T_SIZE/2 - 2, y - T_SIZE/2 - 2, text_color)

      spr(TOOL_SPRITES[tool.type], x, y)

      if selected_tool == tool.type then
        rect(x, y, x + T_SIZE - 1, y + T_SIZE, 7)
      end

      if tool_gx == gx and tool_gy == gy then
        rect(x, y, x + T_SIZE - 1, y + T_SIZE, 12)
      end
    end
  end

  spr(CURSOR_SPRITE, mx-1, my-1)
end

function is_mirror(cell)
  return cell == LASER_V or cell == LASER_H or cell == LASER_DA or cell == LASER_DB
end

function is_splitter(cell)
  return cell == LASER_V_SPLIT or cell == LASER_H_SPLIT or cell == LASER_D_SPLIT_A or cell == LASER_D_SPLIT_B
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
  return {flr(x/T_SIZE) - FIELD_OFFSET[1] + 1, flr(y/T_SIZE) - FIELD_OFFSET[2] + 1}
end

function grid_to_pos(c, r)
  return {(c + FIELD_OFFSET[1] - 1) * T_SIZE, (r + FIELD_OFFSET[2] - 1) * T_SIZE}
end

function join_str(...)
  local args = {...}
  local result = EMPTY
  for i, v in pairs(args) do
    result = result .. tostr(v) .. (i < #args and ":" or EMPTY)
  end

  return result
end

levels = {
  {
    name = "First Reflection",
    field = {
      {type = LASER_EMIT, fx = 1, fy = 5, dx = 1, dy = 0},
      {type = LASER_TARGET, sprites = "test", fx = 5, fy = 1}
    },
    tools = { 
      {type = TOOL_MIRROR, max = 3},
      {type = TOOL_SPLIT, max = 0}
    },
    par = 2
  },
  {
    name = "Around the Corner",
    field = {
      {type = LASER_EMIT, fx = 1, fy = 1, dx = 1, dy = 0},
      {type = LASER_BLOCK, fx = 6, fy = 1},
      {type = LASER_TARGET, sprites = "test", fx = 9, fy = 5}
    },
    tools = { 
      {type = TOOL_MIRROR, max = 4},
      {type = TOOL_SPLIT, max = 0}
    },
    par = 3
  },
  {
    name = "Double Bend",
    field = {
      {type = LASER_EMIT, fx = 1, fy = 1, dx = 1, dy = 0},
      {type = LASER_BLOCK, fx = 6, fy = 1},
      {type = LASER_TARGET, sprites = "test", fx = 5, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 9, fy = 5}
    },
    tools = { 
      {type = TOOL_MIRROR, max = 5},
      {type = TOOL_SPLIT, max = 0}
    },
    par = 4
  },
  {
    name = "Through the Gap",
    field = {
      {type = LASER_EMIT, fx = 1, fy = 1, dx = 1, dy = 0},
      {type = LASER_BLOCK, fx = 5, fy = 1},
      {type = LASER_BLOCK, fx = 5, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 9, fy = 3},
      {type = LASER_TARGET, sprites = "test", fx = 9, fy = 7}
    },
    tools = { 
      {type = TOOL_MIRROR, max = 5},
      {type = TOOL_SPLIT, max = 0}
    },
    par = 4
  },
  {
    name = "Level 5",
    field = {
      { type = LASER_EMIT, fx = 1, fy = 2, dx = 1, dy = 0 },
      { type = LASER_EMIT, fx = 5, fy = 1, dx = 0, dy = 1 },
      { type = LASER_BLOCK, sprites = "test", fx = 9, fy = 2},
      { type = LASER_TARGET, sprites = "test", fx = 7, fy = 9},
      { type = LASER_TARGET, sprites = "test", fx = 9, fy = 9},
      { type = LASER_BLOCK, sprites = "test", fx = 8, fy = 9},
      { type = LASER_BLOCK, sprites = "test", fx = 8, fy = 10},
      },
    tools = {{type = TOOL_MIRROR, max = 6}},
    par = 4
  },
  {
    name = "Level 6",
    field = {
      { type = LASER_EMIT, fx = 5, fy = 5, dx = -1, dy = -1 },
      { type = LASER_EMIT, fx = 6, fy = 6, dx = 1, dy = 1 },
      { type = LASER_BLOCK, sprites = "test", fx = 5, fy = 4},
      { type = LASER_BLOCK, sprites = "test", fx = 7, fy = 6},
      { type = LASER_BLOCK, sprites = "test", fx = 5, fy = 7},
      { type = LASER_BLOCK, sprites = "test", fx = 5, fy = 6},
      { type = LASER_TARGET, sprites = "test", fx = 6, fy = 4},
      { type = LASER_TARGET, sprites = "test", fx = 5, fy = 7},
      },
    tools = {{type = TOOL_MIRROR, max = 6}},
    par = 5
  },
  {
    name = "Double Beam Maze",
    field = {
      {type = LASER_EMIT, fx = 1, fy = 3, dx = 1, dy = 0},   -- East emitter
      {type = LASER_EMIT, fx = 10, fy = 7, dx = -1, dy = 0}, -- West emitter
      {type = LASER_BLOCK, fx = 5, fy = 3},
      {type = LASER_BLOCK, fx = 5, fy = 7},
      {type = LASER_TARGET, sprites = "test", fx = 3, fy = 1},
      {type = LASER_TARGET, sprites = "test", fx = 7, fy = 10}
    },
    tools = { 
      {type = TOOL_MIRROR, max = 5},  -- Optimal: 4, Par: 5, Max: 6 total
      {type = TOOL_SPLIT, max = 1}
    },
    par = 5
  },
  {
    name = "Triple Target",
    field = {
      {type = LASER_EMIT, fx = 1, fy = 5, dx = 1, dy = 0},
      {type = LASER_BLOCK, fx = 4, fy = 2},
      {type = LASER_BLOCK, fx = 4, fy = 8},
      {type = LASER_TARGET, sprites = "test", fx = 8, fy = 2},
      {type = LASER_TARGET, sprites = "test", fx = 8, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 8, fy = 8}
    },
    tools = {
      {type = TOOL_MIRROR, max = 6},
      {type = TOOL_SPLIT, max = 0}
    },
    par = 5
  },
  {
    name = "Cross Fire",
    field = {
      {type = LASER_EMIT, fx = 1, fy = 5, dx = 1, dy = 0},
      {type = LASER_EMIT, fx = 5, fy = 1, dx = 0, dy = 1},
      {type = LASER_BLOCK, fx = 5, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 9, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 5, fy = 9},
      {type = LASER_TARGET, sprites = "test", fx = 1, fy = 1}
    },
    tools = {
      {type = TOOL_MIRROR, max = 7},
      {type = TOOL_SPLIT, max = 0}
    },
    par = 6
  },
  {
    name = "Diagonal Dance",
    field = {
      {type = LASER_EMIT, fx = 2, fy = 2, dx = 1, dy = 1},
      {type = LASER_BLOCK, fx = 5, fy = 5},
      {type = LASER_BLOCK, fx = 6, fy = 6},
      {type = LASER_TARGET, sprites = "test", fx = 9, fy = 2},
      {type = LASER_TARGET, sprites = "test", fx = 2, fy = 9},
      {type = LASER_TARGET, sprites = "test", fx = 9, fy = 9}
    },
    tools = {
      {type = TOOL_MIRROR, max = 8},
      {type = TOOL_SPLIT, max = 0}
    },
    par = 6
  },
  {
    name = "First Split",
    field = {
      {type = LASER_EMIT, fx = 5, fy = 1, dx = 0, dy = 1},
      {type = LASER_TARGET, sprites = "test", fx = 3, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 7, fy = 5}
    },
    tools = {
      {type = TOOL_MIRROR, max = 2},
      {type = TOOL_SPLIT, max = 1}
    },
    par = 3
  },
  {
    name = "Split Path",
    field = {
      {type = LASER_EMIT, fx = 1, fy = 3, dx = 1, dy = 0},
      {type = LASER_BLOCK, fx = 5, fy = 3},
      {type = LASER_TARGET, sprites = "test", fx = 9, fy = 1},
      {type = LASER_TARGET, sprites = "test", fx = 9, fy = 5}
    },
    tools = {
      {type = TOOL_MIRROR, max = 3},
      {type = TOOL_SPLIT, max = 1}
    },
    par = 4
  },
  {
    name = "Four Corners",
    field = {
      {type = LASER_EMIT, fx = 5, fy = 5, dx = 1, dy = 0},
      {type = LASER_TARGET, sprites = "test", fx = 2, fy = 2},
      {type = LASER_TARGET, sprites = "test", fx = 8, fy = 2},
      {type = LASER_TARGET, sprites = "test", fx = 2, fy = 8},
      {type = LASER_TARGET, sprites = "test", fx = 8, fy = 8}
    },
    tools = {
      {type = TOOL_MIRROR, max = 4},
      {type = TOOL_SPLIT, max = 2}
    },
    par = 5
  },
  {
    name = "Split Maze",
    field = {
      {type = LASER_EMIT, fx = 1, fy = 1, dx = 1, dy = 0},
      {type = LASER_EMIT, fx = 10, fy = 10, dx = -1, dy = 0},
      {type = LASER_BLOCK, fx = 5, fy = 1},
      {type = LASER_BLOCK, fx = 6, fy = 10},
      {type = LASER_TARGET, sprites = "test", fx = 3, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 7, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 10, fy = 5}
    },
    tools = {
      {type = TOOL_MIRROR, max = 5},
      {type = TOOL_SPLIT, max = 2}
    },
    par = 6
  },
  {
    name = "Double Split",
    field = {
      {type = LASER_EMIT, fx = 5, fy = 1, dx = 0, dy = 1},
      {type = LASER_BLOCK, fx = 1, fy = 5},
      {type = LASER_BLOCK, fx = 9, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 3, fy = 3},
      {type = LASER_TARGET, sprites = "test", fx = 7, fy = 3},
      {type = LASER_TARGET, sprites = "test", fx = 3, fy = 7},
      {type = LASER_TARGET, sprites = "test", fx = 7, fy = 7}
    },
    tools = {
      {type = TOOL_MIRROR, max = 4},
      {type = TOOL_SPLIT, max = 3}
    },
    par = 6
  },
  {
    name = "Cascade",
    field = {
      {type = LASER_EMIT, fx = 1, fy = 2, dx = 1, dy = 0},
      {type = LASER_EMIT, fx = 1, fy = 8, dx = 1, dy = 0},
      {type = LASER_BLOCK, fx = 4, fy = 2},
      {type = LASER_BLOCK, fx = 4, fy = 8},
      {type = LASER_BLOCK, fx = 7, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 10, fy = 2},
      {type = LASER_TARGET, sprites = "test", fx = 10, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 10, fy = 8}
    },
    tools = {
      {type = TOOL_MIRROR, max = 6},
      {type = TOOL_SPLIT, max = 2}
    },
    par = 7
  },
  {
    name = "Star Pattern",
    field = {
      {type = LASER_EMIT, fx = 5, fy = 5, dx = 1, dy = 0},
      {type = LASER_TARGET, sprites = "test", fx = 1, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 9, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 5, fy = 1},
      {type = LASER_TARGET, sprites = "test", fx = 5, fy = 9}
    },
    tools = {
      {type = TOOL_MIRROR, max = 3},
      {type = TOOL_SPLIT, max = 3}
    },
    par = 6
  },
  {
    name = "Diagonal Split",
    field = {
      {type = LASER_EMIT, fx = 3, fy = 3, dx = 1, dy = 1},
      {type = LASER_BLOCK, fx = 6, fy = 6},
      {type = LASER_TARGET, sprites = "test", fx = 1, fy = 7},
      {type = LASER_TARGET, sprites = "test", fx = 7, fy = 1},
      {type = LASER_TARGET, sprites = "test", fx = 9, fy = 9}
    },
    tools = {
      {type = TOOL_MIRROR, max = 5},
      {type = TOOL_SPLIT, max = 2}
    },
    par = 6
  },
  {
    name = "Grid Lock",
    field = {
      {type = LASER_EMIT, fx = 1, fy = 1, dx = 1, dy = 0},
      {type = LASER_BLOCK, fx = 3, fy = 3},
      {type = LASER_BLOCK, fx = 7, fy = 3},
      {type = LASER_BLOCK, fx = 3, fy = 7},
      {type = LASER_BLOCK, fx = 7, fy = 7},
      {type = LASER_BLOCK, fx = 5, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 2, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 8, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 5, fy = 2},
      {type = LASER_TARGET, sprites = "test", fx = 5, fy = 8}
    },
    tools = {
      {type = TOOL_MIRROR, max = 7},
      {type = TOOL_SPLIT, max = 3}
    },
    par = 8
  },
  {
    name = "Triple Emitter",
    field = {
      {type = LASER_EMIT, fx = 1, fy = 3, dx = 1, dy = 0},
      {type = LASER_EMIT, fx = 5, fy = 1, dx = 0, dy = 1},
      {type = LASER_EMIT, fx = 10, fy = 7, dx = -1, dy = 0},
      {type = LASER_BLOCK, fx = 5, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 9, fy = 3},
      {type = LASER_TARGET, sprites = "test", fx = 5, fy = 9},
      {type = LASER_TARGET, sprites = "test", fx = 1, fy = 7},
      {type = LASER_TARGET, sprites = "test", fx = 3, fy = 1}
    },
    tools = {
      {type = TOOL_MIRROR, max = 6},
      {type = TOOL_SPLIT, max = 3}
    },
    par = 8
  },
  {
    name = "Reflection Pool",
    field = {
      {type = LASER_EMIT, fx = 1, fy = 5, dx = 1, dy = 0},
      {type = LASER_EMIT, fx = 10, fy = 5, dx = -1, dy = 0},
      {type = LASER_BLOCK, fx = 3, fy = 3},
      {type = LASER_BLOCK, fx = 7, fy = 3},
      {type = LASER_BLOCK, fx = 3, fy = 7},
      {type = LASER_BLOCK, fx = 7, fy = 7},
      {type = LASER_TARGET, sprites = "test", fx = 5, fy = 1},
      {type = LASER_TARGET, sprites = "test", fx = 5, fy = 9},
      {type = LASER_TARGET, sprites = "test", fx = 1, fy = 1},
      {type = LASER_TARGET, sprites = "test", fx = 10, fy = 1},
      {type = LASER_TARGET, sprites = "test", fx = 1, fy = 9},
      {type = LASER_TARGET, sprites = "test", fx = 10, fy = 9}
    },
    tools = {
      {type = TOOL_MIRROR, max = 8},
      {type = TOOL_SPLIT, max = 4}
    },
    par = 10
  },
  {
    name = "Spiral",
    field = {
      {type = LASER_EMIT, fx = 5, fy = 5, dx = 1, dy = 0},
      {type = LASER_BLOCK, fx = 4, fy = 4},
      {type = LASER_BLOCK, fx = 6, fy = 4},
      {type = LASER_BLOCK, fx = 4, fy = 6},
      {type = LASER_BLOCK, fx = 6, fy = 6},
      {type = LASER_TARGET, sprites = "test", fx = 2, fy = 2},
      {type = LASER_TARGET, sprites = "test", fx = 8, fy = 2},
      {type = LASER_TARGET, sprites = "test", fx = 2, fy = 8},
      {type = LASER_TARGET, sprites = "test", fx = 8, fy = 8},
      {type = LASER_TARGET, sprites = "test", fx = 5, fy = 1}
    },
    tools = {
      {type = TOOL_MIRROR, max = 8},
      {type = TOOL_SPLIT, max = 4}
    },
    par = 10
  },
  {
    name = "Labyrinth",
    field = {
      {type = LASER_EMIT, fx = 1, fy = 1, dx = 1, dy = 0},
      {type = LASER_EMIT, fx = 10, fy = 10, dx = -1, dy = 0},
      {type = LASER_BLOCK, fx = 3, fy = 2},
      {type = LASER_BLOCK, fx = 7, fy = 2},
      {type = LASER_BLOCK, fx = 5, fy = 4},
      {type = LASER_BLOCK, fx = 3, fy = 6},
      {type = LASER_BLOCK, fx = 7, fy = 6},
      {type = LASER_BLOCK, fx = 5, fy = 8},
      {type = LASER_TARGET, sprites = "test", fx = 1, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 10, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 5, fy = 1},
      {type = LASER_TARGET, sprites = "test", fx = 5, fy = 10},
      {type = LASER_TARGET, sprites = "test", fx = 3, fy = 3},
      {type = LASER_TARGET, sprites = "test", fx = 7, fy = 7}
    },
    tools = {
      {type = TOOL_MIRROR, max = 9},
      {type = TOOL_SPLIT, max = 5}
    },
    par = 11
  },
  {
    name = "Chamber",
    field = {
      {type = LASER_EMIT, fx = 5, fy = 1, dx = 0, dy = 1},
      {type = LASER_EMIT, fx = 1, fy = 5, dx = 1, dy = 0},
      {type = LASER_BLOCK, fx = 2, fy = 2},
      {type = LASER_BLOCK, fx = 8, fy = 2},
      {type = LASER_BLOCK, fx = 2, fy = 8},
      {type = LASER_BLOCK, fx = 8, fy = 8},
      {type = LASER_BLOCK, fx = 5, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 1, fy = 1},
      {type = LASER_TARGET, sprites = "test", fx = 10, fy = 1},
      {type = LASER_TARGET, sprites = "test", fx = 1, fy = 10},
      {type = LASER_TARGET, sprites = "test", fx = 10, fy = 10},
      {type = LASER_TARGET, sprites = "test", fx = 4, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 6, fy = 5}
    },
    tools = {
      {type = TOOL_MIRROR, max = 10},
      {type = TOOL_SPLIT, max = 5}
    },
    par = 12
  },
  {
    name = "Nexus",
    field = {
      {type = LASER_EMIT, fx = 5, fy = 5, dx = 1, dy = 0},
      {type = LASER_EMIT, fx = 5, fy = 5, dx = 0, dy = 1},
      {type = LASER_BLOCK, fx = 3, fy = 3},
      {type = LASER_BLOCK, fx = 7, fy = 3},
      {type = LASER_BLOCK, fx = 3, fy = 7},
      {type = LASER_BLOCK, fx = 7, fy = 7},
      {type = LASER_TARGET, sprites = "test", fx = 1, fy = 3},
      {type = LASER_TARGET, sprites = "test", fx = 9, fy = 3},
      {type = LASER_TARGET, sprites = "test", fx = 1, fy = 7},
      {type = LASER_TARGET, sprites = "test", fx = 9, fy = 7},
      {type = LASER_TARGET, sprites = "test", fx = 3, fy = 1},
      {type = LASER_TARGET, sprites = "test", fx = 7, fy = 1},
      {type = LASER_TARGET, sprites = "test", fx = 3, fy = 9},
      {type = LASER_TARGET, sprites = "test", fx = 7, fy = 9}
    },
    tools = {
      {type = TOOL_MIRROR, max = 10},
      {type = TOOL_SPLIT, max = 6}
    },
    par = 13
  },
  {
    name = "Master Puzzle",
    field = {
      {type = LASER_EMIT, fx = 1, fy = 1, dx = 1, dy = 0},
      {type = LASER_EMIT, fx = 10, fy = 1, dx = 0, dy = 1},
      {type = LASER_EMIT, fx = 1, fy = 10, dx = 1, dy = 0},
      {type = LASER_EMIT, fx = 10, fy = 10, dx = -1, dy = 0},
      {type = LASER_BLOCK, fx = 3, fy = 3},
      {type = LASER_BLOCK, fx = 7, fy = 3},
      {type = LASER_BLOCK, fx = 5, fy = 5},
      {type = LASER_BLOCK, fx = 3, fy = 7},
      {type = LASER_BLOCK, fx = 7, fy = 7},
      {type = LASER_TARGET, sprites = "test", fx = 2, fy = 2},
      {type = LASER_TARGET, sprites = "test", fx = 8, fy = 2},
      {type = LASER_TARGET, sprites = "test", fx = 2, fy = 8},
      {type = LASER_TARGET, sprites = "test", fx = 8, fy = 8},
      {type = LASER_TARGET, sprites = "test", fx = 5, fy = 2},
      {type = LASER_TARGET, sprites = "test", fx = 5, fy = 8},
      {type = LASER_TARGET, sprites = "test", fx = 2, fy = 5},
      {type = LASER_TARGET, sprites = "test", fx = 8, fy = 5}
    },
    tools = {
      {type = TOOL_MIRROR, max = 12},
      {type = TOOL_SPLIT, max = 6}
    },
    par = 15
  },
  }

__gfx__
00000000000000001111111110000000111111111000000000000000000000000000000000000000000000000000000000000000000000000777777070707007
00000000011111101000000010000000000000000000000000000000000000000000000000000000000000000000000000000000070707707070707707777770
00700700011001101000000010000000000000000000000000000000000000000000000000000000000000000000000000000000070000007707770707700777
00077000010110101000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000707077777777077070
00077000010110101000000010000000000000000000000000000000000000000000000000000000000000000000000000000000070000007777770707077077
00700700011001101000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000707077707777700770
00000000011111101000000010000000000000000000000000000000000000000000000000000000000000000000000000000000077070707707070707777770
00000000000000001000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000777777070070707
05577550000cc00000000000cc000000000000cc0660066000555500000000000550000000000550111111110000000000000000000005880000000000000000
55688655000cc00000000000ccc0000000000ccc6556655600555500000000005550000000000555111111110000000000000000000055580000000000000000
56688665000cc000000000000ccc00000000ccc065755756000c50005505505555c5500000055c5511d111d10000000000000000000555550005500000000000
57888875000cc000cccccccc00ccc000000ccc0006577560005cc500555ccc55005cc500005cc500111d1d110000000000000000005885000058850000000000
57888875000cc000cccccccc000ccc0000ccc00006577560005cc50055ccc555005cc500005cc5001111d1110000000000000000005885000558855000000000
56688665000cc000000000000000ccc00ccc0000657557560005c0005505505500055c5555c55000111d1d110000000000000000000555555555555500000000
55688655000cc0000000000000000cccccc00000655665560055550000000000000005555550000011d111d10000000000000000000055588550055800000000
05577550000cc00000000000000000cccc0000000660066000555500000000000000055005500000111111110000000000000000000005888850058800000000
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
