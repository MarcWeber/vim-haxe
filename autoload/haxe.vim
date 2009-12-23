" functions will be loaded lazily when needed

fun! haxe#CursorPositions()
  let line_till_cursor = substitute(getline('.')[:col('.')],'[^. \t()]*$','','')
  let chars_in_line = strlen(line_till_cursor)
  let bytePos = line2byte(line('.')) + chars_in_line -1 " First, we find our current position in the file
  let haxePos = string(bytePos) " By the way vim works, we must keep the position in a buffer variable.

  " haxePos: byte position 
  " chars_in_line: col in line where completion starts. Example:
  "       name.foo() 
  "            ^ here
  return [haxePos, chars_in_line]
endf

" this function writes the current buffer
" col=1 is first character
" g:haxe_build_hxml should be set to the buildfile so that important
" compilation flags can be extracted.
" You should consider creating one .hxml file for each target..
"
" base: prefix used to filter results
fun! haxe#GetCompletions(line, col, base)

  let bytePos = line2byte(a:line) + a:col -1

  " Start constructing the command for haxe
  " The classname will be based on the current filename
  " On both the classname and the filename we make sure
  " the first letter is uppercased.
  let classname = substitute(expand("%:t:r"),"^.","\\u&","")
  let filename = expand("%:p:h")."/".substitute(expand("%:t"),"^.","\\u&","")
  "let filename = $TEMP."\\".substitute(expand("%:t"),"^.","\\u&","")
  
  write
  if exists('g:haxe_build_hxml')
    let contents = join(readfile(g:haxe_build_hxml), " ")
    " remove -main foo
    let contents = substitute(contents, '-main\s*[^ ]*', '', 'g')
    " remove target.swf
    " let contents = substitute(contents, '[^ ]*\.swf', '', 'g')
    let args_from_hxml = contents
  else
    let args_from_hxml = ""
  endif
  " Construction of the base command line
  let strCmd="haxe --no-output -main " . classname . " ". args_from_hxml . " --display " . '"' . filename . '"' . "@" . bytePos . " -cp " . '"' . expand("%:p:h") . '"'
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
  let g:strCmd = strCmd
  let res=system(strCmd)
  if v:shell_error != 0 "If there was an error calling haxe, we return no matches and inform the user
    if !exists("b:haxeErrorFile")
      let b:haxeErrorFile = tempname()
    endif
    let lstErrors = split(res,"\n")
    call writefile(lstErrors,b:haxeErrorFile)
    execute "cgetfile ".b:haxeErrorFile
    " Errors will be available for view with the quickfix commands
    cope
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
      cope
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
      let dicTmp={'word': element[0], 'menu': element[1] }
      if element[1] =~ "->"
        let dicTmp["word"] .= "("
      endif
    endif
    call add(lstComplete,dicTmp)
  endfor
  call filter(lstComplete,'v:val["word"] =~ '.string('^'.base))
  " add ( if the completion is a function
  return lstComplete " Finally, return the list with completions

endf

" The main omnicompletion function
fun! haxe#Complete(findstart,base)
    if a:findstart
        let [haxePos, chars_in_line] = haxe#CursorPositions()
        let b:haxePos = haxePos
        return chars_in_line
    else
        return haxe#GetCompletions(line('.'), b:haxePos, a:base)
    endif
endfun
