-- lua/snipe/keys.lua
-- Default keymap table. Separated so users can cherry-pick without calling setup().

local M = {}

function M.register()
  local nav    = require("snipe.nav")
  local search = require("snipe.search")
  local rg     = require("snipe.rg")

  local maps = {
    -- Nav
    { "n", "<leader>ff", nav.files,                           "files (fd)"            },
    { "n", "<leader>fb", nav.buffers,                         "buffers"               },
    { "n", "<leader>f'", nav.marks,                           "marks"                 },
    { "n", "<leader>fr", nav.references,                      "LSP references"        },
    { "n", "<leader>fo", nav.oldfiles,                        "recent files"          },
    { "n", "<leader>fj", nav.projects,                        "projects"              },
    { "n", "<leader>fd", function() nav.diagnostics(false) end, "diagnostics (buffer)"  },
    { "n", "<leader>f;", function() nav.diagnostics(true)  end, "diagnostics (workspace)"},

    -- Search
    { "n", "<leader>sa",  search.autocmds,                   "Autocmds"              },
    { "n", "<leader>sc",  search.cmdhistory,                 "Command History"       },
    { "n", "<leader>sC",  search.commands,                   "Commands"              },
    { "n", "<leader>sg",  function() search.grep() end,      "Grep (root)"           },
    { "n", "<leader>s.",  search.grep_cwd,                   "Grep (cwd)"            },
    { "n", "<leader>sh",  search.help,                       "Help Pages"            },
    { "n", "<leader>sH",  search.highlights,                 "Highlights"            },
    { "n", "<leader>si",  search.icons,                      "Icons"                 },
    { "n", "<leader>sj",  search.jumps,                      "Jumps"                 },
    { "n", "<leader>sk",  search.keymaps,                    "Keymaps"               },
    { "n", "<leader>sl",  search.loclist,                    "Location List"         },
    { "n", "<leader>sM",  search.manpages,                   "Man Pages"             },
    { "n", "<leader>sp",  search.plugins,                    "Plugin Spec"           },
    { "n", "<leader>sq",  search.quickfix,                   "Quickfix"              },
    { "n", "<leader>su",  search.undo,                       "Undo History"          },
    { "n", "<leader>sw",  function() search.grep_word(true)  end, "Grep Word (root)"  },
    { "n", "<leader>sW",  function() search.grep_word(false) end, "Grep Word (cwd)"   },
    { "n", '<leader>s"',  search.registers,                  "Registers"             },
    { "n", "<leader>s/",  search.searchhistory,              "Search History"        },
    { "n", "<leader>sn",  search.noice,                      "Noice History"         },

    -- Rg
    { "n", "<leader>fw",  rg.rg,                             "grep (fast)"           },
    { "n", "<leader>/",  rg.rg,                             "grep (fast)"           },
  }

  for _, m in ipairs(maps) do
    vim.keymap.set(m[1], m[2], m[3], { desc = m[4], silent = true })
  end
end

return M
