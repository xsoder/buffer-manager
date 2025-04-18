local api = vim.api
local fn = vim.fn
local config = require("buffer-manager.config")

local M = {}

-- UI state
local state = {
	buffer = nil,
	win_id = nil,
	selected_line = 1,
	buffers = {},
	split_type = "normal",
}

-- Check if devicons is available
local has_devicons = pcall(require, "nvim-web-devicons")

-- Get icon for buffer
local function get_icon(bufnr)
	if not config.options.icons or not config.options.use_devicons or not has_devicons then
		return ""
	end

	local name = api.nvim_buf_get_name(bufnr)
	local filename = fn.fnamemodify(name, ":t")
	local extension = fn.fnamemodify(filename, ":e")

	local devicons = require("nvim-web-devicons")
	local icon, icon_hl = devicons.get_icon(filename, extension, { default = true })

	return icon .. " "
end

-- Format buffer path based on configuration
local function format_path(bufnr)
	local name = api.nvim_buf_get_name(bufnr)
	local path_display = config.options.display.path_display

	if name == "" then
		return "[No Name]"
	end

	if path_display == "filename" then
		return fn.fnamemodify(name, ":t")
	elseif path_display == "relative" then
		return fn.fnamemodify(name, ":~:.")
	elseif path_display == "absolute" then
		return name
	elseif path_display == "shortened" then
		local filename = fn.fnamemodify(name, ":t")
		local directory = fn.fnamemodify(name, ":h:t")
		return directory .. "/" .. filename
	end

	return name
end

-- Format a buffer for display
local function format_buffer(bufnr)
	local path = format_path(bufnr)
	local icon = get_icon(bufnr)
	local bufnr_str = config.options.display.show_numbers and string.format("%2d: ", bufnr) or ""
	local modified = config.options.display.show_modified
			and (api.nvim_buf_get_option(bufnr, "modified") and " [+]" or "")
		or ""
	local indicator = config.options.display.show_flags and (api.nvim_get_current_buf() == bufnr and " *" or "") or ""

	return string.format("%s%s%s%s%s", bufnr_str, icon, path, modified, indicator)
end

-- Get a list of buffers to display
local function get_buffer_list()
	local buffers = {}
	local current_bufnr = api.nvim_get_current_buf()

	for _, bufnr in ipairs(api.nvim_list_bufs()) do
		if api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_get_option(bufnr, "buflisted") then
			if bufnr == current_bufnr then
				table.insert(buffers, 1, bufnr) -- Current buffer first
			else
				table.insert(buffers, bufnr)
			end
		end
	end

	return buffers
end

-- Update the buffer list display
local function update_buffer_list()
	if not state.buffer or not api.nvim_buf_is_valid(state.buffer) then
		return
	end

	state.buffers = get_buffer_list()

	local lines = {}
	for i, bufnr in ipairs(state.buffers) do
		local line = format_buffer(bufnr)
		table.insert(lines, line)
	end

	api.nvim_buf_set_option(state.buffer, "modifiable", true)
	api.nvim_buf_set_lines(state.buffer, 0, -1, false, lines)
	api.nvim_buf_set_option(state.buffer, "modifiable", false)

	-- Ensure cursor position is valid
	if state.selected_line > #lines then
		state.selected_line = #lines > 0 and #lines or 1
	end

	-- Move cursor to the selected line
	if state.win_id and api.nvim_win_is_valid(state.win_id) then
		api.nvim_win_set_cursor(state.win_id, { state.selected_line, 0 })
	end
end

-- Create window based on configuration
local function create_window()
	local win_config = config.options.window
	local position = win_config.position

	-- Calculate dimensions
	local width = math.floor(vim.o.columns * win_config.width_ratio)
	local height = math.floor(vim.o.lines * win_config.height_ratio)

	-- Calculate position
	local row, col
	if position == "center" then
		row = math.floor((vim.o.lines - height) / 2)
		col = math.floor((vim.o.columns - width) / 2)
	elseif position == "left" then
		row = math.floor((vim.o.lines - height) / 2)
		col = 0
	elseif position == "right" then
		row = math.floor((vim.o.lines - height) / 2)
		col = vim.o.columns - width
	elseif position == "top" then
		row = 0
		col = math.floor((vim.o.columns - width) / 2)
	elseif position == "bottom" then
		row = vim.o.lines - height - 2
		col = math.floor((vim.o.columns - width) / 2)
	end

	-- Window options
	local opts = {
		style = "minimal",
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		border = win_config.border,
		title = " Buffer Manager ",
		title_pos = "center",
	}

	-- Create floating window
	return api.nvim_open_win(state.buffer, true, opts)
end

-- Set buffer-local keymaps
local function set_keymaps()
	-- Helper function for setting keymaps
	local function map(mode, key, action)
		api.nvim_buf_set_keymap(state.buffer, mode, key, action, { silent = true, noremap = true })
	end

	map("n", "j", ":lua require('buffer-manager').next_buffer()<CR>")
	map("n", "k", ":lua require('buffer-manager').prev_buffer()<CR>")
	map("n", "<Down>", ":lua require('buffer-manager').next_buffer()<CR>")
	map("n", "<Up>", ":lua require('buffer-manager').prev_buffer()<CR>")

	map("n", "<CR>", ":lua require('buffer-manager').select_buffer()<CR>")
	map("n", "<2-LeftMouse>", ":lua require('buffer-manager').select_buffer()<CR>")

	map("n", "d", ":lua require('buffer-manager').delete_buffer()<CR>")
	map("n", "D", ":lua require('buffer-manager').delete_buffer()<CR>")
	map("n", "q", ":lua require('buffer-manager').close()<CR>")
	map("n", "<Esc>", ":lua require('buffer-manager').close()<CR>")

	map("n", "v", ":lua require('buffer-manager').select_buffer('vertical')<CR>")
	map("n", "s", ":lua require('buffer-manager').select_buffer('horizontal')<CR>")
end

local function set_options()
	api.nvim_buf_set_option(state.buffer, "bufhidden", "wipe")
	api.nvim_buf_set_option(state.buffer, "filetype", "bufferlist")
	api.nvim_buf_set_name(state.buffer, "Buffer Manager")

	api.nvim_win_set_option(state.win_id, "cursorline", true)
	api.nvim_win_set_option(state.win_id, "signcolumn", "no")
	api.nvim_win_set_option(state.win_id, "number", false)
	api.nvim_win_set_option(state.win_id, "relativenumber", false)
	api.nvim_win_set_option(state.win_id, "wrap", false)
	api.nvim_win_set_option(state.win_id, "spell", false)

	vim.cmd([[
    syntax match BufferManagerNumber /^\s*\d\+:/
    syntax match BufferManagerModified /\[+\]/
    syntax match BufferManagerIndicator /\*$/
  ]])
end

function M.open()
	if state.win_id and api.nvim_win_is_valid(state.win_id) then
		-- Focus existing window
		api.nvim_set_current_win(state.win_id)
		update_buffer_list()
		return
	end

	state.buffer = api.nvim_create_buf(false, true)

	state.win_id = create_window()

	set_options()
	set_keymaps()

	update_buffer_list()

	api.nvim_win_set_option(state.win_id, "winhighlight", "Normal:BufferManagerNormal,FloatBorder:BufferManagerBorder")
end

-- Open in vertical split
function M.open_vertical()
	state.split_type = "vertical"
	M.open()
end

-- Open in horizontal split
function M.open_horizontal()
	state.split_type = "horizontal"
	M.open()
end

-- Close the buffer window
function M.close()
	if state.win_id and api.nvim_win_is_valid(state.win_id) then
		api.nvim_win_close(state.win_id, true)
	end
	state.win_id = nil
	state.buffer = nil
	state.split_type = "normal"
end

function M.next_buffer()
	if #state.buffers > 0 then
		state.selected_line = math.min(state.selected_line + 1, #state.buffers)
		api.nvim_win_set_cursor(state.win_id, { state.selected_line, 0 })
	end
end

function M.prev_buffer()
	if #state.buffers > 0 then
		state.selected_line = math.max(state.selected_line - 1, 1)
		api.nvim_win_set_cursor(state.win_id, { state.selected_line, 0 })
	end
end

function M.select_buffer(split_type)
	split_type = split_type or state.split_type

	local selected = state.buffers[state.selected_line]
	if not selected then
		return
	end

	local current_win = api.nvim_get_current_win()
	M.close()

	if split_type == "vertical" then
		vim.cmd("vsplit")
	elseif split_type == "horizontal" then
		vim.cmd("split")
	end

	api.nvim_win_set_buf(api.nvim_get_current_win(), selected)
end

-- Delete the selected buffer
function M.delete_buffer()
	local selected = state.buffers[state.selected_line]
	if selected then
		-- Check if buffer is modified
		if api.nvim_buf_get_option(selected, "modified") then
			local choice = vim.fn.confirm("Buffer is modified. Save changes?", "&Yes\n&No\n&Cancel", 1)
			if choice == 1 then
				-- Save changes
				api.nvim_buf_call(selected, function()
					vim.cmd("write")
				end)
			elseif choice == 3 then
				-- Cancel
				return
			end
		end

		-- Delete buffer
		pcall(api.nvim_buf_delete, selected, { force = false })

		-- Update display
		update_buffer_list()
	end
end

return M
