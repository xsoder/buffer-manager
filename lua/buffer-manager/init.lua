local M = {}

local config = require("buffer-manager.config")
local ui = require("buffer-manager.ui")

function M.setup(opts)
	config.setup(opts)
	vim.api.nvim_create_user_command("BufferManager", function()
		ui.open()
	end, {})

	if config.options.default_mappings then
		-- Space bb for buffer management (like Doom Emacs)
		vim.keymap.set("n", config.options.mappings.open, ui.open, { noremap = true, silent = true })
	end
	return M
end

M.open = ui.open
M.close = ui.close
M.next_buffer = ui.next_buffer
M.prev_buffer = ui.prev_buffer
M.select_buffer = ui.select_buffer
M.delete_buffer = ui.delete_buffer

return M
