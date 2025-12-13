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

SNOW_MIN_SIZE = 1
SNOW_MAX_SIZE = 2

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
STATE_INSTRUCTIONS = 6

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

TARGET_SPRITES = {51,52,53,54,55,56,57}

-- globals --

current_state = STATE_MENU
current_level = 1
selected_menu_option = 1
prev_menu_option = 1
preview_level = 1
selected_complete_option = 1
dpad_cursor = {5, 5}
dpad_mode = "field"
dpad_tool_index = 1

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
snowflakes = {}
target_anim_tick = 0
level_complete_timer = 0
input = {
    mode = "controller",
    mode_just_switched = false,
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
    up = {
        just_pressed = false,
        was_pressed = false
      },
    down = {
        just_pressed = false,
        was_pressed = false
      },
    left = {
        just_pressed = false,
        was_pressed = false
      },
    right = {
        just_pressed = false,
        was_pressed = false
      },
    x = {
        just_pressed = false,
        was_pressed = false
      },
    o = {
        just_pressed = false,
        was_pressed = false
      }
  }

-- methods --

function get_level(index)
  return levels[index]
end

function get_level_count()
  return #levels
end

function _init()
  poke(0x5f2d, 1)
  init_snowflakes()
  if current_state == STATE_LEVEL_EDIT then
    load_level(init_empty_level())
  else
    load_level(get_level(current_level))
  end
end

function init_snowflakes()
  for i = 1, 50 do
    add(snowflakes, {
      x = rnd(128),
      y = rnd(128),
      speed = 0.15 + rnd(0.25),
      sway = rnd(1),
      sway_speed = 0.01 + rnd(0.02),
      size = SNOW_MIN_SIZE + flr(rnd(SNOW_MAX_SIZE - SNOW_MIN_SIZE + 1))
    })
  end
end

function update_snowflakes()
  for flake in all(snowflakes) do
    flake.y += flake.speed
    flake.sway += flake.sway_speed
    flake.x += sin(flake.sway) * 0.5

    if flake.y > 128 then
      flake.y = -2
      flake.x = rnd(128)
    end
  end
end

function draw_snowflakes()
  for flake in all(snowflakes) do
    circfill(flake.x, flake.y, flake.size - 1, 7)
  end
end

function _update()
  update_input()
  update_snowflakes()
  if current_state == STATE_MENU then
    update_menu()
  elseif current_state == STATE_PLAYING then
    update_playing()
    if check_win() then
      sfx(SFX_LEVEL_COMPLETE)
      current_state = STATE_LEVEL_COMPLETE
      level_complete_timer = 0
    end
  elseif current_state == STATE_LEVEL_COMPLETE then
    update_level_complete()
  elseif current_state == STATE_WIN then
    update_win()
  elseif current_state == STATE_LEVEL_EDIT then
    update_playing()
  elseif current_state == STATE_LEVEL_SELECT then
    update_level_select()
  elseif current_state == STATE_INSTRUCTIONS then
    update_instructions()
  end
end

function update_playing()
  if dpad_mode == "field" then
    if input.up.just_pressed then
      dpad_cursor[2] = dpad_cursor[2] - 1
      if dpad_cursor[2] < 1 then
        dpad_cursor[2] = 1
      else
        sfx(SFX_UI_HOVER)
      end
    end

    if input.down.just_pressed then
      if dpad_cursor[2] == 10 then
        dpad_mode = "tool_ui"
        dpad_tool_index = 1
        for i, tool in ipairs(tools) do
          if tool == selected_tool then
            dpad_tool_index = i
            break
          end
        end
        if tools[dpad_tool_index] == EMPTY then
          while tools[dpad_tool_index] == EMPTY and dpad_tool_index <= #tools do
            dpad_tool_index = dpad_tool_index + 1
          end
        end
        sfx(SFX_UI_HOVER)
      else
        dpad_cursor[2] = dpad_cursor[2] + 1
        sfx(SFX_UI_HOVER)
      end
    end

    if input.left.just_pressed then
      dpad_cursor[1] = dpad_cursor[1] - 1
      if dpad_cursor[1] < 1 then
        dpad_cursor[1] = 1
      else
        sfx(SFX_UI_HOVER)
      end
    end

    if input.right.just_pressed then
      dpad_cursor[1] = dpad_cursor[1] + 1
      if dpad_cursor[1] > 10 then
        dpad_cursor[1] = 10
      else
        sfx(SFX_UI_HOVER)
      end
    end

    if input.x.just_pressed then
      local gx, gy = unpack(dpad_cursor)
      toggle_cell(gx, gy)
    end

    if input.o.just_pressed then
      local gx, gy = unpack(dpad_cursor)
      clear_cell(gx, gy)
    end
  elseif dpad_mode == "tool_ui" then
    if input.left.just_pressed then
      sfx(SFX_UI_HOVER)
      local start_index = dpad_tool_index
      repeat
        dpad_tool_index = dpad_tool_index - 1
        if dpad_tool_index < 1 then
          dpad_tool_index = #tools
        end
      until tools[dpad_tool_index] != EMPTY or dpad_tool_index == start_index
    end

    if input.right.just_pressed then
      sfx(SFX_UI_HOVER)
      local start_index = dpad_tool_index
      repeat
        dpad_tool_index = dpad_tool_index + 1
        if dpad_tool_index > #tools then
          dpad_tool_index = 1
        end
      until tools[dpad_tool_index] != EMPTY or dpad_tool_index == start_index
    end

    if input.up.just_pressed then
      sfx(SFX_UI_HOVER)
      dpad_mode = "field"
      dpad_cursor[2] = 10
    end

    if input.x.just_pressed or input.o.just_pressed then
      local tool = tools[dpad_tool_index]
      local tool_type = type(tool) == "table" and tool.type or tool
      if tool_type == TOOL_RESET then
        sfx(SFX_REMOVE_TOOL)
        if current_state == STATE_LEVEL_EDIT then
          load_level(init_empty_level())
        else
          load_level(get_level(current_level))
        end
      elseif tool_type == TOOL_MENU then
        sfx(SFX_UI_SELECT)
        current_state = STATE_MENU
        selected_menu_option = 1
      else
        sfx(SFX_PLACE_TOOL)
        selected_tool = tool_type
      end
    end
  end

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
  update_targets()

  level_complete_timer += 1

  if level_complete_timer < 15 then
    return
  end

  if input.mode == "controller" then
    if input.up.just_pressed then
      selected_complete_option = 1
      sfx(SFX_UI_HOVER)
    elseif input.down.just_pressed then
      selected_complete_option = 2
      sfx(SFX_UI_HOVER)
    end

    if input.x.just_pressed then
      sfx(SFX_UI_SELECT)
      if selected_complete_option == 1 then
        if current_level == get_level_count() then
          current_state = STATE_WIN
        else
          current_level = current_level + 1
          dpad_cursor = {5, 5}
          dpad_mode = "field"
          load_level(get_level(current_level))
          current_state = STATE_PLAYING
        end
      else
        dpad_cursor = {5, 5}
        dpad_mode = "field"
        load_level(get_level(current_level))
        current_state = STATE_PLAYING
      end
      selected_complete_option = 1
    end
  else
    local mx, my = unpack(input.cursor)
    local left, top = 71, 3
    local px, py = 3, 3
    local w, h = 48, 18

    local continue_hover = mx >= left + px and mx < left + w - px and my >= top + h - py - T_SIZE*1.5 and my < top + h - py - T_SIZE*1.5 + 6
    local replay_hover = mx >= left + px and mx < left + w - px and my >= top + h - py - T_SIZE*0.5 and my < top + h - py - T_SIZE*0.5 + 6

    if input.lmb.just_pressed then
      if continue_hover then
        sfx(SFX_UI_SELECT)
        if current_level == get_level_count() then
          current_state = STATE_WIN
        else
          current_level = current_level + 1
          dpad_cursor = {5, 5}
          dpad_mode = "field"
          load_level(get_level(current_level))
          current_state = STATE_PLAYING
        end
        selected_complete_option = 1
      elseif replay_hover then
        sfx(SFX_UI_SELECT)
        dpad_cursor = {5, 5}
        dpad_mode = "field"
        load_level(get_level(current_level))
        current_state = STATE_PLAYING
        selected_complete_option = 1
      end
    end
  end
end

function update_win()
  if input.o.just_pressed then
    sfx(SFX_UI_SELECT)
    field = {}
    targets = {}
    laser_plot = {}
    laser_plot_tool_chain = {}
    current_state = STATE_MENU
    selected_menu_option = 1
  end

  if input.lmb.just_pressed then
    local mx, my = unpack(input.cursor)
    if mx >= 44 and mx < 84 and my >= 66 and my < 74 then
      sfx(SFX_UI_SELECT)
      field = {}
      targets = {}
      laser_plot = {}
      laser_plot_tool_chain = {}
      current_state = STATE_MENU
      selected_menu_option = 1
    end
  end

  target_anim_tick += 1
  if target_anim_tick >= 15 then
    target_anim_tick = 0
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
end

function update_instructions()
  if input.o.just_pressed then
    sfx(SFX_UI_SELECT)
    current_state = STATE_MENU
    selected_menu_option = 1
  end

  if input.lmb.just_pressed then
    local mx, my = unpack(input.cursor)
    if mx >= 44 and mx < 84 and my >= 114 and my < 122 then
      sfx(SFX_UI_SELECT)
      current_state = STATE_MENU
      selected_menu_option = 1
    end
  end
end

function update_menu()
  if input.up.just_pressed then
    sfx(SFX_UI_HOVER)
    selected_menu_option = selected_menu_option - 1
    if selected_menu_option < 1 then
      selected_menu_option = 4
    end
  end

  if input.down.just_pressed then
    sfx(SFX_UI_HOVER)
    selected_menu_option = selected_menu_option + 1
    if selected_menu_option > 4 then
      selected_menu_option = 1
    end
  end

  if input.lmb.just_pressed or input.x.just_pressed or input.o.just_pressed then
    if selected_menu_option == 1 then
      sfx(SFX_UI_SELECT)
      current_level = 1
      dpad_cursor = {5, 5}
      dpad_mode = "field"
      current_state = STATE_PLAYING
      load_level(get_level(current_level))
    elseif selected_menu_option == 2 then
      sfx(SFX_UI_SELECT)
      preview_level = current_level
      load_level(get_level(preview_level))
      current_state = STATE_LEVEL_SELECT
    elseif selected_menu_option == 3 then
      sfx(SFX_UI_SELECT)
      current_state = STATE_INSTRUCTIONS
    elseif selected_menu_option == 4 then
      sfx(SFX_UI_SELECT)
      dpad_cursor = {5, 5}
      dpad_mode = "field"
      current_state = STATE_LEVEL_EDIT
      load_level(init_empty_level())
    end
  end

  if input.mode == "mouse" then
    local mx, my = unpack(input.cursor)
    local menu_y = 53
    local spacing = 14

    for i = 1, 4 do
      local y = menu_y + (i - 1) * spacing
      if my >= y and my < y + 8 then
        if selected_menu_option != i then
          sfx(SFX_UI_HOVER)
          selected_menu_option = i
        end
      end
    end
  end

  prev_menu_option = selected_menu_option
end

function update_level_select()
  update_lasers()
  update_targets()

  if input.left.just_pressed then
    if preview_level > 1 then
      sfx(SFX_UI_SELECT)
      preview_level = preview_level - 1
      load_level(get_level(preview_level))
    end
  end

  if input.right.just_pressed then
    if preview_level < get_level_count() then
      sfx(SFX_UI_SELECT)
      preview_level = preview_level + 1
      load_level(get_level(preview_level))
    end
  end

  if input.x.just_pressed then
    sfx(SFX_UI_SELECT)
    current_level = preview_level
    dpad_cursor = {5, 5}
    dpad_mode = "field"
    current_state = STATE_PLAYING
    load_level(get_level(current_level))
  end

  if input.o.just_pressed then
    sfx(SFX_UI_SELECT)
    field = {}
    targets = {}
    laser_plot = {}
    laser_plot_tool_chain = {}
    current_state = STATE_MENU
    selected_menu_option = 1
  end

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

    if mx >= 88 and mx < 120 and my >= 114 and my < 122 then
      sfx(SFX_UI_SELECT)
      current_level = preview_level
      dpad_cursor = {5, 5}
      dpad_mode = "field"
      current_state = STATE_PLAYING
      load_level(get_level(current_level))
    end

    if mx >= 8 and mx < 40 and my >= 114 and my < 122 then
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
  local menu_options = {"play", "level select", "how to play", "playground"}
  local menu_y = 53
  local spacing = 14

  for i, option in ipairs(menu_options) do
    local y = menu_y + (i - 1) * spacing
    local color = selected_menu_option == i and 12 or 7
    if selected_menu_option == i then
      print(">", 41, y, 12)
    end
    print(option, 47, y, color)
  end

  if input.mode == "mouse" then
    local mx, my = unpack(input.cursor)
    spr(CURSOR_SPRITE, mx-1, my-1)
  end
end

function _draw()
	cls()

  if current_state == STATE_MENU then
    draw_menu()
  elseif current_state == STATE_PLAYING then
    draw_playing()
  elseif current_state == STATE_LEVEL_COMPLETE then
    draw_field()
    draw_laser()
    draw_targets()
    draw_level_complete()
  elseif current_state == STATE_WIN then
    draw_win()
  elseif current_state == STATE_LEVEL_EDIT then
    draw_playing()
  elseif current_state == STATE_LEVEL_SELECT then
    draw_level_select()
  elseif current_state == STATE_INSTRUCTIONS then
    draw_instructions()
  end

  draw_snowflakes()
end

function draw_playing()
  draw_map_background()
	draw_field()
  draw_laser()
  draw_targets()
  draw_ui()
end

function draw_win()
  map(16, 0, 0, 0)
  local ox, oy = T_SIZE, T_SIZE
  print("thanks for playing", 28, 54)

  if input.mode == "mouse" then
    local mx, my = unpack(input.cursor)
    local menu_hover = mx >= 44 and mx < 84 and my >= 66 and my < 74

    rectfill(44, 66, 84, 74, menu_hover and 2 or 1)
    rect(44, 66, 84, 74, menu_hover and 12 or 7)
    print("menu", 57, 68, 7)

    spr(CURSOR_SPRITE, mx-1, my-1)
  else
    print("🅾️ menu", 48, 68, 7)
  end
end

function draw_instructions()
  cls()

  print("how to play", 38, 4, 12)

  print("light up all targets with", 8, 14, 7)
  print("the laser beam", 8, 20, 7)

  local y = 30
  spr(TOOL_SPRITES[TOOL_MIRROR], 8, y)
  print("mirror: reflects", 20, y+2, 7)
  print("  the laser", 20, y+8, 7)

  y = 48
  spr(TOOL_SPRITES[TOOL_SPLIT], 8, y)
  print("splitter: splits", 20, y+2, 7)
  print("  the laser", 20, y+8, 7)

  y = 66
  spr(TOOL_SPRITES[TOOL_BLOCK], 8, y)
  print("tree: blocks", 20, y+2, 7)
  print("  the laser", 20, y+8, 7)

  print("❎/click to place and rotate", 8, 86, 7)
  print("🅾️/right-click to remove", 8, 98, 7)

  if input.mode == "mouse" then
    local mx, my = unpack(input.cursor)
    local menu_hover = mx >= 44 and mx < 84 and my >= 114 and my < 122

    rectfill(44, 114, 84, 122, menu_hover and 2 or 1)
    rect(44, 114, 84, 122, menu_hover and 12 or 7)
    print("menu", 57, 116, 7)

    spr(CURSOR_SPRITE, mx-1, my-1)
  else
    print("🅾️ menu", 48, 116, 7)
  end
end

function draw_level_select()
  draw_field()
  draw_laser()
  draw_targets()

  local mx, my = unpack(input.cursor)

  draw_level_name(preview_level)

  local back_hover = false
  local left_hover = false
  local right_hover = false
  local play_hover = false

  if input.mode == "mouse" then
    back_hover = mx >= 8 and mx < 40 and my >= 114 and my < 122
    left_hover = mx >= 4 and mx < 12 and my >= 60 and my < 68
    right_hover = mx >= 116 and mx < 124 and my >= 60 and my < 68
    play_hover = mx >= 88 and mx < 120 and my >= 114 and my < 122

    rectfill(8, 114, 40, 122, back_hover and 2 or 1)
    rect(8, 114, 40, 122, back_hover and 12 or 7)
    print("back", 17, 116, 7)

    rectfill(88, 114, 120, 122, play_hover and 2 or 1)
    rect(88, 114, 120, 122, play_hover and 12 or 7)
    print("play", 97, 116, 7)
  end

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

  if input.mode == "controller" then
    print("🅾️ back", 8, 118, 7)
    print("❎ play", 88, 118, 7)
  end

  if input.mode == "mouse" then
    spr(CURSOR_SPRITE, mx-1, my-1)
  end
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

  if level_data.map_x and level_data.map_y then
    level_data.field = {}

    for fy = 1, 10 do
      for fx = 1, 10 do
        local tile_id = mget(level_data.map_x + fx - 1, level_data.map_y + fy - 1)
        local obj = nil

        if tile_id >= LASER_EMIT_N and tile_id <= LASER_EMIT_NE then
          local dx, dy = unpack(emit_dirs[tile_id])
          obj = {type = LASER_EMIT, fx = fx, fy = fy, dx = dx, dy = dy}
        elseif tile_id == 50 then
          obj = {type = LASER_TARGET, fx = fx, fy = fy}
          targets[join_str(fx, fy)] = {
            fx = fx,
            fy = fy,
            is_active = false,
            sprite = rnd(TARGET_SPRITES)
          }
        elseif tile_id > 0 then
          obj = {type = LASER_BLOCK, fx = fx, fy = fy}
        end

        if obj then
          field[fy][fx] = obj
          add(level_data.field, obj)
        end
      end
    end
  else
    for _, obj in ipairs(level_data.field) do
      field[obj.fy][obj.fx] = obj

      if obj.type == LASER_TARGET then
        targets[join_str(obj.fx, obj.fy)] = {
          fx = obj.fx,
          fy = obj.fy,
          is_active = false,
          sprite = rnd(TARGET_SPRITES)
        }
      end
    end
  end

  for _, tool_data in ipairs(level_data.tools) do
    if type(tool_data) == "table" then
      add(tools, {type=tool_data.type, max=tool_data.max})
    else
      add(tools, tool_data)
    end
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

  local tool_found = false
  if selected_tool != EMPTY then
    for _, tool in ipairs(tools) do
      local tool_type = type(tool) == "table" and tool.type or tool
      if tool_type == selected_tool then
        tool_found = true
        break
      end
    end
  end

  if not tool_found then
    for _, tool in ipairs(tools) do
      local tool_type = type(tool) == "table" and tool.type or tool
      if tool_type != EMPTY and tool_type != TOOL_RESET and tool_type != TOOL_MENU then
        selected_tool = tool_type
        break
      end
    end
  end

  level = level_data
end

function update_input()
  input.mode_just_switched = false

  local mb = stat(34)
  input.cursor = {stat(32)-1, stat(33)-1}
  input.lmb.down = mb & 1 != 0
  input.rmb.down = mb & 2 != 0

  if input.lmb.down then
    if not input.lmb.was_pressed then
      input.lmb.just_pressed = true
      input.lmb.was_pressed = true
      if input.mode != "mouse" then
        input.mode = "mouse"
        input.mode_just_switched = true
        input.lmb.just_pressed = false
      end
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

  local up_down = btn(2)
  if up_down then
    if not input.up.was_pressed then
      input.up.just_pressed = true
      input.up.was_pressed = true
      if input.mode != "controller" then
        input.mode = "controller"
        input.mode_just_switched = true
      end
    else
      input.up.just_pressed = false
    end
  else
    input.up.just_pressed = false
    input.up.was_pressed = false
  end

  local down_down = btn(3)
  if down_down then
    if not input.down.was_pressed then
      input.down.just_pressed = true
      input.down.was_pressed = true
      if input.mode != "controller" then
        input.mode = "controller"
        input.mode_just_switched = true
      end
    else
      input.down.just_pressed = false
    end
  else
    input.down.just_pressed = false
    input.down.was_pressed = false
  end

  local left_down = btn(0)
  if left_down then
    if not input.left.was_pressed then
      input.left.just_pressed = true
      input.left.was_pressed = true
      if input.mode != "controller" then
        input.mode = "controller"
        input.mode_just_switched = true
      end
    else
      input.left.just_pressed = false
    end
  else
    input.left.just_pressed = false
    input.left.was_pressed = false
  end

  local right_down = btn(1)
  if right_down then
    if not input.right.was_pressed then
      input.right.just_pressed = true
      input.right.was_pressed = true
      if input.mode != "controller" then
        input.mode = "controller"
        input.mode_just_switched = true
      end
    else
      input.right.just_pressed = false
    end
  else
    input.right.just_pressed = false
    input.right.was_pressed = false
  end

  local x_down = btn(5)
  if x_down then
    if not input.x.was_pressed then
      input.x.just_pressed = true
      input.x.was_pressed = true
      if input.mode != "controller" then
        input.mode = "controller"
        input.mode_just_switched = true
      end
    else
      input.x.just_pressed = false
    end
  else
    input.x.just_pressed = false
    input.x.was_pressed = false
  end

  local o_down = btn(4)
  if o_down then
    if not input.o.was_pressed then
      input.o.just_pressed = true
      input.o.was_pressed = true
      if input.mode != "controller" then
        input.mode = "controller"
        input.mode_just_switched = true
      end
    else
      input.o.just_pressed = false
    end
  else
    input.o.just_pressed = false
    input.o.was_pressed = false
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

  target_anim_tick += 1
  if target_anim_tick >= 15 then
    target_anim_tick = 0
    for _, target in pairs(targets) do
      if target.is_active then
        target.sprite = rnd(TARGET_SPRITES)
      end
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

    if cell == EMPTY and get_tool_count(selected_tool) <= 0 then
      return
    end
  end

  local new_cell = EMPTY
  local did_action = false
  local old_tool_type = nil

  if current_state == STATE_PLAYING and is_tool(cell) then
    if is_mirror(cell) then
      old_tool_type = TOOL_MIRROR
    elseif is_splitter(cell) then
      old_tool_type = TOOL_SPLIT
    end
  end

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

  if current_state == STATE_PLAYING and did_action then
    if old_tool_type != nil then
      restore_tool(old_tool_type)
    end

    if new_cell != EMPTY and is_tool(new_cell) then
      consume_tool(selected_tool)
    end
  end

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
        is_active = false,
        sprite = rnd(TARGET_SPRITES)
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

  if current_state == STATE_PLAYING and is_tool(cell) then
    if is_mirror(cell) then
      restore_tool(TOOL_MIRROR)
    elseif is_splitter(cell) then
      restore_tool(TOOL_SPLIT)
    end
  end

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

function get_tool_count(tool_type)
  for _, tool in ipairs(tools) do
    if type(tool) == "table" and tool.type == tool_type then
      return tool.max
    end
  end
  return 0
end

function consume_tool(tool_type)
  for _, tool in ipairs(tools) do
    if type(tool) == "table" and tool.type == tool_type then
      if tool.max > 0 then
        tool.max = tool.max - 1
        return true
      end
      return false
    end
  end
  return false
end

function restore_tool(tool_type)
  for _, tool in ipairs(tools) do
    if type(tool) == "table" and tool.type == tool_type then
      tool.max = tool.max + 1
      return true
    end
  end
  return false
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

function draw_map_background()
  map(0, 0, 0, 0, 16, 16)
end

function draw_level_name(lvl)
  local level_num = lvl or current_level
  print("l"..tostr(level_num).." "..level.name, T_SIZE, T_SIZE, 2)
  if level.attribution then
    print(level.attribution, T_SIZE, T_SIZE + 6, 13)
  end
end

function draw_field()
  local ox,oy = unpack(FIELD_OFFSET)

  if level.map_x and level.map_y then
    map(level.map_x, level.map_y, ox * T_SIZE, oy * T_SIZE, 10, 10)

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
    spr(target.is_active and target.sprite or TOOL_SPRITES[TOOL_TARGET], x, y)
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
    local tool_type = type(tool) == "table" and tool.type or tool

    if mx >= x and mx < x + T_SIZE and my >= y and my < y + T_SIZE then
      if tool_type == TOOL_RESET then
        sfx(SFX_REMOVE_TOOL)
        if current_state == STATE_LEVEL_EDIT then
          load_level(init_empty_level())
        else
          load_level(get_level(current_level))
        end
      elseif tool_type == TOOL_MENU then
        sfx(SFX_UI_SELECT)
        current_state = STATE_MENU
        selected_menu_option = 1
      else
        sfx(SFX_PLACE_TOOL)
        selected_tool = tool_type
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

  draw_level_name()

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
      local tool_type = type(tool) == "table" and tool.type or tool

      if tool_type == TOOL_RESET then
        text = "r"
        text_color = 2
      elseif tool_type == TOOL_MENU then
        text = "m"
        text_color = 1
      end

      if text != "" then
        print(text, x + T_SIZE/2 - 2, y - T_SIZE/2 - 2, text_color)
      end

      if type(tool) == "table" and tool.max then
        print(tostr(tool.max), x + T_SIZE/2 - 2, y - T_SIZE/2 - 2, 7)
      end

      spr(TOOL_SPRITES[tool_type], x, y)

      if input.mode == "mouse" then
        if mx >= x and mx < x + T_SIZE and my >= y and my < y + T_SIZE then
          rect(x, y, x + T_SIZE - 1, y + T_SIZE, 12)
        end
      end

      if input.mode == "controller" then
        if dpad_mode == "tool_ui" and i == dpad_tool_index then
          rect(x, y, x + T_SIZE - 1, y + T_SIZE, 11)
        elseif selected_tool == tool_type then
          rect(x, y, x + T_SIZE - 1, y + T_SIZE, 7)
        end
      else
        if selected_tool == tool_type then
          rect(x, y, x + T_SIZE - 1, y + T_SIZE, 7)
        end
      end
    end
  end

  if input.mode == "mouse" then
    if gx >= 1 and gx <= fw and gy >= 1 and gy <= fh then
      local left = (gx+ox-1)*T_SIZE
      local top = (gy+oy-1)*T_SIZE
      rect(left,top,left+T_SIZE,top+T_SIZE,12)
    end
  end

  if input.mode == "controller" and dpad_mode == "field" then
    local dgx, dgy = unpack(dpad_cursor)
    local left = (dgx+ox-1)*T_SIZE
    local top = (dgy+oy-1)*T_SIZE
    rect(left,top,left+T_SIZE,top+T_SIZE,11)
  end

  if input.mode == "mouse" then
    spr(CURSOR_SPRITE, mx-1, my-1)
  end
end

function draw_level_complete()
  draw_level_name()

  local left, top = 71, 3
  local px, py = 3, 3
  local w, h = 48, 18
  local rating = get_star_rating()

  rectfill(left,top,left + w, top + h, 5)
  rect(left,top,left + w, top + h, 7)

  local ox, oy = unpack(FIELD_OFFSET)
  local fw, fh = unpack(FIELD_SIZE)
  local field_bottom = (oy + fh) * T_SIZE

  local num_stars = 3
  local star_padding = 3
  local total_star_width = num_stars * T_SIZE + (num_stars - 1) * star_padding
  local star_start_x = 64 - total_star_width / 2

  for i = 1, num_stars do
    local x, y = star_start_x + (i - 1) * T_SIZE + (i - 1) * star_padding, field_bottom + 6
    local star = rating >= i and STAR_FILL_SPRITE or STAR_SPRITE
    spr(star, x, y)
  end

  local mx, my = unpack(input.cursor)
  local continue_y = top + h - py - T_SIZE*1.5
  local replay_y = top + h - py - T_SIZE*0.5

  local show_continue_indicator = false
  local show_replay_indicator = false

  if input.mode == "controller" then
    show_continue_indicator = selected_complete_option == 1
    show_replay_indicator = selected_complete_option == 2
  else
    local continue_hover = mx >= left + px and mx < left + w - px and my >= continue_y and my < continue_y + 6
    local replay_hover = mx >= left + px and mx < left + w - px and my >= replay_y and my < replay_y + 6
    show_continue_indicator = continue_hover
    show_replay_indicator = replay_hover
  end

  local continue_color = show_continue_indicator and 12 or 7
  local replay_color = show_replay_indicator and 12 or 7

  if show_continue_indicator then
    print(">", left + px, continue_y, 12)
  end
  print("continue", left + px + 6, continue_y, continue_color)

  if show_replay_indicator then
    print(">", left + px, replay_y, 12)
  end
  print("replay", left + px + 6, replay_y, replay_color)

  if input.mode == "mouse" then
    spr(CURSOR_SPRITE, mx-1, my-1)
  end
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

levels = {
  {
    name = "mirror",
    par = 2,
    map_x = 0,
    map_y = 16,
    tools = {{type=TOOL_MIRROR, max=4}},
    attribution = "kd2718"
  },
  {
    name = "snake",
    par = 9,
    map_x = 40,
    map_y = 16,
    tools = {{type=TOOL_MIRROR, max=9}},
  },
  {
    name = "cane",
    par = 4,
    map_x = 0,
    map_y = 26,
    tools = {{type=TOOL_MIRROR, max=6}}
  },
  {
    name = "sword",
    par = 4,
    map_x = 10,
    map_y = 26,
    tools = {{type=TOOL_MIRROR, max=6}}
  },
  {
    name = "ribbon",
    par = 4,
    map_x = 20,
    map_y = 26,
    tools = {{type=TOOL_MIRROR, max=6}}
  },
  {
    name = "stocking",
    par = 7,
    map_x = 0,
    map_y = 36,
    tools = {{type=TOOL_MIRROR, max=9}},
    attribution = "BryterGames"
  },
  {
    name = "split",
    par = 2,
    map_x = 10,
    map_y = 16,
    tools = {{type=TOOL_SPLIT, max=2}}
  },
  {
    name = "diagonally",
    par = 3,
    map_x = 20,
    map_y = 16,
    tools = {{type=TOOL_SPLIT, max=2}}
  },
  {
    name = "sled",
    par = 5,
    map_x = 30,
    map_y = 26,
    tools = {{type=TOOL_SPLIT, max=7}}
  },
  {
    name = "box",
    par = 5,
    map_x = 30,
    map_y = 16,
    tools = {{type=TOOL_SPLIT, max=2}, {type=TOOL_MIRROR, max=6}},
    attribution = "SmellyFishstiks"
  },
  {
    name = "strings",
    par = 7,
    map_x = 50,
    map_y = 16,
    tools = {{type=TOOL_SPLIT, max=4}, {type=TOOL_MIRROR, max=6}}
  },
  {
    name = "star",
    par = 7,
    map_x = 20,
    map_y = 36,
    tools = {{type=TOOL_SPLIT, max=4}, {type=TOOL_MIRROR, max=6}},
    attribution = "doriencey"
  },
  {
    name = "bell",
    par = 7,
    map_x = 10,
    map_y = 36,
    tools = {{type=TOOL_SPLIT, max=2}, {type=TOOL_MIRROR, max=8}}
  },
  {
    name = "circuits",
    par = 8,
    map_x = 50,
    map_y = 26,
    tools = {{type=TOOL_SPLIT, max=5}, {type=TOOL_MIRROR, max=5}}
  }
}

__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000777777070707007
00000000011111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007070707707777770
00700700011001100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007707770707700777
00077000010110100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007077777777077070
00077000010110100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007777770707077077
00700700011001100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007077707777700770
00000000011111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007707070707777770
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000777777070070707
000000000000000000000000000000000000000000000000005cc500000000000c500000000005c00000000000444400005cc5000c5000000000000000000000
00011100000cc000000000000cc0000000000cc000000000005c550000000000cc500000000005cc0003300004ffff40005c5500cc5000000000000000000000
00111110000cc000000000000ccc00000000ccc000000000000c50005505505555c5500000055c55006336004fff4ff4000c500055c550000000000000000000
011ccc11000cc0000ccccccc00ccc000000ccc0000000000005cc500c55ccccc005cc500005cc500003333004f4ff4f4005cc500005cc5000000000000000000
011ccc11000cc0000ccccccc000ccc0000ccc00000000000005cc500ccccc55c005cc500005cc500063333604ffffff4005cc500005cc5000000000000000000
00111110000cc000000000000000ccc00ccc0000000000000005c0005505505500055c5555c55000033333304ff44ff40005c00000055c550000000000000000
00011100000cc0000000000000000cc00cc00000000000000055c50000000000000005cccc5000006333333604ffff400055c500000005cc0000000000000000
00111110000cc00000000000000000000000000000000000005cc50000000000000005c00c5000003333333300444400005cc500000005c00000000000000000
08888000002222220000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
877778002220d0020000000000000000000000000000000000000000000000000001c10000011100000111000001110000011100000111000001110000011100
87778000200d0d000111111000000000000000000000000000000000000000000011111000c111100011111000111110001111100011111000111110001111c0
8777780002022020000000000000000000000000000000000000000000000000011ccc11011ccc11011ccc11011ccc11011ccc11011ccc11011ccc11011ccc11
8787778002022020011111100000000000000000000000000000000000000000011ccc11011ccc110c1ccc11011ccc11011ccc11011ccc11011ccc1c011ccc11
080878000202202000000000000000000000000000000000000000000000000000111110001111100011111000c111100011c110001111c00011111000111110
00008000020220200111111000000000000000000000000000000000000000000001110000011100000111000001110000011100000111000001110000011100
00000000020220200000000000000000000000000000000000000000000000000011111000111110001111100011111000111110001111100011111000111110
000990000009900000077000000aa000000aa000000aa000000aa000000aa000000aa000000aa000000000000000000000000000000000000000000000000000
009aa9000090090000066000000cc000000ff00000033000000ee00000099000000ff00000077000000000000000000000000000000000000000000000000000
99aaaa99999009990065560000c33c0000f99f00003bb30000e88e00009ff90000faaf00007ff700000000000000000000000000000000000000000000000000
9aaa7aa990000009065575600c33b3c00f99a9f003bb7b300e88a8e009ff7f900faa7af007ff7f70000000000000000000000000000000000000000000000000
09a7aa9009000090065755600c3b33c00f9a99f003b7bb300e8a88e009f7ff900fa7aaf007f7ff70000000000000000000000000000000000000000000000000
09aaaa90090000900065560000c33c0000f99f00003bb30000e88e00009ff90000faaf00007ff700000000000000000000000000000000000000000000000000
9aa99aa9900990090065560000c33c0000f99f00003bb30000e88e00009ff90000faaf00007ff700000000000000000000000000000000000000000000000000
999009999990099900066000000cc000000ff00000033000000ee00000099000000ff00000077000000000000000000000000000000000000000000000000000
00000000000aa0700000000000000000000000007777770777777707777777000000000000000000000000000000000000000000000000000000000000000000
07000cc0070330000000000000000000000000000000070700000707000007000000000000000000000000000000000000000000000000000000000000000000
0000ccc0003bb3000000000000000000000000000ccc07070ccc07070ccc07000000000000000000000000000000000000000000000000000000000000000000
000ccc0003bb7b300000000000000000000000000c1c07070c1c07070c1c07000000000000000000000000000000000000000000000000000000000000000000
00ccc00003b7bb300000000000000000000000000c1c07070c1c07070c1c07000000000000000000000000000000000000000000000000000000000000000000
0ccc0070003bb3000000000000000000000000000c1c07070c1c07070c1c07000000000000000000000000000000000000000000000000000000000000000000
0cc00777003bb3070000000000000000000000000c1c07070c1c07070c1c07000000000000000000000000000000000000000000000000000000000000000000
00000070000330000000000000000000000000000c1c07070c1c07070c1c07000000000000000000000000000000000000000000000000000000000000000000
07077000000007000000000000000000000000000c1c07770c1c07770c1c07770000000000000000000000000000000000000000000000000000000000000000
000660000cc077700000000000000000000000000c1c00000c1c00000c1c00000000000000000000000000000000000000000000000000000000000000000000
006556000ccc07000000000000000000000000000c1cccc00c1cccc00c1cccc00000000000000000000000000000000000000000000000000000000000000000
0655756000ccc0000000000000000000000000000c1111c00c1111c00c1111c00000000000000000000000000000000000000000000000000000000000000000
06575560000ccc000000000000000000000000000cccccc00cccccc00cccccc00000000000000000000000000000000000000000000000000000000000000000
006556070000ccc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0065560000700cc00000000000000000000000007777777777777777777777770000000000000000000000000000000000000000000000000000000000000000
70066000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
000000a100000023000000000000232300000000a100002300230000a1000000a100230000000000a10000002323000000a100c200000000e200000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000a100000000230000a100a100232300a100a100002300000023000000a100000000230000002300a10023a1002300a10023002300a1000023002300000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00a10000a1a1002300a100a1000023230000a10000f20000a100002300000000000000000000000000000000000000000000a100000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000a1000000000000a100a100000000a100a1a10000a10000a10000000000a1000023002300000023000000a100002300230023002323a123a12300000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000a12300000000c200000000000000a10000230000a10000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000023a1230023a10000000023000000000000a1a1a100000000a1a100000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000a1a1000000000000a123a1000000000000a10000230000a10000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000a1d20000000000a1000000a100000000a123002300230023a100000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000a1000000000000a1232323a1000000a1a1a10000230000a10000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000092a10000000000a10023232300a1000000a100a1000000a1a1a100000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a1a10000000000000000230000000000a10000008223a100a10000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000023a12300000000a100a123a100a100000000a10000a100a100a100000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
a12300000000000000000023230000002323000000a1a1000000a1a1a10000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
23a1000000000000000000000000000000000000a1a10000a100a1a100a100000000000000000000000000000000000000000000000000000000000000000000
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000000000000000000000000000
01111110011111100111111001117110011111100111111001111110011111100111111001111110011111100111111001111110011111100111111001111110
01100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110
01011010010110100101101001011010010110100101101001011010010110100101101001011010010110100101101001011010010110100101101001011010
01011010010110100101101001011010010110100101101001011010010110700101101001011010010110100101101001011010010110100101101001011010
01100110011001100110011088880110011001100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110
01111110011111100111111877778110011111100111111001111110011111100111111001111110011111100111111001111110011111100111111001111110
00000000000000000000000877780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000200020000000222877778220222002202220000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01111110200020000000222878777800200020202020000000000000000000700000000000000000000000000000000000000000000000000000000001111110
01100110200022200000202082878200220020202200000000000000000000000000000000000000000000000000000000000000000000000000000001100110
01011010200020200000202020080200200020202020000000000000000000000000000000000000000000000000000000000000000000000000000001011010
01011010222022200000202022200200222022002020000000000000000000000000000000000000000000000000000000000000000000000000000001011010
01100110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001100110
01111110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001111110
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000007000000000000000000000000000000000000000000070000000000000000000000
01111110000000000000000000000000000000000000000000000000000077700000000000000000000000000000000000000000000000000000000001111110
01100110000000000000000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000000000001100110
01011010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001011010
01011010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001011010
01100110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001100110
01111110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001111110
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000000000000
00000000000000000000000011111111111111111111111111111111111111111111111111111111111111117771111111111111100000000000000000000000
01111110000000000000000010000000100000001000000010000000100000001000000010000000100000001700000010000000100000000000000001111110
01100110000000000000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000000000000001100110
01011010000000000000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000000000000001011010
01011010000000000000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000000000000001011010
01100110000000000000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000000000000001100110
01111110000000000000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000000000000001111110
00000000000000000000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000000000000000000000
00000000000000000000000011111111111111111111111111111111111111111111111111111111111111111111111111111111100000000000000000000000
01111110000700000000000010000000100330001003300010000000100000001003300010033000100000001000000010000000100000070000000001111110
01100110007770000000000010000000106336001063360010000000100000001063360010633600100000001000000010000000100000000000000001100110
01011010000700000000000010000000103333001033330010000000100000001033330010333300100000001000000010000000100000000000000001011010
01011010000000700000000010000000163333601633336010000000100000001633336016333360700000001000000010000000100000000000000001011010
01100110000000000000000010000000133337301333333010000000100000001333333013333330100000001000000010000000100000000000000001100110
01111110000000000000000010000000633333366333333610000000100000006333333663333336700000001000000010000000100000000070000001111110
00000000000000000000000010000000333333333333333310000000100000003333333333333333100000007000000010000000100000000000000000000000
00000000000000000000000011111111111111111111111111111111111111111117711111111111111771111111111111111111100000000700000000000000
01111110000000000000000010000000100000001000000010000000100000001006600010000000100660001000000010000000100000007770000001111110
01100110000000000000000010000000100000001000000010000000100000001065560010000000106556001000000010000000100000000700000001100110
01011010000000000000000010000000100000001000000010000000100000001655756010000000165575601000000010000000100000000000000001011010
01011010000000000000000010000000100000001000000010000000100000001657556010000000165755601000000010000000100000000000000001011010
01100110000000000000000010000000100000001000000010000000100000001065560010000000106556001000000010000000100000000000000001100110
01111110000000000000000010000000100000001000000010000000100000001065560010000000106556001000000010000000100000000000000001111110
00000007000000000000000010000000100000001000000010000000100000001006600010000000100660001000000010000000100000000000000000000000
00000077700000000000000011111111111111111111111111111111111111111111111111177111111111111111111111111111100000000000000000000000
01111117000000000000000010000000100000001003300010000000100111001001110010066000100000001003300010000000100000000000000001111110
01100110000000000000000010000000100000001063360010000000101111101011111010655600100000001063360010000000100000000000000001100110
01017010000000000000000010000000100000071033330010000000111ccc11111ccc1116557560100000001033330010000000100000007000000001011010
01077710000000000000000010000000100000001633336010000000111ccc11111ccc1116575560100000001633336010007000100000077700000001011010
011071100000000000000000100000001000000013333330100000001011c1101011c11010657600100000001333333010077700100000007000000001100110
011111100000000000000000100000001000000063333336100000001001c1001001c10010677700100000006333333610007000100000000000000001111110
000000000000000000000000100000001000000033333333100000001011c1101011c11010067000100000003333333310000000100000000000000000000000
000000000000000000000000111111111111111111111111111111111111c111111aa11111111111111771111111111111111111100000000000000000000000
011111100000000000000000100000001000000010000000100000001000c000100ff00010000000100660001003300010000000100000000000000001111110
011001100000000000000000100000001000000010000000100000001000c00010f99f0010000000106556001063360010000000100000000000000001100110
010110100000000000000000100000001000000010000000100000001000c0001f99a9f010000000165575601033330010000000100000000700000001011010
010110100000000000000000100000001000000010000000100000001000c0001f9a99f010000000165755601633336010000000100000000070000001011010
011001100000000000000000100000001000000010000000100000001000c00010f99f0010000000106556001333333010000000100000000000000001100110
011111100000000000000000100000001000000010000000100000001000c00010f99f0010000000106576006333333610000000100000000000000001111110
000000000000000000000000100000001000000010000000100000001000c000100ff00010000000100660003333333310000000100000000000000000000000
00000000000000000000000011111111111111111111111111177111111aa1111111c11111111111111111111111111111111111100000000000000000000000
01111110000000000000000010000000100330001000000010066000100770001000c00010000000100000001000000010000000100000000000000001111110
01100110000000000000000010000000106336001000000010655600107777001000c00010000000100000001000000010000000100000000000000001100110
0101101000000000000000001000000010333300100000001655756017ff7f701000c00010000000100000001000000010000000100000000000000001011010
0101101000000000000000001000000016333360100000001657556017f7ff701000c00010000000100000001000000010000000100000000000000001011010
01100110000000000000000010000000133333301000000010655600107ff7001000c00010000000100000001000000010000000100000000000000001100110
01111110000000000000000010000000633333361000000010655600107ff7001000c00010000000100000001000000010000000100000000000000001111110
00000000000000000000000010000000333333331000000010066000100770001000c00010000000100000001000000010000000100000000000000000000000
00000000000000000000000011111111111111111111111111111111111aa1111111c11111111111111111111111111111111111100000000000000000000000
01111110000000000000000010000000100330001000000010000000100330001000c00010033000100000001003300010000000100000000000000001111110
01100110000000000000000010000000106336001000000010000000103bb3001000c00010633600100000001063360010000000100000000000070001100110
0101101000000000000000001000000010333300100000001000000013bb7b301000c00010333300100000001033330010000000170000000000000001011010
0101101000000000000000001000000016333360100000001000000013b7bb301000c00016333360100000001633336010000000777000000000000001011010
01100110000000000000000010000000133333301000000010000000103bb3001000c00013333330100000001333333010000000170000000000000001100110
01111110000000000000000010000000633333361000000010000000103bb3001000c00063333336100000006333333610000000100000000000000001111110
00000000000000000000000010000000333333331000000010000000100330001000c00033333333100000003333333310000000100000000000000000000000
000000000000000000000000111111111111111111177111111111111111c1111111c11111111111111111111111111111111111100000000000000000000000
011111100000000000000000100000001000000010066000100000001000c0001000c00010033000100000001003300010000000100000000000000001711110
011001100000000000000000100000001000000010655600100000001000c0001000c00010633600100000001063360010000000100000000000000001100110
010110100000000000000000100000001000000016557560100000001000c0001000c00010333300100000001033330010000000100000000000000001011010
010110100000000000000000100000001000000016575560100000001000c0001000c00016733360100000001633336010000000100000000000000001011010
011001100000000000000000100000001000000010655600100000001000c0001000c00013333330100000001333333010000000100000000000000001100110
011111100000000000000000100000001000000010655600100000001000c0001000c00063333336100000006333333610000000100000000000000001111110
000000000000000000000000100700001000000010066000100000001000c0001000c00033333333100000003333333310000000100000000000000000000000
000000000000000000000000117771111111111111111111111111111111c1111111c11111111111111111111111111111111111100000000000000000000000
011111100000000000000000100700001003300010000000100000001000c0001000c00010000000100000001000000010000000100000000000000001111110
011001100000000000000000100000001063360010000000100000001000c0001000c00010000000100007001000000010000000100000000000000001100110
010110100000000000000000100000001033330010000000100000001000c0001000c00010000000100077701000000010000000100000000000000001011010
010110100000000000000000100000001633336010000000100000001000c0001000c00010000000100007001000000010000000100000000000000001011010
011001100000000000000000107000001333333010000000100000001000c0001000c00010000000100000001000000010000000100000000000000001100110
011111100000000000000000177700006333333610000000100000001000c0001000c00010000700100000001000000010000000100000000000000001111110
000000000000000000000000107000003333333310000000100000001000c0001000c00010000000100000001000000010000000100000000000000000700000
000000000000000000000000111771111111111111111111111111111111c1111111c11111111111111111111111111111111111100000000000000007770000
011111100000000000000000100660001000000010007000100000001000c0001000c00010000000100000001000000010000000100000000000000001711110
011001100000000000000000106556001000000010077700100000001000c0001000c00010000000100000001000000010000000100000000000000001100110
010110100000000000070000165575601000000010007000100000001000c0001000c00010000000100000001000000010000000100000000000000001011010
010110100000000000777000165755601000000010000000100000001000c0001000c00010000000100000001000000010000000100000000000000001011010
07100110000000000007000010655600100000001000000710000000100000001000000010000000100000001000000010000000100000000000000001100110
77711110000000000000000010655600170000001000000010000000100000001000000010000000100000001000000010000000100000000000000001111110
07000000000000000000000010066000100000001000000010000000100000001000000010000000107000001000000010000000100000000000000000000000
00000000000000000000000011111111111111111111111111111111111111111111111111111111177711111111111111111111100000000000000000000000
01111110000000000000000000000000000000000000000000000000000000000000000000000000007000000000000000000000000000000000000001111110
01100110000000000000000000000000000000000000000000000070000000000000000000222000001110000000000000000000000000000000000001100110
01011010000000000700000000000000070000000000000000000000000000000000000000202000001110000000000000000000000000000000000001011010
01011010000000007770000000000000000000000000000000000000000000000000000000220000001010000000000000000000000000000000000001011010
01100110000000000700000000000000000000000000000000000000000000000000000000202000001010000000000000000000000000000000000001100110
01111110000000000000000000000000000000000000000000000000000000000000000000202000001010000000000000000000000000000000000001111110
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000bbbbbbbb0000000000222222000000000000000000000000000000000000000000000000
011111100000000000000000000000000000000000000000000cc000b05c550b000000002220d002000000000000000000000000000000000000000001111110
011001100000000000000000000000000000000000000000000cc000b00c500b00000000200d0d00011111100000000000000000000000000000000001100110
010110100000000000000000000000000000000000000000000cc000b05cc50b0000000002022020000000000000000000000000000000000000070001011010
010110100000000000000000000000000000000000000000000cc000b05cc50b0000000002022020011111100000000000000000000000000000000001011010
011001100000000000000000000000000000000000000000000cc000b005c00b0000000002022020000000000000000000000000000000000000000001100110
011111100000000000000000000000000000000000000000000cc000b055c50b0000000007022020011111100000000000000000000000000000000001111110
000000000000000000000000000000000000000000000000000cc000b05cc50b0000000002022020000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000bbbbbbbb0000000000000000000000000000000000000000000000000000000000000000
01111110011111100111111001111110011111100111111001111110011111100111111001111110011111100111111001111110011111100111111001111110
01100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110011001100110
01011010010110100101101001011010010110100101101001011010010110100101101001011010070110100101101001011010010110100101101001011010
01011010010110100101101001011010010110100101101001011010010110100101101001011010777110100101101001011010010110100101101001011010
01100110011001100110011001100110011001100110011001100110011001100110011001100110071001100110011001100110011001100110011001100110
01111110011111100111111001111110011111100111111001111110011111100111111001111110011111100111111001111110011111100111111001111110
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

__map__
0101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000000000000000000000000000001011a1a1a1a1a1a1a1a1a1a1a1a1a1a01010000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000000000000000000000000000001011a1a1a1a1a1a1a1a1a1a1a1a1a1a01010000000000004546470000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202020001011a1a1a1a1a1a1a1a1a1a1a1a1a1a01010000000000005556570000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202020001011a1a1a1a1a1a1a1a1a1a1a1a1a1a01010001010101010101010101010100010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202020001011a3435363436373534333736381a01010033350133383436353337363400010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202020001011a3300000000000000000000351a01010000000100000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202020001011a3800000000000000000000331a01010000000100000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202020001011a3500000000000000000000341a01010000000100000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202020001011a3600000000000000000000361a01010000000100000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202020001011a3338343835363336343833351a01010000000100000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202020001011a1a1a1a1a1a1a1a1a1a1a1a1a1a01010000000100000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202020001011a1a1a1a1a1a1a1a1a1a1a1a1a1a01010000000100000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000002020202020202020202020001011a1a1a1a1a1a1a1a1a1a1a1a1a1a01010000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01000000000000000000000000000001011a1a1a1a1a1a1a1a1a1a1a1a1a1a01010000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a321a1a1a1a1a1a1a2b1a1a1a000000001a1a1a1a1a1a1a1a1a1a1a1a1a0000000000000000002b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a321a321a1a1a1a1a001a1a00000032323200001a2e32001a1a1a1a1a1a1a001a001a001a001a001a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a321a321a1a1a001a1a1a0000000000001a001a1a1a321a1a1a1a1a1a1a1a001a001a001a001a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a321a321a001a1a1a1a0032000000000000001a1a321a1a0032001a1a003232323232323232320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1a1a1a1a00320032001a1a00320000003200321a1a1a1a321a001a1a1a1a1a1a321a1a1a000000001a1a321a1a321a321a1a1a1a1a001a001a1a1a1a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1a1a1a1a001a1a1a1a1a1a1a1a1a001a1a1a1a1a1a1a1a1a001a321a1a1a1a0032001a1a1a00001a1a1a00001a321a321a1a1a1a1a1a001a001a1a1a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1a1a1a1a001a1a1a1a1a1a1a1a1a001a1a1a1a1a1a1a1a001a321a321a1a1a0000000000000000001a1a1a321a321a00321a323232323232323232000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1a1a1a1a281a1a1a1a1a1a1a1a1a281a1a1a1a1a1a1a001a1a1a321a321a320000000000000000001a1a1a0032001a1a1a1a001a001a001a001a001a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a001a1a1a1a1a321a321a00000000000000001a1a1a1a1a1a1a1a1a1a1a1a001a001a001a001a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a2f1a1a1a1a1a1a1a321a1a1a281a001a1a1a321a1a1a1a1a1a1a1a1a1a1a2f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1a001a00000000001a00000000000000000000000000000000000000001a00003200000000001a001a0000001a1a0000001a3200320032321a321a320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000323200001a1a001a003232001a001a001a0000321a32000000001a0032000000000000001a0000000000001a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2e0000001a0000320000001a0000323200001a000000003200001a000000320000000000001a00001a00000032320000001a3200321a001a003200320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001a00000000003200001a001a003232001a001a0000001a000032001a000032000000000000001a000000320000320000000028000000002e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000001a000032001a00000000000000000000000000320032001a0000000000002900320000002e00000000000000002a320000001a00000000320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001a1a000000003200002e00320000000032002a001a000032000000000000000000002d0032003200320000323200003200320000002a001a0000320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
0003000023510265201d3001d300162001620022100221001c4000f0000d0000100014000130001d00012000245002000011000100000f0000e00000000000000000000000000000000000000000000000000000
000300001a01021510260102a52000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000300001271000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000300000b73000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000500000f510145101951014520115101b5102051024510275102c51030520000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
