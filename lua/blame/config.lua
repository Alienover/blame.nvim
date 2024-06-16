local formats = require("blame.formats.default_formats")

---@alias FormatFn fun(line_porcelain: Porcelain, config:Config, idx:integer):LineWithHl

---@class Mappings
---@field commit_info string | string[]
---@field stack_push string | string[]
---@field stack_pop string | string[]
---@field show_commit string | string[]
---@field close string | string[]

---@class Config
---@field date_format? string Format of the output date
---@field merge_consecutive boolean Merge consecutive commits and don't repeat
---@field colors string[] | nil List of colors to use for highlights. If nill will use random RGB
---@field format_fn FormatFn Function that formats the output, default: require("blame.formats.default_formats").date_message
---@field max_summary_width number Max width of the summary in 'date_summary' format
---@field mappings Mappings
local config = {
  date_format = "%d.%m.%Y",
  merge_consecutive = false,
  max_summary_width = 30,
  colors = nil,
  format_fn = formats.commit_date_author_fn,
  mappings = {
    commit_info = "i",
    stack_push = "<TAB>",
    stack_pop = "<BS>",
    show_commit = "<CR>",
    close = { "<esc>", "q" },
  },
  ns_id = vim.api.nvim_create_namespace("blame_ns"),
}

return config
