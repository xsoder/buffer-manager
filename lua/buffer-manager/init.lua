local M = {}

local config = require("buffer-manager.config")
local ui = require("buffer-manager.ui")

function M.setup(opts)
    config.setup(opts)

    -- Register commands
    vim.api.nvim_create_user_command("BufferManager", ui.open, {})
    vim.api.nvim_create_user_command("BufferManagerFzf", ui.fzf_search, {})

    -- Set up default keybindings if enabled
    if config.options.default_mappings then
        local open_key = config.options.mappings.open:gsub("<leader>", "<Space>")
        local vertical_key = config.options.mappings.vertical:gsub("<leader>", "<Space>")
        local horizontal_key = config.options.mappings.horizontal:gsub("<leader>", "<Space>")

        vim.keymap.set("n", config.options.mappings.open, ui.open, { noremap = true, silent = true })
        vim.keymap.set("n", open_key, ui.open, { noremap = true, silent = true })

        vim.keymap.set("n", config.options.mappings.vertical, ui.open_vertical, { noremap = true, silent = true })
        vim.keymap.set("n", vertical_key, ui.open_vertical, { noremap = true, silent = true })

        vim.keymap.set("n", config.options.mappings.horizontal, ui.open_horizontal, { noremap = true, silent = true })
        vim.keymap.set("n", horizontal_key, ui.open_horizontal, { noremap = true, silent = true })
    end

    -- Map both <Space>ll and <leader>ll to buffer search
    local function bm_search()
        local ui_mod = require("buffer-manager.ui")
        if pcall(require, "telescope.pickers") then
            -- Open buffer manager UI then enter search mode
            ui_mod.open()
            ui_mod.enter_search_mode()
        else
            local has_fzf, _ = pcall(require, "fzf-lua")
            if not has_fzf then
                vim.notify("buffer-manager.nvim: fzf-lua not found. Install it to enable FZF search.", vim.log.levels.WARN)
                return
            end
            ui_mod.fzf_search()
        end
    end
    vim.keymap.set("n", "<Space>ll", bm_search, { noremap = true, silent = true, desc = "Buffer Manager: Search Buffers" })
    vim.keymap.set("n", "<leader>ll", bm_search, { noremap = true, silent = true, desc = "Buffer Manager: Search Buffers" })
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
M.show_help = ui.show_help

return M
