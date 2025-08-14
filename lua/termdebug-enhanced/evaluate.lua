---@class GdbEvaluationError
---@field type string Error type (syntax, gdb_unavailable, timeout, expression_invalid)
---@field message string Human-readable error message
---@field expression string|nil The expression that failed

---@class termdebug-enhanced.evaluate
---@field evaluate_under_cursor function Evaluate expression under cursor
---@field evaluate_selection function Evaluate visual selection
---@field evaluate_custom function Evaluate custom expression
local M = {}

local utils = require("termdebug-enhanced.utils")

-- Cache for the floating window
---@type number|nil
local float_win = nil
---@type number|nil
local float_buf = nil

-- Helper function to get config safely
---@return table
local function get_config()
  local ok, main = pcall(require, "termdebug-enhanced")
  if ok and main.config then
    return main.config
  end
  -- Return default config if not initialized
  return {
    popup = { border = "rounded", width = 60, height = 10 }
  }
end

-- Validate expression syntax
---@param expr string Expression to validate
---@return boolean valid, string|nil error_msg
local function validate_expression(expr)
  if not expr or expr == "" then
    return false, "Empty expression"
  end
  
  -- Basic syntax validation
  local trimmed = vim.trim(expr)
  if trimmed == "" then
    return false, "Expression contains only whitespace"
  end
  
  -- Check for obviously invalid characters that could cause issues
  if trimmed:match("[{}]") and not trimmed:match("^{.*}$") then
    return false, "Invalid brace syntax"
  end
  
  -- Check for unmatched parentheses
  local paren_count = 0
  for char in trimmed:gmatch(".") do
    if char == "(" then
      paren_count = paren_count + 1
    elseif char == ")" then
      paren_count = paren_count - 1
      if paren_count < 0 then
        return false, "Unmatched closing parenthesis"
      end
    end
  end
  
  if paren_count ~= 0 then
    return false, "Unmatched opening parenthesis"
  end
  
  return true, nil
end

-- Check if GDB is available and ready
---@return boolean available, string|nil error_msg
local function check_gdb_availability()
  if vim.fn.exists(':Termdebug') == 0 then
    return false, "Termdebug not available. Run :packadd termdebug"
  end
  
  if not vim.g.termdebug_running then
    return false, "Debug session not active. Start debugging first"
  end
  
  return true, nil
end

-- Create error display content
---@param error_info GdbEvaluationError Error information
---@return string[] Formatted error content
local function create_error_content(error_info)
  local content = {
    "❌ Evaluation Error",
    string.rep("─", 40),
  }
  
  if error_info.expression then
    table.insert(content, "Expression: " .. error_info.expression)
    table.insert(content, "")
  end
  
  table.insert(content, "Error: " .. error_info.message)
  
  -- Add helpful hints based on error type
  if error_info.type == "syntax" then
    table.insert(content, "")
    table.insert(content, "💡 Hint: Check expression syntax")
  elseif error_info.type == "gdb_unavailable" then
    table.insert(content, "")
    table.insert(content, "💡 Hint: Start debugging session first")
  elseif error_info.type == "timeout" then
    table.insert(content, "")
    table.insert(content, "💡 Hint: Expression may be too complex")
  elseif error_info.type == "expression_invalid" then
    table.insert(content, "")
    table.insert(content, "💡 Hint: Variable may not be in scope")
  end
  
  return content
end

-- Clean up floating window resources
---@return nil
local function cleanup_float_window()
  if float_win and vim.api.nvim_win_is_valid(float_win) then
    local ok, err = pcall(vim.api.nvim_win_close, float_win, true)
    if not ok then
      vim.notify("Failed to close evaluation window: " .. tostring(err), vim.log.levels.WARN)
    end
  end
  if float_buf and vim.api.nvim_buf_is_valid(float_buf) then
    local ok, err = pcall(vim.api.nvim_buf_delete, float_buf, { force = true })
    if not ok then
      vim.notify("Failed to delete evaluation buffer: " .. tostring(err), vim.log.levels.WARN)
    end
  end
  float_win = nil
  float_buf = nil
end

---Create floating window for evaluation results
---@param content string[]|string Content to display
---@param opts table|nil Window options
---@param is_error boolean|nil Whether this is an error display
---@return number|nil, number|nil Window and buffer handles
local function create_float_window(content, opts, is_error)
  opts = opts or {}
  is_error = is_error or false

  -- Close existing window if any
  cleanup_float_window()

  -- Create buffer for content
  local ok, buf = pcall(vim.api.nvim_create_buf, false, true)
  if not ok then
    vim.notify("Failed to create evaluation buffer: " .. tostring(buf), vim.log.levels.ERROR)
    return nil, nil
  end
  float_buf = buf

  -- Process content into lines
  local lines = {}
  if type(content) == "string" then
    lines = vim.split(content, "\n")
  else
    lines = content or {}
  end

  local set_ok, set_err = pcall(vim.api.nvim_buf_set_lines, float_buf, 0, -1, false, lines)
  if not set_ok then
    vim.notify("Failed to set buffer content: " .. tostring(set_err), vim.log.levels.ERROR)
    cleanup_float_window()
    return nil, nil
  end

  -- Calculate window size
  local width = opts.width or 60
  local height = math.min(opts.height or 10, math.max(#lines, 3))

  -- Get cursor position for placement
  local cursor_ok, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
  if not cursor_ok then
    cursor = {1, 0}
  end
  
  local win_width_ok, win_width = pcall(vim.api.nvim_win_get_width, 0)
  if not win_width_ok then
    win_width = 80
  end

  -- Calculate position (try above cursor first, then below)
  local row = cursor[1] - 1
  local col = cursor[2]

  -- Adjust if window would go off screen
  if row - height - 1 < 0 then
    row = row + 2 -- Place below cursor
  else
    row = row - height - 1 -- Place above cursor
  end

  if col + width > win_width then
    col = math.max(0, win_width - width)
  end

  -- Create floating window
  local win_opts = {
    relative = "win",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = opts.border or "rounded",
    noautocmd = true,
  }
  
  local win_ok, win = pcall(vim.api.nvim_open_win, float_buf, false, win_opts)
  if not win_ok then
    vim.notify("Failed to create evaluation window: " .. tostring(win), vim.log.levels.ERROR)
    cleanup_float_window()
    return nil, nil
  end
  float_win = win

  -- Set buffer options (using modern API with error handling)
  pcall(function()
    vim.bo[float_buf].bufhidden = "wipe"
    vim.bo[float_buf].filetype = is_error and "text" or "gdb"
    vim.bo[float_buf].modifiable = false
  end)

  -- Add syntax highlighting for GDB output
  pcall(function()
    local highlight = is_error and "Normal:ErrorMsg,FloatBorder:ErrorMsg" or "Normal:NormalFloat,FloatBorder:FloatBorder"
    vim.wo[float_win].winhl = highlight
  end)

  -- Close on cursor move or insert mode (with error handling)
  pcall(vim.api.nvim_create_autocmd, {"CursorMoved", "InsertEnter", "BufLeave"}, {
    once = true,
    callback = function()
      cleanup_float_window()
    end
  })

  -- Add keybinding to close with Esc (with error handling)
  pcall(vim.api.nvim_buf_set_keymap, float_buf, "n", "<Esc>", "", {
    callback = function()
      cleanup_float_window()
    end,
    noremap = true,
    silent = true
  })

  return float_win, float_buf
end

---Get GDB response using async polling with comprehensive error handling
---@param command string GDB command to execute
---@param expression string Original expression for error reporting
---@param callback fun(lines: string[]|nil, error_info: GdbEvaluationError|nil): nil Callback function
---@return nil
local function get_gdb_response(command, expression, callback)
  -- Check GDB availability first
  local available, availability_error = check_gdb_availability()
  if not available then
    callback(nil, {
      type = "gdb_unavailable",
      message = availability_error,
      expression = expression
    })
    return
  end
  
  utils.async_gdb_response(command, function(response, error)
    if error then
      local error_type = "expression_invalid"
      local error_msg = error
      
      -- Categorize error types
      if error:match("[Tt]imeout") then
        error_type = "timeout"
        error_msg = "GDB response timeout - expression may be too complex"
      elseif error:match("[Nn]ot available") or error:match("[Nn]ot active") then
        error_type = "gdb_unavailable"
      elseif error:match("[Ss]yntax") or error:match("[Ii]nvalid") then
        error_type = "syntax"
      end
      
      callback(nil, {
        type = error_type,
        message = error_msg,
        expression = expression
      })
    else
      -- Check if response indicates an error
      if response and #response > 0 then
        local response_text = table.concat(response, " ")
        if response_text:match("[Nn]o symbol") or 
           response_text:match("[Uu]ndefined") or
           response_text:match("[Ee]rror") then
          callback(nil, {
            type = "expression_invalid",
            message = "Expression not found or not in scope: " .. response_text,
            expression = expression
          })
          return
        end
      end
      
      callback(response, nil)
    end
  end, { timeout = 3000, poll_interval = 50 })
end

---Evaluate expression under cursor and show in popup
---Shows value of variable or expression at cursor position
---@return nil
function M.evaluate_under_cursor()
  local word = vim.fn.expand("<cexpr>")
  if word == "" then
    word = vim.fn.expand("<cword>")
  end

  if word == "" then
    vim.notify("No expression under cursor", vim.log.levels.WARN)
    return
  end

  get_gdb_response("print " .. word, function(response_lines)
    -- Format the output nicely
    local formatted = {}
    table.insert(formatted, "Expression: " .. word)
    table.insert(formatted, string.rep("─", 40))

    -- Try to extract just the value
    local value = utils.extract_value(response_lines)
    if value then
      table.insert(formatted, value)
    else
      for _, line in ipairs(response_lines) do
        table.insert(formatted, line)
      end
    end

    -- Show in floating window
    local config = get_config()
    create_float_window(formatted, config.popup)
  end)
end

---Evaluate visual selection and show in popup
---Evaluates the text selected in visual mode
---@return nil
function M.evaluate_selection()
  -- Get visual selection
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local selection_lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)

  if #selection_lines == 0 then
    return
  end

  local expr = ""
  if #selection_lines == 1 then
    -- Single line selection
    local line = selection_lines[1]
    expr = line:sub(start_pos[3], end_pos[3])
  else
    -- Multi-line selection
    selection_lines[1] = selection_lines[1]:sub(start_pos[3])
    selection_lines[#selection_lines] = selection_lines[#selection_lines]:sub(1, end_pos[3])
    expr = table.concat(selection_lines, " ")
  end

  if expr == "" then
    vim.notify("No expression selected", vim.log.levels.WARN)
    return
  end

  get_gdb_response("print " .. expr, function(response_lines)
    -- Format the output nicely
    local formatted = {}
    table.insert(formatted, "Expression: " .. expr)
    table.insert(formatted, string.rep("─", 40))
    for _, line in ipairs(response_lines) do
      table.insert(formatted, line)
    end

    -- Show in floating window
    local config = get_config()
    create_float_window(formatted, config.popup)
  end)
end

---Evaluate custom expression
---@param expr string|nil Expression to evaluate (prompts if nil)
---@return nil
function M.evaluate_custom(expr)
  if not expr or expr == "" then
    expr = vim.fn.input("Evaluate: ")
  end

  if expr == "" then
    return
  end

  get_gdb_response("print " .. expr, function(response_lines)
    -- Format the output nicely
    local formatted = {}
    table.insert(formatted, "Expression: " .. expr)
    table.insert(formatted, string.rep("─", 40))
    for _, line in ipairs(response_lines) do
      table.insert(formatted, line)
    end

    -- Show in floating window
    local config = get_config()
    create_float_window(formatted, config.popup)
  end)
end

return M