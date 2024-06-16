local utils = require("blame.utils")
local Job = require("plenary.job")

--- @class JobParams
--- @field args table<string>
--- @field root string
--- @field on_success fun(data: string[])
--- @field on_failure fun(message: string)
---
--- @param o JobParams
local function cmd_execute(o)
  local args = { "-C", o.root or "." }
  for _, arg in ipairs(o.args) do
    if arg ~= nil and #arg > 0 then
      table.insert(args, arg)
    end
  end

  Job:new({
    command = "git",
    args = args,
    cwd = "/usr/bin",
    on_exit = function(j, exit_code)
      vim.schedule(function()
        if exit_code ~= 0 then
          if o.on_failure then
            o.on_failure(table.concat(j:stderr_result(), " "))
          end
        else
          if o.on_success then
            o.on_success(j:result())
          end
        end
      end)
    end,
  }):start()
end

---@class Git
---@field config Config
---@field root string
local Git = {}

---@return Git
function Git:new(config)
  local o = {}
  setmetatable(o, { __index = self })

  o.config = config

  local output = vim.fn.system({
    "git",
    "-C",
    vim.fn.expand("%:p:h"),
    "rev-parse",
    "--show-toplevel",
  })

  if output ~= nil and not utils.starts_with(output, "fatal:") then
    self.root = vim.trim(output)
  end

  return o
end

---Execute git blame line porcelain command, returns output string
---@param filename string
---@param commit string?
---@param callback fun(data: string[]) callback on exiting the command with output string
---@param err_cb fun(err: string)?
function Git:blame(filename, commit, callback, err_cb)
  cmd_execute({
    args = {
      "--no-pager",
      "blame",
      commit or "",
      "--line-porcelain",
      "--",
      filename,
    },
    root = assert(self.root),
    on_success = callback,
    on_failure = err_cb or function(err)
      vim.notify(string.format("[Git Blame] %s", err), vim.log.levels.ERROR)
    end,
  })
end

--- @param cwd string
---@param callback fun(root: string)
function Git:git_root(cwd, callback)
  cmd_execute({
    args = {
      "rev-parse",
      "--show-toplevel",
    },
    root = cwd,
    on_success = function(res)
      callback(table.concat(res, ""))
    end,
    on_failure = function(err)
      vim.notify(err, vim.log.levels.ERROR)
    end,
  })
end

---Execute git show
---@param file_path string? relative file path
---@param commit string
---@param callback fun(data: string[]) callback on exiting the command with output string
function Git:show(file_path, commit, callback)
  cmd_execute({
    args = {
      "--no-pager",
      "show",
      "--no-color",
      commit,
      "--",
      file_path or "",
    },
    root = assert(self.root),
    on_success = callback,
    on_failure = function(err)
      vim.notify(string.format("[Git Show] %s", err), vim.log.levels.ERROR)
    end,
  })
end

return Git
