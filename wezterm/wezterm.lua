-- These are the basic's for using wezterm.
-- Mux is the mutliplexes for windows etc inside of the terminal
-- Action is to perform actions on the terminal
local wezterm = require 'wezterm'
local mux = wezterm.mux
local act = wezterm.action

-- These are vars to put things in later (i dont use em all yet)
local config = {}
local keys = {}
local mouse_bindings = {}
local launch_menu = {}

-- This is for newer wezterm vertions to use the config builder 
if wezterm.config_builder then
  config = wezterm.config_builder()
end

-- Default config settings
-- These are the default config settins needed to use Wezterm
-- Just add this and return config and that's all the basics you need

-- Color scheme, Wezterm has 100s of them you can see here:
-- https://wezfurlong.org/wezterm/colorschemes/index.html
config.color_scheme = 'Catppuccin Mocha'
-- This is my chosen font, we will get into installing fonts on windows later
config.font = wezterm.font('JetBrains Mono')
config.font_size = 11
config.launch_menu = launch_menu
-- makes my cursor blink 
config.default_cursor_style = 'BlinkingBar'
config.disable_default_key_bindings = true

-- disables windows size changing when increasing font size
config.adjust_window_size_when_changing_font_size = false

config.keys = {
  -- this adds the ability to use ctrl+v to paste the system clipboard 
  { key = 'V',
    mods = 'CTRL',
    action = act.PasteFrom 'Clipboard',
  },
  -- Can search for a specific command that's potentially built into wez
  {
    key = 'P',
    mods = 'CTRL',
    action = wezterm.action.ActivateCommandPalette,
  },
  {
    key = 'f',
    mods = 'SUPER|SHIFT',
    action = wezterm.action.ToggleFullScreen,
  },
  { -- hotkeys for increasing and decreasing font size for streaming
    key = '=', mods = 'CTRL', action = wezterm.action.IncreaseFontSize
  },
  {
    key = '-', mods = 'CTRL', action = wezterm.action.DecreaseFontSize
  },
  { -- open a new tab in the Fedora home directory
    key = 't', mods = 'SUPER',
    action = act.SpawnCommandInNewTab { cwd = '/home/auri' },
  },
  { -- same as Win+T, but on Ctrl+T (note: shadows readline transpose / fzf trigger)
    key = 't', mods = 'CTRL',
    action = act.SpawnCommandInNewTab { cwd = '/home/auri' },
  },
  { -- AHK bridge for the binding above: Windows swallows Win+T (taskbar),
    -- so the startup AHK script translates Win+T into Ctrl+Shift+F13
    key = 'F13', mods = 'CTRL|SHIFT',
    action = act.SpawnCommandInNewTab { cwd = '/home/auri' },
  },
  { -- open the sshs host picker in a new tab (see 'new-ssh-tab' handler below)
    key = 's', mods = 'CTRL', action = wezterm.action.EmitEvent 'new-ssh-tab',
  },
  { key = '[', mods = 'CTRL', action = wezterm.action.EmitEvent 'opacity-dec', },
  { key = ']', mods = 'CTRL', action = wezterm.action.EmitEvent 'opacity-inc', },
}
config.initial_rows = 48
config.initial_cols = 150

config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
config.enable_kitty_keyboard = false

-- ── Top bar: clean, minimal tab bar + integrated window buttons ────────────
-- The bar blends into the Catppuccin Mocha background; the active tab uses the
-- terminal's own base colour so it melts into the content area.
config.use_fancy_tab_bar = true
-- Integrated min/max/close buttons: dimmed to match the inactive tabs so they
-- sit quietly in the bar.
config.integrated_title_button_color = '#6c7086'
config.integrated_title_button_alignment = 'Right'
config.integrated_title_buttons = { 'Hide', 'Maximize', 'Close' }
-- Keep the bar visible with a single tab, otherwise the window buttons
-- (min/max/close) and the draggable strip vanish.
config.hide_tab_bar_if_only_one_tab = false
config.show_new_tab_button_in_tab_bar = false   -- drop the "+" button
config.show_tab_index_in_tab_bar = false         -- no "1:" prefixes
config.tab_max_width = 28

-- The integrated title-bar strip and the window buttons.
config.window_frame = {
  font = wezterm.font { family = 'JetBrainsMono NFM', weight = 'Regular' },
  font_size = 10.0,                 -- smaller font = slimmer bar
  active_titlebar_bg = '#181825',   -- mantle: blends with the bar
  inactive_titlebar_bg = '#181825',
  button_fg = '#6c7086',            -- dim until hovered
  button_bg = '#181825',
  button_hover_fg = '#cdd6f4',
  button_hover_bg = '#313244',
}

-- Tab colours (overrides only the tab bar; color_scheme handles everything else).
config.colors = {
  tab_bar = {
    background = '#181825',                       -- mantle
    active_tab = {
      bg_color = '#1e1e2e',                       -- base: melts into terminal
      fg_color = '#cba6f7',                       -- mauve accent
      intensity = 'Bold',
    },
    inactive_tab = {
      bg_color = '#181825',
      fg_color = '#6c7086',                       -- dimmed
    },
    inactive_tab_hover = {
      bg_color = '#313244',
      fg_color = '#cdd6f4',
      italic = false,
    },
    new_tab = { bg_color = '#181825', fg_color = '#6c7086' },
    new_tab_hover = { bg_color = '#313244', fg_color = '#cdd6f4' },
  },
}

-- Minimal tab label: just a padded, trimmed title — no index/process clutter.
wezterm.on('format-tab-title', function(tab)
  local title = tab.tab_title
  if not title or #title == 0 then
    title = tab.active_pane.title
  end
  title = title:gsub('^%s*(.-)%s*$', '%1')        -- trim whitespace
  return '  ' .. title .. '  '
end)

-- ── Custom event handlers (wired to the EmitEvent keybinds above) ──────────

-- Ctrl+S: open the sshs host picker in a new tab.
-- Absolute path + explicit flags: WezTerm spawns without a login shell, so
-- neither PATH (~/.cargo/bin) nor the interactive `sshs` alias apply.
wezterm.on('new-ssh-tab', function(_, pane)
  pane:window():spawn_tab {
    args = {
      '/home/auri/.cargo/bin/sshs',
      '-c', '/mnt/c/Users/KA3135/.ssh/config',
      '-t', 'ssh.exe {{{name}}}',
      '-e',
    },
  }
end)

-- Ctrl+[ / Ctrl+]: step the window opacity down/up for this window.
-- (Uses window_background_opacity: the config.background image layer points at
-- a non-existent placeholder file, so adjusting its opacity shows nothing.)
local DEFAULT_TRANSPARENCY_STEP = 0.1

wezterm.on('opacity-inc', function(window, _)
  local overrides = window:get_config_overrides() or {}
  local current = overrides.window_background_opacity or 1.0
  overrides.window_background_opacity = math.min(current + DEFAULT_TRANSPARENCY_STEP, 1.0)
  window:set_config_overrides(overrides)
end)

wezterm.on('opacity-dec', function(window, _)
  local overrides = window:get_config_overrides() or {}
  local current = overrides.window_background_opacity or 1.0
  overrides.window_background_opacity = math.max(current - DEFAULT_TRANSPARENCY_STEP, 0.2)
  window:set_config_overrides(overrides)
end)


-- There are mouse binding to mimc Windows Terminal and let you copy
-- To copy just highlight something and right click. Simple
mouse_bindings = {
  {
    event = { Down = { streak = 3, button = 'Left' } },
    action = wezterm.action.SelectTextAtMouseCursor 'SemanticZone',
    mods = 'NONE',
  },
 {
  event = { Down = { streak = 1, button = "Right" } },
  mods = "NONE",
  action = wezterm.action_callback(function(window, pane)
   local has_selection = window:get_selection_text_for_pane(pane) ~= ""
   if has_selection then
    window:perform_action(act.CopyTo("ClipboardAndPrimarySelection"), pane)
    window:perform_action(act.ClearSelection, pane)
   else
    window:perform_action(act({ PasteFrom = "Clipboard" }), pane)
   end
  end),
 },
}

-- Apply the mouse bindings now that the table is fully defined.
config.mouse_bindings = mouse_bindings

-- This is used to make my foreground (text, etc) brighter than my background
config.foreground_text_hsb = {
  hue = 1.0,
  saturation = 1.2,
  brightness = 1.5,
}


-- This is used to set an image as my background
config.background = {
    {
        source = { File = {path = 'C:/Users/someuserboi/Pictures/Backgrounds/theone.gif', speed = 0.2}},
 opacity = 1,
 width = "100%",
 hsb = {brightness = 0.5},
    }
}

-- IMPORTANT: Sets WSL2 UBUNTU-22.04 as the defualt when opening Wezterm. Get name with wsl --list
-- config.default_domain = 'WSL:Ubuntu-24.04'
config.default_domain = 'WSL:FedoraLinux-44'

return config
