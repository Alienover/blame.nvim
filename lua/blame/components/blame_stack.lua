local utils = require("blame.utils")

---@class BlameStack
---@field ctx Context
---@field blame_view WindowView
---@field blames Porcelain[]
---@field stack_buffer integer
---@field stack_info_float_win integer
---@field commit_stack Porcelain[]
local BlameStack = {}

--- @class BlameStackParams
--- @field ctx Context
--- @field blame_view BlameView
--- @field blames Porcelain[]
---
--- @param params BlameStackParams
---@return BlameStack
function BlameStack:new(params)
  local o = {}
  setmetatable(o, { __index = self })

  o.ctx = params.ctx
  o.blame_view = params.blame_view

  o.stack_buffer = nil
  o.commit_stack = {}

  return o
end

--- @param filename string
---@param hash string
function BlameStack:update(filename, hash)
  local file_commit = hash .. ":" .. filename

  self.ctx.git_client:show(filename, file_commit, function(file_content)
    if file_content[#file_content] == "" then
      table.remove(file_content)
    end

    if self.stack_buffer == nil then
      self:create_blame_buf()
    end

    vim.api.nvim_win_set_buf(self.ctx.original_win, self.stack_buffer)

    vim.api.nvim_set_option_value(
      "modifiable",
      true,
      { buf = self.stack_buffer }
    )
    vim.api.nvim_buf_set_lines(self.stack_buffer, 0, -1, false, file_content)
    vim.api.nvim_set_option_value(
      "modifiable",
      false,
      { buf = self.stack_buffer }
    )

    local row, _ = unpack(vim.api.nvim_win_get_cursor(self.blame_view.window))
    vim.api.nvim_win_set_cursor(self.ctx.original_win, { row, 1 })

    self:refresh_stack_info()
  end)
end

--- @param commit Porcelain
function BlameStack:push(commit)
  if
    #self.commit_stack > 0
    and self.commit_stack[#self.commit_stack].hash == commit.hash
  then
    return
  end

  if commit.previous then
    local filename, hash =
      unpack({ commit.previous.filename, commit.previous.hash })

    table.insert(self.commit_stack, commit)
    self:refresh_stack_info()

    self.blame_view:update(filename, hash)
    self:update(filename, hash)
  else
    vim.notify(
      "Cannot go to previous commit, might be the initial commit for the file",
      vim.log.levels.INFO
    )
  end
end

function BlameStack:pop()
  if #self.commit_stack == 0 then
    return
  end
  if #self.commit_stack == 1 then
    self:close()
    return
  end

  --- @type Porcelain
  table.remove(self.commit_stack, nil)
  self:refresh_stack_info()

  local commit = self.commit_stack[#self.commit_stack]

  local filename, hash =
    unpack({ commit.previous.filename, commit.previous.hash })

  self.blame_view:update(filename, hash)
  self:update(filename, hash)
end

function BlameStack:create_blame_buf()
  self.stack_buffer = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(self.stack_buffer, " Blame Stack")

  local buffer_opts = {
    filetype = vim.api.nvim_get_option_value(
      "filetype",
      { buf = self.ctx.original_buf }
    ),
  }

  for opt, value in pairs(buffer_opts) do
    vim.api.nvim_set_option_value(opt, value, { buf = self.stack_buffer })
  end

  vim.api.nvim_create_autocmd({ "BufHidden", "BufUnload" }, {
    callback = function()
      vim.schedule(function()
        self:close()
      end)
    end,
    buffer = self.stack_buffer,
    group = vim.api.nvim_create_augroup("NvimBlame", { clear = false }),
    desc = "Reset state when closing blame buffer",
  })
end

function BlameStack:reset_to_original_buf()
  local curr_buf = vim.api.nvim_win_get_buf(self.ctx.original_win)

  if curr_buf ~= self.ctx.original_buf then
    local origina_filename = vim.api.nvim_buf_get_name(self.ctx.original_buf)
    self.blame_view:update(origina_filename)

    -- Focus original win
    if vim.api.nvim_win_is_valid(self.ctx.original_win) then
      vim.api.nvim_win_set_buf(self.ctx.original_win, self.ctx.original_buf)
    end
  end

  if
    self.blame_view.window and vim.api.nvim_win_is_valid(self.blame_view.window)
  then
    local row, _ = unpack(vim.api.nvim_win_get_cursor(self.blame_view.window))

    if vim.api.nvim_win_is_valid(self.ctx.original_win) then
      vim.api.nvim_win_set_cursor(self.ctx.original_win, { row, 1 })
    end
  end
end

function BlameStack:refresh_stack_info()
  local lines_text = {}
  for _, v in pairs(self.commit_stack) do
    table.insert(
      lines_text,
      string.format(
        "%s %s %s",
        string.sub(v.hash, 0, 7),
        os.date(self.ctx.config.date_format, v.committer_time),
        v.author
      )
    )
  end
  local width = utils.longest_string_in_array(lines_text) + 8
  local height = #self.commit_stack

  local info_buf
  if self.stack_info_float_win == nil then
    info_buf = vim.api.nvim_create_buf(false, true)

    self.stack_info_float_win = vim.api.nvim_open_win(info_buf, false, {
      relative = "win",
      win = self.ctx.original_win,
      col = vim.api.nvim_win_get_width(self.ctx.original_win),
      row = 1,
      width = width,
      height = height,
      border = "rounded",
    })
    vim.api.nvim_win_set_hl_ns(self.stack_info_float_win, self.ctx.config.ns_id)

    local win_opts = {
      number = false,
      relativenumber = false,
      signcolumn = "no",
      scrollbind = false,
      cursorbind = false,
      cursorline = false,
    }

    for opt, value in pairs(win_opts) do
      vim.api.nvim_set_option_value(
        opt,
        value,
        { win = self.stack_info_float_win }
      )
    end
  else
    info_buf = vim.api.nvim_win_get_buf(self.stack_info_float_win)

    vim.api.nvim_win_set_height(self.stack_info_float_win, height)
    vim.api.nvim_win_set_width(self.stack_info_float_win, width)
  end

  vim.api.nvim_buf_set_lines(info_buf, 0, -1, false, lines_text)
  local lns = vim.api.nvim_buf_get_lines(info_buf, 0, -1, false)
  for idx, v in ipairs(lns) do
    vim.api.nvim_buf_add_highlight(
      info_buf,
      self.ctx.config.ns_id,
      idx == #lns and string.sub(v, 0, 7) or "Comment",
      idx - 1,
      0,
      -1
    )
  end

  vim.api.nvim_win_set_cursor(self.stack_info_float_win, { height, 0 })
end

function BlameStack:close_stack_info()
  if
    self.stack_info_float_win
    and vim.api.nvim_win_is_valid(self.stack_info_float_win)
  then
    vim.api.nvim_win_close(self.stack_info_float_win, true)
  end
  self.stack_info_float_win = nil
  self.commit_stack = {}
end

function BlameStack:close_stack_buffer()
  if
    self.stack_buffer ~= nil and vim.api.nvim_buf_is_valid(self.stack_buffer)
  then
    vim.api.nvim_buf_delete(self.stack_buffer, { force = true })
  end
  self.stack_buffer = nil
end

function BlameStack:close()
  -- Reset content
  self:reset_to_original_buf()

  self:close_stack_info()
  self:close_stack_buffer()
end

---@param filename string
---@param hash string should show previous commit
---@param cb fun(any) callback on show command end
function BlameStack:get_show_file_content(filename, hash, cb)
  local file_commit = hash .. ":" .. filename

  self.ctx.git_client:show(filename, file_commit, function(file_content)
    -- most of the time empty line is inserted from git-show. Might create issues but for now this crude check works
    if file_content[#file_content] == "" then
      table.remove(file_content)
    end

    if cb ~= nil then
      cb(file_content)
    end
  end)
end

return BlameStack
