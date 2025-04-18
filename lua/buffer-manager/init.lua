local M = {}

local config = require("buffer-manager.config")
local ui = require("buffer-manager.ui")

function M.setup(opts)
	config.setup(opts)
	vim.api.nvim_create_user_command("BufferManager", function()
		ui.fzf_search()
	end, {})

	if config.options.default_mappings then
		vim.keymap.set("n", config.options.mappings.open, ui.fzf_search, { noremap = true, silent = true })
		vim.keymap.set("n", config.options.mappings.vertical, ui.open_vertical, { noremap = true, silent = true })
		vim.keymap.set("n", config.options.mappings.horizontal, ui.open_horizontal, { noremap = true, silent = true })
	end
	return M
end

M.open = ui.open
M.open_vertical = ui.open_vertical
M.open_horizontal = ui.open_horizontal
M.close = ui.close
M.next_buffer = ui.next_buffer
M.prev_buffer = ui.prev_buffer
M.select_buffer = ui.select_buffer
M.delete_buffer = ui.delete_buffer
M.enter_search_mode = ui.enter_search_mode
M.exit_search_mode = ui.exit_search_mode
M.add_to_search = ui.add_to_search
M.remove_from_search = ui.remove_from_search
M.apply_search = ui.apply_search
M.filter_buffers = ui.filter_buffers
M.fzf_search = ui.fzf_search
M.ripgrep_search = ui.ripgrep_search

return M
