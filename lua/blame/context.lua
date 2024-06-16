local Git = require("blame.git")

--- @class Context
--- @field config Config
---
--- @field original_win integer?
--- @field original_buf integer?
---
--- @field git_client Git
local M = {}

--- @return Context
function M:new(config)
  local ctx = {}

  setmetatable(ctx, { __index = self })

  ctx.config = config

  ctx.git_client = Git:new(config)

  ctx.original_win = vim.api.nvim_get_current_win()
  ctx.original_buf = vim.api.nvim_get_current_buf()

  return ctx
end

return M
