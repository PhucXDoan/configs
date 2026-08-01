" dofile(vim.fn.expand("~/Documents/configs/init.lua"))

let g:TARGET=""

" command! R :exec ":! clear && ./cli.py clean && ./cli.py build " . " && ./cli.py flash " . g:TARGET
" command! C :exec ":! clear && ./cli.py clean && ./cli.py build "

command! R :exec ":! clear && ./script.py upload"
command! C :exec ":! clear && ./script.py compile"

command! A :exec ":! clear && ./cli.py clean && ./cli.py build "
command! M :exec ":! clear && ./cli.py clean && ./cli.py build --metapreprocess-only"
command! T :exec ":! clear && ./cli.py test"

if has("win32")
    set shell=pwsh
endif

" Some convenient shortcuts.
exec "command! RC :e " . expand('<sfile>:p')
command! E   :w | Explore
command! TMP :e ~/tmp

set nowrap               " No line wrapping.
set expandtab            " Expand \t into spaces.
set softtabstop=4        " Amount of spaces per tab.
set shiftwidth=4         " Amount of spaces per indent.
set hlsearch             " Highlight search matches.
set incsearch            " Go to the next search match as it is being typed.
set autoindent           " Copy indent from previous line.
set showcmd              " This shows the amount of lines selected.
set ruler                " Show additional information at the bottom.
set laststatus=2         " Show the file name.
set rulerformat=%(%=%l%) " Show only line number of the cursor.
set timeoutlen=0         " Remove the delay after <ESC>.
set nrformats+=alpha     " Allow alphabetical characters to be incremented/decremented.
set scrolloff=4          " Minimal number of screen lines to keep above and below the cursor.
set shortmess-=S         " Show search count message when searching.
set autoread             " Reread a file if it has changed on disk.
set t_Co=256             " Allow 256 colors in terminal.

" Use very-magic mode when searching.
nnoremap / /\v

" Search using the previous selection.
nnoremap L :<c-u>let @/=@"<cr>gvy:let [@/,@"]=[@",@/]<cr>/\V<c-r>=substitute(escape(@/,'/\'),'\n','\\n','g')<cr><cr>

syntax enable         " Switch on syntax highlighting.
colorscheme industry  " Theme.
syntax sync fromstart " Makes region highlighting more reliable.
nohlsearch            " Stop the highlighting for the 'hlsearch' option. This is set automatically due to 'set hlsearch'.

function OnFileType()

    "
    " C.
    "

    if expand('%:e') == 'jai' || expand('%:e') == 'c' || expand('%:e') == 'h' || expand('%:e') == 'meta'
        set syntax=off
        syntax match  Comment                            /\v\/\/.*$/
        syntax region Comment                            start=/\v\/\*/ end=/\v\*\//
        syntax region String  transparent                start=/\v\"/   end=/\v\"/
    endif

    "
    " Python.
    "

    if expand('%:e') == 'py'
        set syntax=off
        syntax match Comment /\v(^|\s)\zs\#.*$/
    endif

    "
    " MetaPreprocessor.
    "

    if expand('%:e') == 'meta'
        set filetype=c
    endif

    if expand('%:e') == 'c' || expand('%:e') == 'h' || expand('%:e') == 'meta' || expand('%:e') == 'ld' || expand('%:e') == 'S'
        syntax match Meta                                                            /\v^\s*(\/\*)?\s*(\#include>.*\n\s*)?(^\s*\/\*\s*\#meta>.*\n\s*)\_.{-}\*\//
        syntax match MetaBody    contained containedin=Meta     contains=ControlFlow /\v^\s*(\/\*)?\s*(\#include>.*\n\s*)?(^\s*\/\*\s*\#meta>.*\n\s*)@<=\s*\_.{-}\*\//
        syntax match MetaComment contained containedin=MetaBody                      /\v(^|\s)\zs\#.*$/
    endif

    if expand('%:e') == 'py'
        syntax match Meta /\v%^(^\s*\#include>.*\n\s*)?#meta>.*\n/
    endif

    "
    " Misc.
    "

    syntax match ExWhitespace /\v\t/   containedin=ALL " Lines containing tabs.
    syntax match ExWhitespace /\v\s+$/ containedin=ALL " Lines ending with whitespace.

    if expand('%:e') == '.ino' ||  expand('%:e') == 'c' ||  expand('%:e') == 'h' || expand('%:e') == 'meta' || expand('%:e') == 'py' || expand('%:e') == 'txt'
        syntax match   ControlFlow     /\v(<return>|<goto>|<bug>)/
        syntax match   WeakControlFlow /\v(<sus>|<panic>)/
        syntax keyword Sorry           sorry
        syntax match   Tmp             containedin=ALL /\v<TMP(_)?\w*>*/
        syntax keyword Todo            containedin=ALL TODO
    endif

    "
    " Coloring.
    "

    highlight CursorLine ctermfg=none ctermbg=none ctermul=yellow cterm=underline

    highlight ExWhitespace    ctermfg=white        ctermbg=red
    highlight Comment         ctermfg=cyan         ctermbg=none
    highlight Meta            ctermfg=lightgreen   ctermbg=none
    highlight MetaBody        ctermfg=lightgreen   ctermbg=none
    highlight MetaComment     ctermfg=darkgreen    ctermbg=none
    highlight ControlFlow     ctermfg=yellow       ctermbg=none
    highlight WeakControlFlow ctermfg=lightred     ctermbg=none
    highlight Search          ctermfg=59           ctermbg=230
    highlight Tmp             ctermfg=black        ctermbg=yellow
    highlight Todo            ctermfg=black        ctermbg=magenta
    highlight Sorry           ctermfg=white        ctermbg=darkred
    highlight String          ctermfg=lightmagenta ctermbg=none
    syntax sync fromstart " Makes region highlighting more reliable.
endfunction

augroup vimrc
    autocmd!
    autocmd VimEnter          * :if !argc() | Explore | endif " Go into Netrw on startup only if no explicit files to be edited were given.
    autocmd BufEnter,WinEnter * :set cursorline   " Enable cursor line...
    autocmd WinLeave          * :set nocursorline " ... and disable it so it's only appearing in the currently active window.
    autocmd BufEnter,FileType * :call OnFileType()
augroup END
