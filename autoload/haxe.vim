" functions will be loaded lazily when needed
exec scriptmanager#DefineAndBind('s:c','g:vim_haxe', '{}')

let s:c['f_as_files'] = get(s:c, 'f_as_files', funcref#Function('haxe#ASFiles'))
let s:c['source_directories'] = get(s:c, 'source_directories', [])
let s:c['flash_develop_checkout'] = get(s:c, 'flash_develop_checkout', '')
let s:c['f_scan_as'] = get(s:c, 'f_scan_as', funcref#Function('flashlibdata#ScanASFile'))
let s:c['local_name_expr'] = get(s:c, 'local_name_expr', 'tlib#input#List("s","select local name", names)')

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

" this function writes the current buffer
" col=1 is first character
" g:haxe_build_hxml should be set to the buildfile so that important
" compilation flags can be extracted.
" You should consider creating one .hxml file for each target..
"
" base: prefix used to filter results
fun! haxe#GetCompletions(line, col, base)
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
    " We keep the results from the comand in a variable
    let g:strCmd = strCmd
    let res=system(strCmd)
    "call delete(tmpFilename)
    if v:shell_error != 0 "If there was an error calling haxe, we return no matches and inform the user
      if !exists("b:haxeErrorFile")
        let b:haxeErrorFile = tempname()
      endif
      throw "lstErrors"
    endif

    let lstXML = split(res,"\n") " We make a list with each line of the xml

    if len(lstXML) == 0
      let lstComplete = []
    elseif lstXML[0] != '<list>' "If is not a class definition, we check for type definition
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
  catch lstErrors
    let lstErrors = split(substitute(res, tmpFilename, expand('%'),'g'),"\n")
    call writefile(lstErrors,b:haxeErrorFile)
    execute "cgetfile ".b:haxeErrorFile
    " Errors will be available for view with the quickfix commands
    cope | wincmd p
    let lstComplete = []
  endtry

  if empty(lstComplete)
    " add classes from packages
    for file in funcref#Call(s:c['f_as_files'])
      if file =~ '\.as$'
        " parsing files can be slow (because vim regex is slow) so cache result
        let scanned = cached_interpretation_of_file#ScanIfNewer(file,
          \ {'scan_func' : s:c['f_scan_as'], 'fileCache':1})
        if has_key(scanned,'class')
          call add(lstComplete, {'word': scanned['class'], 'menu': 'class in '.get(scanned,'package','')})
        endif
      endif
    endfor
  endif

  call filter(lstComplete,'v:val["word"] =~ '.string('^'.a:base))
  return lstComplete

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

fun! haxe#BuildHXMLPath()
  if !exists('g:haxe_build_hxml')
    let g:haxe_build_hxml=input('specify your build.hxml file. It should contain one haxe invokation only: ','','file')
  endif
  return g:haxe_build_hxml
endf

" extract flash version from build.hxml
fun! haxe#ParseHXML(lines)
  let d = {}

  let contents = ""

  let contents = join(a:lines, " ")
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
  return cached_interpretation_of_file#ScanIfNewer(
    \ haxe#BuildHXMLPath(),
    \ { 'scan_func' : funcref#Function('haxe#ParseHXML') } )
endf

" as files which are searched for imports etc
" add custom directories to g:vim_haxe['source_directories']
fun! haxe#ASFiles()
  let files = []

  let fdc = s:c['flash_develop_checkout']

  if fdc != ''
    let tv = get(haxe#BuildHXML(),'flash_target_version', -1)
    if tv == 9
      call extend(files, glob#Glob(fdc.'/'.'FD3/FlashDevelop/Bin/Debug/Library/AS3/intrinsic/FP9/**/*.as'))
    elseif tv == 10
      call extend(files, glob#Glob(fdc.'/'.'FD3/FlashDevelop/Bin/Debug/Library/AS3/intrinsic/FP10/**/*.as'))
    endif
  else
    echoe "consider checking out flashdevelop and setting let g:vim_haxe['flash_develop_checkout'] = 'path_to_checkout'"
  endif

  for d in s:c['source_directories']
    call extend(files, glob#Glob(d.'/**/*.as'))
  endfor

  let g:files = files
  return files
endf

fun! haxe#ScannedFiles()
  let list = []
  for file in funcref#Call(s:c['f_as_files'])
    let scanned = cached_interpretation_of_file#ScanIfNewer(file,
      \ {'scan_func' : s:c['f_scan_as'], 'fileCache':1})
    call add(list, {'file': file, 'scanned': scanned })
  endfor
  return list
endfun

fun! haxe#FindImportFromQuickFix()
  let class = matchstr(getline('.'), 'Class not found : \zs.*\|Unknown identifier : \zs.*')

  let solutions = []

  " add classes from packages
  for file in funcref#Call(s:c['f_as_files'])
    if file =~ '\.as$'
      " parsing files can be slow (because vim regex is slow) so cache result
      let scanned = cached_interpretation_of_file#ScanIfNewer(file,
        \ {'scan_func' : s:c['f_scan_as'], 'fileCache':1})
      if has_key(scanned,'class') && scanned['class'] == class && has_key(scanned,'package')
        call add(solutions, scanned['package'].'.'.class)
      endif
    endif
  endfor
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

  if search('^import','cwb') == 0
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

  for i in haxe#ScannedFiles()
    let f = i['file']
    let s = i['scanned']
    if ("package" =~ type) && has_key(s,'package') && s['package'] =~ a:name
      call add(list, {'d': i, 'what':s['package'].' :package', 'file':f})
    endif
    if ("class" =~ type) && has_key(s,'class') && s['class'] =~ a:name
      call add(list, {'d': i, 'what':s['class'].' :class', 'line': s['class_line'], 'file':f})
    endif
    if ("interface" =~ type) && has_key(s,'interface') && s['interface'] =~ a:name
      call add(list, {'d': i, 'what':s['interface'].' :interface', 'line': s['interface_line'], 'file':f})
    endif
    let functions = filter(copy(s['functions']), 'v:key =~'.string(a:name))
    if ("function" =~ type)
      for [k,v] in items(functions)
        call add(list, {'d': i, 'what':k.' :f ', 'line':v, 'file':f})
      endfor
    endif
    if ("consts" =~ type)
      let consts = filter(copy(s['consts']),'v:key =~'.string(a:name))
      for [k,v] in items(consts)
        call add(list, {'d': i, 'what':k.' :const '.get(v,'type','-'), 'line':get(v,'line',0), 'file':f})
      endfor
    endif
  endfor

  return list
endf

fun! haxe#GotoThingRegex(name)
  let things = haxe#ThingByRegex(a:name)
  let thing = tlib#input#List("i",'choose thing', map(copy(things),'v:val["what"]'))
  if thing == ''
    echoe "not found"
    return
  endif
  let d = things[thing-1]
  silent! exec 'sp '.d['file'].'|'.get(d,'line',0)
endf

fun! haxe#ParentsOfObject(object)
  let object = a:object
  let hirarchy = []
  while 1
    let items = haxe#ThingByRegex('^'.object.'$', 'class')
    if empty(items) | break | endif
    if len(items) > 1 | echoe "using first match for ".object | endif
    let match = items[0]
    call add(hirarchy, object)
    let object = get(match['d']['scanned'],'class_extends',"-")
    if object == "-" | break | endif
  endwhile
  return hirarchy
endf
