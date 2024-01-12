" Plug 'junegunn/seoul256.vim'
" Plug 'joshdick/onedark.vim'
" Plug 'fatih/molokai'
" Plug 'navarasu/onedark.nvim'
" Plug 'olimorris/onedarkpro.nvim'  
" Plug 'NLKNguyen/papercolor-theme'
" Plug 'dense-analysis/ale'
" Plug 'vim-airline/vim-airline'
" Plug 'vim-airline/vim-airline-themes'
" Plug 'josa42/coc-sh'
" Plug 'kana/vim-textobj-user'
" Plug 'kana/vim-textobj-indent'
" Plug 'kana/vim-textobj-syntax'
" Plug 'kana/vim-textobj-function', { 'for':['c', 'cpp', 'vim', 'java'] }
" Plug 'sgur/vim-textobj-parameter'
" Plug 'voldikss/vim-floaterm'
" Plug 'scrooloose/nerdtree'
" Plug 'preservim/tagbar'
" Plug 'skywind3000/quickmenu.vim'  
" Plug 'voldikss/vim-floaterm' "浮窗
" Plug 'junegunn/vim-easy-align' "轻松对齐
" Plug 'tpope/vim-fireplace', { 'for': 'clojure' }  
" Plug 'rdnetto/YCM-Generator', { 'branch': 'stable' }
" Plug 'nsf/gocode', { 'tag': 'v.20150303', 'rtp': 'vim' }
" Plug 'rakr/vim-one'
" Plug 'nvim-treesitter/nvim-treesitter'
" Plug 'neovim/nvim-lspconfig' "nvim
" Plug 'ray-x/go.nvim'
" Plug 'ray-x/guihua.lua' 
" Plug 'ray-x/aurora'

call plug#begin()
 Plug 'neoclide/coc.nvim', {'branch': 'release'}
 Plug 'fatih/vim-go', { 'do': ':GoUpdateBinaries' }
 Plug 'ludovicchabant/vim-gutentags'
 Plug 'AndrewRadev/splitjoin.vim'
 Plug 'tomasr/molokai'
 Plug 'ctrlpvim/ctrlp.vim'
 Plug 'Yggdroot/LeaderF', { 'do': ':LeaderfInstallCExtension' }
 Plug 'airblade/vim-rooter'
 Plug 'jlanzarotta/bufexplorer'
 Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
 Plug 'junegunn/fzf.vim'
 Plug 'SirVer/ultisnips'
 Plug 'honza/vim-snippets'
 Plug 'autozimu/LanguageClient-neovim', { 'branch': 'next', 'do': 'bash install.sh'}
call plug#end()

"--------------
" vim基本属性配置
"--------------
set nu 
set nowrap
set showmatch 
set number
set cul
set mouse=a
set showmode
set showcmd
set encoding=utf-8  
set t_Co=256
set autoindent
set tabstop=4
set shiftwidth=4
set expandtab
set softtabstop=4
set relativenumber
set linebreak
set scrolloff=5
set sidescrolloff=15
set laststatus=2
set ruler
set showmatch
set hlsearch
set incsearch
set ignorecase
set smartcase
set spell spelllang=en_us
set nobackup
set noswapfile
set undofile
set autochdir
set history=10000
set autoread
set wildmenu
set wildmode=longest:list,full
set backspace=2
set exrc
set confirm      
set fileencodings=utf-8,ucs-bom,shift-jis,gb18030,gbk,gb2312,cp936,utf-16,big5,euc-jp,latin1      
set splitbelow      
set splitright     
set noundofile
set hidden
set shortmess+=c
set updatetime=100
set laststatus=2
set tags=./.tags;,.tags
set fileencoding=utf-8                                             
set termencoding=utf-8                                             
set nocompatible
set smartindent                                                    
set cindent                                                        
set termguicolors
set autowrite
set nospell
set foldmethod=indent
set foldenable              " 开始折叠
set foldmethod=syntax       " 设置语法折叠
set foldcolumn=0            " 设置折叠区域的宽度
setlocal foldlevel=1        " 设置折叠层数为
set foldlevelstart=99       " 打开文件是默认不折叠代码
set updatetime=100

highlight Folded guibg=NONE guifg=NONE
highlight FoldColumn guibg=NONE guifg=NONE
syntax on                                                                                                            
filetype plugin indent on 
let g:netrw_winsize = 25
let g:auto_save = 1
let g:auto_save_events = ["InsertLeave", "TextChanged", "TextChangedI", "CursorHoldI", "CompleteDone"]
let g:rehash256 = 1
let g:molokai_original = 1
colorscheme molokai
nmap <Tab> :bnext<Return>
nmap <S-Tab> :bprev<Return>
nnoremap <space> za
vnoremap <c-y> "+y
nnoremap <c-p> "+p
nnoremap <space> @=((foldclosed(line('.')) < 0) ? 'zc' : 'zo')<CR>

"--------------
" gutentags配置
"--------------
let g:gutentags_project_root = ['.root', '.svn', '.git', '.hg', '.project']
let g:gutentags_ctags_tagfile = '.tags'
let s:vim_tags = expand('~/.cache/tags')
let g:gutentags_cache_dir = s:vim_tags
let g:gutentags_ctags_extra_args = ['--fields=+niazS', '--extra=+q']
let g:gutentags_ctags_extra_args += ['--c++-kinds=+px']
let g:gutentags_ctags_extra_args += ['--c-kinds=+px']
if !isdirectory(s:vim_tags)
   silent! call mkdir(s:vim_tags, 'p')
endif

""--------------
"" vim-go配置
""--------------
let g:go_imports_autosave=0
map <F2> :GoFillStruct<cr>
map <F3> :GoAlternate<cr>
map <F4> :GoTest<cr>
map <F5> :GoDebugContinue<cr>
"map <F9> :GoDebugBreakpoint<cr>
"map <F8> :GoDebugNext<cr>
"map <F7> :GoDebugStep<cr>
"map <S-F8> :GoDebugStepOut<cr>
let g:go_debug_windows = {'vars':'rightbelow 60vnew','stack':'rightbelow 10new'}
let g:airline_theme='onedark'
let g:lightline = {'colorscheme': 'onedark'}
let g:onedark_termcolors=256  
let g:rehash256 = 1
let g:go_auto_type_info = 1
"let g:go_auto_sameids = 1
let g:go_auto_use_cmpfunc = 1
let g:go_list_type = "quickfix"
let g:go_metalinter_enabled = ["vet", "errcheck", "golangci-lint"]
let g:go_metalinter_autosave = 1
let g:go_metalinter_autosave_enabled = ["vet", "errcheck", "golangci-lint"]
let g:go_metalinter_deadline = "10s"
let g:go_metalinter_fast = 1
let g:go_metalinter_linters = ["vet", "errcheck", "golangci-lint"]
let g:go_metalinter_deadline = "5s"
let g:go_fmt_fail_silently = 1
let g:go_def_mode = 'godef'
let g:go_gopls_enabled = 1
let g:go_def_mode='gopls'
let g:go_info_mode='gopls'
let g:go_autodetect_gopath = 1
let g:go_fmt_command = "goimports"
let g:go_decls_includes = "func,type"
let g:LanguageClient_serverCommands = {'go': ['gopls']}
let g:go_list_type = "quickfix"
let g:go_test_timeout = '10s'
"let g:go_fmt_fail_silently = 1 "关闭quickfix
"let g:go_addtags_transform = "camelcase"
let g:go_highlight_types = 1
let g:go_highlight_fields = 1
let g:go_highlight_functions = 1
let g:go_highlight_function_calls = 1
let g:go_highlight_operators = 1
let g:go_highlight_extra_types = 1
let g:go_highlight_build_constraints = 1
let g:go_highlight_generate_tags = 1
function! s:build_go_files()
  let l:file = expand('%')
  if l:file =~# '^\f\+_test\.go$'
    call go#test#Test(0, 1)
  elseif l:file =~# '^\f\+\.go$'
    call go#cmd#Build(0)
  endif
endfunction
autocmd FileType go nmap <leader>b :<C-u>call <SID>build_go_files()<CR>
map <C-n> :cnext<CR>
map <C-m> :cprevious<CR>
autocmd BufWritePre *.go :call LanguageClient#textDocument_formatting_sync()
autocmd BufNewFile,BufRead *.go setlocal noexpandtab tabstop=4 shiftwidth=4 
nnoremap <leader>a :cclose<CR>
autocmd FileType go nmap <leader>b  <Plug>(go-build)
autocmd FileType go nmap <leader>r  <Plug>(go-run)
autocmd FileType go nmap <leader>t  <Plug>(go-test)
autocmd FileType go nmap <Leader>c <Plug>(go-coverage-toggle)
autocmd FileType go nmap <Leader>i <Plug>(go-info)

"--------------
" coc.nvim推荐的配置--------------------
"--------------
set hidden
set nobackup
set nowritebackup
set cmdheight=2
set updatetime=300
set shortmess+=c
if has("nvim-0.5.0") || has("patch-8.1.1564")
  set signcolumn=number
else
  set signcolumn=yes
endif
inoremap <silent><expr> <c-@> coc#refresh()
inoremap <silent><expr> <cr> pumvisible() ? coc#_select_confirm(): "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"
nmap <silent> sn <Plug>(coc-diagnostic-prev)
nmap <silent> sp <Plug>(coc-diagnostic-next)
nmap <silent> gd <Plug>(coc-definition)
nmap <silent> gy <Plug>(coc-type-definition)
nmap <silent> gi <Plug>(coc-implementation)
nmap <silent> gr <Plug>(coc-references)
nnoremap <silent> K :call <SID>show_documentation()<CR>
function! s:show_documentation()
  if (index(['vim','help'], &filetype) >= 0)
    execute 'h '.expand('<cword>')
  elseif (coc#rpc#ready())
    call CocActionAsync('doHover')
  else
    execute '!' . &keywordprg . " " . expand('<cword>')
  endif
endfunction
nmap <leader>rn <Plug>(coc-rename)
xmap <leader>f  <Plug>(coc-format-selected)
nmap <leader>f  <Plug>(coc-format-selected)
augroup mygroup
  autocmd!
  autocmd FileType typescript,json setl formatexpr=CocAction('formatSelected')
  autocmd User CocJumpPlaceholder call CocActionAsync('showSignatureHelp')
augroup end
xmap <leader>a  <Plug>(coc-codeaction-selected)
nmap <leader>a  <Plug>(coc-codeaction-selected)
nmap <leader>ac  <Plug>(coc-codeaction)
nmap <leader>qf  <Plug>(coc-fix-current)
xmap if <Plug>(coc-funcobj-i)
omap if <Plug>(coc-funcobj-i)
xmap af <Plug>(coc-funcobj-a)
omap af <Plug>(coc-funcobj-a)
xmap ic <Plug>(coc-classobj-i)
omap ic <Plug>(coc-classobj-i)
xmap ac <Plug>(coc-classobj-a)
omap ac <Plug>(coc-classobj-a)
nmap <silent> <C-s> <Plug>(coc-range-select)
xmap <silent> <C-s> <Plug>(coc-range-select)
command! -nargs=0 Format :call CocAction('format')
command! -nargs=? Fold :call     CocAction('fold', <f-args>)
command! -nargs=0 OR   :call     CocAction('runCommand', 'editor.action.organizeImport')
nnoremap <silent><nowait> <space>a  :<C-u>CocList diagnostics<cr>


" "--------------
" " crip config
" "--------------
let g:ctrlp_map = '<c-p>'
let g:ctrlp_cmd = 'CtrlP /Users/jim/Workdata/goland/src/jspp'
let g:ctrlp_working_path_mode = 'w'
let g:ctrlp_root_markers = ['pom.xml', '.p4ignore']
let g:ctrlp_user_command = 'find %s -type f'        " MacOSX/Linux
let g:ctrlp_user_command = 'dir %s /-n /b /s /a-d'  " Windows
let g:ctrlp_user_command = ['.git', 'cd %s && git ls-files -co --exclude-standard']
set wildignore+="*/tmp/*,*.so,*.swp,*.zip"
let g:ctrlp_switch_buffer = 'et'
let g:ctrlp_custom_ignore = '\v[\/]\.(git|hg|svn)$'
let g:ctrlp_custom_ignore = {
  \ 'dir':  '\v[\/]\.(git|hg|svn)$',
  \ 'file': '\v\.(exe|so|dll)$',
  \ 'link': 'some_bad_symbolic_links',
  \ }

"--------------
" FZF配置
"--------------
nnoremap <silent><nowait> <space>o :<C-u>FZF --reverse --info=inline --border /Users/jim/Workdata/goland/src/jspp<CR> 
nnoremap <silent><nowait> <space>a :<C-u>Ag<CR> 
nnoremap <silent><nowait> <space>r :<C-u>Rg<CR> 
nnoremap <silent><nowait> <space>g :<C-u>RG<CR> 
command!  -bang -nargs=* Ag   call fzf#vim#ag(<q-args>, fzf#vim#with_preview(), <bang>1)
command!  -bang -nargs=* Rg   call fzf#vim#grep("rg  --ignore-file /Users/jim/.ignore.ag.rg   --column --line-number --no-heading --color=always --smart-case -- ".shellescape(<q-args>), fzf#vim#with_preview(), <bang>1)
command!  -bang -nargs=* RG   call fzf#vim#grep2("rg  --ignore-file /Users/jim/.ignore.ag.rg  --column --line-number --no-heading --color=always --smart-case -- ", <q-args>, fzf#vim#with_preview(), <bang>1)

"--------------
" LeaderF start
"--------------
let mapleader=";" 
let g:Lf_CommandMap = {'<C-K>': ['<Up>'], '<C-J>': ['<Down>']}
let g:Lf_ShowDevIcons = 0
let g:Lf_WorkingDirectoryMode = 'a'
let g:Lf_RootMarkers = ['.workspace_root']
let g:Lf_UseVersionControlTool=0 
let g:Lf_DefaultExternalTool='rg'
let g:Lf_ExternalCommand = 'fd --ignore-file  /Users/jim/.ignore.ag.rg "%s"'
let g:Lf_PreviewInPopup = 0
let g:Lf_WindowHeight = 0.3
let g:Lf_PopupHeight = float2nr(&lines * 0.3)
let g:Lf_CacheDirectory = "/tmp"
let g:Lf_StlColorscheme = 'onedark'
let g:Lf_PopupAutoAdjustHeight = 1
let g:Lf_GtagsAutoGenerate = 1
let g:Lf_GtagsGutentags = 1
let g:Lf_ShortcutF = '<s-space>'
let g:Lf_ShortcutB = '<c-l>'
let g:Lf_PreviewResult = {'Function': 20, 'BufTag': 20 }
let g:Lf_NumberOfCache = 10000
let g:Lf_GtagsAutoGenerate = 1
let g:Lf_GtagsSource = 1
let g:Lf_Gtagsconf = '/usr/local/Cellar/global/6.6.10/share/gtags/gtags.conf'
let g:Lf_Gtagslabel = 'native-pygments'
let g:Lf_ReverseOrder = 0
let g:Lf_DefaultMode = 'NameOnly'
noremap <leader>f :LeaderfSelf<cr>
noremap <leader>fm :LeaderfMru<cr>
noremap <leader>ff :LeaderfFunction<cr>
noremap fb :LeaderfBuffer<cr>
noremap <leader>ft :LeaderfBufTag<cr>
noremap <leader>fl :LeaderfLine<cr>
noremap <leader>fw :LeaderfWindow<cr>
noremap <leader>frr :LeaderfRgRecall<cr>
noremap <leader>fgo :<C-U><C-R>=printf("Leaderf! gtags --recall %s", "")<CR><CR>
noremap <leader>fgn :<C-U><C-R>=printf("Leaderf gtags --next %s", "")<CR><CR>
noremap <leader>fgp :<C-U><C-R>=printf("Leaderf gtags --previous %s", "")<CR><CR>
noremap <Plug>LeaderfRgPrompt2 :<C-U>Leaderf rg --ignore-file /Users/jim/.ignore.ag.rg -e<Space>
nmap <a-space>   <Plug>LeaderfRgPrompt2
nmap <leader>ra  <Plug>LeaderfRgCwordLiteralNoBoundary
nmap <leader>rb  <Plug>LeaderfRgCwordLiteralBoundary
nmap <leader>rc  <Plug>LeaderfRgCwordRegexNoBoundary
nmap <leader>rd  <Plug>LeaderfRgCwordRegexBoundary
nmap <leader>fgd <Plug>LeaderfGtagsDefinition
nmap <leader>fgr <Plug>LeaderfGtagsReference
nmap <leader>fgs <Plug>LeaderfGtagsSymbol
nmap <leader>fgg <Plug>LeaderfGtagsGrep

"--------------
" Rooter start
"--------------
let g:rooter_targets = '/,*.yml,*.yaml,*.go,*.proto'
let g:rooter_patterns = ['.workspace_root']
let g:eleline_slim = 1
let g:onedark_config = {
  \ 'style': 'deep',
  \ 'toggle_style_key': '<leader>ts',
  \ 'ending_tildes': v:true,
  \ 'diagnostics': {
    \ 'darker': v:false,
    \ 'background': v:false,
  \ },
\ } 

""--------------
"" vim-floaterm配置
""-------------- 
"nnoremap   <silent>   <F7>    :FloatermNew --height=0.9 --position=bottomright<CR>
"tnoremap   <silent>   <F7>    <C-\><C-n>:FloatermNew --height=0.9 --position=bottomright<CR>
"nnoremap   <silent>   <F8>    :FloatermPrev<CR>
"tnoremap   <silent>   <F8>    <C-\><C-n>:FloatermPrev<CR>
"nnoremap   <silent>   <F9>    :FloatermNext<CR>
"tnoremap   <silent>   <F9>    <C-\><C-n>:FloatermNext<CR>
"nnoremap   <silent>   <F2>   :FloatermToggle<CR>
"tnoremap   <silent>   <F2>   <C-\><C-n>:FloatermToggle<CR>
"command! Rg FloatermNew --width=0.8 --height=0.8 rg
"nmap <leader>rg :Rg<CR>

