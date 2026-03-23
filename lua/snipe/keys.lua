-- lua/snipe/keys.lua
-- Default keymap table. Separated so users can cherry-pick without calling setup().

local M = {}

function M.register()
  local nav    = require("snipe.nav")
  local search = require("snipe.search")
  local rg     = require("snipe.rg")
  local git_root = require("snipe.picker").git_root

  local maps = {
    -- Nav
    { "n", "<leader>ff", nav.files,                         "Nav: files (fd)"               },
    { "n", "<leader>fb", nav.buffers,                       "Nav: buffers"                  },
    { "n", "<leader>f'", nav.marks,                         "Nav: marks"                    },
    { "n", "<leader>fr", nav.references,                    "Nav: LSP references"            },
    { "n", "<leader>fo", nav.oldfiles,                      "Nav: recent files"             },
    { "n", "<leader>fj", nav.projects,                      "Nav: projects"                 },
    { "n", "<leader>fd", function() nav.diagnostics(false) end, "Nav: diagnostics (buffer)" },
    { "n", "<leader>f;", function() nav.diagnostics(true)  end, "Nav: diagnostics (workspace)" },

    -- Search
    { "n", "<leader>sa",  search.autocmds,                  "Search: Autocmds"              },
    { "n", "<leader>sc",  search.cmdhistory,                 "Search: Command History"       },
    { "n", "<leader>sC",  search.commands,                   "Search: Commands"              },
    { "n", "<leader>sg",  function() search.grep() end,      "Search: Grep (root)"           },
    { "n", "<leader>s.",  search.grep_cwd,                   "Search: Grep (cwd)"            },
    { "n", "<leader>sh",  search.help,                       "Search: Help Pages"            },
    { "n", "<leader>sH",  search.highlights,                 "Search: Highlights"            },
    { "n", "<leader>si",  search.icons,                      "Search: Icons"                 },
    { "n", "<leader>sj",  search.jumps,                      "Search: Jumps"                 },
    { "n", "<leader>sk",  search.keymaps,                    "Search: Keymaps"               },
    { "n", "<leader>sl",  search.loclist,                    "Search: Location List"         },
    { "n", "<leader>sM",  search.manpages,                   "Search: Man Pages"             },
    { "n", "<leader>sp",  search.plugins,                    "Search: Plugin Spec"           },
    { "n", "<leader>sq",  search.quickfix,                   "Search: Quickfix"              },
    { "n", "<leader>su",  search.undo,                       "Search: Undo History"          },
    { "n", "<leader>sw",  function() search.grep_word(true)  end, "Search: Grep Word (root)" },
    { "n", "<leader>sW",  function() search.grep_word(false) end, "Search: Grep Word (cwd)"  },
    { "n", '<leader>s"',  search.registers,                  "Search: Registers"             },
    { "n", "<leader>s/",  search.searchhistory,              "Search: Search History"        },
    { "n", "<leader>sn",  search.noice,                      "Search: Noice History"         },

    -- Rg
    { "n", "<leader>fw",  rg.rg,                             "Rg: grep (fast)"              },
  }

  for _, m in ipairs(maps) do
    vim.keymap.set(m[1], m[2], m[3], { desc = m[4], silent = true })
  end
end

return M
