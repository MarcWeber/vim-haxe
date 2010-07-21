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

    autocmd BufRead,BufNewFile *.m,*.as
      \  nnoremap <silent> <buffer> <LocalLeader>p :call HaxeAddClasspath()<Cr>
      \| nnoremap <silent> <buffer> <LocalLeader>l :call HaxeAddLib()<Cr>

    autocmd BufRead,BufNewFile *.hxml setlocal filetype=haxe_hxml

    " This is executed multiple times - don't know how to fix it
    " AddOnThingHandler contains Uniq(..)
    autocmd BufRead,BufEnter vim_view_fun://['haxe#ClassView* call on_thing_handler#AddOnThingHandler('b',funcref#Function('haxe#gfHandler'))
  augroup end
endif

command! -nargs=1 FlexDoc :call haxe#OpenDocFor(<f-args>)
command! -nargs=1 GotoThing :call haxe#GotoThing('',<q-args>)
command! -nargs=1 GotoThingRegex :call haxe#GotoThing('regex', <f-args>)
command! -nargs=1 ParentsOfObject :echo join(haxe#ClassInfo(<f-args>)["hirarchy"]," > ")
command! -nargs=1 -complete=file HaxeSetBuildXML call haxe#SetBuildXml(<q-args>)<cr>

call actions#AddAction('run haxe compiler (hxml)', {'action': funcref#Function('haxe#CompileRHS')})
for target in ["neko","cpp","php","swf"]
  call actions#AddAction('run haxe compiler targeting '.target, {'action': funcref#Function('haxe#CompileRHS', { 'args' : ["target-".target] })})
  call actions#AddAction('run haxe compilation result target '.target, {'action': funcref#Function('haxe#CompileRHS', { 'args' : ["run-".target] })})
endfor

" register completions functions
fun! s:RegisterCompletions()
  let completions =  [
        \ {'description' : 'HAXE complete functions', 'func': 'haxe#CompleteHAXE'},
        \ {'description' : 'HAXE complete classes', 'func': 'haxe#CompleteClassNames'},
        \ ]

  for c in completions
    let c['scope'] = 'haxe'
    let c['completeopt'] = 'preview,menu,menuone'
    call vim_addon_completion#RegisterCompletionFunc(c)
  endfor
endf

call s:RegisterCompletions()
