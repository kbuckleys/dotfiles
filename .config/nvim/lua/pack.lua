-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/

vim.pack.add({
    'https://github.com/lukas-reineke/indent-blankline.nvim.git',
    'https://github.com/brenoprata10/nvim-highlight-colors.git',
    'https://github.com/nvim-treesitter/nvim-treesitter.git',
    'https://github.com/nvim-tree/nvim-web-devicons.git',
    'https://github.com/nvim-lualine/lualine.nvim.git',
    "https://github.com/rafamadriz/friendly-snippets",
    'https://github.com/akinsho/bufferline.nvim.git',
    'https://github.com/nvim-lua/plenary.nvim.git',
    'https://github.com/mikavilpas/yazi.nvim.git',
    "https://github.com/delphinus/md-render.nvim",
    "https://github.com/neovim/nvim-lspconfig",
    "https://github.com/windwp/nvim-autopairs",
    "https://github.com/folke/which-key.nvim",
    "https://github.com/mason-org/mason.nvim",
    "https://github.com/chentoast/marks.nvim",
    "https://github.com/delphinus/budoux.lua",
    "https://github.com/nvim-mini/mini.nvim",
    "https://github.com/tpope/vim-fugitive",
})

-- Update
vim.api.nvim_create_user_command("PackUpdate", function()
    vim.pack.update()
end, { desc = "Update all plugins" })

require("nvim-autopairs").setup({
  check_ts = true, -- Enable Treesitter integration
  disable_filetype = { "TelescopePrompt", "spectre_panel" },
  fast_wrap = {}
})

require('marks').setup()
require("mini.surround").setup()

require('nvim-highlight-colors').setup({
  render = 'background',
})

require("ibl").setup({
  indent = { char = "│" },
  scope = {
    enabled = true,
    show_start = true,
    show_end = true
  }
})

require("mini.notify").setup({
    -- only show messages
    content = {
        format = function(notif)
            return notif.msg
        end
    },
    window = {
        -- Bottom right, sitting directly on top of the statusline. Derived from
        -- the options rather than hardcoded, so turning the statusline off or
        -- giving the cmdline height back keeps the window off both of them.
        --
        -- Borderless, so the message is bare text over the buffer. The empty
        -- title is belt and braces: a border is what hosts a title, so dropping
        -- the border already hides mini.notify's " Notifications " caption --
        -- but the caption is force-set on every open and merged with
        -- tbl_deep_extend('force', ...), where a nil is an absent key rather
        -- than an erasure, so it can only ever be overridden by a value.
        config = function()
            local has_statusline = vim.o.laststatus > 0
            local pad = vim.o.cmdheight + (has_statusline and 1 or 0)
            return {
                anchor = "SE",
                col = vim.o.columns,
                row = vim.o.lines - pad,
                border = "none",
                title = ""
            }
        end,

        -- Notifications are the one float with no surface (zenon.lua gives
        -- MiniNotifyNormal bg=NONE), so mini.notify's default winblend of 25
        -- has nothing to blend but the buffer text underneath, which would show
        -- through the message. 0 keeps the text it is reporting on legible.
        winblend = 0
    }
})

-- setup() already pointed vim.notify here, but its INFO level paints the text
-- DiagnosticInfo -- the message colour comes from a per-notification extmark,
-- not from MiniNotifyNormal, so recolouring that group alone would not touch
-- it. Route INFO through MiniNotifyNormal (zenon yellow) and leave ERROR and
-- WARN on their diagnostic colours, which is the whole signal fzf.lua's
-- failure notifications rely on.
vim.notify = require("mini.notify").make_notify({
    INFO = { hl_group = "MiniNotifyNormal" }
})

require("mini.completion").setup({
    lsp_completion = {
        auto_setup = true
    }
})

local snippets = require("mini.snippets")
snippets.setup({
    snippets = { snippets.gen_loader.from_lang() }
})

require("which-key").setup({
    preset = "helix"
})

require("mason").setup()

require("nvim-treesitter").setup()

vim.api.nvim_create_autocmd("FileType", {
  desc = "Start treesitter highlighting when a parser is available",
  callback = function(ev)
    local lang = vim.treesitter.language.get_lang(ev.match)
    if lang and pcall(vim.treesitter.start, ev.buf, lang) then
      vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end
})
