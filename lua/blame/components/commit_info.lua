local utils = require("blame.utils")
local mappings = require("blame.mappings")

---@class CommitInfo
---@field config Config
---@field window integer?
local CommitInfo = {}

--- @param ctx Context
--- @return CommitInfo
function CommitInfo:new(ctx)
  local o = {
    config = ctx.config,

    window = nil,
  }

  setmetatable(o, { __index = self })

  return o
end

--- @param commit Porcelain
function CommitInfo:render(commit)
  local content = {}
  local longest_key_length = 1
  for k, _ in pairs(commit) do
    if not utils.ends_with(k, "tz") and k ~= "content" then
      if #k > longest_key_length then
        longest_key_length = #k
      end

      table.insert(content, k)
    end
  end

  table.sort(content)

  local width = longest_key_length
  for idx, key in ipairs(content) do
    local value = commit[key]

    if key == "previous" then
      value = string.format("%s %s", value.hash, value.filename)
    elseif utils.ends_with(key, "time") then
      value = os.date(self.config.date_format, value)
    end

    local row = string.format(
      "%s: %s%s",
      key,
      string.rep(" ", longest_key_length - #key),
      value
    )
    content[idx] = row

    if #row > width then
      width = #row
    end
  end
  local height = #content

  local buffer = vim.api.nvim_create_buf(false, true)

  self.window = vim.api.nvim_open_win(buffer, false, {
    relative = "cursor",
    col = 0,
    row = 1,
    width = width + 8,
    height = height,
    border = "rounded",
  })

  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, content)

  vim.api.nvim_set_option_value("modifiable", false, { buf = buffer })
  vim.api.nvim_set_option_value("scrollbind", false, { win = self.window })
  vim.api.nvim_set_option_value("cursorbind", false, { win = self.window })
  vim.api.nvim_set_option_value("cursorline", false, { win = self.window })

  for idx, line in ipairs(content) do
    local key_end = string.find(line, ":") - 1
    vim.api.nvim_buf_add_highlight(
      buffer,
      self.config.ns_id,
      "Comment",
      idx - 1,
      0,
      key_end
    )
  end

  return buffer
end

function CommitInfo:is_open()
  return self.window ~= nil
end

function CommitInfo:close()
  if self.window ~= nil and vim.api.nvim_win_is_valid(self.window) then
    vim.api.nvim_win_close(self.window, true)
  end

  self.window = nil
end

---@param commit Porcelain
function CommitInfo:open(commit)
  if self.window then
    vim.api.nvim_set_current_win(self.window)
    return
  end

  local bufnr = self:render(commit)

  mappings.set_keymap(
    "n",
    "close",
    ":q<cr>",
    { buffer = bufnr, nowait = true, silent = true, noremap = true },
    self.config
  )

  vim.api.nvim_create_autocmd({ "BufHidden", "BufUnload" }, {
    callback = function()
      self:close()
    end,
    buffer = bufnr,
    group = vim.api.nvim_create_augroup("NvimBlame", { clear = false }),
    desc = "Clean up info window on buf close",
  })
end

return CommitInfo
