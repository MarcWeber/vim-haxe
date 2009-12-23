""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Name:		        haxeOmnicomplete vim plugin v 1.01
"                   Copyright(c)2008 Carlos Fco. Delgado M.
"
" Description:	    Allows to use the haxe compiler for omnicomplete in vim.
"                   Includes some niceties like being able to jump to errors 
"                   using the quickfix commands after compiler errors during
"                   omnicompletion. For use and installation, please check
"                   README.
"
" Author:	        Carlos Fco. Delgado M <carlos.f.delgado at gmail.com>
"
" Last Change:	    09-Dic-2008 Fixed another problem with paths (thanks
"                   again Laurence), added support for completing namespaces
"					and types in function calls.
"                   see CHANGELOG.
"
"  This program is free software; you can redistribute it and/or modify
"  it under the terms of the GNU General Public License as published by
"  the Free Software Foundation; either version 2 of the License, or
"  (at your option) any later version.
"
"  This program is distributed in the hope that it will be useful,
"  but WITHOUT ANY WARRANTY; without even the implied warranty of
"  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
"  GNU General Public License for more details.
"
"  You should have received a copy of the GNU General Public License
"  along with this program; if not, write to the Free Software
"  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
"
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Enough stuff, show me the code!
" Allows to add a classpath to the comand line used for omnicompletion
fun! HaxeAddClasspath()
    if has("gui_running")
        let cp = inputdialog("Add a classpath: ",'','')
    else
        let cp = input("Add a classpath: ",'','')
    endif
    if cp == ''
        return
    endif
    if !exists("b:haxeClasspath")
        let b:haxeClasspath = []
    endif

    call add(b:haxeClasspath,cp)
endfun

" Allows to add a haxelib to the comand line used for omnicompletion
fun! HaxeAddLib()
    if has("gui_running")
        let cp = inputdialog("Add a haxelib library: ",'','')
    else
        let cp = input("Add a haxelib library: ",'','')
    endif
    if cp == ''
        return
    endif
    if !exists("b:haxeLibs")
        let b:haxeLibs = []
    endif

    call add(b:haxeLibs,cp)
endfun

" This function gets rid of the XML tags in the completion list.
" There must be a better way, but this works for now.
fun! HaxePrepareList(v)
    let text = substitute(a:v,"\<i n=\"","","")
    let text = substitute(text,"\"\>\<t\>","*","")
    let text = substitute(text,"\<[^>]*\>","","g")
    let text = substitute(text,"\&gt\;",">","g")
    let text = substitute(text,"\&lt\;","<","g")
    return text
endfun

" Called on BufRead and BufNew to check for the globals
" Again, there must be a better way, feel free to improve
" and send patch.
fun! HaxeCheckForGlobals()
    if exists("g:globalHaxeClasspath")
        if type(g:globalHaxeClasspath) != type([])
            return
        endif
        let b:haxeClasspath = g:globalHaxeClasspath
    endif
    if exists("g:globalHaxeLibs")
        if type(g:globalHaxeLibs) != type([])
            return
        endif
        let b:haxeLibs = g:globalHaxeLibs
    endif
endfun

if !exists('g:vim_haxe_no_filetype')
  " Map the keys /p and /l to HaxeAddClasspath() and HaxeAddLib() respectively.
  " Mapping could be different if you changed your <LocalLeader> key.
  " set filetype so that the ftplugin/haxe.vim is loaded
  " Declaring errorformat to parse the errors that we may encounter during autocomplete.
  " Check for the global variables on load or new haxe file
  augroup Haxe
    autocmd BufRead,BufNewFile *.m,*.hx setlocal filetype=haxe
      \| nnoremap <silent> <buffer> <LocalLeader>p :call HaxeAddClasspath()<Cr>
      \| nnoremap <silent> <buffer> <LocalLeader>l :call HaxeAddLib()<Cr>
      \| setlocal errorformat=%f:%l:\ characters\ %\\d%\\+-%c\ %m
      \| autocmd BufNewFile,BufRead *.hx call HaxeCheckForGlobals()
  augroup end
endif

