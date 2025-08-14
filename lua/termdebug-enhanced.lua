-- LazyVim plugin spec
return {
	"termdebug-enhanced",
	dir = vim.fn.expand("~") .. "/termdebug-enhanced", -- Adjust path as needed
	dependencies = {
		-- Optional: for better UI popups (uncomment if you want to use nui)
		-- "MunifTanjim/nui.nvim",
	},
	event = "VeryLazy",
	keys = {
		{ "<leader>dd", "<cmd>TermdebugStart<cr>", desc = "Start debugging" },
		{ "<leader>dq", "<cmd>TermdebugStop<cr>", desc = "Stop debugging" },
	},
	opts = {
		-- Override with your specific debugger path
		debugger = "arm-none-eabi-gdb.exe",
		gdbinit = ".gdbinit",

		-- UI configuration
		popup = {
			border = "rounded",
			width = 60,
			height = 10,
		},

		memory_viewer = {
			width = 80,
			height = 20,
			format = "hex", -- hex, decimal, binary
			bytes_per_line = 16,
		},

		-- VSCode-like keybindings
		keymaps = {
			continue = "<F5>",
			step_over = "<F10>",
			step_into = "<F11>",
			step_out = "<S-F11>",
			toggle_breakpoint = "<F9>",
			stop = "<S-F5>",
			restart = "<C-S-F5>",
			evaluate = "K", -- Hover to evaluate (like LSP)
			evaluate_visual = "K", -- Evaluate selection
			watch_add = "<leader>dw",
			watch_remove = "<leader>dW",
			memory_view = "<leader>dm",
			memory_edit = "<leader>dM",
			variable_set = "<leader>ds",
		},
	},
	config = function(_, opts)
		require("termdebug-enhanced").setup(opts)
	end,
}

