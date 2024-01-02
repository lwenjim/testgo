
"--------------
" vim基本属性配置
"--------------
set nu 
set nowrap
"set cursorline
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
set number       
set confirm      
set mouse=a
set encoding=utf-8 
set fileencodings=utf-8,ucs-bom,shift-jis,gb18030,gbk,gb2312,cp936,utf-16,big5,euc-jp,latin1      
set tabstop=4          	
set shiftwidth=4      	
set expandtab         	
set autoindent        
set showmatch         
set hlsearch          
set incsearch       
set splitbelow      
set splitright     
set noundofile
set nobackup
set noswapfile

set encoding=utf-8
set hidden
set shortmess+=c
set updatetime=100
set laststatus=2

    
vnoremap <c-y> "+y
nnoremap <c-p> "+p

syntax on 

let g:netrw_winsize = 25
let mapleader=";" 

nmap <Tab> :bnext<Return>
nmap <S-Tab> :bprev<Return>




let g:auto_save = 1
let g:auto_save_events = ["InsertLeave", "TextChanged", "TextChangedI", "CursorHoldI", "CompleteDone"]

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








"--------------
" vim-go配置
"--------------
let g:go_imports_autosave=0

map <F2> :GoFillStruct<cr>
map <F3> :GoAlternate<cr>
map <F4> :GoTest<cr>
map <F5> :GoDebugContinue<cr>
map <F9> :GoDebugBreakpoint<cr>
map <F8> :GoDebugNext<cr>
map <F7> :GoDebugStep<cr>
map <S-F8> :GoDebugStepOut<cr>


let g:go_debug_windows = {
      \ 'vars':       'rightbelow 60vnew',
      \ 'stack':      'rightbelow 10new',
\ }
















"--------------
" tagbar配置
"--------------
nnoremap <silent><nowait> <space>t :<C-u>TagbarToggle<CR> 
let g:tagbar_width=25
let g:tagbar_autofocus=1
let g:UltiSnipsExpandTrigger="<C-t>"







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







"--------------
" coc.nvim推荐的配置结束----------------
"--------------
call plug#begin()
  Plug 'ludovicchabant/vim-gutentags'
  Plug 'neoclide/coc.nvim', {'branch': 'release'}
  Plug 'fatih/vim-go', { 'do': ':GoUpdateBinaries' }
  Plug 'jlanzarotta/bufexplorer'
  Plug 'preservim/tagbar'
  Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
  Plug 'junegunn/fzf.vim'
  Plug 'SirVer/ultisnips'
  Plug 'honza/vim-snippets'
  Plug 'junegunn/seoul256.vim'
  Plug 'joshdick/onedark.vim'
  Plug 'Yggdroot/LeaderF', { 'do': ':LeaderfInstallCExtension' }
  Plug 'airblade/vim-rooter'
  Plug 'rakr/vim-one'
  Plug 'NLKNguyen/papercolor-theme'
  Plug 'navarasu/onedark.nvim'
  Plug 'voldikss/vim-floaterm'
call plug#end()




"--------------
" vim-go 推荐的配置结束
"--------------

let g:airline_theme='onedark'
let g:lightline = {'colorscheme': 'onedark'}
let g:onedark_termcolors=256  
let g:rehash256 = 1
let g:go_auto_type_info = 1
"let g:go_auto_sameids = 1
let g:go_auto_use_cmpfunc = 1
let g:go_list_type = "quickfix"

" let g:go_metalinter_enabled = ["vet", "errcheck", "golangci-lint"]
" let g:go_metalinter_autosave = 1
" let g:go_metalinter_autosave_enabled = ["vet", "errcheck", "golangci-lint"]
" let g:go_metalinter_deadline = "10s"
" let g:go_metalinter_fast = 1
" let g:go_metalinter_linters = ["vet", "errcheck", "golangci-lint"]

let g:go_fmt_fail_silently = 1
let g:go_def_mode = 'godef'
let g:go_gopls_enabled = 1
let g:go_autodetect_gopath = 1
let g:go_fmt_command = "goimports"
let g:go_decls_includes = "func,type"
" let g:go_debug=['shell-commands']


"--------------
" crip config
"--------------
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
let g:Lf_StlColorscheme = 'powerline'
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

nmap <a-space> <Plug>LeaderfRgPrompt2
nmap <leader>ra <Plug>LeaderfRgCwordLiteralNoBoundary
nmap <leader>rb <Plug>LeaderfRgCwordLiteralBoundary
nmap <leader>rc <Plug>LeaderfRgCwordRegexNoBoundary
nmap <leader>rd <Plug>LeaderfRgCwordRegexBoundary
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
"--------------
" onedark
"--------------
let g:airline_theme='one'
"colorscheme onedark
"colorscheme papercolor
colorscheme onedark




"--------------
" coc-snippets
"--------------

let g:UltiSnipsExpandTrigger="<tab>"
let g:UltiSnipsJumpForwardTrigger="<c-b>"
let g:UltiSnipsJumpBackwardTrigger="<c-z>"

let g:UltiSnipsEditSplit="vertical"
let g:coc_snippet_next = '<tab>'


set cursorline
hi CursorLine   cterm=NONE ctermbg=NONE ctermfg=NONE guibg=white guifg=white
"set cursorcolumn
"hi CursorColumn cterm=NONE ctermbg=NONE ctermfg=white

hi Comment ctermfg=green guifg=green
hi Search guifg=red guibg=white
hi Identifier ctermfg =blue cterm =none

" ============= vim-floaterm配置=========================
nnoremap   <silent>   <F7>    :FloatermNew --height=0.9 --position=bottomright<CR>
tnoremap   <silent>   <F7>    <C-\><C-n>:FloatermNew --height=0.9 --position=bottomright<CR>
nnoremap   <silent>   <F8>    :FloatermPrev<CR>
tnoremap   <silent>   <F8>    <C-\><C-n>:FloatermPrev<CR>
nnoremap   <silent>   <F9>    :FloatermNext<CR>
tnoremap   <silent>   <F9>    <C-\><C-n>:FloatermNext<CR>
nnoremap   <silent>   <F2>   :FloatermToggle<CR>
tnoremap   <silent>   <F2>   <C-\><C-n>:FloatermToggle<CR>

hi Floaterm guibg=black
hi FloatermBorder guibg=orange guifg=cyan
hi FloatermNC guifg=gray
command! Rg FloatermNew --width=0.8 --height=0.8 rg
nmap <leader>rg :Rg<CR>
" ============ vim-floaterm配置=========================
