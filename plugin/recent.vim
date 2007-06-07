" Vim plugin	Remember a list of recently written files.  Provide commands
"		to open the files in windows or tabs.
" General: {{{1
" File:		recent.vim
" Last Change:	2007 Jun 07
" Version:	12
" Vim Version:	Vim7
" Author:	Andy Wokula <anwoku@yahoo.de>
"
" Credits: {{{1
"   Inspired by vimscript #1228
"   Suggestions by: Ilia N Ternovich
"   See also: #207, #521

" Installation: {{{1
"   put file in plugin folder -- :help add-plugin
"   install the help file -- :help :helptags
"
" TODO {{{1
" see ~\vimfiles\recent-stuff.txt
" }}}

" Script Init Folklore: {{{1
if exists("loaded_recent") || &cp || &im
    finish
endif
let loaded_recent = 1

if v:version < 700
    " sorry, Vim7 required
    echomsg "recent: You need at least Vim7"
    finish
endif

let s:save_cpo = &cpo
set cpo&vim

" Variables 1: {{{1
let s:WinModes = ["thiswin", "newwin", "newtab"]
let s:ListChanged = 0

" Check User Options, Build Menu: {{{1
" global variables not to be changed later are turned into script variables

if !exists("g:RecentFullname")
    " per default use <first-entry-of-runtimepath>.'/recent_files'
    let s:RecentName = "recent_files"
    let s:RecentFullname = matchstr(&rtp, '[^,]*').'/'.s:RecentName
else
    let s:RecentFullname = g:RecentFullname
    let s:RecentName = fnamemodify(s:RecentFullname, ":t")
    unlet g:RecentFullname
endif
" finish script if cannot write to recent_files
if filereadable(s:RecentFullname)
	    \ ? !filewritable(s:RecentFullname)
	    \ : writefile([], s:RecentFullname) < 0
    echoerr "s:RecentFullname='".s:RecentFullname."' not writeable, abort."
    finish
    " writefile may also throw a vim exception (das ist Jacke wie Hose;)
endif
if !exists("g:RecentStartup")
    let g:RecentStartup = 1
endif
if !exists("g:RecentTypes")
    let g:RecentTypes = ""
endif
if !exists("g:RecentHlGroups")
    let g:RecentHlGroups = ""
endif
if !exists("g:RecentIgnore")
    let g:RecentIgnore = '*.svn,*.cvs,*.bak,*~'
endif
if !exists("g:RecentWinmode")
    let g:RecentWinmode = "thiswin"
else
    if index(s:WinModes, g:RecentWinmode) < 0
	echoerr 'Warning: g:RecentWinmode must be in' string(s:WinModes)
		    \.", revert to 'thiswin'"
	let g:RecentWinmode = "thiswin"
    endif
endif
if !exists("g:RecentReuse")
    let g:RecentReuse = 0
endif
if has("menu") && !(exists("g:RecentMenu") && g:RecentMenu == "")
    if !exists("g:RecentMenu")
	let g:RecentMenu = "Plugin.&Recent."
    endif
    " no shortcut for Plugin, because &Plugin and Plug&in are different
    " menus
    exe 'an' g:RecentMenu.':R&ecent :Recent<cr>'
    exe 'an' g:RecentMenu.':Re&memberFile :RememberFile<cr>'
    exe 'an' g:RecentMenu.'&Winmode.thi&swin :let RecentWinmode="thiswin"<cr>'
    exe 'an' g:RecentMenu.'&Winmode.new&win  :let RecentWinmode="newwin"<cr>'
    exe 'an' g:RecentMenu.'&Winmode.new&tab  :let RecentWinmode="newtab"<cr>'
    exe 'an' g:RecentMenu.'&Reuse.&on :let RecentReuse=1<cr>'
    exe 'an' g:RecentMenu.'&Reuse.o&ff :let RecentReuse=0<cr>'
    exe 'an' g:RecentMenu.'&Layout.&QuickView :Recent\|bot vnew\|let RecentWinmode="thiswin"\|let RecentReuse=1\|Recent<cr>'
    exe 'an' g:RecentMenu.'&Layout.&Tabpages :let RecentWinmode="newtab"\|let RecentReuse=0\|Recent<cr>'
    unlet g:RecentMenu
endif

" Autocommands: (also check Startup cond.) {{{1
augroup Recentfiles
    au!
    " set options when reading the file list:
    exec "au BufRead" s:RecentName "call s:RecentFtplugin()"
    exec "au BufNewFile,BufRead" g:RecentIgnore "let b:RecentIgn = 1"
    " add file to the list, if it is written:
    au BufWritePost * call s:RecentfilesAdd(expand("<afile>:p"))
augroup End
unlet g:RecentIgnore

" Prepare For Startup:
if g:RecentStartup
    " starting without arguments loads the list of recent files
    if argc()==0 && filereadable(s:RecentFullname)
	" not now, wait until VimEnter:
	augroup Recentfiles
	    " take care for  vim -S Session.vim
	    au VimEnter *	if bufname("")==""
	    au VimEnter * nested    Recent
	    au VimEnter *	endif
	    au VimEnter *	au! Recentfiles VimEnter *
	augroup End
    endif
endif
unlet g:RecentStartup

" Variables 2: commands used together with g:RecentWinmode {{{1
" edit file:
let s:EditCmd = {"thiswin" : "edit", "newwin" : "new", "newtab" : "999tabedit"
	    \, "thiswinlis" : "edit", "newwinlis" : "top new", "newtablis": "0tabedit"
	    \, "thiswinmod" : "split", "newwinmod" : "top new", "newtabmod" : "0tabedit"}
" goto buffer:
let s:BufCmd = {"thiswin" : "buf", "newwin" : "sbuf", "newtab" : "999tab sbuf"
	    \, "thiswinlis" : "buf", "newwinlis" : "top sbuf", "newtablis" : "0tab sbuf"
	    \, "thiswinmod" : "sbuf", "newwinmod" : "top sbuf", "newtabmod" : "0tab sbuf"}
" line 1/3: open a file from recent_files (with <Enter>, gf, etc.)
" line 2/3: open recent_files, if can reuse current win
" line 3/3: open recent_files, if current buffer modified

" RecentFtplugin: set options for the recent_files buffer {{{1
" (after BufRead)
function s:RecentFtplugin()
    no <buffer><silent> gf :Recentgf thiswin<cr>
    no <buffer><silent> <c-w>f :Recentgf newwin<cr>
    no <buffer><silent> <c-w>gf :Recentgf newtab<cr>
    no <buffer><silent> <cr> :Recentgf<cr>
    if has("mouse")
	map <buffer> <2-leftmouse> <cr>
    endif
    command! -buffer -bar -nargs=? Recentgf call s:Recentgf(<q-args>)

    setl number nowrap
    setl noswapfile nobuflisted autoread

    call s:RecentSyntax()
    let b:RecentIgn = 1
endfunction

" RecentSyntax: Syntax settings for recent_files (after BufRead) {{{1
" could be "out-sourced"
function s:RecentSyntax()
    if !exists("g:syntax_on")
	return
    endif
    syn clear
    let hlgroups = split(g:RecentHlGroups, ",")
    let hlglen = len(hlgroups)
    if !hlglen|return|endif
    let ftgroups = split(g:RecentTypes, ",")
    let i = 0
    for ftg in ftgroups
	if ftg==""|cont|endif
	let gn = "recentGroup".i
	let pat = escape(ftgroups[i], '|')
	exec "syn match" gn '/^\V\.\*\%('.pat.'\)\$/ display'
	exec "hi link" gn hlgroups[i%hlglen]
	let i+=1
    endfor
endfunction

" GetTabWin: return [number of tabpage, number of win in tabpage] {{{1
" for an existing buffer (first found)
" (in fact not needed because of 'switchbuf')
function s:GetTabWin(bufnr)
    " there is no direct mapping, we have to search through the tabpages
    let tabpcount = tabpagenr("$")  " first tabpage has no 1
    let tabnr = 1
    while tabnr <= tabpcount
	let bufwnr = index(tabpagebuflist(tabnr), a:bufnr)
	if bufwnr >= 0
	    return [tabnr, bufwnr+1]
	endif
	let tabnr += 1
    endwhile
    return [-1, -1]
endfunction

" Reuse: return Winmode depending on g:RecentReuse {{{1
" side effect: first go to tabpage or alternate window
" (used by s:Visit - open a filename from recent_files)
function s:Reuse(winmode)
    if a:winmode == "newtab" || !g:RecentReuse
	" Winmode "newtab" or no reuse: keep it
	return a:winmode
    endif
    " Winmodes "thiswin", "newwin" together with "Reuse Tabpage: on"
    exec "tabnext" s:lasttab
    " if tabpage closed, current tab reused (contains recent_files)
    let winmode = a:winmode
    if winnr("#") && fnamemodify(bufname(""),":t") == s:RecentName 
	wincmd p
    endif
    let inuse = &mod || &bt!='' || &pvw
    if inuse || winnr("#")==winnr()
	" if reuse of window is bad idea, create new window
	let winmode = "newwin"
    elseif !inuse && bufname("")==""
	" always reuse window of unnamed and unmodified buffer
	let winmode = "thiswin"
    endif
    return winmode  " 'thiswin' or 'newwin'
endfunction

" Visit: edit filename or reuse buffer and tabpage/window of filename {{{1
" (if possible);
" if cannot reuse window, reuse window of recent_files = current window
function s:Visit(filename, winmode)
    " filename: must be full qualified file name
    " winmode: "", "thiswin", "newwin" or "newtab"
    let winmode = (a:winmode=="" ? g:RecentWinmode : a:winmode)
    let bnum = bufnr(a:filename."$")
    " Note: includes unlisted and unloaded buffers (survives :bd for
    " example)
    if bnum > 0
	" a:filename has a buffer (maybe not shown in any tab)
	let tabwin = s:GetTabWin(bnum)
	if tabwin[0] > 0
	    " it is shown in a tab, go there:
	    exec "tabnext" tabwin[0]
	    exec tabwin[1] "wincmd w"
	else
	    " goto buffer, new window needed; thiswin: reuse current window
	    " (should work, because recent_files is autowritten)
	    exec s:BufCmd[s:Reuse(winmode)] bnum
	    setlocal buflisted
	endif
    elseif filereadable(a:filename)
	" :edit without a check edits new file (not wanted)
	" edit file, new window needed
	" maybe TODO: check if key is correct
	exec s:EditCmd[s:Reuse(winmode)] a:filename
	if line("'\"") > 0 && line("'\"") <= line("$")
	    " :h last-position-jump
	    normal! g'"
	endif
	let bnum = bufnr(a:filename."$")
    else
	" cannot read file, throw exception (a clean way to do that?)
	throw ":E447:"
    endif
    " w:RecentLastWrittenBuffer(Number)InThisWindow / Window last written
    let w:RecentWlw = bnum
endfunction

" VisitList: edit recent_files, reuse buffer and tab+window if possible {{{1
" split window if necessary
function s:VisitList() abort
    let s:lasttab = tabpagenr()
    let inuse = &modified || &buftype!='' || &previewwindow
    let mod = inuse ? "mod" : "lis"
    " nofile check: if current buffer has no name and is not modified, use
    " its window:
    let nofile = !inuse && bufname("")==""
    let bnum = bufnr(s:RecentFullname."$")
    if bnum > 0
	" buffer for recent_files exists
	let tabwin = s:GetTabWin(bnum)
	if tabwin[0] > 0
	    " recent_files is shown in a tab, go there
	    exec "tabnext" tabwin[0]
	    exec tabwin[1] "wincmd w"
	else
	    " goto buffer, new window needed
	    exec (nofile ? "buf" : s:BufCmd[g:RecentWinmode.mod]) bnum
	endif
	if s:ListChanged
	    " if a file was written (-> recent_files changed with
	    " writefile(), Vim doesn't notice?), reload explicitly; silently
	    " discard manual changes
	    edit!
	    let s:ListChanged = 0
	endif
    else
	exec (nofile ? "edit" : s:EditCmd[g:RecentWinmode.mod]) s:RecentFullname
	" (do not always re-check if recent_files exists)
    endif
endfunction

" Recentgf: from recent_files buffer: open file under cursor {{{1
function <sid>Recentgf(winmode)
    " winmode: "", "thiswin", "newwin" or "newtab"
    noauto update	    " auto write recent_files
    " filename under cursor, trim whitespace (FIXME):
    let filename = substitute(getline("."), '^\s*\|\s*$','','g')
    " make filename full qualified:
    let filename = fnamemodify(filename, ":p")
    try
	call s:Visit(filename, a:winmode)
    catch /:E447:/
	" can't find file "..." in path
	let canwrite = filewritable(s:RecentFullname)
	if canwrite
	    del		" file under cursor, can be undone
	    noauto upd	" update: no-change possible if recent_files empty
	else
	    echo "Cannot write to" s:RecentFullname .", entry kept"
	endif
    catch /:E325:/
	" swap file found, do nothing
    endtry
endfunction

" RecentfilesAdd: BufWritePost *: add filename to recent_files {{{1
function s:RecentfilesAdd(filename)
    " filename: full qualified name
    " update recent_files (only) the first time the file in current window
    " is written
    let bnum = bufnr(a:filename."$")
    if exists("w:RecentWlw") && bnum == w:RecentWlw
	return
    endif
    " do not add recent_files and files with suffixes to be ignored:
    if exists("b:RecentIgn")
	return
    endif
    let filename = fnamemodify(a:filename, ":~")
    let rfname = s:RecentFullname
    silent! let rflist = readfile(rfname)
    let li = index(rflist, filename)
    if li < 0
	" file not in list
	call add(rflist, filename)
	" call insert(rflist, filename)
	call writefile(rflist, rfname)
	" next time, :edit! recent_files
	let s:ListChanged = 1
    endif
    let w:RecentWlw = bnum
endfunction

" AddFile: manually add current file to recent_files {{{1
function s:AddFile() abort
    if bufname("")=="" || exists("b:RecentIgn")
	" do not open file list, if buffer has no filename or if filename is
	" to be ignored (e.g. recent_files)
	return
    endif
    " exact format of filenames used in recent_files
    let filename = fnamemodify(bufname(""), ":p:~")
    " open file list (!)
    Recent
    " add filename, only if not there
    " Note: filename must be followed by white space or EOL
    " (to skip partial matches)
    if !search('\V'.escape(filename, '\').'\%(\s\|\$\)')
	call append("$", filename)
	$
	" call append(0, filename)
	" 1
	write
	" added 'abort' to VisitList() and AddFile():
	" if :Recent fails (unlikely), then never :write
    endif
    " ... always jump to entry
endfunction

" CycleWinmodes: cycle through the Winmodes for :Recent and Enter {{{1
function s:CycleWinmodes()
    let wmi = (1+index(s:WinModes,g:RecentWinmode))%len(s:WinModes)
    let g:RecentWinmode = s:WinModes[wmi]
    echo "Winmode:" g:RecentWinmode
endfunction

" ToggleReuse: toggle RecentReuse {{{1
function s:ToggleReuse()
    let g:RecentReuse = (g:RecentReuse ? 0 : 1)
    echo "Reuse last accessed tabpage or window:" g:RecentReuse ? "on" : "off"
endfunction

" RecentVisit: s:Visit wrapper for the ftplugin {{{1
function RecentVisit(filename, winmode)
    call s:Visit(a:filename, a:winmode)
endfunction

" Commands: the 4 Recent* commands {{{1
command -bar Recent call s:VisitList()
command -bar RememberFile call s:AddFile()
command -bar RecentWinmode call s:CycleWinmodes()
command -bar RecentReuse call s:ToggleReuse()

" Cleanup and Modeline: {{{1
let &cpo = s:save_cpo

" vim:set ts=8 fdm=marker fdc=2:
