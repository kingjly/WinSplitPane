local wezterm = require 'wezterm'

local config = wezterm.config_builder()

config.unix_domains = {
  {
    name = 'unix',
  },
}

config.default_gui_startup_args = { 'connect', 'unix' }

return config
