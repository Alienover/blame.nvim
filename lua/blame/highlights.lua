local M = {}

---Highlights each unique hash with a random fg
---@param parsed_lines Porcelain[]
---@param config Config
M.create_highlights_per_hash = function(parsed_lines, config)
  local ok, comment_hl = pcall(vim.api.nvim_get_hl, 0, { name = "Comment" })
  if ok then
    vim.api.nvim_set_hl(
      config.ns_id,
      "Comment",
      comment_hl --[[@as vim.api.keyset.highlight]]
    )
  end

  for _, value in ipairs(parsed_lines) do
    local full_hash = value.hash
    local hash = string.sub(full_hash, 1, 7)
    if vim.fn.hlID(hash) == 0 then
      vim.api.nvim_set_hl(config.ns_id, hash, {
        fg = "#" .. full_hash:sub(1, 6),
      })
    end
  end
end

---@class LineWithHl
---@field idx integer
---@field values {textValue: string, hl: string, start_index: integer, end_index: integer}[]
---@field format string

---@param  porcelain_lines Porcelain[]
---@param config Config
---@return LineWithHl[]
M.get_hld_lines_from_porcelain = function(porcelain_lines, config)
  local blame_lines = {}
  for idx, v in ipairs(porcelain_lines) do
    if
      config.merge_consecutive
      and idx > 1
      and porcelain_lines[idx - 1].hash == v.hash
    then
      blame_lines[#blame_lines + 1] = {
        idx = idx,
        values = {
          {
            textValue = "",
            hl = nil,
          },
        },
        format = "",
      }
    else
      local line_with_hl = config.format_fn(v, config, idx)
      blame_lines[#blame_lines + 1] = line_with_hl
    end
  end
  return blame_lines
end

return M
