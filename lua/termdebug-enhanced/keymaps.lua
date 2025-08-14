---@class KeymapEntry
---@field mode string Keymap mode
---@field key string Key combination

---@class termdebug-enhanced.keymaps
local M = {}

local utils = require("termdebug-enhanced.utils")

-- Lazy load modules to avoid circular dependencies
---@return termdebug-enhanced.evaluate
local function get_eval()
  return require("termdebug-enhanced.evaluate")
end

---@return termdebug-enhanced.memory
local function get_memory()
  return require("termdebug-enhanced.memory")
end

---@type KeymapEntry[]
local active_keymaps = {}

---Setup debugging keymaps
---@param keymaps KeymapConfig Keymap configuration
---@return nil
function M.setup_keymaps(keymaps)
  -- VSCode-like debugging keymaps
  local mappings = {
    [keymaps.continue] = { cmd = "Continue", desc = "Continue execution" },
    [keymaps.step_over] = { cmd = "Over", desc = "Step over" },
    [keymaps.step_into] = { cmd = "Step", desc = "Step into" },
    [keymaps.step_out] = { cmd = "Finish", desc = "Step out" },
    [keymaps.stop] = { cmd = "Stop", desc = "Stop debugging" },
    [keymaps.restart] = { cmd = function()
      vim.cmd("Stop")
      vim.defer_fn(function()
        vim.cmd("Run")
      end, 100)
    end, desc = "Restart debugging" },
  }

  -- Set up standard debugging keymaps
  for key, mapping in pairs(mappings) do
    if key and key ~= "" then
      vim.keymap.set("n", key, function()
        if type(mapping.cmd) == "function" then
          mapping.cmd()
        else
          vim.cmd(mapping.cmd)
        end
      end, { desc = mapping.desc, buffer = false })
      table.insert(active_keymaps, { mode = "n", key = key })
    end
  end

  -- Breakpoint toggle with proper toggle logic
  if keymaps.toggle_breakpoint then
    vim.keymap.set("n", keymaps.toggle_breakpoint, function()
      local line = vim.fn.line(".")
      local file = vim.fn.expand("%:p")

      -- Get current breakpoints
      utils.async_gdb_response("info breakpoints", function(response, error)
        if error then
          -- No breakpoints exist, just add one
          utils.async_gdb_response("break " .. file .. ":" .. line, function()
            vim.notify("Breakpoint set at line " .. line)
          end)
          return
        end

        -- Parse breakpoints and check if one exists at this location
        local breakpoints = utils.parse_breakpoints(response)
        local bp_num = utils.find_breakpoint(breakpoints, file, line)

        if bp_num then
          -- Breakpoint exists, remove it
          utils.async_gdb_response("delete " .. bp_num, function()
            vim.notify("Breakpoint " .. bp_num .. " removed")
          end)
        else
          -- No breakpoint here, add one
          utils.async_gdb_response("break " .. file .. ":" .. line, function()
            vim.notify("Breakpoint set at line " .. line)
          end)
        end
      end, { timeout = 1000 })
    end, { desc = "Toggle breakpoint" })
    table.insert(active_keymaps, { mode = "n", key = keymaps.toggle_breakpoint })
  end

  -- Evaluate under cursor (like LSP hover)
  if keymaps.evaluate then
    vim.keymap.set("n", keymaps.evaluate, function()
      get_eval().evaluate_under_cursor()
    end, { desc = "Evaluate expression under cursor" })
    table.insert(active_keymaps, { mode = "n", key = keymaps.evaluate })
  end

  -- Evaluate visual selection
  if keymaps.evaluate_visual then
    vim.keymap.set("v", keymaps.evaluate_visual, function()
      get_eval().evaluate_selection()
    end, { desc = "Evaluate selected expression" })
    table.insert(active_keymaps, { mode = "v", key = keymaps.evaluate_visual })
  end

  -- Watch expressions
  if keymaps.watch_add then
    vim.keymap.set("n", keymaps.watch_add, function()
      local expr = vim.fn.input("Watch expression: ")
      if expr ~= "" then
        utils.async_gdb_response("display " .. expr, function(_response, error)
          if not error then
            vim.notify("Watch added: " .. expr)
          end
        end)
      end
    end, { desc = "Add watch expression" })
    table.insert(active_keymaps, { mode = "n", key = keymaps.watch_add })
  end

  -- Memory viewer
  if keymaps.memory_view then
    vim.keymap.set("n", keymaps.memory_view, function()
      get_memory().view_memory_at_cursor()
    end, { desc = "View memory at cursor" })
    table.insert(active_keymaps, { mode = "n", key = keymaps.memory_view })
  end

  -- Memory edit
  if keymaps.memory_edit then
    vim.keymap.set("n", keymaps.memory_edit, function()
      get_memory().edit_memory_at_cursor()
    end, { desc = "Edit memory/variable at cursor" })
    table.insert(active_keymaps, { mode = "n", key = keymaps.memory_edit })
  end

  -- Variable set
  if keymaps.variable_set then
    vim.keymap.set("n", keymaps.variable_set, function()
      local var = vim.fn.expand("<cword>")
      local value = vim.fn.input("Set " .. var .. " = ")
      if value ~= "" then
        utils.async_gdb_response("set variable " .. var .. " = " .. value, function(_response, error)
          if not error then
            vim.notify("Variable " .. var .. " set to " .. value)
          end
        end)
      end
    end, { desc = "Set variable value" })
    table.insert(active_keymaps, { mode = "n", key = keymaps.variable_set })
  end
end

---Clean up all active keymaps
---@return nil
function M.cleanup_keymaps()
  for _, mapping in ipairs(active_keymaps) do
    pcall(vim.keymap.del, mapping.mode, mapping.key)
  end
  active_keymaps = {}
end

return M