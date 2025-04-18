local M = {}

M.options = {
	icons = false,
	use_devicons = true,
	default_mappings = true,
	mappings = {
		open = "<leader>bb",
		vertical = "<leader>bv",
		horizontal = "<leader>bs",
	},
	window = {
		width_ratio = 0.3,
		height_ratio = 0.3,
		border = "single",
		position = "center",
	},
	display = {
		show_numbers = true,
		show_modified = true,
		show_flags = true,
		path_display = "filename",
	},
	search = {
		enabled = true,
		keybinding = "/",
		prompt = "Search: ",
		live_update = true,
	},
	fzf = {
		enabled = true,
		keybinding = "gf",
		prompt = "Buffer Search> ",
		preview = true,
		preview_window = "right:50%",
	},
	ripgrep = {
		enabled = true,
		keybinding = "gr",
		prompt = "Ripgrep search: ",
		args = {
			"vimgrep",
			"smart-case",
		},
	},
}

-- Apply user configuration
function M.setup(opts)
	opts = opts or {}
	M.options = vim.tbl_deep_extend("force", M.options, opts)

	-- Check if devicons is available
	if M.options.use_devicons and not pcall(require, "nvim-web-devicons") then
		M.options.use_devicons = false
		vim.notify("buffer-manager.nvim: nvim-web-devicons not found, disabling icons", vim.log.levels.WARN)
	end

	-- Check for FZF dependency
	if M.options.fzf.enabled then
		local has_fzf = pcall(require, "fzf-lua")
		if not has_fzf then
			M.options.fzf.enabled = false
			vim.notify(
				"buffer-manager.nvim: fzf-lua not found. Install it with your package manager to enable FZF features.",
				vim.log.levels.INFO
			)
		end
	end

	-- Check for ripgrep dependency
	if M.options.ripgrep.enabled then
		local rg_exists = vim.fn.executable("rg") == 1
		if not rg_exists then
			M.options.ripgrep.enabled = false
			vim.notify(
				"buffer-manager.nvim: ripgrep (rg) not found, disabling ripgrep integration",
				vim.log.levels.WARN
			)
		end
	end

	-- Setup highlights
	M.setup_highlights()
end

-- Setup highlight groups
function M.setup_highlights()
	local highlights = {
		BufferManagerNormal = { link = "Normal" },
		BufferManagerBorder = { link = "FloatBorder" },
		BufferManagerTitle = { link = "Title" },
		BufferManagerSelected = { link = "CursorLine" },
		BufferManagerCurrent = { link = "SpecialKey" },
		BufferManagerModified = { link = "WarningMsg" },
		BufferManagerIndicator = { link = "Type" },
		BufferManagerPath = { link = "Comment" },
		BufferManagerSearchPrompt = { link = "Question" },
	}

	for group, val in pairs(highlights) do
		vim.api.nvim_set_hl(0, group, val)
	end
end

return M
