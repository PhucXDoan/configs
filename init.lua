local function apply_trailing_space()
  for _, match in ipairs(vim.fn.getmatches()) do
    if match.group == "TrailingSpace" then return end
  end
  vim.fn.matchadd("TrailingSpace", [[\s\+$]])
end

local function apply_config()
  vim.opt.scrolloff   = 3
  vim.opt.tabstop     = 4
  vim.opt.shiftwidth  = 4
  vim.opt.expandtab   = true
  vim.opt.softtabstop = 4
  vim.opt.backspace   = { "indent", "eol" }
  vim.opt.wrap        = false
  vim.opt.smartindent = false
  vim.opt.cindent     = false
  vim.opt.indentexpr  = ""

  vim.api.nvim_set_hl(0, "TrailingSpace", { bg = "#FF0000" })

  -- Remove any existing TrailingSpace matches to avoid duplicates on reload
  for _, match in ipairs(vim.fn.getmatches()) do
    if match.group == "TrailingSpace" then
      vim.fn.matchdelete(match.id)
    end
  end
  vim.fn.matchadd("TrailingSpace", [[\s\+$]])
end

apply_config()

vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
  callback = apply_trailing_space,
})

vim.api.nvim_create_user_command("RR", function()
  vim.cmd("source " .. "C:/Users/Phuc/Documents/configs/init.lua")
  local current_win = vim.api.nvim_get_current_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    vim.api.nvim_set_current_win(win)
    apply_config()
    vim.cmd("edit")
  end
  vim.api.nvim_set_current_win(current_win)
end, {})

vim.api.nvim_create_user_command("RC", function()
  vim.cmd("edit " .. "C:/Users/Phuc/Documents/configs/init.lua")
end, {})

vim.api.nvim_set_hl(0, "OdinError", { bg = "#FF0000" })

local odin_error_match_id = nil

local function clear_odin_error()
  if odin_error_match_id then
    pcall(vim.fn.matchdelete, odin_error_match_id)
    odin_error_match_id = nil
    vim.api.nvim_clear_autocmds({ group = "OdinErrorClear" })
  end
end

vim.api.nvim_create_augroup("OdinErrorClear", { clear = true })

local function odin_build(run_gwiz)
  vim.cmd("silent! wall")
  clear_odin_error()

  local cwd = vim.fn.getcwd()
  local lines = {}
  vim.fn.jobstart(
    { "odin", "build", ".", "-vet-shadowing", "-o:none", "-max-error-count:1", "-debug" },
    {
      cwd = cwd,
      stderr_buffered = true,
      stdout_buffered = true,
      on_stderr = function(_, data) vim.list_extend(lines, data) end,
      on_stdout = function(_, data) vim.list_extend(lines, data) end,
      on_exit = function(_, code)
        vim.schedule(function()
          if code ~= 0 then
            for _, line in ipairs(lines) do
              local file, row, col, msg = line:match("^(.-)%((%d+):(%d+)%)%s+.-%:%s*(.+)$")
              if file then
                vim.cmd("edit " .. vim.fn.fnameescape(file))
                vim.api.nvim_win_set_cursor(0, { tonumber(row), tonumber(col) - 1 })
                vim.cmd("normal! zz")
                odin_error_match_id = vim.fn.matchadd("OdinError", "\\%" .. row .. "l")
                vim.api.nvim_create_autocmd("CursorMoved", {
                  group = "OdinErrorClear",
                  buffer = 0,
                  once = true,
                  callback = clear_odin_error,
                })
                vim.defer_fn(function()
                  vim.api.nvim_echo({{ table.concat(lines, "\n"), "ErrorMsg" }}, true, {})
                end, 10)
                break
              end
            end
          elseif run_gwiz then
            vim.cmd("set splitright | vsplit | enew")
            vim.fn.termopen({ "pwsh", "-NoLogo", "-NoProfile", "-Command", ".\\gwiz.exe" }, { cwd = cwd })
            vim.cmd("startinsert")
          end
        end)
      end,
    }
  )
end

vim.api.nvim_create_user_command("R", function() odin_build(true)  end, {})
vim.api.nvim_create_user_command("C", function() odin_build(false) end, {})


local function levenshtein(a, b)
  local m, n = #a, #b
  local d = {}
  for i = 0, m do d[i] = { [0] = i } end
  for j = 0, n do d[0][j] = j end
  for i = 1, m do
    for j = 1, n do
      if a:sub(i,i) == b:sub(j,j) then
        d[i][j] = d[i-1][j-1]
      else
        d[i][j] = 1 + math.min(d[i-1][j], d[i][j-1], d[i-1][j-1])
      end
    end
  end
  return d[m][n]
end

local function jump_to(r)
  vim.cmd("edit " .. vim.fn.fnameescape(r.file))
  vim.api.nvim_win_set_cursor(0, { r.lnum, 0 })
  vim.cmd("normal! zz")
end

vim.keymap.set("n", "\\", function()
  vim.cmd("silent! wall")
  local input = vim.fn.input("goto: ")
  if input == "" then return end

  local exact, all_decls = {}, {}
  local files = vim.fn.glob(vim.fn.getcwd() .. "/**/*.odin", false, true)
  for _, file in ipairs(files) do
    local lnum = 0
    for line in io.lines(file) do
      lnum = lnum + 1
      local name = line:match("^%s*([%w_]+)%s*::")
      if name then
        local entry = { file = file, lnum = lnum, text = line, name = name }
        if name == input then
          table.insert(exact, entry)
        end
        table.insert(all_decls, entry)
      end
    end
  end

  local function show_menu(items)
    local menu = {}
    for i, r in ipairs(items) do
      table.insert(menu, string.format("%d) %s", i, vim.trim(r.text)))
    end
    local choice = vim.fn.inputlist(menu)
    if choice >= 1 and choice <= #items then
      jump_to(items[choice])
    end
  end

  if #exact == 1 then
    jump_to(exact[1])
  elseif #exact > 1 then
    show_menu(exact)
  else
    -- No exact match: rank by edit distance, drop anything too far away
    -- Prefix matches are always included (dist = 0 for sorting purposes)
    local threshold = math.floor(#input * 0.5)
    local closest = {}
    for _, entry in ipairs(all_decls) do
      if entry.name:sub(1, #input) == input then
        table.insert(closest, { entry = entry, dist = 0 })
      else
        local dist = levenshtein(input, entry.name)
        if dist <= threshold then
          table.insert(closest, { entry = entry, dist = dist })
        end
      end
    end
    table.sort(closest, function(a, b) return a.dist < b.dist end)
    if #closest == 0 then
      vim.api.nvim_echo({{ "No close match found for: " .. input, "WarningMsg" }}, false, {})
      return
    end
    local top = {}
    for i = 1, math.min(5, #closest) do top[i] = closest[i].entry end
    if #top == 1 then
      jump_to(top[1])
    else
      show_menu(top)
    end
  end
end, { noremap = true })


vim.cmd([[cnoreabbrev term split \| terminal]])

vim.keymap.set("t", "<C-w>N", "<C-\\><C-n>")

vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    vim.o.scrollback = 10000
    vim.cmd("startinsert")
  end,
})


vim.keymap.set("t", "<C-w>h", "<C-\\><C-n><C-w>h")
vim.keymap.set("t", "<C-w>j", "<C-\\><C-n><C-w>j")
vim.keymap.set("t", "<C-w>k", "<C-\\><C-n><C-w>k")
vim.keymap.set("t", "<C-w>l", "<C-\\><C-n><C-w>l")

vim.opt.shell = "pwsh"
vim.opt.shellcmdflag = "-NoLogo -NoProfile -Command"

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    if vim.fn.argc() == 0 then
      vim.cmd("Explore")
    end
  end,
})

vim.opt.cursorline = true
vim.api.nvim_set_hl(0, "CursorLine", { underline = true, bg = "NONE", sp = "#FFFF00" })

vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
  callback = function()
    vim.opt_local.cursorline = true
  end,
})

vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
  callback = function()
    vim.opt_local.cursorline = false
  end,
})

vim.api.nvim_set_hl(0, "TodoHighlight", { bg = "#FF00FF", fg = "#FFFFFF", bold = true })
vim.api.nvim_set_hl(0, "TmpHighlight",  { bg = "#FFFF00", fg = "#000000", bold = true })

local function apply_todo_highlight()
  for _, match in ipairs(vim.fn.getmatches()) do
    if match.group == "TodoHighlight" then return end
  end
  vim.fn.matchadd("TodoHighlight", [[\<TODO\>]])
end

local function apply_tmp_highlight()
  for _, match in ipairs(vim.fn.getmatches()) do
    if match.group == "TmpHighlight" then return end
  end
  vim.fn.matchadd("TmpHighlight", [[\<TMP\(_\w\+\)\?\>]])
end

apply_todo_highlight()
apply_tmp_highlight()

vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
  callback = function()
    apply_todo_highlight()
    apply_tmp_highlight()
  end,
})

vim.api.nvim_set_hl(0, "OdinComment",     { fg = "#00FFFF" })
vim.api.nvim_set_hl(0, "OdinControlFlow", { fg = "#FF8800", bold = true })
vim.api.nvim_set_hl(0, "OdinLiteral",     { fg = "#B6E3CE" })

local function apply_odin_syntax(force)
  if not force and vim.b.odin_syntax_applied then return end
  vim.cmd([[
    syntax clear
    syntax region  OdinLiteral start=/"/ skip=/\\"/ end=/"/
    syntax region  OdinLiteral start=/'/ skip=/\\'/ end=/'/
    syntax region  OdinLiteral start=/`/            end=/`/
    syntax keyword OdinLiteral true false nil
    syntax match   OdinLiteral "\<\d\(\d\|_\)*\(\.\d\+\)\?\([eE][+-]\?\d\+\)\?\>"
    syntax match   OdinLiteral "\<0x[0-9a-fA-F_]\+\>"
    syntax match   OdinLiteral "\<0o[0-7_]\+\>"
    syntax match   OdinLiteral "\<0b[01_]\+\>"
    syntax match   OdinComment "//.*$" containedin=ALL
    syntax keyword OdinControlFlow return break continue or_return or_break or_continue fallthrough defer goto
    syntax match   OdinControlFlow "\<defer_\w\+"
    syntax match   OdinComment "//.*$" containedin=ALL
  ]])
  vim.b.odin_syntax_applied = true
end

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.odin",
  callback = function()
    vim.bo.filetype = "odin"
    vim.bo.indentexpr = ""
    vim.bo.smartindent = false
    vim.bo.cindent = false

    local function ca_line(row)
      local line   = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
      local expr   = line:match("^%s*(.-)%s*=.*$") or line:match("^%s*(.-)%s*,?%s*$")
      local indent = line:match("^(%s*)")
      return {
        "",
        indent .. "case " .. expr .. ": {",
        indent .. "    panic(\"TODO\")",
        indent .. "}",
      }
    end

    vim.keymap.set("n", "ca", function()
      local count = vim.v.count1
      for _ = 1, count do
        local row       = vim.api.nvim_win_get_cursor(0)[1]
        local new_lines = ca_line(row)
        vim.api.nvim_buf_set_lines(0, row - 1, row, false, new_lines)
        vim.api.nvim_win_set_cursor(0, { row + #new_lines, 0 })
      end
    end, { buffer = true })

    vim.keymap.set("v", "ca", function()
      -- Exit visual first so '< and '> marks are committed
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", true)
      local s = vim.fn.line("'<")
      local e = vim.fn.line("'>")
      -- Grab indent before any replacements
      local first_line = vim.api.nvim_buf_get_lines(0, s - 1, s, false)[1]
      if not first_line then return end
      local indent = first_line:match("^(%s*)")
      -- Collect all expanded lines first (bottom-up to preserve row numbers)
      local replacements = {}
      for row = e, s, -1 do
        replacements[row] = ca_line(row)
      end
      -- Apply bottom-up so earlier row numbers stay valid
      for row = e, s, -1 do
        vim.api.nvim_buf_set_lines(0, row - 1, row, false, replacements[row])
      end
      -- Each ca_line produces 4 lines; insert fallthrough after the last one
      local count = e - s + 1
      local insert_row = s - 1 + count * 4
      vim.api.nvim_buf_set_lines(0, insert_row, insert_row, false, {
        "",
        indent .. "case: panic(\"Invalid.\")",
        "",
      })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    end, { buffer = true })
    apply_odin_syntax(true)
  end,
})

vim.api.nvim_create_autocmd("WinEnter", {
  callback = function()
    if vim.bo.filetype == "odin" then
      apply_odin_syntax(false)
    end
  end,
})

vim.cmd([[cnoreabbrev E Explore]])

vim.keymap.set("n", "/", "/\\v", { noremap = true })
vim.keymap.set("n", "?", "?\\v", { noremap = true })
