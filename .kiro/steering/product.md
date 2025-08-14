# Product Overview

Termdebug Enhanced is a Neovim plugin that extends the built-in termdebug functionality with VSCode-like debugging features specifically designed for embedded development.

## Core Purpose
- Enhance Neovim's built-in termdebug with modern debugging UX
- Provide VSCode-familiar keybindings for developers transitioning to Neovim
- Focus on embedded/ARM development workflows with GDB integration

## Key Features
- **VSCode-like keybindings** (F5, F9, F10, F11, etc.)
- **Hover evaluation** using `K` key (similar to LSP hover)
- **Memory viewer** with hex dump display for embedded debugging
- **Memory/variable editing** capabilities
- **Floating popup windows** for evaluation results
- **Visual mode evaluation** for complex expressions
- **Auto-configuration** for ARM GDB debugging

## Target Users
- Embedded developers using Neovim
- Developers familiar with VSCode debugging experience
- C/C++ developers working with GDB
- Users of LazyVim or similar Neovim distributions

## Design Philosophy
- Familiar keybindings reduce learning curve
- Non-intrusive enhancement of existing termdebug
- Focus on embedded development workflows
- Reliable async communication with GDB