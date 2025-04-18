local M = {
	options = {
		icons = false,
		use_devicons = true,
		default_mappings = true,
		mappings = {
			open = "<leader>bb",
			vertical = "<leader>bv",
			horizontal = "<leader>bs",
		},
		window = {
			width_ratio = 0.6,
			height_ratio = 0.6,
			border = "rounded",
			position = "center",
		},
		display = {
			show_numbers = true,
			show_modified = true,
			show_flags = true,
			path_display = "shortened",
		},
	},
}

-- Apply user configuration
function M.setup(opts)
	opts = opts or {}
	M.options = vim.tbl_deep_extend("force", M.options, opts)

	if M.options.use_devicons and not pcall(require, "nvim-web-devicons") then
		M.options.use_devicons = false
		vim.notify("buffer-manager.nvim: nvim-web-devicons not found, disabling icons", vim.log.levels.WARN)
	end
	M.setup_highlights()
end

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
	}

	for group, val in pairs(highlights) do
		vim.api.nvim_set_hl(0, group, val)
	end
end

return M
