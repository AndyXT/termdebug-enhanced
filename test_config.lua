-- Test configuration for termdebug-enhanced
-- This shows how to properly configure the plugin

require("termdebug-enhanced").setup({
  -- Use standard gdb instead of arm-none-eabi-gdb
  debugger = "gdb",  -- or "C:\\path\\to\\gdb.exe" on Windows
  
  -- Remove gdbinit if you don't have one
  -- gdbinit = ".gdbinit",
  
  -- UI settings
  popup = {
    border = "rounded",
    width = 60,
    height = 10,
  },
  
  memory_viewer = {
    width = 80,
    height = 20,
    format = "hex",
    bytes_per_line = 16,
  },
  
  -- Fixed keymaps (no duplicates)
  keymaps = {
    continue = "<F5>",
    step_over = "<F10>",
    step_into = "<F11>",
    step_out = "<S-F11>",
    toggle_breakpoint = "<F9>",
    stop = "<S-F5>",
    restart = "<C-S-F5>",
    evaluate = "K",                    -- Evaluate under cursor
    evaluate_visual = "<leader>K",     -- Evaluate selection (different key)
    watch_add = "<leader>dw",
    watch_remove = "<leader>dW",
    memory_view = "<leader>dm",
    memory_edit = "<leader>dM",
    variable_set = "<leader>ds",
  },
})

print("✓ Termdebug Enhanced configured successfully!")
print("")
print("Available commands:")
print("  :TermdebugStart [program]  - Start debugging")
print("  :TermdebugStop            - Stop debugging")
print("  :TermdebugDiagnose        - Show diagnostics")
print("  :Evaluate <expr>          - Evaluate expression")
print("  :EvaluateCursor           - Evaluate under cursor")
print("  :MemoryView [addr]        - View memory")
print("")
print("Key bindings:")
print("  F5                        - Continue")
print("  F9                        - Toggle breakpoint")
print("  F10                       - Step over")
print("  F11                       - Step into")
print("  Shift+F11                 - Step out")
print("  K                         - Evaluate under cursor")
print("  <leader>K                 - Evaluate selection")
print("  <leader>dm                - View memory")
print("  <leader>dM                - Edit memory")
print("")
print("To test:")
print("1. Create a simple C program")
print("2. Compile with debug info: gcc -g program.c -o program")
print("3. Start debugging: :TermdebugStart ./program")
print("4. Set breakpoint: F9 on a line")
print("5. Run: F5")
print("6. When stopped, test evaluate: K on a variable")
