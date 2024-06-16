local M = {}

---Calculates the longest string in the string[]Calculates the longest string in the string[]Calculates the longest string in the string[]Calculates the longest string in the string[]Calculates the longest string in the string[]Calculates the longest string in the string[]Calculates the longest string in the string[]Calculates the longest string in the string[]
---@param string_array string[]
---@return integer
M.longest_string_in_array = function(string_array)
  local longest = 0
  for _, value in ipairs(string_array) do
    if vim.fn.strdisplaywidth(value) > longest then
      longest = vim.fn.strdisplaywidth(value)
    end
  end
  return longest
end

--- @param str string
--- @param start string
M.starts_with = function(str, start)
  return str:sub(1, #start) == start
end

--- @param str string
--- @param ending string
M.ends_with = function(str, ending)
  return ending == "" or string.sub(str, -#ending) == ending
end

return M
