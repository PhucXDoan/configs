local odin_error_match_id = nil
local r_mode = nil

local function add_match_once(group, pattern)
  for _, match in ipairs(vim.fn.getmatches()) do
    if match.group == group then
      return
    end
  end

  vim.fn.matchadd(group, pattern)
end

local function delete_matches_by_group(group)
  for _, match in ipairs(vim.fn.getmatches()) do
    if match.group == group then
      vim.fn.matchdelete(match.id)
    end
  end
end

local function open_file_at_line(path, row, col)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  vim.api.nvim_win_set_cursor(0, { row, col })
  vim.cmd("normal! zz")
end

local function show_error_output(lines)
  vim.defer_fn(function()
    vim.api.nvim_echo({ { table.concat(lines, "\n"), "ErrorMsg" } }, true, {})
  end, 10)
end

local function mark_odin_error_line(row)
  odin_error_match_id = vim.fn.matchadd("OdinError", "\\%" .. row .. "l")
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = "OdinErrorClear",
    buffer = 0,
    once = true,
    callback = function()
      if odin_error_match_id then
        pcall(vim.fn.matchdelete, odin_error_match_id)
        odin_error_match_id = nil
        vim.api.nvim_clear_autocmds({ group = "OdinErrorClear" })
      end
    end,
  })
end

local function clear_odin_error()
  if not odin_error_match_id then
    return
  end

  pcall(vim.fn.matchdelete, odin_error_match_id)
  odin_error_match_id = nil
  vim.api.nvim_clear_autocmds({ group = "OdinErrorClear" })
end

local function open_runner(cmd, cwd)
  vim.cmd("set splitright | vsplit | enew")

  local win = vim.api.nvim_get_current_win()
  vim.fn.termopen(cmd, {
    cwd = cwd,
    on_exit = function(_, code)
      if code ~= 0 then
        return
      end

      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end)
    end,
  })

  vim.cmd("startinsert")
end

local function apply_config()
  vim.g.netrw_liststyle = 3
  vim.g.netrw_banner = 0

  vim.opt.scrolloff = 3
  vim.opt.tabstop = 4
  vim.opt.shiftwidth = 4
  vim.opt.expandtab = true
  vim.opt.softtabstop = 4
  vim.opt.backspace = { "indent", "eol" }
  vim.opt.wrap = false
  vim.opt.smartindent = false
  vim.opt.cindent = false
  vim.opt.indentexpr = ""
  if vim.fn.has("win32") == 1 then
      vim.opt.shell = "pwsh"
  end
  vim.opt.shellcmdflag = "-NoLogo -NoProfile -Command"
  vim.opt.cursorline = true

  vim.api.nvim_set_hl(0, "TrailingSpace", { bg = "#FF0000" })
  vim.api.nvim_set_hl(0, "OdinError", { bg = "#FF0000" })
  vim.api.nvim_set_hl(0, "CursorLine", { underline = true, bg = "NONE", sp = "#FFFF00" })
  vim.api.nvim_set_hl(0, "TodoHighlight", { bg = "#FF00FF", fg = "#FFFFFF", bold = true })
  vim.api.nvim_set_hl(0, "TmpHighlight", { bg = "#FFFF00", fg = "#000000", bold = true })
  vim.api.nvim_set_hl(0, "OdinComment", { fg = "#00FFFF" })
  vim.api.nvim_set_hl(0, "OdinControlFlow", { fg = "#FF8800", bold = true })
  vim.api.nvim_set_hl(0, "OdinLiteral", { fg = "#B6E3CE" })

  delete_matches_by_group("TrailingSpace")
  add_match_once("TrailingSpace", [[\s\+$]])
  add_match_once("TodoHighlight", [[\<TODO\>]])
  add_match_once("TmpHighlight", [[\<TMP\(_\w\+\)\?\>]])
end

local function reload_config()
  vim.cmd("source " .. "~/Documents/configs/init.lua")

  local current_win = vim.api.nvim_get_current_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    vim.api.nvim_set_current_win(win)
    apply_config()
    vim.cmd("edit")
  end
  vim.api.nvim_set_current_win(current_win)
end

local function edit_config()
  vim.cmd("edit " .. "~/Documents/configs/init.lua")
end

local function handle_odin_build_error(lines)
  for _, line in ipairs(lines) do
    local file, row, col = line:match("^(.-)%((%d+):(%d+)%)%s+.-%:%s*.+$")
    if file then
      open_file_at_line(file, tonumber(row), tonumber(col) - 1)
      mark_odin_error_line(row)
      show_error_output(lines)
      return
    end
  end
end

local function handle_python_type_error(lines)
  for _, line in ipairs(lines) do
    local file, row = line:match("^(.-)%:(%d+)%:%s*error%:")
    if file then
      open_file_at_line(file, tonumber(row), 0)
      mark_odin_error_line(row)
      show_error_output(lines)
      return
    end
  end
end

local function odin_build(run_after_success)
  vim.cmd("silent! wall")
  clear_odin_error()

  local cwd = vim.fn.getcwd()
  local lines = {}

  vim.fn.jobstart({
    "odin",
    "build",
    ".",
    "-vet-shadowing",
    "-o:none",
    "-max-error-count:1",
    "-debug",
  }, {
    cwd = cwd,
    stderr_buffered = true,
    stdout_buffered = true,
    on_stderr = function(_, data)
      vim.list_extend(lines, data)
    end,
    on_stdout = function(_, data)
      vim.list_extend(lines, data)
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          handle_odin_build_error(lines)
          return
        end

        if not run_after_success then
          return
        end

        local exe = vim.fn.fnamemodify(cwd, ":t") .. ".exe"
        open_runner({ "pwsh", "-NoLogo", "-NoProfile", "-Command", ".\\" .. exe }, cwd)
      end)
    end,
  })
end

local function run_python()
  vim.cmd("silent! wall")
  clear_odin_error()

  local cwd = vim.fn.getcwd()
  local path = r_mode
  local lines = {}

  vim.fn.jobstart({ "pwsh", "-NoLogo", "-NoProfile", "-Command", "python -m mypy . --disallow-untyped-defs" }, {
    cwd = cwd,
    stderr_buffered = true,
    stdout_buffered = true,
    on_stderr = function(_, data)
      vim.list_extend(lines, data)
    end,
    on_stdout = function(_, data)
      vim.list_extend(lines, data)
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          handle_python_type_error(lines)
          return
        end

        open_runner({ "pwsh", "-NoLogo", "-NoProfile", "-Command", "python " .. path }, cwd)
      end)
    end,
  })
end

local function run_r()
  if r_mode == nil then
    local odin_files = vim.fn.glob(vim.fn.getcwd() .. "/*.odin", false, true)
    if #odin_files > 0 then
      r_mode = "odin"
    else
      local input = vim.fn.input("R mode (odin / <python path>): ")
      if input == "" then
        return
      end
      r_mode = input
    end
  end

  if r_mode == "odin" then
    odin_build(true)
    return
  end

  run_python()
end

local function reset_r_mode()
  r_mode = nil
end

local function levenshtein(a, b)
  local m = #a
  local n = #b
  local d = {}

  for i = 0, m do
    d[i] = { [0] = i }
  end

  for j = 0, n do
    d[0][j] = j
  end

  for i = 1, m do
    for j = 1, n do
      if a:sub(i, i) == b:sub(j, j) then
        d[i][j] = d[i - 1][j - 1]
      else
        d[i][j] = 1 + math.min(d[i - 1][j], d[i][j - 1], d[i - 1][j - 1])
      end
    end
  end

  return d[m][n]
end

local function jump_to(entry)
  open_file_at_line(entry.file, entry.lnum, 0)
end

local function show_jump_menu(items)
  local menu = {}

  for i, entry in ipairs(items) do
    table.insert(menu, string.format("%d) %s", i, vim.trim(entry.text)))
  end

  local choice = vim.fn.inputlist(menu)
  if choice >= 1 and choice <= #items then
    jump_to(items[choice])
  end
end

local function find_odin_declarations(input)
  local exact = {}
  local all_decls = {}
  local files = vim.fn.glob(vim.fn.getcwd() .. "/**/*.odin", false, true)

  for _, file in ipairs(files) do
    local lnum = 0

    for line in io.lines(file) do
      lnum = lnum + 1
      local name = line:match("^%s*([%w_]+)%s*::")
      if name then
        local entry = {
          file = file,
          lnum = lnum,
          text = line,
          name = name,
        }

        if name == input then
          table.insert(exact, entry)
        end

        table.insert(all_decls, entry)
      end
    end
  end

  return exact, all_decls
end

local function find_closest_odin_declarations(input, all_decls)
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

  table.sort(closest, function(a, b)
    return a.dist < b.dist
  end)

  return closest
end

local function goto_odin_decl()
  vim.cmd("silent! wall")

  local input = vim.fn.input("goto: ")
  if input == "" then
    return
  end

  local exact, all_decls = find_odin_declarations(input)

  if #exact == 1 then
    jump_to(exact[1])
    return
  end

  if #exact > 1 then
    show_jump_menu(exact)
    return
  end

  local closest = find_closest_odin_declarations(input, all_decls)
  if #closest == 0 then
    vim.api.nvim_echo({ { "No close match found for: " .. input, "WarningMsg" } }, false, {})
    return
  end

  local top = {}
  for i = 1, math.min(5, #closest) do
    top[i] = closest[i].entry
  end

  if #top == 1 then
    jump_to(top[1])
  else
    show_jump_menu(top)
  end
end

local function apply_odin_syntax(force)
  if not force and vim.b.odin_syntax_applied then
    return
  end

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

local function make_case_lines(row)
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
  local expr = line:match("^%s*(.-)%s*=.*$") or line:match("^%s*(.-)%s*,?%s*$")
  local indent = line:match("^(%s*)")

  return {
    "",
    indent .. "case " .. expr .. ": {",
    indent .. "    panic(\"TODO\")",
    indent .. "}",
  }
end

local function odin_case_normal()
  local count = vim.v.count1

  for _ = 1, count do
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local new_lines = make_case_lines(row)
    vim.api.nvim_buf_set_lines(0, row - 1, row, false, new_lines)
    vim.api.nvim_win_set_cursor(0, { row + #new_lines, 0 })
  end
end

local function odin_case_visual()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", true)

  local s = vim.fn.line("'<")
  local e = vim.fn.line("'>")
  local first_line = vim.api.nvim_buf_get_lines(0, s - 1, s, false)[1]
  if not first_line then
    return
  end

  local indent = first_line:match("^(%s*)")
  local replacements = {}

  for row = e, s, -1 do
    replacements[row] = make_case_lines(row)
  end

  for row = e, s, -1 do
    vim.api.nvim_buf_set_lines(0, row - 1, row, false, replacements[row])
  end

  local count = e - s + 1
  local insert_row = s - 1 + count * 4
  vim.api.nvim_buf_set_lines(0, insert_row, insert_row, false, {
    "",
    indent .. "case: panic(\"Invalid.\")",
    "",
  })

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
end

local function setup_odin_buffer()
  vim.bo.filetype = "odin"
  vim.bo.indentexpr = ""
  vim.bo.smartindent = false
  vim.bo.cindent = false

  vim.keymap.set("n", "ca", odin_case_normal, { buffer = true })
  vim.keymap.set("v", "ca", odin_case_visual, { buffer = true })

  apply_odin_syntax(true)
end

apply_config()

vim.api.nvim_create_augroup("OdinErrorClear", { clear = true })

vim.api.nvim_create_user_command("RR", reload_config, {})
vim.api.nvim_create_user_command("RC", edit_config, {})
vim.api.nvim_create_user_command("R", run_r, {})
vim.api.nvim_create_user_command("RReset", reset_r_mode, {})
vim.api.nvim_create_user_command("C", function()
  odin_build(false)
end, {})

vim.keymap.set("n", "\\", goto_odin_decl, { noremap = true })
vim.keymap.set("t", "<C-w>N", "<C-\\><C-n>")
vim.keymap.set("t", "<C-w>h", "<C-\\><C-n><C-w>h")
vim.keymap.set("t", "<C-w>j", "<C-\\><C-n><C-w>j")
vim.keymap.set("t", "<C-w>k", "<C-\\><C-n><C-w>k")
vim.keymap.set("t", "<C-w>l", "<C-\\><C-n><C-w>l")
vim.keymap.set("n", "/", "/\\v", { noremap = true })
vim.keymap.set("n", "?", "?\\v", { noremap = true })

vim.cmd([[cnoreabbrev term split \| terminal]])
vim.cmd([[cnoreabbrev E Explore]])

vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
  callback = function()
    add_match_once("TrailingSpace", [[\s\+$]])
    add_match_once("TodoHighlight", [[\<TODO\>]])
    add_match_once("TmpHighlight", [[\<TMP\(_\w\+\)\?\>]])
  end,
})

vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    vim.o.scrollback = 10000
    vim.cmd("startinsert")
  end,
})

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    if vim.fn.argc() == 0 then
      vim.cmd("Explore")
    end
  end,
})

vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
  callback = function()
    vim.opt_local.cursorline = true
    vim.bo.smartindent = false
    vim.bo.cindent = false
    vim.bo.indentexpr = ""
  end,
})

vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
  callback = function()
    vim.opt_local.cursorline = false
  end,
})

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.odin",
  callback = setup_odin_buffer,
})

vim.api.nvim_create_autocmd("WinEnter", {
  callback = function()
    if vim.bo.filetype == "odin" then
      apply_odin_syntax(false)
    end
  end,
})

vim.api.nvim_create_user_command('TMP', function()
  vim.cmd('split ' .. vim.fn.expand('~/TMP'))
end, {})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "*",
  callback = function()
    vim.opt.formatoptions:remove({ "c", "r", "o" })
  end,
})
