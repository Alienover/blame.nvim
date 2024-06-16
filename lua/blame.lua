local config = require("blame.config")
local blame_view = require("blame.views.blame")

---@class Blame
---@field config Config?
---@field last_opened_view nil | BlameView
local M = {
  config = nil,
  last_opened_view = nil,
}

---@return boolean | nil
M.is_open = function()
  return M.last_opened_view ~= nil and M.last_opened_view:is_open()
end

---@param setup_args Config | nil
M.setup = function(setup_args)
  M.config = vim.tbl_deep_extend("force", config, setup_args or {})

  vim.api.nvim_create_user_command("BlameToggle", function()
    local view = blame_view:new(M.config)

    -- normal open blame window
    if M.last_opened_view == nil or not M.last_opened_view:is_open() then
      view:open()
      M.last_opened_view = view
      return
    end

    local curr_win = vim.api.nvim_get_current_win()
    if M.last_opened_view.ctx.original_win == curr_win then
      view:close(curr_win)
      M.last_opened_view = nil
      return
    end

    M.last_opened_view:close()

    vim.schedule(function()
      view:open()
      M.last_opened_view = view
    end)
  end, {})
end

return M
