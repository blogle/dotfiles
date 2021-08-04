set nocompatible              " be iMproved, required
filetype off                  " required

" Install vim-plug if not found
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
endif

" Run PlugInstall if there are missing plugins
autocmd VimEnter * if len(filter(values(g:plugs), '!isdirectory(v:val.dir)'))
  \| PlugInstall --sync | source $MYVIMRC
\| endif


call plug#begin('~/.vim/plugged')

"Ale
"Plug 'w0rp/ale'
"
Plug 'aklt/plantuml-syntax'

" Semantic Completion
Plug 'zxqfl/tabnine-vim'

"Buffer status bar
Plug 'bling/vim-bufferline'

"Nix Highlighting
Plug 'LnL7/vim-nix'

"HashiCorp hcl
Plug 'git@github.com:jvirtanen/vim-hcl.git'

"Git integration
Plug 'tpope/vim-fugitive'

"CtrlP File Finder
Plug 'kien/ctrlp.vim'

"EasyMotion
Plug 'Lokaltog/vim-easymotion'

"TabCompletion
Plug 'ervandew/supertab'

"Flying with Vim
Plug 'bling/vim-airline'

"Tmuxline
Plug 'edkolev/tmuxline.vim'

"Align
Plug 'vim-scripts/Align'

"Cython Highlighting
Plug 'lambdalisue/vim-cython-syntax'

"Julia Highlighting
Plug 'JuliaEditorSupport/julia-vim'

"Rust Highlighting
Plug 'rust-lang/rust.vim'

" Language Server
Plug 'prabirshrestha/async.vim'
Plug 'prabirshrestha/vim-lsp'

" Brief help
" :PlugList       - lists configured plugins
" :PlugInstall    - installs plugins; append `!` to update or just :PlugUpdate
" :PlugClean      - confirms removal of unused plugins; append `!` to auto-approve removal

call plug#end()

" VIM CONFIG BELOW
" ================

" Auto Reload vimrc
"au BufWritePost .vimrc so ~/.vimrc

" Set line numbers
set number

" Set sensible whitespace rules
set autoindent
set smartindent
set tabstop=4
set shiftwidth=4
set expandtab

" Allow for switching amongst unsaved buffers
set hidden

"Make backspace sane
set backspace=2

"Use system keyboard
"set clipboard=unnamed

"Quick commands
nnoremap ; :

" Enable syntax highlighting and colorscheme
syntax enable
set term=screen-256color
"set background=dark
"colorscheme gruvbox

"Ignore binaries/zi
set wildignore+=*/tmp/*,*.so,*.swp,*.zip     " MacOSX/Linux
set wildignore+=*\\tmp\\*,*.swp,*.zip,*.exe  " Windows

" Highlight search terms
set hlsearch

" Show search matches as you type
set incsearch

" Get rid of the beeping
set noerrorbells visualbell t_vb=
if has('autocmd')
	autocmd GUIEnter * set visualbell t_vb=
endif

" VIM backups are dumb
set nobackup
set noswapfile

" Window navigation
map <C-a> <C-w>h
map <C-e> <C-w>j
map <C-u> <C-w>k
map <C-o> <C-w>l
set splitbelow

map e g<Down>
map o <Right>
map u g<Up>
map a <Left>
noremap h a
noremap H A
noremap j u

" Map Leader key
let mapleader = ","
let maplocalleader = ","

" Buffer Navigation
map <Leader>m <esc>:bprevious<CR>
map <Leader>n <esc>:bnext<CR>

"Toggle Line Numbers
set number
nnoremap <silent><C-l> :set nonumber!<CR>

"Ale
nmap <Leader>e <Plug>(ale_next_wrap)
let g:ale_sign_column_always = 1
let g:ale_open_list = 0

if executable('rls')
    au User lsp_setup call lsp#register_server({
        \ 'name': 'rls',
        \ 'cmd': {server_info->['rustup', 'run', 'nightly', 'rls']},
        \ 'whitelist': ['rust'],
        \ })
endif


if executable('pyls')
    au User lsp_setup call lsp#register_server({
        \ 'name': 'pyls',
        \ 'cmd': {server_info->['pyls']},
        \ 'whitelist': ['python'],
        \ })
endif

let g:lsp_signs_enabled = 1         " enable signs
let g:lsp_diagnostics_echo_cursor = 1 " enable echo under cursor when in normal mode
highlight link LspErrorText GruvboxRedSign " requires gruvbox
highlight clear LspWarningLine

" Get current document diagnostics information
":LspDocumentDiagnostics

" Go to definition
noremap gt <esc>:LspDefinition<CR>

" Show implementation of interface
noremap gi <esc>:LspImplementation<CR>

" Find references
noremap gr <esc>:LspReferences<CR>

" Rename symbol
noremap <F2> :LspRename<CR>

" Format entire document
noremap <leader>f <esc>:LspDocumentFormat<CR>

" Show hover information
noremap <leader>t <esc>:LspHover<CR>

" Format document selection
":LspDocumentRangeFormat

" Show document symbols
":LspDocumentSymbol

" Search/Show workspace symbol
":LspWorkspaceSymbol

"Easy Motion
nmap s <Plug>(easymotion-s)

"CtrlP Config
set grepprg =rg\ --vimgrep
let g:ctrlp_user_command = 'rg %s --files --color=never --glob ""'
let g:ctrlp_use_caching = 0
set wildignore +=*/.git/*,*/tmp/*,*.swp
