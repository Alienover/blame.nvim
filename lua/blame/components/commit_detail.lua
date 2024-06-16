local mappings = require("blame.mappings")

--- @class CommitDetail
--- @field ctx Context
--- @field window integer?
--- @field buffer integer?
--- @field auto_group integer?
local CommitDetail = {}

--- @param ctx Context
--- @return CommitDetail
function CommitDetail:new(ctx)
  local state = {
    ctx = ctx,

    window = nil,
    buffer = nil,

    auto_group = nil,
  }

  setmetatable(state, { __index = self })

  return state
end

--- @param title string
--- @param content string[]
function CommitDetail:render(title, content)
  vim.api.nvim_command("leftabove vnew")

  self.window = vim.api.nvim_get_current_win()
  self.buffer = vim.api.nvim_get_current_buf()

  vim.api.nvim_buf_set_lines(self.buffer, 0, -1, false, content)
  vim.api.nvim_buf_set_name(self.buffer, title)
  vim.api.nvim_win_set_width(self.window, 80)

  local buffer_opts = {
    bufhidden = "wipe",
    buftype = "nofile",
    buflisted = false,
    swapfile = false,
    modifiable = false,
    readonly = true,
    syntax = "diff",
  }

  local window_opts = {
    spell = false,
    number = false,
    relativenumber = false,
    winbar = string.rep(" ", 4) .. "Commit Detail",
    winfixwidth = true,
    foldcolumn = "0",
    foldenable = false,
    signcolumn = "no",
    scrollbind = false,
    cursorbind = false,
  }

  for opt, value in pairs(buffer_opts) do
    vim.api.nvim_set_option_value(opt, value, { buf = self.buffer })
  end

  for opt, value in pairs(window_opts) do
    vim.api.nvim_set_option_value(opt, value, { win = self.window })
  end
end

--- @param parent integer?
function CommitDetail:setup_autocmd(parent)
  self.auto_group =
    vim.api.nvim_create_augroup("NvimCommitDetail", { clear = true })

  vim.api.nvim_create_autocmd({ "BufHidden", "BufUnload" }, {
    group = self.auto_group,
    buffer = self.buffer,

    callback = function()
      self:close(parent)
    end,
  })

  vim.api.nvim_create_autocmd({ "WinLeave" }, {
    group = self.auto_group,
    buffer = self.buffer,

    callback = function()
      vim.schedule(function()
        local focused_win = vim.api.nvim_get_current_win()

        if self.window ~= nil and vim.api.nvim_win_is_valid(self.window) then
          self:close(focused_win)
        end
      end)
    end,
  })
end

--- @class CommitDetailParams
--- @field parent integer?
--- @field commit Porcelain
---
--- @param o CommitDetailParams
function CommitDetail:open(o)
  self.ctx.git_client:show(o.commit.filename, o.commit.hash, function(content)
    self:render(o.commit.hash, content)

    self:setup_autocmd(o.parent)

    mappings.set_keymap("n", "close", ":q<CR>", {
      buffer = self.buffer,
      nowait = true,
      silent = true,
      noremap = true,
    }, self.ctx.config)
  end)
end

--- @param next_win integer?
function CommitDetail:close(next_win)
  local ok, auto_cmds =
    pcall(vim.api.nvim_get_autocmds, { group = self.auto_group })

  if ok then
    for _, cmd in ipairs(auto_cmds) do
      vim.api.nvim_del_autocmd(cmd.id)
    end

    vim.api.nvim_del_augroup_by_id(self.auto_group)
  end

  vim.schedule(function()
    if vim.api.nvim_win_is_valid(self.window) then
      vim.api.nvim_win_close(self.window, true)
    end

    if vim.api.nvim_buf_is_valid(self.buffer) then
      vim.api.nvim_buf_delete(self.buffer, { force = true })
    end

    if next_win ~= nil and vim.api.nvim_win_is_valid(next_win) then
      vim.api.nvim_set_current_win(next_win)
    end
  end)
end

return CommitDetail
