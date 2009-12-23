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

" The main omnicompletion function
fun! HaxeComplete(findstart,base)
    if a:findstart
        let bytePos = line2byte(line('.')) + col('.') - 2 " First, we find our current position in the file
        let b:haxePos = string(bytePos) " By the way vim works, we must keep the position in a buffer variable.
        return bytePos " Useless but vim expects this call to return a number.
    else
        " Start constructing the command for haxe
        " The classname will be based on the current filename
        " On both the classname and the filename we make sure
        " the first letter is uppercased.
        let classname = substitute(expand("%:t:r"),"^.","\\u&","")
        let filename = expand("%:p:h")."/".substitute(expand("%:t"),"^.","\\u&","")
        "let filename = $TEMP."\\".substitute(expand("%:t"),"^.","\\u&","")
        execute "w"
        " Construction of the base command line
        let strCmd="haxe --no-output -main " . classname . " --display " . '"' . filename . '"' . "@" . b:haxePos . " -cp " . '"' . expand("%:p:h") . '"'
        let @" = strCmd
        " If this haxe file uses other classpaths, we check they are declared
        " in the buffer variable haxeClasspath. To add classpaths, call
        " HaxeAddClasspath()
        if exists("b:haxeClasspath")
            if len(b:haxeClasspath) != 0
                for x in b:haxeClasspath
                    let strCmd = strCmd . " -cp " . x
                endfor
            endif
        endif
        " If this haxe file uses libs from haxelib, we check they are declared
        " in the buffer variable haxeLibs. To add libs, call HaxeAddLib()
        if exists("b:haxeLibs")
            if len(b:haxeLibs) != 0
                for x in b:haxeLibs
                    let strCmd = strCmd . " -lib " . x
                endfor
            endif
        endif
        "After checking for both classpaths and libs, whe get the final comand
        "line to pass to a system() call.

        " We keep the results from the comand in a variable
        let res=system(strCmd)
        if v:shell_error != 0 "If there was an error calling haxe, we return no matches and inform the user
            if !exists("b:haxeErrorFile")
                let b:haxeErrorFile = tempname()
            endif
            let lstErrors = split(res,"\n")
            call writefile(lstErrors,b:haxeErrorFile)
            execute "cgetfile ".b:haxeErrorFile
            " Errors will be available for view with the quickfix commands
            echoerr "You have errors in your code, use cl to view them."
            return []
        endif

        let lstXML = split(res,"\n") " We make a list with each line of the xml
        
        if len(lstXML) == 0 " If there were no lines, then we return no matches
            return []
        endif
        if lstXML[0] != '<list>' "If is not a class definition, we check for type definition
			if lstXML[0] != '<type>' " If not a type definition then something went wrong... 
				if !exists("b:haxeErrorFile")
					let b:haxeErrorFile = tempname()
				endif
				let lstErrors = split(res,"\n")
				call writefile(lstErrors,b:haxeErrorFile)
				execute "cgetfile ".b:haxeErrorFile
				" Errors will be available for view with the quickfix commands
				echoerr "You have errors in your code, use cl to view them."
				return [] " For now, let's return no matches
			else " If it was a type definition
				call filter(lstXML,'v:val !~ "type>"') " Get rid of the type tags
				call map(lstXML,'HaxePrepareList(v:val)') " Get rid of the xml in the other lines
				let lstComplete = [] " Initialize our completion list
				for item in lstXML " Create a dictionary for each line, and add them to a list
					let dicTmp={'word': item}
				endfor
				call add(lstComplete,dicTmp)
				return lstComplete " Finally, return the list with completions
			endif
        endif
        call filter(lstXML,'v:val !~ "list>"') " Get rid of the list tags
        call map(lstXML,'HaxePrepareList(v:val)') " Get rid of the xml in the other lines
        let lstComplete = [] " Initialize our completion list
        for item in lstXML " Create a dictionary for each line, and add them to a list
            let element = split(item,"*")
			if len(element) == 1 " Means we only got a package class name
				let dicTmp={'word': element[0]}
			else " Its a method name
				let dicTmp={'word': element[0], 'menu': element[1]}
			endif
            call add(lstComplete,dicTmp)
        endfor
        return lstComplete " Finally, return the list with completions
    endif
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

" Map the haxe filetypes to use HaxeComplete for omnicompletion
autocmd BufNewFile,BufRead *.hx set omnifunc=HaxeComplete
" Map the keys /p and /l to HaxeAddClasspath() and HaxeAddLib() respectively.
" Mapping could be different if you changed your <LocalLeader> key.
autocmd BufNewFile,BufRead *.hx nnoremap <silent> <buffer> <LocalLeader>p :call HaxeAddClasspath()<Cr>
autocmd BufNewFile,BufRead *.hx nnoremap <silent> <buffer> <LocalLeader>l :call HaxeAddLib()<Cr>
" Declaring errorformat to parse the errors that we may encounter during autocomplete.
autocmd BufNewFile,BufRead *.hx setlocal errorformat=
\%f:%l:\ characters\ %\\d%\\+-%c\ %m
" Check for the global variables on load or new haxe file
autocmd BufNewFile,BufRead *.hx call HaxeCheckForGlobals()
