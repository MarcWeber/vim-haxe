" functions will be loaded lazily when needed
exec scriptmanager#DefineAndBind('s:c','g:vim_haxe', '{}')

let s:c['f_as_files'] = get(s:c, 'f_as_files', funcref#Function('haxe#ASFiles'))
let s:c['source_directories'] = get(s:c, 'source_directories', [])
let s:c['flash_develop_checkout'] = get(s:c, 'flash_develop_checkout', '')
let s:c['local_name_expr'] = get(s:c, 'local_name_expr', 'tlib#input#List("s","select local name", names)')
let s:c['browser'] = get(s:c, 'browser', 'Browse %URL%')

fun! haxe#LineTillCursor()
  return getline('.')[:col('.')-2]
endf
fun! haxe#CursorPositions()
  let line_till_completion = substitute(haxe#LineTillCursor(),'[^.: \t()]*$','','')
  let chars_in_line = strlen(line_till_completion)

  " haxePos: byte position 
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

" HAXE executable completion function {{{1

" completes using haxe compiler
"
" this function writes the current buffer
" col=1 is first character
" g:haxe_build_hxml should be set to the buildfile so that important
" compilation flags can be extracted.
" You should consider creating one .hxml file for each target..
"
" base: prefix used to filter results
fun! haxe#CompleteHAXEFun(line, col, base)
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
  let g:tmpFilename = tmpFilename

  let linesTillC = getline(1, a:line-1)+[getline('.')[:(a:col-1)]]
  " hacky: remove package name. This way the file doesn't have to be put into
  " subdirectories
  let lines = map(linesTillC, 'v:val =~ '.string('^package\s\+').' ? "" : v:val')
  call writefile( lines
        \ , tmpFilename)

  let bytePos = len(join(lines,"\n"))
  
  " Construction of the base command line
  let d = haxe#BuildHXML()
  let strCmd="haxe --no-output -main " . classname . " " . d['ExtraCompletArgs']. " --display " . '"' . tmpFilename . '"' . "@" . bytePos . " -cp " . '"' . expand("%:p:h") . '" -cp "'.tmpDir.'"'

  try
    let dolstErrors = 0

    " We keep the results from the comand in a variable
    let g:strCmd = strCmd
    let res=system(strCmd.' 2>&1')

    let g:res = res
    "call delete(tmpFilename)
    if v:shell_error != 0
      " HaXe still returns completions. However there may be errors
      " So do both: show errors and completions
      let dolstErrors =1
    endif

    let lstXML = split(res,"\n") " We make a list with each line of the xml

    " strip error lines
    let tagLine = 0
    while tagLine < len(lstXML) && lstXML[tagLine] !~ '^<list'
      let tagLine += 1
    endw
    let lstXML = lstXML[(tagLine):]
    if tagLine > 0
      let dolstErrors = 1
    endif

    if len(lstXML) == 0
      let lstComplete = []
    elseif lstXML[0] != '<list>' "If is not a class definition, we check for type definition
      if lstXML[0] != '<type>' " If not a type definition then something went wrong... 
        let dolstErrors = 1
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
        if element[1] == "Void -> Void"
          " function does not expect arguments
          let dicTmp["word"] .= "()"
        elseif element[1] =~ "->"
          let dicTmp["word"] .= "("
        endif
      endif
      call add(lstComplete,dicTmp)
    endfor
  catch lstErrors
    let dolstErrors = 1
  endtry

  if dolstErrors
    let lstErrors = split(substitute(res, tmpFilename, expand('%'),'g'),"\n")
    if !exists("s:haxeErrorFile")
      let s:haxeErrorFile = tempname()
    endif
    call writefile(lstErrors,s:haxeErrorFile)
    execute "cgetfile ".s:haxeErrorFile
    " Errors will be available for view with the quickfix commands
    cope | wincmd p
  endif

  call filter(lstComplete,'v:val["word"] =~ '.string('^'.a:base))
  return lstComplete
endf

" completes classnames
fun! haxe#CompleteClassNamesFun(line, col, base)
  let lstComplete = []
  if empty(lstComplete)
    " add classes from packages
    for d in funcref#Call(s:c['f_as_files'])
      for file in d['files']
        if file =~ '\.as$'
          " parsing files can be slow (because vim regex is slow) so cache result
          let scanned = cached_file_contents#CachedFileContents(file,
            \ s:c['f_scan_as'], d['cachable'])
          if has_key(scanned,'class')
            call add(lstComplete, {'word': scanned['class'], 'menu': 'class in '.get(scanned,'package','')})
          endif
        endif
      endfor
    endfor
  endif
  call filter(lstComplete,'v:val["word"] =~ '.string('^'.a:base))
  return lstComplete
endf

" completion helper function calling completion functions {{{1
" calls completion functions
fun! haxe#CompleteHelper(findstart, base, funs)
  if a:findstart
    let b:haxePos = haxe#CursorPositions()
    return b:haxePos['col']
  else
    let result = []
    for f in a:funs
      call extend(result, call(function('haxe#'.f),[b:haxePos['line'], b:haxePos['col'], a:base]))
    endfor
    return result
  endif
endf

" completion interface: use these functions {{{1

" complete using haxe executable
fun! haxe#CompleteHAXE(findstart, base)
  return haxe#CompleteHelper(a:findstart, a:base, ["CompleteHAXEFun"])
endfun

" complete classnames (may be slow)
fun! haxe#CompleteClassNames(findstart, base)
  return haxe#CompleteHelper(a:findstart, a:base, ["CompleteClassNamesFun"])
endfun

" complete both
fun! haxe#CompleteAll(findstart, base)
  return haxe#CompleteHelper(a:findstart, a:base, ["CompleteHAXEFun", "CompleteClassNamesFun"])
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

  let completions = haxe#CompleteHAXEFun(line('.'), strlen(line_pref), base)
  " filter again, exact match
  call filter(completions,'v:val["word"] =~ '.string('^'.base.'$'))
  if len(completions) == 1
    let item = completions[0]
    let maybeSemicolon = line_pref =~ '$' ? ';' : ';'

    let names = [base]
    let type = ''

    if has_key(item, 'menu')
      let type = substitute(completions[0]['menu'],'.\{-}\([^ ()]*\)$','\1','')
      call add(names, substitute(type,'\%(\..*\)\?\%(<.*>\)\?','','g'))
      let type = ':'.type
    endif
    call haxe#AddCamelCaseNames(names)

    let delVar = ""
    let existing_var = matchlist(lineTC, 'var \([^.: \t]*\)\([^ \t]*\)\s*=\s*')
    if empty(existing_var)
      " this.foo -> var foo
      let existing_var = matchlist(lineTC, 'this\.\([^.: \t]*\)\([^ \t]*\)\s*=\s*')
    endif

    if !empty(existing_var)
      " remove existing var name:type .. =
      let name = existing_var[1]
      let delVar = repeat("\<del>", len(existing_var[0]))
    else
      exec 'let name = '.s:c['local_name_expr']
    endif

    " TODO add suffix 1,2,.. if name is already in use!
    return maybeSemicolon."\<esc>Ivar ".name.type." = ".delVar."\<esc>"
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

fun! haxe#HXMLFilesCompletion(ArgLead, CmdLine, CursorPos)
  return filter(split(glob("*.hxml"), "\n"),'v:val =~'.string(a:ArgLead))
endf

fun! haxe#BuildHXMLPath()
  if !exists('g:haxe_build_hxml')
    let g:haxe_build_hxml=input('specify your build.hxml file. It should contain one haxe invokation only: ','','customlist,haxe#HXMLFilesCompletion')
    call haxe#HXMLChanged()
  endif
  return g:haxe_build_hxml
endf



" extract flash version from build.hxml
let s:c['f_scan_hxml'] = get(s:c, 'f_scan_hxml', {'func': funcref#Function('haxe#ParseHXML'), 'version' : 3} )
fun! haxe#ParseHXML(filename)
  let d = {}
  let contents = join(readfile(a:filename), " ")
  " remove -main foo
  let contents = substitute(contents, '-main\s*[^ ]*', '', 'g')
  " remove target.swf
  " let contents = substitute(contents, '[^ ]*\.swf', '', 'g')
  let args_from_hxml = contents

  let d['ExtraCompletArgs'] = args_from_hxml

  if contents =~ '-swf9'
    let d['flash_target_version'] = 9
  endif

  let flashTargetVersion = matchstr(args_from_hxml, '-swf-version\s\+\zs[0-9.]\+\ze')
  if flashTargetVersion != ''
    let d['flash_target_version'] = flashTargetVersion
  endif

  return d
endf

" cached version of current build.hxml file
fun! haxe#BuildHXML()
  return cached_file_contents#CachedFileContents(
    \ haxe#BuildHXMLPath(),
    \ s:c['f_scan_hxml'] )
endf

" as files which are searched for imports etc
" add custom directories to g:vim_haxe['source_directories']
" returns [ { 'dir' : 'directory', 'cachable' : 0 /1 } ]
fun! haxe#ASFiles()
  let files = []

  let fdc = s:c['flash_develop_checkout']

  if fdc != ''
    let tv = get(haxe#BuildHXML(),'flash_target_version', 10)
    if tv == 9
      call add(files, { 'cachable': 1, 'files': glob#Glob(fdc.'/'.'FD3/FlashDevelop/Bin/Debug/Library/AS3/intrinsic/FP9/**/*.as', {'cachable':1})})
    elseif tv == 10
      call add(files, { 'cachable': 1, 'files': glob#Glob(fdc.'/'.'FD3/FlashDevelop/Bin/Debug/Library/AS3/intrinsic/FP10/**/*.as', {'cachable':1})})
    endif
  else
    echoe "consider checking out flashdevelop and setting let g:vim_haxe['flash_develop_checkout'] = 'path_to_checkout'"
  endif

  for d in s:c['source_directories']
    call add(files, { 'cachable' : get(d, 'cachable', 0), 'files': glob#Glob(d['dir'].'/**/*.as')})
    call add(files, { 'cachable' : get(d, 'cachable', 0), 'files': glob#Glob(d['dir'].'/**/*.hx')})
  endfor
  call add(files, { 'cachable' : 0, 'files': split(glob('./**/*.as'),"\n")})
  call add(files, { 'cachable' : 0, 'files': split(glob('./**/*.hx'),"\n")})

  return files
endf

fun! haxe#ScannedFiles()
  let list = []
  for d in funcref#Call(s:c['f_as_files'])
    for file in d['files']
      let scanned = cached_file_contents#CachedFileContents(file, s:c['f_scan_as'], 
        \ d['cachable'])
      call add(list, {'file': file, 'scanned': scanned })
    endfor
  endfor
  return list
endfun

fun! haxe#FindImportFromQuickFix()
  let class = matchstr(getline('.'), 'Class not found : \zs.*\|Unknown identifier : \zs.*\|The definition of base class \zs[^ ]*\ze was not found')

  let solutions = []

  " add classes from packages
  for d in funcref#Call(s:c['f_as_files'])
    for file in d['files']
      if file =~ '\.as$'
        " parsing files can be slow (because vim regex is slow) so cache result
        let scanned = cached_file_contents#CachedFileContents(file,
          \ s:c['f_scan_as'], d['cachable'])
        if (  (has_key(scanned,'class') && scanned['class'] == class)
          \  || (has_key(scanned,'interface') && scanned['interface'] == class)
          \ ) && has_key(scanned,'package')
          call add(solutions, scanned['package'].'.'.class)
        endif
      endif
    endfor
  endfor
  if matchstr(getline('.'),'[^|]*\.\zs[^|]*') == 'as'
    for idx in range(len(solutions)-1,0,-1)
      call insert(solutions, substitute(solutions[idx],'\.[^.]*$', '.*',''), idx)
    endfor
  endif
  let solutions = tlib#list#Uniq(solutions)
  if empty(solutions)
    echoe "not found: '".class.'"'
    return
  elseif len(solutions) > 1
    let solution = tlib#input#List("s",'choose import', solutions)
  else
    let solution = solutions[0]
  endif
  exec "normal \<cr>G"

  let line = search('^\s*import\s*'.solution,'cwb')
  if line != 0
    wincmd p
    echo "class is imported at line :".line." - nothing to be done"
    return
  endif

  if search('^\s*import','cwb') == 0
    " no import found, add above (first line)
    let a = "ggO"
  else
    " one import found, add below
    let a = "o"
  endif
  exec "normal ".a."import ".solution.";\<esc>"
  wincmd p
  silent! cnext
endf

fun! haxe#AddCamelCaseNames(list)
  for i in copy(a:list)
    let upper = substitute(i,'\U','','g')
    if len(upper) > 2
      call add(a:list, tolower(upper))
    endif
  endfor
endf

" name is regex
" optional arg: "function\|interface\|class" list functions, classes and interfaces only
fun! haxe#ThingByRegex(name, ...)
  let type = a:0 > 0 ? a:1 : ""

  let list = []

  let findPackage = "package" =~ type
  let findClass = "class" =~ type
  let findInterface = "interface" =~ type
  let findFunctions = "function" =~ type
  let findConsts = "consts" =~ type
  let matchvval = 'v:val =~'.string(a:name)
  let is_regex = a:name =~ '[*\.]'

  for i in haxe#ScannedFiles()
    let f = i['file']
    let s = i['scanned']
    if findPackage && has_key(s,'package') && s['package'] =~ a:name
      call add(list, {'d': i, 'what':s['package'].' :package', 'file':f})
    endif
    if findClass && has_key(s,'class') && s['class'] =~ a:name
      call add(list, {'d': i, 'what':s['class'].' :class', 'line': s['class_line'], 'file':f})
    endif
    if findInterface && has_key(s,'interface') && s['interface'] =~ a:name
      call add(list, {'d': i, 'what':s['interface'].' :interface', 'line': s['interface_line'], 'file':f})
    endif
    if findFunctions
      let functions = s['functions']
      for k in filter(keys(functions),matchvval)
        let v = functions[k]
        call add(list, {'d': i, 'what':k.' :f ', 'line':v, 'file':f})
      endfor
    endif
    if findConsts
      let consts = s['consts']
      for k in filter(keys(consts), matchvval)
        if k !~ a:name | continue | endif
        let v = consts[k]
        call add(list, {'d': i, 'what':k.' :const '.get(v,'type','-'), 'line':get(v,'line',0), 'file':f})
      endfor
    endif
  endfor

  return list
endf

" duplicating code for performance reason :-(
fun! haxe#ThingByString(name, ...)
  let type = a:0 > 0 ? a:1 : ""

  let list = []

  let findPackage = "package" =~ type
  let findClass = "class" =~ type
  let findInterface = "interface" =~ type
  let findFunctions = "function" =~ type
  let findConsts = "consts" =~ type
  let matchvval = 'v:val =='.string(a:name)

  let has_fun =  "s['functions'][".string(a:name)."]"
  let has_const = "s['consts'][".string(a:name)."]"

  for i in haxe#ScannedFiles()
    let s = i['scanned']
    if findPackage && has_key(s,'package') && s['package'] == a:name
      call add(list, {'d': i, 'what':s['package'].' :package', 'file':i['file']})
    endif
    if findClass && has_key(s,'class') && s['class'] == a:name
      call add(list, {'d': i, 'what':s['class'].' :class', 'line': s['class_line'], 'file':i['file']})
    endif
    if findInterface && has_key(s,'interface') && s['interface'] == a:name
      call add(list, {'d': i, 'what':s['interface'].' :interface', 'line': s['interface_line'], 'file':i['file']})
    endif
    if findFunctions
      if exists(has_fun)
        let v = s['functions'][a:name]
        call add(list, {'d': i, 'what':a:name.' :f ', 'line':v, 'file':i['file']})
      endif
    endif
    if findConsts
      if exists(has_const)
        let v = s['consts'][a:name]
        call add(list, {'d': i, 'what':a:name.' :const '.get(v,'type','-'), 'line':get(v,'line',0), 'file':i['file']})
      endif
    endif
  endfor

  return list
endf

" GotoThing('', name)
" GotoThing('regex', regex)
fun! haxe#GotoThing(type, name)
  let things = a:type == 'regex' ? haxe#ThingByRegex(a:name) : haxe#ThingByString(a:name)
  let thing = tlib#input#List("i",'choose thing', map(copy(things),'v:val["what"]'))
  if thing == ''
    echoe "not found"
    return
  endif
  let d = things[thing-1]
  silent! exec 'sp '.d['file'].'|'.get(d,'line',0)
endf

fun! haxe#ClassInfo(object)
  let object = a:object
  let hirarchy = []
  let childs = []
  while 1
    let items = haxe#ThingByRegex('^'.object.'$', 'class')
    if empty(items) | break | endif
    if len(items) > 1 | echom "using first match for ".object | endif
    let match = items[0]
    if !exists('d')
      let d = match
    endif
    call add(hirarchy, object)
    let object = get(match['d']['scanned'],'class_extends',"-")
    if object == "-" | break | endif
  endwhile

  for d in haxe#ScannedFiles()
    if get(d['scanned'],'class_extends','') == a:object
      call add(childs, d['scanned']['class'])
    endif
  endfor
  return { 'hirarchy' : hirarchy, 'childs' : childs, 'd': d}
endf

fun! haxe#ClassView(class)
  let info = haxe#ClassInfo(a:class)
  let lines = []
  call add(lines, "parents: ". join(info["hirarchy"]," > "))
  call add(lines, "childs: ". join(info["childs"], " , "))
  return join(lines,"\n")
endf

fun! haxe#gfHandler()
  let r = []
  let class = expand("<cword>")
  for d in haxe#ThingByString(class)
    call add(r, {'filename': d['file'], 'break': 1, 'line_nr': get(d,'line',0), 'info': d['what'] })
    call add(r, {'filename': views#View('fun',['haxe#ClassView',class], 1), 'break': 1})
  endfor

  " Flex docs
  for f in haxe#HtmlDocFor(class)
    call add(r, {'exec': haxe#DocAction(f) , 'break': 1, 'info': 'flex docs '.class})
  endfor
  return r
endf


" Flex documentation {{{1
" glob in doc dircetory

fun! haxe#DocAction(htmlFile)
  return substitute(s:c['browser'],'%URL%',a:htmlFile,'')
endf

fun! haxe#HtmlDocFor(class)
  let fdd = haxe#FlexDocsDir()
  if type(fdd) == type('') && fdd != ''
    return  split(glob(fdd.'/**/'.a:class.'.html'),"\n")
  endif
endf

fun! haxe#OpenDocFor(class)
  let list = haxe#HtmlDocFor(a:class)
  exec haxe#DocAction(tlib#input#List("s","select html doc page", list))
endf

" }}}1

let s:thisFile=expand('<sfile>')

fun! haxe#ASSources()
  let srcDir = get(s:c, 'as-sources', '')
  if srcDir == ''
    throw "you have to set g:vim_haxe_flashlib
  endif
endf

fun! haxe#FlashLibVersion()
  if !exists('g:vim_haxe_flash_lib_version')
    " TODO improve this!
    throw "you have to set the flashlib version using SetFlashLibVersion (use tab completion)"
  endif
  return g:vim_haxe_flash_lib_version
endf


let s:classregex='interface\s\+'
let s:packageregex='^package\s\+\([^\n\r ]*\)'

let s:c['f_scan_as'] = get(s:c, 'f_scan_as', {'func': funcref#Function('haxe#ScanASFile'), 'version' : 1, 'use_file_cache' : 1} )
" very simple .as / .hx 'parser'
" It only stores function names, class names and the line numbers where those
" functions occur. This way it can be used as tag replacement
fun! haxe#ScanASFile(filename)
  let file_lines = readfile(a:filename)

  let d = {
        \ 'functions' : {},
        \ 'consts' : {}
        \ }

  let regex = join([
    \ '\(interface\)\s\+\([^ ]*\)',
    \ '\(class\)\s\+\([^{ ]*\)\%(\s\+extends\s\+\([^ ]*\)\)\?',
    \ '^\(package\)\s\+\([^{(\n\r ]*\)',
    \ '\(function\)\s\+\([^{(\n\r ]*\)'
    \ ], '\|')

  let regex2 = '\(public\)\%(\s\+\%(static\|const\)\)*\s\+\([^\n\r ]*\)\%(\s\+:\s\+\([^\n\r ]*\)\)\?'

  let g:r = regex

  let nr = 1
  while nr < len(file_lines)
    let l = file_lines[nr-1]
    let m = matchlist(l, regex)
    if !empty(m)
      if m[1] == 'interface'
        let d['interface'] = m[2]
        let d['interface_line'] = nr
      elseif m[3] == 'class'
        let d['class'] = m[4]
        let d['class_line'] = nr
        let d['class_extends'] = m[5]
      elseif m[6] == 'package'
        let d['package'] = m[7]
      elseif m[8] == 'function'
        if m[9] != ''
          let d['functions'][m[9]] = nr
        endif
      else
        echoe "unkown match :".string(m)
      endif
    else
      let m = matchlist(l, regex2)
      if !empty(m)
        let d['consts'][m[2]] = {'type': m[3], 'line' : nr}
      endif
    endif

    let nr = nr +1
  endwhile

  return d
endf

fun! haxe#FlexDocsDir()
  if has_key(s:c,'flex_docs')
    return s:c['flex_docs']
  else
    return 0
  endif
endf

fun! haxe#CompileRHS(...)
  let target = a:0 > 0 ? a:1 : ""
  let ef= 
        \  '%f:%l:\ characters\ %c-%*[^\ ]\ %m,'
        \ .'%f:%l:\ %m'

  if target == ""
    return "call bg#RunQF(['haxe',".string(haxe#BuildHXMLPath())."], 'c', ".string(ef).")"
  endif

  let class = expand('%:r')

  if target[-4:] == "neko"
    let nekoFile = class.'.n'

    if target == "target-neko"
      let args = actions#VerifyArgs(['haxe','-main',class,'-neko',nekoFile])
      call s:tmpHxml(args)
      return "call bg#RunQF(".string(args).", 'c', ".string(ef).")"
    elseif target == "run-neko"
      let args = actions#VerifyArgs(['neko',nekoFile])
      return "call bg#RunQF(".string(args).", 'c', ".string("none").")"
    endif
  endif

  if target[-3:] == "php"
    let phpFront = "index.php"
    let phpDir = "php-target"

    if target == "target-php"
      let args = actions#VerifyArgs(['haxe','-main',class,'--php-front',phpFront,'-php', phpDir])
      call s:tmpHxml(args)
      return "call bg#RunQF(".string(args).", 'c', ".string(ef).")"
    elseif target == "run-php"
      let args = actions#VerifyArgs(['php',phpDir.'/'.phpFront])
      return "call bg#RunQF(".string(args).", 'c', ".string("none").")"
    endif
  endif

  if target[-3:] == "swf"
    if target == "target-swf"
      let args = actions#VerifyArgs(['haxe','-main',class, "-swf-version","10" ,"-swf9", class.'.swf'])
      call s:tmpHxml(args)
      return "call bg#RunQF(".string(args).", 'c', ".string(ef).")"
    elseif target == "run-php"
      throw "not implemented"
    endif
  endif

  throw "target not implemented yet (TODO)"

endfun

" write tmp.hxml file to make completion work
" yes - this isn't the nicest solution.
fun! s:tmpHxml(args)
  let f='tmp.hxml'
  call writefile([a:args], f)
  let g:haxe_build_hxml = f
  call haxe#HXMLChanged()
endf

fun! haxe#HXMLChanged()
  let words = split(haxe#BuildHXML()['ExtraCompletArgs'],'\s\+')
  echo words
  if index(words,"-swf-version") > 0
    let subdir = "flash"
  elseif index(words,"-swf9") > 0
    let subdir = "flash9"
  else
    for i in ['cpp','php','neko']
      if index(words,"-".i) > 0
        let subdir = i
        break
      endif
    endfor
  endif

  let std = haxe#HaxeSourceDir().'/std/'
  let dirToTag = std.subdir
  " TODO think about whether an existing ctaging library can be used?
  if (!exists('g:vim_haxe_ctags_command_recursive'))
    let g:vim_haxe_ctags_command_recursive = "ctags -R "
  endif

  call haxe#TagAndAdd(dirToTag,'.')
  " StringTools, Lamba etc:
  call haxe#TagAndAdd(std, '*.hx')

  " TODO tag haxelib libraries!
endf

fun! haxe#TagAndAdd(d, pat)
  call vcs_checkouts#ExecIndir([{'d': a:d, 'c': g:vim_haxe_ctags_command_recursive.' '.a:pat}])
  exec 'set tags+='.a:d.'/tags'
endf

let s:root = fnamemodify(expand('<sfile>'),':h:h:h')
fun! haxe#HaxeSourceDir()
  let srcdir = exists('g:vim_haxe_haxe_src_dir') ? g:vim_haxe_haxe_src_dir : s:root.'/haxe-src'
  if !isdirectory(srcdir.'/std')
    if input('trying to checkout haxe-src into '.srcdir.'. ok ? [y/n]') == 'y'
      call mkdir(srcdir,'p')
      " checking out std ony would suffice. disk is cheap today..
      call vcs_checkouts#Checkout(srcdir, {'type':'svn','url': 'http://haxe.googlecode.com/svn/trunk' })
    endif
  endif
  return srcdir
endfun
