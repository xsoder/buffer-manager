local api = vim.api
local fn = vim.fn
local config = require("buffer-manager.config")
local Job = require("plenary.job")

local has_fzf, fzf = pcall(require, "fzf-lua")
if not has_fzf then
	config.options.fzf.enabled = false
end

local M = {}

-- UI state
local state = {
	buffer = nil,
	win_id = nil,
	selected_line = 1,
	buffers = {},
	split_type = "normal",
	search_mode = false,
	search_query = "",
	original_buffers = {},
	rg_results = {},
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
	if name == "" then
		return "[No Name]"
	end

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

	-- Get current line position for the buffer
	local line_pos = ""
	if api.nvim_get_current_buf() == bufnr then
		local cursor_pos = api.nvim_win_get_cursor(0)
		line_pos = string.format(" [%d]", cursor_pos[1])
	end

	return string.format("%s%s%s%s%s%s", bufnr_str, icon, path, modified, indicator, line_pos)
end

local uv = vim.loop
local function get_buffer_list()
	local buffers = {}
	for _, bufnr in ipairs(api.nvim_list_bufs()) do
		if
			api.nvim_buf_is_valid(bufnr)
			and api.nvim_buf_is_loaded(bufnr)
			and api.nvim_buf_get_option(bufnr, "buflisted")
		then
			local name = api.nvim_buf_get_name(bufnr)
			if name ~= "" and uv.fs_stat(name) then
				table.insert(buffers, bufnr)
			end
		end
	end
	return buffers
end

local function update_buffer_list()
	if not state.buffer or not api.nvim_buf_is_valid(state.buffer) then
		return
	end

	if not state.search_mode then
		state.buffers = get_buffer_list()
	end

	local lines = {}
	for i, bufnr in ipairs(state.buffers) do
		local line = format_buffer(bufnr)
		table.insert(lines, line)
	end

	api.nvim_buf_set_option(state.buffer, "modifiable", true)

	-- Clear buffer contents
	api.nvim_buf_set_lines(state.buffer, 0, -1, false, lines)

	if state.search_mode then
		local prompt_text = config.options.search.prompt .. state.search_query
		api.nvim_buf_set_lines(state.buffer, #lines, #lines, false, { "" })
		api.nvim_buf_set_lines(state.buffer, #lines, -1, false, { prompt_text })
	end

	api.nvim_buf_set_option(state.buffer, "modifiable", false)

	if state.selected_line > #state.buffers then
		state.selected_line = #state.buffers > 0 and #state.buffers or 1
	end

	-- Move cursor to the selected line
	if state.win_id and api.nvim_win_is_valid(state.win_id) and #state.buffers > 0 then
		if state.search_mode then
			local last_line = api.nvim_buf_line_count(state.buffer)
			local prompt_text = config.options.search.prompt .. state.search_query
			api.nvim_win_set_cursor(state.win_id, { last_line, #prompt_text })
		else
			api.nvim_win_set_cursor(state.win_id, { state.selected_line, 0 })
		end
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

function M.enter_search_mode()
	if not state.buffer or not api.nvim_buf_is_valid(state.buffer) then
		return
	end

	state.search_mode = true
	state.search_query = ""
	state.original_buffers = vim.deepcopy(state.buffers)

	local function map(mode, key, action)
		api.nvim_buf_set_keymap(state.buffer, mode, key, action, { silent = true, noremap = true })
	end

	for _, key in ipairs({ "j", "k", "<Down>", "<Up>", "<CR>", "<2-LeftMouse>", "d", "D", "q", "<Esc>", "v", "s", "/" }) do
		pcall(function()
			api.nvim_buf_del_keymap(state.buffer, "n", key)
		end)
	end

	map("n", "<CR>", ":lua require('buffer-manager.ui').apply_search()<CR>")
	map("n", "<Esc>", ":lua require('buffer-manager.ui').exit_search_mode()<CR>")

	local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./\\:"
	for i = 1, #chars do
		local c = chars:sub(i, i)
		map("n", c, string.format(':lua require("buffer-manager.ui").add_to_search("%s")<CR>', c))
	end

	map("n", "<BS>", ':lua require("buffer-manager.ui").remove_from_search()<CR>')
	map("n", "<Space>", ':lua require("buffer-manager.ui").add_to_search(" ")<CR>')

	update_buffer_list()
end

function M.add_to_search(char)
	if not state.search_mode then
		return
	end

	state.search_query = state.search_query .. char
	M.filter_buffers()
end

function M.remove_from_search()
	if not state.search_mode or #state.search_query == 0 then
		return
	end

	state.search_query = string.sub(state.search_query, 1, -2)
	M.filter_buffers()
end

function M.apply_search()
	if not state.search_mode then
		return
	end

	state.search_mode = false
	if #state.buffers == 0 then
		state.buffers = state.original_buffers
	end

	state.original_buffers = {}

	-- Restore normal keymaps
	set_normal_keymaps()

	update_buffer_list()
end

-- Exit search mode without applying
function M.exit_search_mode()
	if not state.search_mode then
		return
	end

	state.search_mode = false
	state.search_query = ""
	state.buffers = state.original_buffers
	state.original_buffers = {}

	-- Restore normal keymaps
	set_normal_keymaps()

	update_buffer_list()
end

-- Filter buffers based on search query
function M.filter_buffers()
	if #state.search_query == 0 then
		state.buffers = vim.deepcopy(state.original_buffers)
	else
		state.buffers = {}

		for _, bufnr in ipairs(state.original_buffers) do
			local name = api.nvim_buf_get_name(bufnr)
			local filename = fn.fnamemodify(name, ":t")

			-- Case-insensitive matching
			if
				string.find(string.lower(filename), string.lower(state.search_query))
				or string.find(string.lower(name), string.lower(state.search_query))
			then
				table.insert(state.buffers, bufnr)
			end
		end
	end

	update_buffer_list()
end

function set_normal_keymaps()
	if not state.buffer or not api.nvim_buf_is_valid(state.buffer) then
		return
	end

	for _, key in ipairs({ "j", "k", "<Down>", "<Up>", "<CR>", "<2-LeftMouse>", "d", "D", "q", "<Esc>", "v", "s", "/" }) do
		pcall(function()
			api.nvim_buf_del_keymap(state.buffer, "n", key)
		end)
	end

	local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./\\:"
	for i = 1, #chars do
		local c = chars:sub(i, i)
		pcall(function()
			api.nvim_buf_del_keymap(state.buffer, "n", c)
		end)
	end

	pcall(function()
		api.nvim_buf_del_keymap(state.buffer, "n", "<BS>")
	end)
	pcall(function()
		api.nvim_buf_del_keymap(state.buffer, "n", "<Space>")
	end)

	-- Helper function for setting keymaps
	local function map(mode, key, action)
		api.nvim_buf_set_keymap(state.buffer, mode, key, action, { silent = true, noremap = true })
	end

	map("n", "j", ":lua require('buffer-manager.ui').next_buffer()<CR>")
	map("n", "k", ":lua require('buffer-manager.ui').prev_buffer()<CR>")
	map("n", "<Down>", ":lua require('buffer-manager.ui').next_buffer()<CR>")
	map("n", "<Up>", ":lua require('buffer-manager.ui').prev_buffer()<CR>")

	map("n", "<CR>", ":lua require('buffer-manager.ui').select_buffer()<CR>")
	map("n", "<2-LeftMouse>", ":lua require('buffer-manager.ui').select_buffer()<CR>")

	map("n", "d", ":lua require('buffer-manager.ui').delete_buffer()<CR>")
	map("n", "D", ":lua require('buffer-manager.ui').delete_buffer()<CR>")
	map("n", "q", ":lua require('buffer-manager.ui').close()<CR>")
	map("n", "<Esc>", ":lua require('buffer-manager.ui').close()<CR>")

	map("n", "v", ":lua require('buffer-manager.ui').select_buffer('vertical')<CR>")
	map("n", "s", ":lua require('buffer-manager.ui').select_buffer('horizontal')<CR>")

	map("n", "?", ":lua require('buffer-manager.ui').show_help()<CR>")

	if config.options.search.enabled then
		map("n", config.options.search.keybinding, ":lua require('buffer-manager.ui').enter_search_mode()<CR>")
	end

	-- We don't add the FZF keybinding here since it's already available globally as <Space>gf
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
    syntax match BufferManagerSearchPrompt /^Search: .*$/
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
	set_normal_keymaps()
	update_buffer_list()

	api.nvim_win_set_option(state.win_id, "winhighlight", "Normal:BufferManagerNormal,FloatBorder:BufferManagerBorder")
end

function M.open_vertical()
	state.split_type = "vertical"
	M.open()
end

function M.open_horizontal()
	state.split_type = "horizontal"
	M.open()
end

function M.close()
	if state.win_id and api.nvim_win_is_valid(state.win_id) then
		api.nvim_win_close(state.win_id, true)
	end
	state.win_id = nil
	state.buffer = nil
	state.split_type = "normal"
	state.search_mode = false
	state.search_query = ""
	state.original_buffers = {}
end

function M.next_buffer()
	if state.search_mode or #state.buffers == 0 then
		return
	end

	state.selected_line = math.min(state.selected_line + 1, #state.buffers)
	api.nvim_win_set_cursor(state.win_id, { state.selected_line, 0 })
end

function M.prev_buffer()
	if state.search_mode or #state.buffers == 0 then
		return
	end

	state.selected_line = math.max(state.selected_line - 1, 1)
	api.nvim_win_set_cursor(state.win_id, { state.selected_line, 0 })
end

function M.select_buffer(split_type)
	if state.search_mode then
		return
	end

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

function M.delete_buffer()
	if state.search_mode then
		return
	end

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

function M.fzf_search()
	if not has_fzf then
		M.open()
		return
	end

	if state.search_mode then
		return
	end

	local valid_buffers = {}
	for _, bufnr in ipairs(api.nvim_list_bufs()) do
		if
			api.nvim_buf_is_valid(bufnr)
			and api.nvim_buf_is_loaded(bufnr)
			and api.nvim_buf_get_option(bufnr, "buflisted")
		then
			local name = api.nvim_buf_get_name(bufnr)
			if name ~= "" then
				table.insert(valid_buffers, bufnr)
			end
		end
	end

	if #valid_buffers == 0 then
		vim.notify("No valid buffers to show", vim.log.levels.INFO)
		return
	end

	local buffers = {}

	for _, bufnr in ipairs(api.nvim_list_bufs()) do
		if api.nvim_buf_is_loaded(bufnr) and api.nvim_buf_get_option(bufnr, "buflisted") then
			local name = api.nvim_buf_get_name(bufnr)
			local filename = fn.fnamemodify(name, ":t")
			local function format_buffer(bufnr)
				if not api.nvim_buf_is_valid(bufnr) then
					return nil
				end

				local name = api.nvim_buf_get_name(bufnr)
				if name == "" then
					return nil
				end

				local icon = get_icon(bufnr)
				local path = format_path(bufnr)
				local modified = api.nvim_buf_get_option(bufnr, "modified") and " [+]" or ""
				local current = bufnr == api.nvim_get_current_buf() and " *" or ""

				return string.format("%s %s%s%s", icon, path, modified, current)
			end

			table.insert(buffers, {
				name = name,
				display = format_buffer(bufnr),
				bufnr = bufnr,
			})
		end
	end

	local source = {}
	for _, buf in ipairs(buffers) do
		if api.nvim_buf_is_valid(buf.bufnr) then
			local name = api.nvim_buf_get_name(buf.bufnr)
			if name ~= "" then
				table.insert(source, buf.display)
			end
		end
	end

	fzf.fzf_exec(source, {
		prompt = config.options.fzf.prompt,
		fzf_opts = {
			["--layout"] = "reverse",
			["--info"] = "inline",
			["--no-preview"] = "",
		},
		winopts = {
			height = config.options.window.height_ratio,
			width = config.options.window.width_ratio,
			border = config.options.window.border,
			relative = "editor",
			row = math.floor((vim.o.lines - math.floor(vim.o.lines * config.options.window.height_ratio)) / 2),
			col = math.floor((vim.o.columns - math.floor(vim.o.columns * config.options.window.width_ratio)) / 2),
			title = " Buffer Manager ",
			title_pos = "center",
		},
		actions = {
			["default"] = function(selected)
				if selected and #selected > 0 then
					local display = selected[1]
					for _, buf in ipairs(buffers) do
						if buf.display == display then
							api.nvim_set_current_buf(buf.bufnr)
							break
						end
					end
				end
			end,
			["ctrl-v"] = function(selected)
				if selected and #selected > 0 then
					local display = selected[1]
					for _, buf in ipairs(buffers) do
						if buf.display == display then
							vim.cmd("vsplit")
							api.nvim_set_current_buf(buf.bufnr)
							break
						end
					end
				end
			end,
			["ctrl-s"] = function(selected)
				if selected and #selected > 0 then
					local display = selected[1]
					for _, buf in ipairs(buffers) do
						if buf.display == display then
							vim.cmd("split")
							api.nvim_set_current_buf(buf.bufnr)
							break
						end
					end
				end
			end,
			["ctrl-d"] = function(selected)
				if selected and #selected > 0 then
					local display = selected[1]
					for _, buf in ipairs(buffers) do
						if buf.display == display then
							if api.nvim_buf_get_option(buf.bufnr, "modified") then
								local choice =
									vim.fn.confirm("Buffer is modified. Save changes?", "&Yes\n&No\n&Cancel", 1)
								if choice == 1 then
									api.nvim_buf_call(buf.bufnr, function()
										vim.cmd("write")
									end)
								elseif choice == 3 then
									return
								end
							end
							pcall(api.nvim_buf_delete, buf.bufnr, { force = false })
							break
						end
					end
				end
			end,
		},
	})
end

-- Show help with all available keybindings
function M.show_help()
	local help_buffer = api.nvim_create_buf(false, true)
	api.nvim_buf_set_option(help_buffer, "bufhidden", "wipe")

	-- Create help content
	local lines = {
		" Buffer Manager - Available Keybindings ",
		"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
		"",
		" Navigation:",
		"   j/k or ↓/↑       : Navigate through buffers",
		"",
		" Buffer Actions:",
		"   Enter or double-click : Select buffer",
		"   d/D                  : Delete buffer",
		"   v                    : Open in vertical split",
		"   s                    : Open in horizontal split",
		"",
		" Search & Find:",
		"   /                    : Enter search mode",
	}

	if config.options.fzf.enabled then
		table.insert(lines, "   " .. config.options.fzf.keybinding .. "                    : Open FZF fuzzy finder")
	end

	table.insert(lines, "")
	table.insert(lines, " Other:")
	table.insert(lines, "   ?                    : Show this help")
	table.insert(lines, "   q/Esc                : Close buffer manager/help")
	table.insert(lines, "")
	table.insert(lines, " Press any key to close this help window")

	-- Set buffer content
	api.nvim_buf_set_lines(help_buffer, 0, -1, false, lines)
	api.nvim_buf_set_option(help_buffer, "modifiable", false)

	-- Calculate window dimensions
	local width = 50
	local height = #lines
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	-- Window options
	local opts = {
		style = "minimal",
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		border = config.options.window.border,
		title = " Help ",
		title_pos = "center",
	}

	-- Create floating window
	local help_win = api.nvim_open_win(help_buffer, true, opts)

	-- Set window options
	api.nvim_win_set_option(help_win, "winblend", 0)
	api.nvim_win_set_option(help_win, "cursorline", false)

	-- Set buffer filetype for potential highlighting
	api.nvim_buf_set_option(help_buffer, "filetype", "help")

	-- Add keymapping to close on any key
	local keys = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789`-=[]\\;',./~!@#$%^&*()_+{}|:\"<>?"
	for i = 1, #keys do
		local c = keys:sub(i, i)
		api.nvim_buf_set_keymap(help_buffer, "n", c, "<cmd>close<CR>", { silent = true, noremap = true })
	end

	-- Add special keys
	for _, key in ipairs({ "<Space>", "<CR>", "<Esc>", "<Tab>", "<BS>", "<Up>", "<Down>", "<Left>", "<Right>" }) do
		api.nvim_buf_set_keymap(help_buffer, "n", key, "<cmd>close<CR>", { silent = true, noremap = true })
	end
end

return M
