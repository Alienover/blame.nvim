local utils = require("blame.utils")
local mappings = require("blame.mappings")
local highlights = require("blame.highlights")
local blames_parser = require("blame.porcelain_parser")

local Context = require("blame.context")
local CommitInfo = require("blame.components.commit_info")
local CommitDetail = require("blame.components.commit_detail")
local BlameStack = require("blame.components.blame_stack")

local blame_enabled_options =
  { "scrollbind", "cursorbind", "cursorline", "wrap" }

---@param lines_with_hl LineWithHl[]
---@return string[]
local function lines_with_hl_to_text_lines(lines_with_hl)
  local text_lines = {}
  for _, line in ipairs(lines_with_hl) do
    local text_fragments = {}
    for _, value in ipairs(line.values) do
      table.insert(text_fragments, value.textValue)
    end
    table.insert(
      text_lines,
      string.format(line.format, (table.unpack or unpack)(text_fragments))
    )
  end
  return text_lines
end

---@class BlameView
---@field original_win_opts table
---@field window integer?
---@field buffer integer?
---@field blame_stack BlameStack?
---@field blames Porcelain[]
---@field config Config
---@field ctx Context
---@field commit_info CommitInfo
---@field commit_detail CommitDetail
local View = {}
View.__index = View

--- @param config Config
function View.new(config)
  local self = setmetatable({}, View)

  self.original_win_opts = {}
  self.window = nil
  self.buffer = nil
  self.blame_stack = nil
  self.blames = {}

  self.config = config
  self.ctx = Context:new(config)
  self.commit_info = CommitInfo:new(self.ctx)
  self.commit_detail = CommitDetail:new(self.ctx)

  return self
end

function View:clear()
  self = setmetatable({}, View)
end

--- @param text_lines string[]
function View:setup_blame_window(text_lines)
  if self.window == nil then
    vim.api.nvim_command("leftabove vnew")

    self.buffer = vim.api.nvim_get_current_buf()
    self.window = vim.api.nvim_get_current_win()
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = self.buffer })

  vim.api.nvim_buf_set_lines(self.buffer, 0, -1, false, text_lines)

  local width = utils.longest_string_in_array(text_lines) + 8
  vim.api.nvim_win_set_width(self.window, width)
  vim.api.nvim_win_set_hl_ns(self.window, self.config.ns_id)

  local blame_buf_opts = {
    bufhidden = "wipe",
    buftype = "nofile",
    buflisted = false,
    swapfile = false,
    modifiable = false,
    ft = "blame",
  }

  local blame_win_opts = {
    spell = false,
    number = false,
    relativenumber = false,
    winbar = string.rep(" ", 4) .. "Git Blame",
    winfixwidth = true,
    foldcolumn = "0",
    foldenable = false,
    signcolumn = "no",
  }

  -- Sync cursor position before setting scrollbind and cursorline
  self:setup_cursor()

  for opt, value in pairs(blame_buf_opts) do
    vim.api.nvim_set_option_value(opt, value, { buf = self.buffer })
  end

  for opt, value in pairs(blame_win_opts) do
    vim.api.nvim_set_option_value(opt, value, { win = self.window })
  end

  for _, opt in ipairs(blame_enabled_options) do
    self.original_win_opts[opt] =
      vim.api.nvim_get_option_value(opt, { win = self.ctx.original_win })

    vim.api.nvim_set_option_value(opt, true, { win = self.ctx.original_win })
    vim.api.nvim_set_option_value(opt, true, { win = self.window })
  end
end

--- @param lines_with_hl LineWithHl[]
function View:apply_highlights(lines_with_hl)
  for _, line in ipairs(lines_with_hl) do
    for _, value in ipairs(line.values) do
      if value.hl and value.start_index > 0 and value.end_index > 0 then
        vim.api.nvim_buf_add_highlight(
          self.buffer,
          self.ctx.config.ns_id,
          value.hl,
          line.idx - 1,
          value.start_index - 1,
          value.end_index
        )
      end
    end
  end
end

function View:setup_cursor()
  -- INFO: scroll to the top as the original window
  -- to keep the cursor at the same position
  local current_top = vim.fn.line("w0", self.ctx.original_win)
    + vim.api.nvim_get_option_value(
      "scrolloff",
      { win = self.ctx.original_win }
    )

  vim.api.nvim_win_set_cursor(self.window, { current_top, 0 })
  vim.cmd.normal({ "zt", bang = true })

  -- INFO: set cursor to the current line
  local row = unpack(vim.api.nvim_win_get_cursor(self.ctx.original_win))
  vim.api.nvim_win_set_cursor(self.window, { row, 0 })
end

function View:setup_autocmd()
  self.auto_group = vim.api.nvim_create_augroup("NvimBlame", { clear = true })

  vim.api.nvim_create_autocmd({ "BufHidden", "BufUnload" }, {
    group = self.auto_group,
    buffer = self.buffer,
    desc = "Reset state to closed when the buffer is exited.",

    callback = function()
      print("blame window is about to close")
      self.commit_info:close()
      self:close(self.ctx.original_win)
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "WinLeave" }, {
    group = self.auto_group,
    buffer = self.buffer,
    desc = "Remove info window on cursor move",

    callback = function()
      if self.commit_info:is_open() == true then
        self.commit_info:close()
      end
    end,
  })
end

function View:setup_keybinds()
  --- @param fn fun(commit: Porcelain)
  local function with_commit(fn)
    return function()
      local row, _ = unpack(vim.api.nvim_win_get_cursor(self.window))
      local commit = self.blames[row]

      fn(commit)
    end
  end

  local bindings = {
    close = ":q<cr>",
    show_commit = with_commit(function(commit)
      self.commit_detail:open({
        commit = commit,
        parent = self.window,
      })
    end),
    stack_push = with_commit(function(commit)
      self.blame_stack:push(commit)
    end),
    stack_pop = function()
      self.blame_stack:pop()
    end,
    commit_info = with_commit(function(commit)
      self.commit_info:open(commit)
    end),
  }

  for bind_name, handler in pairs(bindings) do
    mappings.set_keymap("n", bind_name, handler, {
      buffer = self.buffer,
      nowait = true,
      silent = true,
      noremap = true,
    }, self.ctx.config)
  end
end

--- @param lines Porcelain[]
function View:create_highlights(lines)
  highlights.create_highlights_per_hash(lines, self.ctx.config)

  local lines_with_hl =
    highlights.get_hld_lines_from_porcelain(lines, self.ctx.config)
  local text_lines = lines_with_hl_to_text_lines(lines_with_hl)

  return text_lines, lines_with_hl
end

--- @param next_win integer?
function View:close(next_win)
  if not self:is_open() then
    return
  end

  if self.auto_group ~= nil then
    local auto_cmds = vim.api.nvim_get_autocmds({
      group = self.auto_group,
      buffer = self.buffer,
    })

    -- Clear all related auto cmds
    for _, cmd in ipairs(auto_cmds) do
      vim.api.nvim_del_autocmd(cmd.id)
    end

    vim.api.nvim_del_augroup_by_id(self.auto_group)
  end

  -- Reset original window options
  if vim.api.nvim_win_is_valid(self.ctx.original_win) then
    for _, opt in ipairs(blame_enabled_options) do
      vim.api.nvim_set_option_value(
        opt,
        self.original_win_opts[opt],
        { win = self.ctx.original_win }
      )
    end

    self.original_win_opts = {}
  end

  self.window = nil
  self.buffer = nil
  self.ctx = nil

  -- Reset blame stack
  self.blame_stack:close()

  vim.api.nvim_exec_autocmds(
    "User",
    { pattern = "BlameViewClosed", modeline = false, data = "window" }
  )

  if next_win ~= nil and vim.api.nvim_win_is_valid(next_win) then
    vim.schedule(function()
      vim.api.nvim_set_current_win(next_win)
    end)
  end
end

--- @param blames Porcelain[]
function View:render(blames)
  local text_lines, lines_with_hl = self:create_highlights(blames)

  self:setup_blame_window(text_lines)

  self:apply_highlights(lines_with_hl)

  self.blames = blames
end

function View:open()
  local filename = vim.api.nvim_buf_get_name(self.ctx.original_buf)

  self.ctx.git_client:blame(filename, nil, function(data)
    local lines = blames_parser.parse_porcelain(data)

    self.blame_stack = BlameStack:new({
      ctx = self.ctx,
      blame_view = self,
      blames = lines,
    })

    self:render(lines)

    self:setup_autocmd()
    self:setup_keybinds()

    vim.api.nvim_exec_autocmds(
      "User",
      { pattern = "BlameViewOpened", modeline = false, data = "window" }
    )
  end)
end

function View:is_open()
  return self.window ~= nil and vim.api.nvim_win_is_valid(self.window)
end

--- @param filename string
--- @param commit string?
function View:update(filename, commit)
  if self:is_open() then
    self.ctx.git_client:blame(filename, commit, function(data)
      local lines = blames_parser.parse_porcelain(data)

      self:render(lines)
    end)
  end
end

return View
