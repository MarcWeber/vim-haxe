" functions will be loaded lazily when needed

fun! haxe#LineTillCursor()
  return getline('.')[:col('.')-2]
endf
fun! haxe#CursorPositions()
  let line_till_completion = substitute(haxe#LineTillCursor(),'[^. \t()]*$','','')
  let chars_in_line = strlen(line_till_completion)

  " haxePos: byte position 
  " chars_in_line: col in line where completion starts. Example:
  "       name.foo() 
  "            ^ here
  return {'line' : line('.'), 'col': chars_in_line }
endf

fun! haxe#TmpDir()
  if !exists('g:vim_haxe_tmp_dir')
    let g:vim_haxe_tmp_dir = fnamemodify(tempname(),':h')
  endif
  return g:vim_haxe_tmp_dir
endf

" this function writes the current buffer
" col=1 is first character
" g:haxe_build_hxml should be set to the buildfile so that important
" compilation flags can be extracted.
" You should consider creating one .hxml file for each target..
"
" base: prefix used to filter results
fun! haxe#GetCompletions(line, col, base)
  let bytePos = string(line2byte(a:line) + a:col -1)

  " Start constructing the command for haxe
  " The classname will be based on the current filename
  " On both the classname and the filename we make sure
  " the first letter is uppercased.
  let classname = substitute(expand("%:t:r"),"^.","\\u&","")

  let tmpDir = haxe#TmpDir()

  " somehowe haxe can't parse the file if trailing ) or such appear
  " Thus truncate the file at the location where completion starts
  " This also means that error locations must be rewritten
  let tmpFilename = tmpDir.'/'.expand('%:t')
  call writefile(getline(1, a:line-1)+[getline('.')[:(a:col-1)]], tmpFilename)
  
  " silently write buffer
  silent! write
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
  let strCmd="haxe --no-output -main " . classname . " " . args_from_hxml. " --display " . '"' . tmpFilename . '"' . "@" . bytePos . " -cp " . '"' . expand("%:p:h") . '" -cp "'.tmpDir.'"'

  try
    " We keep the results from the comand in a variable
    let g:strCmd = strCmd
    let res=system(strCmd)
    call delete(tmpFilename)
    if v:shell_error != 0 "If there was an error calling haxe, we return no matches and inform the user
      if !exists("b:haxeErrorFile")
        let b:haxeErrorFile = tempname()
      endif
      throw "lstErrors"
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
        throw "lstErrors"
      else " If it was a type definition
        call filter(lstXML,'v:val !~ "type>"') " Get rid of the type tags
        call map(lstXML,'haxe#HaxePrepareList(v:val)') " Get rid of the xml in the other lines
        let lstComplete = [] " Initialize our completion list
        for item in lstXML " Create a dictionary for each line, and add them to a list
          let dicTmp={'word': item}
        endfor
        call add(lstComplete,dicTmp)
        return lstComplete " Finally, return the list with completions
      endif
    endif
    call filter(lstXML,'v:val !~ "list>"') " Get rid of the list tags
    call map(lstXML,'haxe#HaxePrepareList(v:val)') " Get rid of the xml in the other lines
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
    call filter(lstComplete,'v:val["word"] =~ '.string('^'.a:base))
    " add ( if the completion is a function
    return lstComplete " Finally, return the list with completions

  catch lstErrors
    let lstErrors = split(substitute(res, tmpFilename, expand('%'),'g'),"\n")
    call writefile(lstErrors,b:haxeErrorFile)
    execute "cgetfile ".b:haxeErrorFile
    " Errors will be available for view with the quickfix commands
    cope | wincmd p
    return []
  endtry

endf

" The main omnicompletion function
fun! haxe#Complete(findstart,base)
    if a:findstart
        let b:haxePos = haxe#CursorPositions()
        return b:haxePos['col']
    else
        return haxe#GetCompletions(b:haxePos['line'], b:haxePos['col'], a:base)
    endif
endfun

" must be called using <c-r>=haxe#DefineLocalVar()<c-r> from an imap mapping
" defines a typed local var
" flash.Lib.current -> var mc:flash.display.MovieClip = flash.Lib.current;
fun! haxe#DefineLocalVar()
  " everything including the last component. But trailing () must be removed
  let lineTC = haxe#LineTillCursor()
  let line_till_completion = substitute(lineTC,'(.*$','','')
  let line_pref = substitute(lineTC,'[^. \t()]*$','','')
  let base = substitute(line_till_completion,'.\{-}\([^ .()]*\)$','\1','')

  let completions = haxe#GetCompletions(line('.'), strlen(line_pref), base)
  " filter again, exact match
  call filter(completions,'v:val["word"] =~ '.string('^'.base.'$'))
  if len(completions) == 1
    let item = completions[0]
    if has_key(item, 'menu')
      let type = substitute(completions[0]['menu'],'.\{-}\([^ ()]*\)$','\1','')
      let name = substitute(type,'<.*>','','g')
      let type = ':'.type
    else
      let type = ''
      let name = base
    endif
    exec 'let name = '.(exists('g:vim_hax_local_name_expr') ? g:vim_hax_local_name_expr : 'tolower(name)')
    let maybeSemicolon = line_pref =~ ';$' ? ';' : ''
    " TODO add suffix 1,2,.. if name is already in use!
    return maybeSemicolon."\<esc>Ivar ".name.type." = \<esc>"
  else
    echoe "1 completion expceted but got: ".len(completions)
    return ''
  endif
endf



" This function gets rid of the XML tags in the completion list.
" There must be a better way, but this works for now.
fun! haxe#HaxePrepareList(v)
    let text = substitute(a:v,"\<i n=\"","","")
    let text = substitute(text,"\"\>\<t\>","*","")
    let text = substitute(text,"\<[^>]*\>","","g")
    let text = substitute(text,"\&gt\;",">","g")
    let text = substitute(text,"\&lt\;","<","g")
    return text
endfun
