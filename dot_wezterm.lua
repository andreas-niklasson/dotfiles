local wezterm = require 'wezterm'

local config = wezterm.config_builder and wezterm.config_builder() or {}

-- Default shell
config.default_prog = { 'pwsh.exe', '-NoLogo' }

-- Window size (matches initialCols/initialRows)
config.initial_cols = 140
config.initial_rows = 30

-- Font (FiraCode NF with Symbols Nerd Font as fallback for missing glyphs)
config.font = wezterm.font('FiraCode Nerd Font Mono Light')
-- config.font = wezterm.font_with_fallback({ 'FiraCode NF', 'Symbols Nerd Font Mono' })
config.font_size = 12

-- Let fonts render Nerd Font glyphs instead of WezTerm's built-in block glyph renderer
-- (without this, some PUA codepoints like \uf5ef are drawn as circles by WezTerm itself)
config.custom_block_glyphs = false

-- Cursor (vintage = blinking underline in Windows Terminal)
config.default_cursor_style = 'BlinkingUnderline'

-- Keep pane open after process exits (closeOnExit: "never")
config.exit_behavior = 'Hold'

-- Acrylic backdrop (useAcrylicInTabRow)
config.win32_system_backdrop = 'Acrylic'

-- wezterm.gui isn't available to the mux server
function get_appearance()
  if wezterm.gui then
    return wezterm.gui.get_appearance()
  end
  return 'Dark'
end

function scheme_for_appearance(appearance)
  if appearance:find 'Dark' then
    return 'GruvboxDark'
  else
    return 'GruvboxLight'
  end
end

local function lsd_theme_for_appearance(appearance)
  if appearance:find 'Dark' then
    return 'dark'
  else
    return 'light'
  end
end

local function tabline_theme_overrides(scheme)
  if scheme == 'GruvboxDark' then
    return {
      tab = {
        active = { fg = '#83a598', bg = '#504945' },
        inactive = { fg = '#a89984', bg = '#3c3836' },
        inactive_hover = { fg = '#ebdbb2', bg = '#504945' },
      },
    }
  end

  return {
    tab = {
      active = { fg = '#076678', bg = '#d5c4a1' },
      inactive = { fg = '#665c54', bg = '#ebdbb2' },
      inactive_hover = { fg = '#3c3836', bg = '#d5c4a1' },
    },
  }
end

local function copy_lsd_theme_file(theme)
  local home = os.getenv 'USERPROFILE'
  if not home then
    return false
  end

  local lsd_dir = home .. '\\.config\\lsd'
  local src_path = lsd_dir .. '\\colors-' .. theme .. '.yaml'
  local dst_path = lsd_dir .. '\\colors.yaml'

  local src = io.open(src_path, 'r')
  if not src then
    wezterm.log_error('lsd theme source not found: ' .. src_path)
    return false
  end

  local content = src:read '*a'
  src:close()

  local dst = io.open(dst_path, 'w')
  if not dst then
    wezterm.log_error('lsd theme destination not writable: ' .. dst_path)
    return false
  end

  dst:write(content)
  dst:close()
  return true
end

local function sync_lsd_colors(appearance)
  local theme = lsd_theme_for_appearance(appearance)
  if wezterm.GLOBAL.lsd_theme_synced == theme then
    return
  end

  if copy_lsd_theme_file(theme) then
    wezterm.GLOBAL.lsd_theme_synced = theme
  end
end

local appearance = get_appearance()
config.color_scheme = scheme_for_appearance(appearance)
config.set_environment_variables = {
  TERM_BACKGROUND = lsd_theme_for_appearance(appearance),
}
sync_lsd_colors(appearance)

-- Tab bar (tabline.wez) — loaded locally to avoid GitHub timeouts breaking config
local tabline_plugin_dir = (os.getenv 'USERPROFILE' .. '\\.config\\wezterm\\plugins\\tabline.wez'):gsub('\\', '/')
local tabline_plugin_url = 'file:///' .. tabline_plugin_dir

local tabline
local tabline_ok, tabline_err = pcall(function()
  tabline = wezterm.plugin.require(tabline_plugin_url)
end)

if not tabline_ok then
  wezterm.log_error('tabline.wez failed to load: ' .. tostring(tabline_err))
  config.use_fancy_tab_bar = false
  config.hide_tab_bar_if_only_one_tab = true
  config.tab_max_width = 32
else
  tabline.setup {
    options = {
      icons_enabled = true,
      theme = scheme_for_appearance(appearance),
      theme_overrides = tabline_theme_overrides(scheme_for_appearance(appearance)),
      tabs_enabled = true,
      section_separators = {
        left = wezterm.nerdfonts.pl_left_hard_divider,
        right = wezterm.nerdfonts.pl_right_hard_divider,
      },
      component_separators = {
        left = wezterm.nerdfonts.pl_left_soft_divider,
        right = wezterm.nerdfonts.pl_right_soft_divider,
      },
      tab_separators = {
        left = wezterm.nerdfonts.pl_left_hard_divider,
        right = wezterm.nerdfonts.pl_right_hard_divider,
      },
    },
    sections = {
      tabline_a = { 'mode' },
      tabline_b = { 'workspace' },
      tabline_c = { ' ' },
      tab_active = {
        'index',
        { 'parent', padding = 0 },
        '/',
        { 'cwd', padding = { left = 0, right = 1 } },
        { 'zoomed', padding = 0 },
      },
      tab_inactive = { 'index', { 'process', padding = { left = 0, right = 1 } } },
      tabline_x = {
        { 'ram', throttle = 3 },
        { 'cpu', throttle = 3, use_pwsh = true },
      },
      tabline_y = { { 'datetime', style = '%H:%M' } },
      tabline_z = { 'domain' },
    },
  }

  config.hide_tab_bar_if_only_one_tab = false
  tabline.apply_to_config(config)

  -- apply_to_config sets window_decorations = 'RESIZE'; override after it
  config.window_decorations = 'INTEGRATED_BUTTONS|RESIZE'
  config.integrated_title_button_style = 'Windows'
  config.integrated_title_button_alignment = 'Right'
  config.integrated_title_buttons = { 'Hide', 'Maximize', 'Close' }
  config.show_new_tab_button_in_tab_bar = true

  config.colors = config.colors or {}
  config.colors.tab_bar = config.colors.tab_bar or {}
  config.colors.tab_bar.new_tab = {
    bg_color = '#3c3836',
    fg_color = '#a89984',
  }
  config.colors.tab_bar.new_tab_hover = {
    bg_color = '#504945',
    fg_color = '#ebdbb2',
  }

  wezterm.GLOBAL.tabline_theme_synced = scheme_for_appearance(appearance)
end

local function sync_tabline_theme(current_appearance, window)
  if not tabline_ok then
    return
  end

  local scheme = scheme_for_appearance(current_appearance)
  if wezterm.GLOBAL.tabline_theme_synced == scheme then
    return
  end

  tabline.set_theme(scheme, tabline_theme_overrides(scheme))
  wezterm.GLOBAL.tabline_theme_synced = scheme
  if window then
    tabline.refresh(window, nil)
  end
end

wezterm.on('window-config-reloaded', function(window)
  if not wezterm.gui then
    return
  end

  local current_appearance = wezterm.gui.get_appearance()
  sync_lsd_colors(current_appearance)
  sync_tabline_theme(current_appearance, window)
end)


-- Key bindings
config.keys = {
  { key = 'c', mods = 'CTRL',       action = wezterm.action.CopyTo 'Clipboard' },
  -- Send SIGINT (ctrl+c character) since CTRL+C is now used for copy
  { key = 'c', mods = 'CTRL|SHIFT', action = wezterm.action.SendKey { key = 'c', mods = 'CTRL' } },
  { key = 'v', mods = 'CTRL',       action = wezterm.action.PasteFrom 'Clipboard' },
  { key = 'f', mods = 'CTRL|SHIFT', action = wezterm.action.Search { CaseSensitiveString = '' } },
  -- alt+shift+d: split pane (auto direction)
  { key = 'd', mods = 'ALT|SHIFT',  action = wezterm.action.SplitPane { direction = 'Right' } },
  -- alt+shift+n: duplicate pane to the right
  { key = 'n', mods = 'ALT|SHIFT',  action = wezterm.action.SplitPane { direction = 'Right' } },
  -- alt+shift+t: duplicate pane downward
  { key = 't', mods = 'ALT|SHIFT',  action = wezterm.action.SplitPane { direction = 'Down' } },
  {
      key = 'w',
      mods = 'CTRL|SHIFT',
      action = wezterm.action.CloseCurrentPane { confirm = true },
    },
}

config.exit_behavior = 'Close'  -- or 'CloseOnCleanExit'


-- Launch menu (right-click the + button in the tab bar)
config.launch_menu = {
  {
    label = 'PowerShell 7',
    args  = { 'pwsh.exe', '-NoLogo' },
  },
  {
    label = 'Ubuntu (WSL)',
    args  = { 'wsl.exe', '-d', 'Ubuntu' },
  },
  {
    label = 'Developer Command Prompt (VS 2022)',
    args  = {
      'cmd.exe', '/k',
      'C:\\Program Files\\Microsoft Visual Studio\\2022\\Community\\Common7\\Tools\\VsDevCmd.bat',
    },
  },
  {
    label = 'Developer PowerShell (VS 2022)',
    args  = {
      'pwsh.exe', '-NoExit', '-Command',
      'Import-Module "C:\\Program Files\\Microsoft Visual Studio\\2022\\Community\\Common7\\Tools\\Microsoft.VisualStudio.DevShell.dll";'
        .. ' Enter-VsDevShell -VsInstallPath "C:\\Program Files\\Microsoft Visual Studio\\2022\\Community" -SkipAutomaticLocation',
    },
  },
}

return config
