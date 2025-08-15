---@class Validation
local M = {}

local lib = require("termdebug-enhanced.lib")

---Validate string field
---@param value any Value to validate
---@param field_name string Field name for error message
---@return boolean valid, string|nil error
local function validate_string(value, field_name)
	if not value or value == "" then
		return false, field_name .. " cannot be empty"
	end
	if type(value) ~= "string" then
		return false, field_name .. " must be a string"
	end
	return true, nil
end

---Validate positive number
---@param value any Value to validate
---@param field_name string Field name for error message
---@return boolean valid, string|nil error
local function validate_positive_number(value, field_name)
	if not value then
		return true, nil -- Optional field
	end
	if type(value) ~= "number" or value <= 0 then
		return false, field_name .. " must be a positive number"
	end
	return true, nil
end

---Basic configuration validation
---@param config table Configuration to validate
---@return boolean valid, string[] errors
function M.validate_config(config)
	local errors = {}

	if not config or type(config) ~= "table" then
		return false, { "Configuration must be a table" }
	end

	-- Validate debugger
	local debugger_valid, debugger_error = validate_string(config.debugger, "debugger")
	if not debugger_valid then
		table.insert(errors, debugger_error)
	elseif vim.fn.executable(config.debugger) == 0 then
		table.insert(errors, "Debugger executable not found: " .. config.debugger)
	end

	-- Validate popup config
	if config.popup then
		local width_valid, width_error = validate_positive_number(config.popup.width, "popup.width")
		if not width_valid then
			table.insert(errors, width_error)
		end

		local height_valid, height_error = validate_positive_number(config.popup.height, "popup.height")
		if not height_valid then
			table.insert(errors, height_error)
		end
	end

	-- Validate memory viewer config
	if config.memory_viewer then
		local width_valid, width_error = validate_positive_number(config.memory_viewer.width, "memory_viewer.width")
		if not width_valid then
			table.insert(errors, width_error)
		end

		local height_valid, height_error = validate_positive_number(config.memory_viewer.height, "memory_viewer.height")
		if not height_valid then
			table.insert(errors, height_error)
		end

		if config.memory_viewer.format then
			local valid_formats = { hex = true, decimal = true, binary = true }
			if not valid_formats[config.memory_viewer.format] then
				table.insert(errors, "memory_viewer.format must be 'hex', 'decimal', or 'binary'")
			end
		end
	end

	return #errors == 0, errors
end

---Runtime validation helpers
M.validate = {}

---Validate memory address
---@param address string Address to validate
---@return boolean valid, string|nil error
function M.validate.address(address)
	if not address or vim.trim(address) == "" then
		return false, "Empty address"
	end

	local trimmed = vim.trim(address)
	if trimmed:match("^0x%x+$") or trimmed:match("^%d+$") or trimmed:match("^[%a_][%w_]*$") then
		return true, nil
	end

	return false, "Invalid address format"
end

---Validate expression
---@param expression string Expression to validate
---@return boolean valid, string|nil error
function M.validate.expression(expression)
	if not expression or vim.trim(expression) == "" then
		return false, "Empty expression"
	end

	-- Basic parentheses check
	local paren_count = 0
	for char in expression:gmatch(".") do
		if char == "(" then
			paren_count = paren_count + 1
		elseif char == ")" then
			paren_count = paren_count - 1
			if paren_count < 0 then
				return false, "Unmatched closing parenthesis"
			end
		end
	end

	return paren_count == 0, paren_count ~= 0 and "Unmatched parentheses" or nil
end

return M

