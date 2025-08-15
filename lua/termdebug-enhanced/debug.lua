---@class termdebug-enhanced.debug
---@field test_popup function Test popup creation
---@field diagnose_gdb_functions function Diagnose GDB functions
---@field test_f10_keymap function Test F10 keymap
---@field test_direct_evaluation function Test direct evaluation
---@field debug_all_buffers function Debug all buffers
---@field test_gdb_response function Test GDB response
local M = {}

local utils = require("termdebug-enhanced.utils")
local config = require("termdebug-enhanced.config")

---Test function to verify popup creation works
---@return nil
function M.test_popup()
	vim.notify("Testing popup creation...", vim.log.levels.INFO)
	local evaluate = require("termdebug-enhanced.evaluate")
	local popup_config = config.get_popup()
	local test_content = {
		"✓ Test Popup",
		"─────────────",
		"",
		"This is a test popup to verify",
		"that the floating window creation",
		"is working correctly.",
		"",
		"If you see this, the popup",
		"functionality is working!"
	}

	-- Use evaluate module's create_float_window if exported
	-- Otherwise create a simple test window
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, test_content)
	
	local win_opts = {
		relative = "cursor",
		row = 1,
		col = 0,
		width = 40,
		height = #test_content,
		style = "minimal",
		border = popup_config.border or "rounded",
	}
	
	local ok, win = pcall(vim.api.nvim_open_win, buf, false, win_opts)
	if ok and win then
		vim.notify("Test popup created successfully!", vim.log.levels.INFO)
		-- Auto-close after 3 seconds
		vim.defer_fn(function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end, 3000)
	else
		vim.notify("Test popup creation failed!", vim.log.levels.ERROR)
	end
end

---Diagnose available GDB functions and commands
---@return nil
function M.diagnose_gdb_functions()
	vim.notify("=== GDB Function Diagnostics ===", vim.log.levels.INFO)

	-- Check basic termdebug availability
	vim.notify("Termdebug command exists: " .. tostring(vim.fn.exists(":Termdebug") == 1), vim.log.levels.INFO)
	vim.notify("Termdebug running: " .. tostring(vim.g.termdebug_running or false), vim.log.levels.INFO)

	-- Check for various GDB command functions
	local functions_to_check = {
		"TermdebugCommand",
		"TermDebugSendCommand",
		"TermdebugSendCommand",
		"TermDebugCommand",
		"Evaluate",
		"Gdb",
		"TermdebugEvaluate"
	}

	for _, func_name in ipairs(functions_to_check) do
		local exists = vim.fn.exists('*' .. func_name) == 1
		vim.notify("Function " .. func_name .. " exists: " .. tostring(exists), vim.log.levels.INFO)
	end

	-- Check for termdebug commands
	local commands_to_check = {
		"Continue",
		"Over",
		"Step",
		"Finish",
		"Stop",
		"Run",
		"Break",
		"Clear",
		"Evaluate"
	}

	vim.notify("--- Checking Termdebug Commands ---", vim.log.levels.INFO)
	for _, cmd_name in ipairs(commands_to_check) do
		local exists = vim.fn.exists(':' .. cmd_name) == 1
		vim.notify("Command :" .. cmd_name .. " exists: " .. tostring(exists), vim.log.levels.INFO)
	end

	-- Check for GDB buffer
	local gdb_buf = utils.find_gdb_buffer()
	vim.notify("GDB buffer found: " .. tostring(gdb_buf ~= nil), vim.log.levels.INFO)
	if gdb_buf then
		vim.notify("GDB buffer ID: " .. gdb_buf, vim.log.levels.INFO)
		local buf_name = vim.api.nvim_buf_get_name(gdb_buf)
		vim.notify("GDB buffer name: " .. buf_name, vim.log.levels.INFO)
	end

	-- Check global variables
	local gdb_vars = {
		"termdebug_running",
		"termdebugger",
		"termdebug_wide",
		"gdb_channel"
	}

	for _, var_name in ipairs(gdb_vars) do
		local value = vim.g[var_name]
		vim.notify("vim.g." .. var_name .. " = " .. vim.inspect(value), vim.log.levels.INFO)
	end

	vim.notify("=== End GDB Diagnostics ===", vim.log.levels.INFO)
end

---Test F10 keymap functionality
---@return nil
function M.test_f10_keymap()
	vim.notify("=== Testing F10 Keymap ===", vim.log.levels.INFO)

	-- Check if F10 is mapped
	local f10_mapping = vim.fn.maparg("<F10>", "n")
	vim.notify("F10 mapping: " .. vim.inspect(f10_mapping), vim.log.levels.INFO)

	-- Test the Over command directly
	vim.notify("Testing :Over command directly...", vim.log.levels.INFO)
	local over_ok, over_err = pcall(vim.cmd, "Over")
	vim.notify("Over command result: " .. tostring(over_ok) .. ", error: " .. tostring(over_err), vim.log.levels.INFO)

	-- Test sending "next" command directly to GDB
	vim.notify("Testing direct GDB 'next' command...", vim.log.levels.INFO)
	if vim.fn.exists('*TermDebugSendCommand') == 1 then
		local send_ok, send_err = pcall(vim.fn.TermDebugSendCommand, "next")
		vim.notify("Direct 'next' command result: " .. tostring(send_ok) .. ", error: " .. tostring(send_err), vim.log.levels.INFO)
	else
		vim.notify("TermDebugSendCommand not available", vim.log.levels.WARN)
	end

	-- Check current keymaps
	vim.notify("Current normal mode keymaps containing F10:", vim.log.levels.INFO)
	local keymaps = vim.api.nvim_get_keymap("n")
	for _, keymap in ipairs(keymaps) do
		if keymap.lhs and keymap.lhs:match("F10") then
			vim.notify("Found F10 keymap: " .. vim.inspect(keymap), vim.log.levels.INFO)
		end
	end

	vim.notify("=== End F10 Test ===", vim.log.levels.INFO)
end

---Test evaluation with direct GDB buffer reading
---@return nil
function M.test_direct_evaluation()
	vim.notify("=== Testing Direct Evaluation ===", vim.log.levels.INFO)

	local word = vim.fn.expand("<cword>")
	if word == "" then
		word = "test_var"
	end

	vim.notify("Testing evaluation of: " .. word, vim.log.levels.INFO)

	-- Send command directly and read buffer immediately
	if vim.fn.exists('*TermDebugSendCommand') == 1 then
		local send_ok = pcall(vim.fn.TermDebugSendCommand, "print " .. word)
		vim.notify("Command sent: " .. tostring(send_ok), vim.log.levels.INFO)

		if send_ok then
			-- Wait a moment then read the GDB buffer directly
			vim.defer_fn(function()
				local gdb_buf = utils.find_gdb_buffer()
				if gdb_buf then
					-- Get more lines to ensure we capture the response
					local lines = vim.api.nvim_buf_get_lines(gdb_buf, -50, -1, false)
					vim.notify("Recent GDB buffer lines (" .. #lines .. " lines): " .. vim.inspect(lines), vim.log.levels.INFO)

					-- Try to find the response
					local response_lines = {}
					local found_start = false
					local start_index = nil

					-- First, find where the response starts (the $N = line)
					for i = #lines, 1, -1 do
						local line = lines[i]
						if line:match("%$%d+%s*=") then
							start_index = i
							found_start = true
							vim.notify("Found $N = pattern at line " .. i .. ": " .. line, vim.log.levels.INFO)
							break
						end
					end

					-- If we found the start, capture all lines until the next (gdb) prompt
					if found_start and start_index then
						for i = start_index, #lines do
							local line = lines[i]
							if line:match("^%(gdb%)") then
								-- Stop at the next GDB prompt
								break
							else
								table.insert(response_lines, line)
								vim.notify("Captured response line: " .. line, vim.log.levels.INFO)
							end
						end
					end

					vim.notify("Final extracted response: " .. vim.inspect(response_lines), vim.log.levels.INFO)

					if #response_lines > 0 then
						vim.notify("Direct evaluation test succeeded!", vim.log.levels.INFO)
					else
						vim.notify("No response found in buffer", vim.log.levels.WARN)
					end
				else
					vim.notify("GDB buffer not found", vim.log.levels.ERROR)
				end
			end, 500) -- Wait 500ms for response
		end
	else
		vim.notify("TermDebugSendCommand not available", vim.log.levels.ERROR)
	end

	vim.notify("=== End Direct Evaluation Test ===", vim.log.levels.INFO)
end

---Debug all buffers to find where GDB output is going
---@return nil
function M.debug_all_buffers()
	vim.notify("=== Debugging All Buffers ===", vim.log.levels.INFO)

	local buffers = vim.api.nvim_list_bufs()
	vim.notify("Found " .. #buffers .. " total buffers", vim.log.levels.INFO)

	for _, buf in ipairs(buffers) do
		if vim.api.nvim_buf_is_valid(buf) then
			local name = vim.api.nvim_buf_get_name(buf)
			local lines = vim.api.nvim_buf_get_lines(buf, -10, -1, false)

			-- Check if this buffer contains GDB-like content
			local has_gdb_content = false
			for _, line in ipairs(lines) do
				if line:match("%(gdb%)") or line:match("%$%d+%s*=") or line:match("print") then
					has_gdb_content = true
					break
				end
			end

			if has_gdb_content or name:match("[Gg]db") or name:match("[Dd]ebug") then
				vim.notify("Buffer " .. buf .. " (" .. name .. ") - GDB content detected:", vim.log.levels.INFO)
				vim.notify("Last 10 lines: " .. vim.inspect(lines), vim.log.levels.INFO)
			else
				vim.notify("Buffer " .. buf .. " (" .. name .. ") - No GDB content", vim.log.levels.DEBUG)
			end
		end
	end

	-- Also check what find_gdb_buffer returns
	local gdb_buf = utils.find_gdb_buffer()
	vim.notify("utils.find_gdb_buffer() returned: " .. tostring(gdb_buf), vim.log.levels.INFO)

	vim.notify("=== End Buffer Debug ===", vim.log.levels.INFO)
end

---Test function to verify GDB response mechanism
---@return nil
function M.test_gdb_response()
	vim.notify("Testing GDB response mechanism...", vim.log.levels.INFO)

	-- First run diagnostics
	M.diagnose_gdb_functions()

	-- Check if GDB is available
	if vim.fn.exists(":Termdebug") == 0 then
		vim.notify("Termdebug not available. Run :packadd termdebug", vim.log.levels.WARN)
		return
	end

	if not vim.g.termdebug_running then
		vim.notify("Debug session not active. Start debugging first", vim.log.levels.WARN)
		return
	end

	vim.notify("GDB is available, testing response...", vim.log.levels.INFO)

	-- Use simple GDB response for testing
	utils.simple_gdb_response("print 42", function(response_lines, error_msg)
		if error_msg then
			vim.notify("GDB response test failed: " .. error_msg, vim.log.levels.ERROR)
		else
			vim.notify("GDB response test succeeded! Lines: " .. vim.inspect(response_lines), vim.log.levels.INFO)

			-- Now test popup creation with the response
			local popup_config = config.get_popup()
			local test_content = {
				"✓ GDB Response Test",
				"─────────────────────",
				"",
				"Command: print 42",
				"Response received successfully:",
			}

			if response_lines and #response_lines > 0 then
				for _, line in ipairs(response_lines) do
					table.insert(test_content, "  " .. line)
				end
			else
				table.insert(test_content, "  (no response lines)")
			end

			table.insert(test_content, "")
			table.insert(test_content, "This proves GDB communication works!")

			-- Create test popup
			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, test_content)
			
			local win_opts = {
				relative = "cursor",
				row = 1,
				col = 0,
				width = 50,
				height = #test_content,
				style = "minimal",
				border = popup_config.border or "rounded",
			}
			
			local ok, win = pcall(vim.api.nvim_open_win, buf, false, win_opts)
			if ok and win then
				vim.notify("GDB response popup created successfully!", vim.log.levels.INFO)
				-- Auto-close after 5 seconds
				vim.defer_fn(function()
					if vim.api.nvim_win_is_valid(win) then
						vim.api.nvim_win_close(win, true)
					end
				end, 5000)
			else
				vim.notify("Failed to create popup with GDB response!", vim.log.levels.ERROR)
			end
		end
	end)
end

---Create user commands for debug functions
---@return nil
function M.setup_commands()
	vim.api.nvim_create_user_command("TDETestPopup", M.test_popup, { desc = "Test popup creation" })
	vim.api.nvim_create_user_command("TDEDiagnoseGDB", M.diagnose_gdb_functions, { desc = "Diagnose GDB functions" })
	vim.api.nvim_create_user_command("TDETestF10", M.test_f10_keymap, { desc = "Test F10 keymap" })
	vim.api.nvim_create_user_command("TDETestDirectEval", M.test_direct_evaluation, { desc = "Test direct evaluation" })
	vim.api.nvim_create_user_command("TDEDebugBuffers", M.debug_all_buffers, { desc = "Debug all buffers" })
	vim.api.nvim_create_user_command("TDETestGDBResponse", M.test_gdb_response, { desc = "Test GDB response" })
end

return M