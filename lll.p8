pico-8 cartridge // http://www.pico-8.com
version 42
__lua__

-- constants --

EMPTY = ""
T_SIZE = 8
FIELD_SIZE = {10,10}
FIELD_OFFSET = {3,3}
TOOL_UI_OFFSET = {7,14}

SFX_UI_HOVER = 0
SFX_UI_SELECT = 1
SFX_PLACE_TOOL = 2
SFX_REMOVE_TOOL = 3
SFX_LEVEL_COMPLETE = 4

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
TOOL_MENU = "MENU"
TOOL_MIRROR = "MIRROR"
TOOL_SPLIT = "SPLIT"
TOOL_BLOCK = "BLOCK"
TOOL_TARGET = "TARGET"
TOOL_EMIT = "EMIT"

CURSOR_SPRITE = 32
STAR_FILL_SPRITE = 48
STAR_SPRITE = 49

-- emitter sprite IDs (counter-clockwise from north)
LASER_EMIT_N = 40
LASER_EMIT_NW = 41
LASER_EMIT_W = 42
LASER_EMIT_SW = 43
LASER_EMIT_S = 44
LASER_EMIT_SE = 45
LASER_EMIT_E = 46
LASER_EMIT_NE = 47

STATE_MENU = 0
STATE_LEVEL_SELECT = 1
STATE_PLAYING = 2
STATE_LEVEL_COMPLETE = 3
STATE_WIN = 4
STATE_LEVEL_EDIT = 5

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
    [TOOL_MENU] = 34,
    [TOOL_MIRROR] = 17,
    [TOOL_SPLIT] = 22,
    [TOOL_BLOCK] = 26,
    [TOOL_TARGET] = 50,
    [TOOL_EMIT] = 16
  }

TARGET_SPRITES = {51,52,53,54,55,56}

-- globals --

current_state = STATE_MENU
current_level = 1
selected_menu_option = 1
prev_menu_option = 1
preview_level = 1

field = {}
targets = {}
tools = {}

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
      },
    rmb = {
        just_pressed = false,
        was_pressed = false,
        down = false
      },
    x = false,
    o = false
  }

-- methods --

function get_level(index)
  return new_levels[index]
end

function get_level_count()
  return #new_levels
end

function _init()
  poke(0x5f2d, 1)
  if current_state == STATE_LEVEL_EDIT then
    load_level(init_empty_level())
  else
    load_level(get_level(current_level))
  end
end

function _update()
  update_input()
  if current_state == STATE_MENU then
    update_menu()
  elseif current_state == STATE_PLAYING then
    update_playing()
    if check_win() then
      sfx(SFX_LEVEL_COMPLETE)
      current_state = STATE_LEVEL_COMPLETE
    end
  elseif current_state == STATE_LEVEL_COMPLETE then
    update_level_complete()
  elseif current_state == STATE_WIN then
    update_win()
  elseif current_state == STATE_LEVEL_EDIT then
    update_playing()
  elseif current_state == STATE_LEVEL_SELECT then
    update_level_select()
  end
end

function update_playing()
  if input.lmb.just_pressed then
    local mx,my = unpack(input.cursor)
    local gx,gy = unpack(pos_to_grid(mx,my))
    toggle_cell(gx, gy)
  end

  if input.rmb.just_pressed then
    local mx,my = unpack(input.cursor)
    local gx,gy = unpack(pos_to_grid(mx,my))
    clear_cell(gx, gy)
  end

  update_lasers()
  update_targets()
  update_ui()
end

function update_level_complete()
  if input.x or input.o then
    sfx(SFX_UI_SELECT)
    if input.x and current_level == get_level_count() then
      current_state = STATE_WIN
    else
      current_level = input.x and current_level + 1 or current_level
      load_level(get_level(current_level))
      current_state = STATE_PLAYING
    end
  end
end

function update_win()
  if input.o then
    sfx(SFX_UI_SELECT)
    current_level = 1
    selected_tool = EMPTY
    load_level(get_level(current_level))
    current_state = STATE_PLAYING
  end

  for y = 5, 11, 5 do
    for x = 18, 29, 1 do
      mset(x,y,rnd(TARGET_SPRITES))
    end
  end
  for x = 18, 30, 11 do
    for y = 6, 9, 1 do
      mset(x,y,rnd(TARGET_SPRITES))
    end
  end
end

function update_menu()
  if input.lmb.just_pressed then
    local mx, my = unpack(input.cursor)

    if selected_menu_option == 1 then
      sfx(SFX_UI_SELECT)
      current_level = 1
      current_state = STATE_PLAYING
      load_level(get_level(current_level))
    elseif selected_menu_option == 2 then
      sfx(SFX_UI_SELECT)
      preview_level = current_level
      load_level(get_level(preview_level))
      current_state = STATE_LEVEL_SELECT
    elseif selected_menu_option == 3 then
      sfx(SFX_UI_SELECT)
      current_state = STATE_LEVEL_EDIT
      load_level(init_empty_level())
    end
  end

  local mx, my = unpack(input.cursor)
  local menu_y = 53
  local spacing = 14

  for i = 1, 3 do
    local y = menu_y + (i - 1) * spacing
    if my >= y and my < y + 8 then
      if selected_menu_option != i then
        sfx(SFX_UI_HOVER)
        selected_menu_option = i
      end
    end
  end

  prev_menu_option = selected_menu_option
end

function update_level_select()
  update_lasers()
  update_targets()

  if input.lmb.just_pressed then
    local mx, my = unpack(input.cursor)

    if mx >= 4 and mx < 12 and my >= 60 and my < 68 then
      if preview_level > 1 then
        sfx(SFX_UI_SELECT)
        preview_level = preview_level - 1
        load_level(get_level(preview_level))
      end
    end

    if mx >= 116 and mx < 124 and my >= 60 and my < 68 then
      if preview_level < get_level_count() then
        sfx(SFX_UI_SELECT)
        preview_level = preview_level + 1
        load_level(get_level(preview_level))
      end
    end

    if mx >= 52 and mx < 76 and my >= 54 and my < 70 then
      sfx(SFX_UI_SELECT)
      current_level = preview_level
      current_state = STATE_PLAYING
      load_level(get_level(current_level))
    end

    if mx >= 52 and mx < 76 and my >= 2 and my < 10 then
      sfx(SFX_UI_SELECT)
      field = {}
      targets = {}
      laser_plot = {}
      laser_plot_tool_chain = {}
      current_state = STATE_MENU
      selected_menu_option = 1
    end
  end
end

function draw_menu()
  map(32, 0, 0, 0)
  local menu_options = {"play", "level select", "playground"}
  local menu_y = 53
  local spacing = 14

  print("laser light logic", 26, 24, 7)

  for i, option in ipairs(menu_options) do
    local y = menu_y + (i - 1) * spacing
    local color = selected_menu_option == i and 12 or 7
    print(option, 44, y, color)
  end

  spr(CURSOR_SPRITE, stat(32)-1, stat(33)-1)
end

function _draw()
	cls()

  if current_state == STATE_MENU then
    draw_menu()
  elseif current_state == STATE_PLAYING then
    draw_playing()
  elseif current_state == STATE_LEVEL_COMPLETE then
    draw_playing()
    draw_level_complete()
  elseif current_state == STATE_WIN then
    draw_win()
  elseif current_state == STATE_LEVEL_EDIT then
    draw_playing()
  elseif current_state == STATE_LEVEL_SELECT then
    draw_level_select()
  end
end

function draw_playing()
	draw_field()
  draw_laser()
  draw_targets()
  draw_ui()
end

function draw_win()
  map(16, 0, 0, 0)
  local ox, oy = T_SIZE, T_SIZE
  print("thanks for playing", 28, 54)
	print("🅾️ restart", 44, 70)
end

function draw_level_select()
  draw_field()
  draw_laser()
  draw_targets()

  local mx, my = unpack(input.cursor)

  local back_hover = mx >= 52 and mx < 76 and my >= 2 and my < 10
  local left_hover = mx >= 4 and mx < 12 and my >= 60 and my < 68
  local right_hover = mx >= 116 and mx < 124 and my >= 60 and my < 68
  local play_hover = mx >= 52 and mx < 76 and my >= 54 and my < 70

  rectfill(52, 2, 76, 10, back_hover and 2 or 1)
  rect(52, 2, 76, 10, back_hover and 12 or 7)
  print("back", 57, 4, 7)

  if preview_level > 1 then
    rectfill(4, 60, 12, 68, left_hover and 9 or 8)
    rect(4, 60, 12, 68, left_hover and 12 or 7)
    print("<", 7, 62, 7)
  end

  if preview_level < get_level_count() then
    rectfill(116, 60, 124, 68, right_hover and 9 or 8)
    rect(116, 60, 124, 68, right_hover and 12 or 7)
    print(">", 119, 62, 7)
  end

  rectfill(52, 54, 76, 70, play_hover and 12 or 11)
  rect(52, 54, 76, 70, play_hover and 12 or 7)
  print("play", 57, 60, 7)

  print("level "..tostr(preview_level), 48, 46, 7)

  spr(CURSOR_SPRITE, mx-1, my-1)
end


function new_field()
  local w,h = unpack(FIELD_SIZE)
  local f = {}

  for i = 1, h do
    local r = {}
    for j = 1, w do
      r[j] = EMPTY
    end
    f[i] = r
  end

  return f
end

function init_empty_level()
  return {
    name = "editor",
    field = {},
    tools = {},
    par = 0
  }
end

function load_level(level_data)
  targets = {}
  tools = {}
  field = new_field()

  -- emitter direction mapping (counter-clockwise from north)
  local emit_dirs = {
    [LASER_EMIT_N] = {0, -1},   -- north
    [LASER_EMIT_NW] = {-1, -1},  -- northwest
    [LASER_EMIT_W] = {-1, 0},   -- west
    [LASER_EMIT_SW] = {-1, 1},   -- southwest
    [LASER_EMIT_S] = {0, 1},    -- south
    [LASER_EMIT_SE] = {1, 1},    -- southeast
    [LASER_EMIT_E] = {1, 0},    -- east
    [LASER_EMIT_NE] = {1, -1}    -- northeast
  }

  -- read from map if map coordinates are provided
  if level_data.map_x and level_data.map_y then
    level_data.field = {}

    for fy = 1, 10 do
      for fx = 1, 10 do
        local tile_id = mget(level_data.map_x + fx - 1, level_data.map_y + fy - 1)
        local obj = nil

        if tile_id >= LASER_EMIT_N and tile_id <= LASER_EMIT_NE then
          -- laser emitter
          local dx, dy = unpack(emit_dirs[tile_id])
          obj = {type = LASER_EMIT, fx = fx, fy = fy, dx = dx, dy = dy}
        elseif tile_id == 50 then
          -- target
          obj = {type = LASER_TARGET, fx = fx, fy = fy}
          targets[join_str(fx, fy)] = {
            fx = fx,
            fy = fy,
            is_active = false
          }
        elseif tile_id > 0 then
          -- block
          obj = {type = LASER_BLOCK, fx = fx, fy = fy}
        end

        if obj then
          field[fy][fx] = obj
          add(level_data.field, obj)
        end
      end
    end
  else
    -- use existing field data for old-style levels
    for _, obj in ipairs(level_data.field) do
      field[obj.fy][obj.fx] = obj

      if obj.type == LASER_TARGET then
        targets[join_str(obj.fx, obj.fy)] = {
          fx = obj.fx,
          fy = obj.fy,
          is_active = false
        }
      end
    end
  end

  -- tools is now a simple array of tool types (no max counts)
  for _, tool_data in ipairs(level_data.tools) do
    -- support both old format {type = ..., max = ...} and new format (just the type string)
    local tool_type = type(tool_data) == "table" and tool_data.type or tool_data
    add(tools, tool_type)
  end

  if current_state == STATE_LEVEL_EDIT then
    add(tools, TOOL_MIRROR)
    add(tools, TOOL_SPLIT)
    add(tools, TOOL_BLOCK)
    add(tools, TOOL_TARGET)
    add(tools, TOOL_EMIT)
  end

  add(tools, EMPTY)
  add(tools, TOOL_RESET)
  add(tools, TOOL_MENU)

  selected_tool = selected_tool == EMPTY and tools[1] or selected_tool

  level = level_data
end

function update_input()
  local mb = stat(34)
  input.cursor = {stat(32)-1, stat(33)-1}
  input.lmb.down = mb & 1 != 0
  input.rmb.down = mb & 2 != 0

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

  if input.rmb.down then
    if not input.rmb.was_pressed then
      input.rmb.just_pressed = true
      input.rmb.was_pressed = true
    else
      input.rmb.just_pressed = false
    end
  else
    input.rmb.just_pressed = false
    input.rmb.was_pressed = false
  end

  input.o = btn(4)
  input.x = btn(5)
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

function get_star_rating()
  local par = get_level(current_level).par
  local tools_used = 0

  for i, row in ipairs(field) do
    for j, cell in ipairs(row) do
      if is_tool(cell) then
        tools_used = tools_used + 1
      end
    end
  end

  if tools_used > par then
    return 1
  elseif tools_used == par then
    return 2
  elseif tools_used > 0 and tools_used < par then
    return 3
  else
    return 0
  end
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
  if c != EMPTY and c != nil then
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
  if cell == nil or selected_tool == EMPTY then
    return
  end

  local t = type(cell) == "table" and cell.type or cell

  if current_state == STATE_PLAYING then
    if t == LASER_BLOCK or t == LASER_EMIT or t == LASER_TARGET then
      return
    end
  end

  local new_cell = EMPTY
  local did_action = false

  if selected_tool == TOOL_SPLIT then
    if cell == EMPTY then
      new_cell = {type=LASER_V_SPLIT, fx=gx, fy=gy}
      did_action = true
    elseif t == LASER_V_SPLIT then
      new_cell = {type=LASER_D_SPLIT_A, fx=gx, fy=gy}
      did_action = true
    elseif t == LASER_D_SPLIT_A then
      new_cell = {type=LASER_H_SPLIT, fx=gx, fy=gy}
      did_action = true
    elseif t == LASER_H_SPLIT then
      new_cell = {type=LASER_D_SPLIT_B, fx=gx, fy=gy}
      did_action = true
    elseif t == LASER_D_SPLIT_B then
      new_cell = {type=LASER_V_SPLIT, fx=gx, fy=gy}
      did_action = true
    elseif is_mirror(cell) then
      new_cell = {type=LASER_V_SPLIT, fx=gx, fy=gy}
      did_action = true
    end
  elseif selected_tool == TOOL_MIRROR then
    if cell == EMPTY then
      new_cell = {type=LASER_V, fx=gx, fy=gy}
      did_action = true
    elseif t == LASER_V then
      new_cell = {type=LASER_DA, fx=gx, fy=gy}
      did_action = true
    elseif t == LASER_DA then
      new_cell = {type=LASER_H, fx=gx, fy=gy}
      did_action = true
    elseif t == LASER_H then
      new_cell = {type=LASER_DB, fx=gx, fy=gy}
      did_action = true
    elseif t == LASER_DB then
      new_cell = {type=LASER_V, fx=gx, fy=gy}
      did_action = true
    elseif is_splitter(cell) then
      new_cell = {type=LASER_V, fx=gx, fy=gy}
      did_action = true
    end
  elseif selected_tool == TOOL_BLOCK then
    if cell == EMPTY or t == LASER_BLOCK then
      new_cell = (cell == EMPTY) and {type=LASER_BLOCK, fx=gx, fy=gy} or EMPTY
      did_action = true
    end
  elseif selected_tool == TOOL_TARGET then
    if cell == EMPTY or t == LASER_TARGET then
      new_cell = (cell == EMPTY) and {type=LASER_TARGET, fx=gx, fy=gy} or EMPTY
      did_action = true
    end
  elseif selected_tool == TOOL_EMIT then
    if cell == EMPTY then
      new_cell = {type=LASER_EMIT, fx=gx, fy=gy, dx=0, dy=-1}
      did_action = true
    elseif t == LASER_EMIT then
      local obj = cell
      -- rotate counter-clockwise: N ヌ●★ NW ヌ●★ W ヌ●★ SW ヌ●★ S ヌ●★ SE ヌ●★ E ヌ●★ NE ヌ●★ N
      if obj.dx == 0 and obj.dy == -1 then
        new_cell = {type=LASER_EMIT, fx=gx, fy=gy, dx=-1, dy=-1}
      elseif obj.dx == -1 and obj.dy == -1 then
        new_cell = {type=LASER_EMIT, fx=gx, fy=gy, dx=-1, dy=0}
      elseif obj.dx == -1 and obj.dy == 0 then
        new_cell = {type=LASER_EMIT, fx=gx, fy=gy, dx=-1, dy=1}
      elseif obj.dx == -1 and obj.dy == 1 then
        new_cell = {type=LASER_EMIT, fx=gx, fy=gy, dx=0, dy=1}
      elseif obj.dx == 0 and obj.dy == 1 then
        new_cell = {type=LASER_EMIT, fx=gx, fy=gy, dx=1, dy=1}
      elseif obj.dx == 1 and obj.dy == 1 then
        new_cell = {type=LASER_EMIT, fx=gx, fy=gy, dx=1, dy=0}
      elseif obj.dx == 1 and obj.dy == 0 then
        new_cell = {type=LASER_EMIT, fx=gx, fy=gy, dx=1, dy=-1}
      elseif obj.dx == 1 and obj.dy == -1 then
        new_cell = {type=LASER_EMIT, fx=gx, fy=gy, dx=0, dy=-1}
      else
        new_cell = {type=LASER_EMIT, fx=gx, fy=gy, dx=0, dy=-1}
      end
      did_action = true
    end
  end

  if did_action then
    sfx(SFX_PLACE_TOOL)
  end

  field[gy][gx] = new_cell

  if current_state == STATE_LEVEL_EDIT then
    if cell != EMPTY and type(cell) == "table" then
      for i, obj in ipairs(level.field) do
        if obj.fx == gx and obj.fy == gy then
          del(level.field, obj)
          break
        end
      end
    end

    if new_cell != EMPTY then
      add(level.field, new_cell)
    end

    local target_key = join_str(gx, gy)
    if new_cell != EMPTY and new_cell.type == LASER_TARGET then
      targets[target_key] = {
        fx = gx,
        fy = gy,
        is_active = false
      }
    elseif cell != EMPTY and t == LASER_TARGET then
      targets[target_key] = nil
    end
  end
end

function clear_cell(gx, gy)
  local cell = get_cell(gx, gy)
  if cell == nil or cell == EMPTY then
    return
  end

  local t = type(cell) == "table" and cell.type or cell

  if current_state == STATE_PLAYING then
    if not is_tool(cell) then
      return
    end
  end

  sfx(SFX_REMOVE_TOOL)
  field[gy][gx] = EMPTY

  if type(cell) == "table" then
    for i, obj in ipairs(level.field) do
      if obj.fx == gx and obj.fy == gy then
        del(level.field, obj)
        break
      end
    end

    if t == LASER_TARGET then
      targets[join_str(gx, gy)] = nil
    end
  end
end

function is_tool(cell)
  if cell == EMPTY then return false end
  local t = type(cell) == "table" and cell.type or cell
  return t != LASER_EMIT and t != LASER_TARGET and t != LASER_BLOCK
end

function is_splitter(cell)
  if cell == EMPTY then return false end
  local t = type(cell) == "table" and cell.type or cell
  return t == LASER_V_SPLIT or t == LASER_H_SPLIT or t == LASER_D_SPLIT_A or t == LASER_D_SPLIT_B
end

function get_cell(gx, gy)
  if gy > 0 and gy <= #field and gx > 0 and gx <= #field[1] then
    return field[gy][gx]
  end

  return nil
end

function reflect(dx, dy, cell)
  local t = type(cell) == "table" and cell.type or cell

  if t == LASER_BLOCK or t == LASER_EMIT then
    return {{0,0}}
  end

  if t == LASER_V then
    if dx == 0 then
      return {{0,0}}
    end
    return {{dx * -1, dy}}
  elseif t == LASER_H then
    if dy == 0 then
      return {{0,0}}
    end
    return {{dx, dy * -1}}
  elseif t == LASER_DA then
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
  elseif t == LASER_DB then
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
  elseif t == LASER_V_SPLIT then
    if dx == 0 then
      return {{0,0}}
    end
    return {{0,-1}, {0,1}}
  elseif t == LASER_H_SPLIT then
    if dy == 0 then
      return {{0,0}}
    end
    return {{-1,0}, {1,0}}
  elseif t == LASER_D_SPLIT_A then
    if (dx != 0 and dy == 0) or (dx == 0 and dy != 0) or (dx != dy) then
      return {{-1, -1}, {1,1}}
    end
    return {{0,0}}
  elseif t == LASER_D_SPLIT_B then
    if (dx != 0 and dy == 0) or (dx == 0 and dy != 0) or (dx == dy) then
      return {{-1, 1}, {1,-1}}
    end
    return {{0,0}}
  else
    return {{dx,dy}}
  end
end

function draw_field()
  local ox,oy = unpack(FIELD_OFFSET)

  -- draw the 16x16 background map
  map(0, 0, 0, 0, 16, 16)

  -- draw level map background if map coordinates are defined
  if level.map_x and level.map_y then
    map(level.map_x, level.map_y, ox * T_SIZE, oy * T_SIZE, 10, 10)

    -- for map-based levels, only draw placed tools (mirrors/splitters)
    for i, row in ipairs(field) do
      for j, cell in ipairs(row) do
        if is_tool(cell) then
          local left = (j+ox-1)*T_SIZE
          local top = (i+oy-1)*T_SIZE
          local t = type(cell) == "table" and cell.type or cell
          local sprite = LASER_SPRITES[t]
          if sprite then
            spr(sprite, left, top)
          end
        end
      end
    end
  else
    -- for old-style levels, draw all field objects
    for i, row in ipairs(field) do
      for j, cell in ipairs(row) do
        local left = (j+ox-1)*T_SIZE
        local top = (i+oy-1)*T_SIZE
        local t = type(cell) == "table" and cell.type or cell
        local sprite = LASER_SPRITES[t]
        if sprite then
          spr(sprite, left, top)
        end
      end
    end
  end
end

function draw_laser()
  local prev_color = color()
  color(12)

  for _, segment in ipairs(laser_plot) do
    local x1,y1,x2,y2 = unpack(segment)
    line(x1,y1,x2,y2)
  end

  color(prev_color)
end

function draw_targets()
  for _, target in pairs(targets) do
    local x, y = unpack(grid_to_pos(target.fx, target.fy))
    spr(target.is_active and rnd(TARGET_SPRITES) or 50, x, y)
  end
end

function update_ui()
  if not input.lmb.just_pressed then
    return
  end

  local mx, my = unpack(input.cursor)
  local _, ty = unpack(TOOL_UI_OFFSET)
  local gx, gy = unpack(pos_to_grid(mx, my))

  local tool_count = 0
  for _, tool in ipairs(tools) do
    if tool != EMPTY then
      tool_count = tool_count + 1
    end
  end

  local ox, oy = unpack(FIELD_OFFSET)
  local fw, fh = unpack(FIELD_SIZE)
  local field_center = ox + fw / 2
  local tx = field_center - tool_count / 2

  for i, tool in ipairs(tools) do
    local x, y = (i-1+tx) * T_SIZE, ty * T_SIZE

    if mx >= x and mx < x + T_SIZE and my >= y and my < y + T_SIZE then
      if tool == TOOL_RESET then
        sfx(SFX_REMOVE_TOOL)
        if current_state == STATE_LEVEL_EDIT then
          load_level(init_empty_level())
        else
          load_level(get_level(current_level))
        end
      elseif tool == TOOL_MENU then
        sfx(SFX_UI_SELECT)
        current_state = STATE_MENU
        selected_menu_option = 1
      else
        sfx(SFX_PLACE_TOOL)
        selected_tool = tool
      end
    end
  end
end

function draw_ui()
  local mx,my = unpack(input.cursor)
  local ox,oy = unpack(FIELD_OFFSET)
  local fw,fh = unpack(FIELD_SIZE)
  local _, ty = unpack(TOOL_UI_OFFSET)
  local gx, gy = unpack(pos_to_grid(mx, my))

  print("l"..tostr(current_level).." "..level.name, T_SIZE, T_SIZE, 2)

  local tool_count = 0
  for _, tool in ipairs(tools) do
    if tool != EMPTY then
      tool_count = tool_count + 1
    end
  end

  local field_center = ox + fw / 2
  local tx = field_center - tool_count / 2

  for i, tool in ipairs(tools) do
    if tool != EMPTY then
      local x, y = (i-1+tx) * T_SIZE, ty * T_SIZE
      local text = ""
      local text_color = 7

      if tool == TOOL_RESET then
        text = "r"
        text_color = 8
      elseif tool == TOOL_MENU then
        text = "m"
        text_color = 1
      end

      if text != "" then
        print(text, x + T_SIZE/2 - 2, y - T_SIZE/2 - 2, text_color)
      end

      spr(TOOL_SPRITES[tool], x, y)

      if mx >= x and mx < x + T_SIZE and my >= y and my < y + T_SIZE then
        rect(x, y, x + T_SIZE - 1, y + T_SIZE, 12)
      end

      if selected_tool == tool then
        rect(x, y, x + T_SIZE - 1, y + T_SIZE, 7)
      end
    end
  end

  if gx >= 1 and gx <= fw and gy >= 1 and gy <= fh then
    local left = (gx+ox-1)*T_SIZE
    local top = (gy+oy-1)*T_SIZE
    rect(left,top,left+T_SIZE,top+T_SIZE,12)
  end

  spr(CURSOR_SPRITE, mx-1, my-1)
end

function draw_level_complete()
  local left, top = 71, 3
  local px, py = 3, 3
  local w, h = 48, 18
  local rating = get_star_rating()

  rectfill(left,top,left + w, top + h, 5)
  rect(left,top,left + w, top + h, 7)

  for i = 1, 3 do
    local x, y = T_SIZE + (i - 1) * T_SIZE + (i - 1) * 3 , (T_SIZE - 1) * 2
    local star = rating >= i and STAR_FILL_SPRITE or STAR_SPRITE
    spr(star, x, y)
  end

  print("❎ continue", left + px, top + h - py - T_SIZE*1.5,7)
	print("🅾️ replay", left + px, top + h - py - T_SIZE*0.5,7)
end

function is_mirror(cell)
  if cell == EMPTY then return false end
  local t = type(cell) == "table" and cell.type or cell
  return t == LASER_V or t == LASER_H or t == LASER_DA or t == LASER_DB
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

-- old levels array removed to save memory
-- all levels are now map-based in new_levels
levels = {}

new_levels = {
  {
    name = "cane",
    par = 4,
    map_x = 0,
    map_y = 26,
    tools = {TOOL_MIRROR}
  },
  {
    name = "sword",
    par = 4,
    map_x = 10,
    map_y = 26,
    tools = {TOOL_MIRROR}
  },
  {
    name = "ribbon",
    par = 4,
    map_x = 20,
    map_y = 26,
    tools = {TOOL_MIRROR}
  },
  {
    name = "sled",
    par = 5,
    map_x = 30,
    map_y = 26,
    tools = {TOOL_SPLIT}
  },
  {
    name = "mech",
    par = 7,
    map_x = 40,
    map_y = 26,
    tools = {TOOL_MIRROR, TOOL_SPLIT}
  },
  {
    name = "meteor",
    par = 6,
    map_x = 0,
    map_y = 16,
    tools = {TOOL_MIRROR, TOOL_SPLIT}
  },
  {
    name = "strings",
    par = 7,
    map_x = 10,
    map_y = 16,
    tools = {TOOL_MIRROR, TOOL_SPLIT}
  }
}

__gfx__
00000000000000001111111110000000111111111000000000000000000000000000000000000000000000000000000000000000000000000777777070707007
00000000011111101000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000007070707707777770
00700700011001101000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000007707770707700777
00077000010110101000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000007077777777077070
00077000010110101000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000007777770707077077
00700700011001101000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000007077707777700770
00000000011111101000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000007707070707777770
00000000000000001000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000777777070070707
000000000000000000000000000000000000000000000000005cc500000000000c500000000005c00000000000444400005cc5000c5000000000000000000055
00011100000cc000000000000cc0000000000cc000000000005c550000000000cc500000000005cc0003300004ffff40005c5500cc5000000000000000666655
00111110000cc000000000000ccc00000000ccc000000000000c50005505505555c5500000055c55006336004fff4ff4000c500055c550000000000006111165
011ccc11000cc0000ccccccc00ccc000000ccc0000000000005cc500c55ccccc005cc500005cc500003333004f4ff4f4005cc500005cc5000000000061111116
011ccc11000cc0000ccccccc000ccc0000ccc00000000000005cc500ccccc55c005cc500005cc500063333604ffffff4005cc500005cc50000000000d111111d
00111110000cc000000000000000ccc00ccc0000000000000005c0005505505500055c5555c55000033333304ff44ff40005c00000055c5500000000d116611d
00011100000cc0000000000000000cc00cc00000000000000055c50000000000000005cccc5000006333333604ffff400055c500000005cc00000000d115511d
00111110000cc00000000000000000000000000000000000005cc50000000000000005c00c5000003333333300444400005cc500000005c000000000ddd55ddd
08888000008888880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
87777800888070080000000000000000000000000000000000000000000000000001c10000011100000111000001110000011100000111000001110000011100
87778000800707000111111000000000000000000000000000000000000000000011111000c111100011111000111110001111100011111000111110001111c0
8777780008088080000000000000000000000000000000000000000000000000011ccc11011ccc11011ccc11011ccc11011ccc11011ccc11011ccc11011ccc11
8787778008088080011111100000000000000000000000000000000000000000011ccc11011ccc110c1ccc11011ccc11011ccc11011ccc11011ccc1c011ccc11
080878000808808000000000000000000000000000000000000000000000000000111110001111100011111000c111100011c110001111c00011111000111110
00008000080880800111111000000000000000000000000000000000000000000001110000011100000111000001110000011100000111000001110000011100
00000000080880800000000000000000000000000000000000000000000000000011111000111110001111100011111000111110001111100011111000111110
000aa000000aa00000077000000aa000000aa000000aa000000aa000000aa000000aa000000ff000000000000000000000000000000000000000000000000000
00aaaa0000a00a0000066000000cc000000ff00000033000000ee000000990000008800000077000000000000000000000000000000000000000000000000000
aaaaaaaaaaa00aaa0065560000c33c0000f99f00003bb30000e88e00009ff900008aa800007ff700000000000000000000000000000000000000000000000000
aaaaaaaaa000000a065575600c33b3c00f99a9f003bb7b300e88a8e009ff7f9008aa7a8007ff7f70000000000000000000000000000000000000000000000000
0aaaaaa00a0000a0065755600c3b33c00f9a99f003b7bb300e8a88e009f7ff9008a7aa8007f7ff70000000000000000000000000000000000000000000000000
0aaaaaa00a0000a00065560000c33c0000f99f00003bb30000e88e00009ff900008aa800007ff700000000000000000000000000000000000000000000000000
aaaaaaaaa00aa00a0065560000c33c0000f99f00003bb30000e88e00009ff900008aa800007ff700000000000000000000000000000000000000000000000000
aaa00aaaaaa00aaa00066000000cc000000ff00000033000000ee000000990000008800000077000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000a100000023000000000000232300000000a100002300230000f1000000a100230000000000a10000002323000000a10000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000a100000000230000a100a100232300a100a100002300000023000000a100000000230000002300a10023a1002300a1000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00a10000a1a1002300a100a1000023230000f10000f20000a1000023000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000a1000000000000a100a100000000a100a1a10000a10000a10000000000a1000023002300000023000000f1000023000000000000000000000000000000
__map__
0101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000000000000000000000000000001011a1a1a1a1a1a1a1a1a1a1a1a1a1a01010000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000000000000000000000000000001011a1a1a1a1a1a1a1a1a1a1a1a1a1a01010000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202030001011a1a1a1a1a1a1a1a1a1a1a1a1a1a01010000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202030001011a1a1a1a1a1a1a1a1a1a1a1a1a1a01010001010101010101010101010100010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202030001011a3435363436373534333736381a01010033350133383436353337363400010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202030001011a3300000000000000000000351a01010000000100000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202030001011a3800000000000000000000331a01010000000100000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202030001011a3500000000000000000000341a01010000000100000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202030001011a3600000000000000000000361a01010000000100000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202030001011a3338343835363336343833351a01010000000100000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202030001011a1a1a1a1a1a1a1a1a1a1a1a1a1a01010000000100000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202030001011a1a1a1a1a1a1a1a1a1a1a1a1a1a01010000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000004040404040404040404050001011a1a1a1a1a1a1a1a1a1a1a1a1a1a01010000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000000000000000000000000000001011a1a1a1a1a1a1a1a1a1a1a1a1a1a01010000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000002b010000000000000000010100000000000000000101000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001a1a00001a1a000000001a001a001a001a001a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000032003200001a001a001a001a001a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00001a002c2c32001a0000323232323232323232000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000003200321a001a1a1a001a001a1a1a1a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001a00323200000000001a1a1a1a001a001a1a1a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001a000032001a001a0032323232323232323200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000320000001a001a00001a001a001a001a001a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001a00000000000000001a001a001a001a001a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
320000000000000000002f000000000000000000010000000000000000010100000000000000000101000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1a001a00000000001a00000000000000000000000000000000000000001a00003200000000001a001a0000001a1a0000001a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000323200001a1a001a003232001a001a001a0000321a32000000001a0032000000000000001f0000000000001a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2e0000001f0000320000001f0000323200001a000000003200001a000000320000000000001a00001a00000032320000001a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001a00000000003200001a001a003232001a001a0000001a000032001a000032000000000000001a00000032000032000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000001a000032001a00000000000000000000000000320032001a0000000000002900320000002e00000000000000002a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001a1a000000003200002e00320000000032002a001a000032000000000000000000002d0032003200320000323200003200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
0003000023510265201d3001d300162001620022100221001c4000f0000d0000100014000130001d00012000245002000011000100000f0000e00000000000000000000000000000000000000000000000000000
000300001a01021510260102a52000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000300001271000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000300000b73000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000500000f510145101951014520115101b5102051024510275102c51030520000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
