" functions will be loaded lazily when needed
" exec vam#DefineAndBind('s:c','g:vim_haxe', '{}')
if !exists('g:vim_haxe') | let g:vim_haxe = {} | endif | let s:c = g:vim_haxe

let s:root = fnamemodify(expand('<sfile>'),':h:h:h')

let s:c['f_as_files'] = get(s:c, 'f_as_files', funcref#Function('haxe#ASFiles'))
let s:c['source_directories'] = get(s:c, 'source_directories', [])


let s:c['haxe_src'] = get(s:c, 'haxe_src', s:root.'/haxe-src')
let s:c['flash_develop_checkout'] = get(s:c, 'flash_develop_checkout', s:root.'/flash-develop-checkout')

let s:c['local_name_expr'] = get(s:c, 'local_name_expr', 'tlib#input#List("s","select local name", names)')
let s:c['browser'] = get(s:c, 'browser', 'Browse %URL%')


let s:regex_package = '^\%(package\)\s\+\([^{(\n\r ;]*\)'

fun! haxe#LineTillCursor()
  return getline('.')[:col('.')-2]
endf
fun! haxe#CursorPositions()
  let l = haxe#LineTillCursor()
  let line_till_completion = substitute(l,'[^.:<> \t()]*$','','')
  let b:char_before_completion = ''
  if len(line_till_completion) > 0
    let b:char_before_completion = line_till_completion[-1:]
  endif
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

" add var of current function to complete list
" This should be implemented in HaXe - but it takes me no time doing it in
" VimL
fun! haxe#AddLocalVars(regex, additional_regex)
  if b:char_before_completion == '.'
    return
  endif
  let lidx = line('.')
  let r = []
  while lidx > 0
    let l = getline(lidx)
    if l =~ 'function'
      " break
      for x in r | call complete_add(x) | endfor
      return
    endif
    " join lines by " " until ; is found
    if l =~ '^\s*var\>'
      let i = lidx
      let conc = ''
      while l !~ ';' && i < line('.')
        let conc .= l
        let i+=1
        let l = getline(i)
      endwhile
      let conc .= " ".l
      let without_var = matchstr(conc, '^\s*var\>\s*\zs[^;]*')
      for var in split(without_var,',\s*')
        let v = matchstr(var, '\zs[^;: \t]*')
        if v =~ a:regex || (a:additional_regex != "" && v =~ a:additional_regex)
          call add(r, {'word': v, 'menu': 'var in func '.matchstr(var,'^[^;: \t]*\zs.*')})
        endif
      endfor
    endif
    let lidx = lidx -1
  endwhile
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
fun! haxe#CompleteHAXEFun(line, col, base, ...)
  let opts = a:0 > 0 ? a:1 : {}

  let additional_regex = ""
  if get(opts, "use_additional_regex", 0)
    let patterns = vim_addon_completion#AdditionalCompletionMatchPatterns(a:base
          \ , "vim_dev_plugin_completion_func", {'match_beginning_of_string': 0})
    let additional_regex = get(patterns, 'vim_regex', "")
  endif

  call haxe#AddLocalVars(a:base, additional_regex)

  " Start constructing the command for haxe
  " The classname will be based on the current filename
  " On both the classname and the filename we make sure
  " the first letter is uppercased.
  let classname = substitute(expand("%:t:r"),"^.","\\u&","")

  let tmpDir = haxe#TmpDir()

  let linesTillC = getline(1, a:line-1)+[getline('.')[:(a:col-1)]]
  " hacky: remove package name. This way the file doesn't have to be put into
  " subdirectories
  let [b,eof] = [&binary, &endofline]
  setlocal binary
  setlocal noendofline

  " don't trigger vim-addon-action actions on buf write
  let g:prevent_action = 1
  silent w!
  let g:prevent_action = 0
  " set old settings
  exec 'setlocal '.(b?'':'no').'binary'
  exec 'setlocal '.(eof?'':'no').'endofline'

  let bytePos = len(join(linesTillC,"\n"))
  
  " Construction of the base command line
  let d = haxe#BuildHXML()
  let list = matchlist(getline(search(s:regex_package, 'bn')), s:regex_package)
  let package =
        \ len(list) > 1
        \ ? list[1].'.'
        \ : ""

  let strCmd="haxe --no-output -main " . package.classname . " " . substitute(d['ExtraCompletArgs'],'-main\s\+[^ ]*','',''). " --display " . '"' . expand('%') . '"' . "@" . bytePos

  try
    let dolstErrors = 0

    " We keep the results from the comand in a variable
    let g:strCmd = strCmd
    let res=system(strCmd.' 2>&1')

    let g:res = res
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
      if item == '' | continue | endif
      let element = split(item,"*")
      if len(element) == 1 " Means we only got a package class name
        let dicTmp={'word': element[0]}
      else " Its a method name
        let dicTmp={'word': element[0], 'menu': element[1], 'info': element[1] }
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
    let lstErrors = split(res,"\n")
    if !exists("s:haxeErrorFile")
      let s:haxeErrorFile = tempname()
    endif
    call writefile(lstErrors,s:haxeErrorFile)
    execute "cgetfile ".s:haxeErrorFile
    " Errors will be available for view with the quickfix commands
    cope | wincmd p
  endif

  call filter(lstComplete,'v:val["word"] =~ '.string('^'.a:base).  ( additional_regex == "" ? "" : '|| v:val["word"] =~ '.string('^'.additional_regex) ) )
  return lstComplete
endf

" completes classnames and static functions
" with package name
fun! haxe#CompleteClassNamesFun(line, col, base, ...)
  let opts = a:0 > 0 ? a:1 : {}

  let additional_regex = ""
  if get(opts, "use_additional_regex", 0)
    let patterns = vim_addon_completion#AdditionalCompletionMatchPatterns(a:base
          \ , "vim_dev_plugin_completion_func", {'match_beginning_of_string': 0})
    let additional_regex = get(patterns, 'vim_regex', "")
  endif

  " tag based, cause its faster
  for t in taglist('^'.a:base.'.*')+(additional_regex == "" ? [] : taglist(additional_regex))
    if t['kind'] == 'c'
      let scanned = cached_file_contents#CachedFileContents(t['filename'], s:c['f_scan_as'])
      " add package prefix if not yet imported
      let p = ''
      if get(scanned,'package','') != "" && !search('import\s\+'.scanned['package'].'\s\+;','n')
        let p = scanned['package'].'.'
      endif
      call complete_add({'word': p.t['name'], 'menu': 'class by tag file: '.t['filename']})

    elseif t['kind'] == 'f'
      " assume tags generated by ctags ..
      if t['cmd'] !~ '\<static\>' | continue | endif
      let fun_name = t['name']
      let scanned = cached_file_contents#CachedFileContents(t['filename'], s:c['f_scan_as'])
      " add package prefix if not yet imported
      let p = ''
      if get(scanned, 'package','') != "" && !search('import\s\+'.scanned['package'].'\s\+;','n')
        let p = scanned['package'].'.'
      endif

      " find class providing functions
      let class = ""
      for [k,v] in items(get(scanned, 'classes', {}))
        if index(keys(get(v,'functions', {})), fun_name) != -1
          let class = k
        endif
        unlet k v
      endfor
      let p .= class.'.'
      let args = matchstr(t['cmd'], '.*\zs([^{]*')
      call complete_add({'word': p.fun_name.'(', 'menu': args.' tag file: '.t['filename']})
    endif
  endfor
  return []
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
      call extend(result, call(function('haxe#'.f),[b:haxePos['line'], b:haxePos['col'], a:base, {'use_additional_regex':1}]))
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

fun! haxe#BuildHXMLPath(...)
  let old = exists('g:haxe_build_hxml') ? g:haxe_build_hxml : ""
  if a:0 > 0
    let new_=a:1
  elseif !exists('g:haxe_build_hxml')
    let new_=input('specify your build.hxml file. It should contain one haxe invokation only: ','','customlist,haxe#HXMLFilesCompletion')
  else
    let new_ = g:haxe_build_hxml
  endif
  let g:haxe_build_hxml = new_
  return g:haxe_build_hxml
endf


" extract flash version from build.hxml
let s:c['f_scan_hxml'] = get(s:c, 'f_scan_hxml', {'func': funcref#Function('haxe#ParseHXML'), 'version' : 3} )
fun! haxe#ParseHXML(filename)
  let contents = join(map(readfile(a:filename),'substitute(v:val, '.string('#.*').',"","g")'), " ")
  return haxe#ParseArgs(contents)
endf

fun! haxe#ParseArgs(s)
  let d = {}
  " remove -main foo
  " remove target.swf
  " let contents = substitute(contents, '[^ ]*\.swf', '', 'g')
  let args_from_hxml = a:s

  let d['ExtraCompletArgs'] = args_from_hxml

  let jsFile = matchstr(args_from_hxml, '-js\s\+\zs\S\+\ze')
  if jsFile != ''
    let d['js'] = jsFile
  endif

  let flashTargetVersion = matchstr(args_from_hxml, '-swf-version\s\+\zs[0-9.]\+\ze')
  if flashTargetVersion != ''
    let d['flash_target_version'] = flashTargetVersion
  endif

  let d['cps'] = []
  let d['libs'] = {}

  let args = split(a:s,'\s\+\|\s*\n\s*')
  let nr = 0

  while nr < len(args)
    let arg = args[nr]
    if arg == "-cp"
      let nr = nr +1
      call add(d['cps'], expand(args[nr]))
    elseif arg == "-lib"
      let nr = nr +1
      let name = args[nr]
      let d['libs'][name] = haxe#FindLib(name)

    elseif arg == "-swf9" && !has_key(d,'flash_target_version')
      let d['flash_target_version'] = 9
    elseif arg =~ '-swf-version=\d\+'
      let d['flash_target_version'] = matchstr(arg,'\zs\d*\ze$')
    endif
    let nr = nr +1
  endwhile

  return d
endf

fun! haxe#FindLib(name)
  return split(system('haxelib path '.a:name),"\n")[0]

  " alternative VimL implementation
  let dir = readfile($HOME."/.haxelib",'b')[0]
  if (!isdirectory(dir))
    throw "Can't find haxelib directory "+dir
  endif

  " assume you want latest / last
  return split(glob(dir.'/'.a:name.'/*'),"\n")[-1]
endf

" cached version of current build.hxml file
let s:old_hxml_contents = {}
fun! haxe#BuildHXML()
  let old = s:old_hxml_contents
  let s:old_hxml_contents = cached_file_contents#CachedFileContents(
    \ haxe#BuildHXMLPath(),
    \ s:c['f_scan_hxml'] )
  if (s:old_hxml_contents != old)
    call haxe#HXMLChanged()
  endif
  return s:old_hxml_contents
endf

fun! haxe#FlashDevelopCheckout()
  let srcdir = s:c['flash_develop_checkout']
  if !isdirectory(srcdir)
    if input('trying to checkout flash develop sources into '.srcdir.'. ok ? [y/n]') == 'y'
      call mkdir(srcdir,'p')
      " checking out std ony would suffice. disk is cheap today..
      call vcs_checkouts#Checkout(srcdir, {'type':'svn','url': 'http://flashdevelop.googlecode.com/svn/trunk' })
    else
      return ""
    endif
  endif
  return srcdir
endf

fun! haxe#FlashSourcesByVersion(targetVersion)
  let fdc = haxe#FlashDevelopCheckout()
  if a:targetVersion == 9
    return  fdc.'/FD3/FlashDevelop/Bin/Debug/Library/AS3/intrinsic/FP9'
  elseif a:targetVersion == 10
    return fdc.'/FD3/FlashDevelop/Bin/Debug/Library/AS3/intrinsic/FP10'
  endif
endf

" as files which are searched for imports etc
" add custom directories to g:vim_haxe['source_directories']
" returns [ { 'dir' : 'directory', 'cachable' : 0 /1 } ]
fun! haxe#ASFiles()
  let files = []

  let fdc = haxe#FlashDevelopCheckout()

    let targetVersion = get(haxe#BuildHXML(),'flash_target_version', 10)
    call add(files, { 'cachable': 1, 'files': glob#Glob(haxe#FlashSourcesByVersion(targetVersion).'/**/*.as', {'cachable':1})})

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
  throw "outdated - use faster haxe#AddImportFromQuickfix()"
  let class = matchstr(getline('.'), 'Class not found : \zs.*\|Unknown identifier : \zs.*\|The definition of base class \zs[^ ]*\ze was not found')

  let solutions = []

  " add classes from packages
  for d in funcref#Call(s:c['f_as_files'])
    for file in d['files']
      if file =~ '\.as$'
        " parsing files can be slow (because vim regex is slow) so cache result
        let scanned = cached_file_contents#CachedFileContents(file,
          \ s:c['f_scan_as'], d['cachable'])
        if (  (has_key(scanned,'classes') && has_key(scanned.classes, class))
          \  || (has_key(scanned,'interfaces') && has_key(scanned.interfaces, class))
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
  exec "normal \<cr>"

  call haxe#DoImport(solution)
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
  let line = getline('.')
  let reg = '^\(import\|using\)\s\+\(\S*\)\s*;.*'
  if line =~ reg
    let m = matchlist(line, reg)
    let parsed = haxe#BuildHXML()
    let path = substitute(m[2],'\.','/','g').'.hx'
    for cp in parsed.cps + ["."]
      let f = cp.'/'.path
      if filereadable(f)
        call add(r, {'filename': f, 'break': 1})
        break
      endif
    endfor
  else
    let class = expand("<cword>")
    for d in haxe#ThingByString(class)
      call add(r, {'filename': d['file'], 'break': 1, 'line_nr': get(d,'line',0), 'info': d['what'] })
      call add(r, {'filename': views#View('fun',['haxe#ClassView',class], 1), 'break': 1})
    endfor

    " Flex docs
    for f in haxe#HtmlDocFor(class)
      call add(r, {'exec': haxe#DocAction(f) , 'break': 1, 'info': 'flex docs '.class})
    endfor
  endif
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

let s:c['f_scan_as'] = get(s:c, 'f_scan_as', {'func': funcref#Function('haxe#ScanASFile'), 'version' : 6, 'use_file_cache' : 1} )
" very simple .as / .hx 'parser'
" It only stores function names, class names and the line numbers where those
" functions occur. This way it can be used as tag replacement
fun! haxe#ScanASFile(filename)
  " TODO finish rewriting, add enum support ...
  let file_lines = readfile(a:filename)

  let regex_interface = '\%(interface\)\s\+\([^ ]*\)'
  let regex_class = '\%(class\)\s\+\([^{ ]*\)\%(\s\+extends\s\+\([^ <]*\)\)\?'
  let regex_package = s:regex_package
  let regex_function = '\%(function\)\s\+\([^{(\n\r ]*\)'
  let regex_enum = '^\s*enum\s\+\(\S\+\)'

  " .as can only have one class per file.
  " HaXe allows multiple.
  let d = {
        \ 'classes': {},
        \ 'interfaces': {},
        \ 'functions' : {},
        \ 'consts' : {}
        \ }

  let nr =0
  for line in file_lines
    let nr += 1

    if line =~ regex_package
      let m = matchlist(line, regex_package)
      let d['package'] = m[1]
      continue
    endif

    if line =~ regex_class
      let m = matchlist(line, regex_class)
      let class_name = m[1]
      if class_name == "" | continue | endif
      let current = {'type': 'class', 'name': class_name, 'extends' : m[2], 'functions' : {} }
      let d.classes[class_name] = current
      continue
    endif


    if line =~ regex_interface
      let m = matchlist(line, regex_interface)
      let interface_name = m[1]
      let current = {'type': 'interface', 'name': interface_name, 'extends' : m[2], 'functions' : {} }
      let d.interfaces[interface_name] = current
      continue
    endif


    if line =~ regex_function
      if exists('current.functions')
        let m = matchlist(line, regex_function)
        let fun_name = m[1]
        if fun_name == "" | continue | endif
        let current.functions[fun_name] = { 'line_nr': nr, 'name' : fun_name, 'line' : line }
      endif
      continue
    endif
    
  endfor

  return d

  " == old code, no longer used. TODO remove ==

  let regex = join([
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
        \ '%f:%l:\ characters\ %c-%*[^\ ]\ %m,'
        \ .'%f:%l:\ %m'

  if target == ""
    return "call bg#RunQF(['haxe',".string(haxe#BuildHXMLPath())."], 'c', ".string(ef).")"
  endif

  if target == "hxml-nodejs"
    let dummyArgs = ''
    let onFinish = funcref#Function('haxe#RestartNodejs', {'args': [dummyArgs] })
    return "call bg#RunQF(['haxe',".string(haxe#BuildHXMLPath())."], 'c', ".string(ef).", ".string(onFinish).")"
  endif

  let class = expand('%:r')

  if target[-4:] == "neko"
    let nekoFile = class.'.n'

    if target == "target-neko"
      let args = actions#VerifyArgs(['haxe','-main',class,'-neko',nekoFile])
      call s:tmpHxml(args[1:])
      return "call bg#RunQF(".string(args).", 'c', ".string(ef).")"
    elseif target == "run-neko"
      let args = actions#VerifyArgs(['neko',nekoFile])
      let ef = 'Called\ from\ %f\ line\ %l'
      return "call bg#RunQF(".string(args).", 'c', ".string(ef).")"
    endif
  endif

  if target[-3:] == "php"
    let phpFront = "index.php"
    let phpDir = "php-target"

    if target == "target-php"
      let args = actions#VerifyArgs(['haxe','-main',class,'--php-front',phpFront,'-php', phpDir])
      call s:tmpHxml(args[1:])
      return "call bg#RunQF(".string(args).", 'c', ".string(ef).")"
    elseif target == "run-php"
      let args = actions#VerifyArgs(['php',phpDir.'/'.phpFront])
      return "call bg#RunQF(".string(args).", 'c', ".string("none").")"
    endif
  endif

  if target[-2:] == "js"
    let jsFront = class.".js"

    if target == "target-js"
      let args = actions#VerifyArgs(['haxe','-main',class, '-js',jsFront])
      call s:tmpHxml(args[1:])
      return "call bg#RunQF(".string(args).", 'c', ".string(ef).")"
    elseif target == "run-js"
      let args = actions#VerifyArgs(['js',jsFront])
      return "call bg#RunQF(".string(args).", 'c', ".string("none").")"
    elseif target == "run-rhino-js"
      let args = actions#VerifyArgs(['rhino','-debug',jsFront])
      let ef= 
            \  '%*[\ \\t]at\ %f:%l'
      return "call bg#RunQF(".string(args).", 'c', ".string(ef).")"
    endif
  endif

  if target[-3:] == "swf"
    if target == "target-swf"
      let args = actions#VerifyArgs(['haxe','-main',class, "-swf-version","10" ,"-swf9", class.'.swf'])
      call s:tmpHxml(args[1:])
      return "call bg#RunQF(".string(args).", 'c', ".string(ef).")"
    elseif target == "run-swf"
      throw "not implemented"
    endif
  endif

  if target[-3:] == "cpp"
    if target == "target-cpp"
      let args = actions#VerifyArgs(['haxe','--remap','neko:cpp', '-main',class, "-cpp", "cpp-build"])
      call s:tmpHxml(args[1:])
      return "call bg#RunQF(".string(args).", 'c', ".string(ef).")"
    elseif target == "run-cpp"
      throw "not implemented"
    endif
  endif

endfun

" refactor: also used in vim-addon-urweb
fun! haxe#RestartNodejs(port, status)
  if 1*a:status == 0
    let jsFile = haxe#BuildHXML()['js']

    let cmd = 'nodejs '.shellescape(jsFile)

    if get(s:c,'use_vim_addon_async',0)
      if has_key(s:c, 'nodejs_buf')
        " kill
        let ctx = getbufvar(s:c.nodejs_buf, 'ctx')
        call ctx.kill()
      endif

      " restart
      let ctx = {'cmd':cmd, 'move_last':1}
      if has_key(s:c, 'nodejs_buf')
        let ctx.log_bufnr = s:c.nodejs_buf
      endif
      call async_porcelaine#LogToBuffer(ctx)
      let s:c.nodejs_buf = bufnr('%')

      exec 'command! KillNodejs call getbufvar(g:vim_haxe.nodejs_buf, "ctx").kill()'
    else

      " echoing multiple lines is annoying
      let messages = []
      call add(messages,"restarting nodejs ".jsFile)

      if !has_key(s:c,'pid_file')
        let s:c.pid_file = tempname()
      endif
      let pidFile = s:c.pid_file

      let p_e = shellescape(pidFile)
      if filereadable(pidFile)
        call add(messages, "killing server")
        call system('kill -9 `cat '.p_e.'`')
      endif

      exec vam#DefineAndBind('tmpFile','g:nodejs_server_log','tempname()')
      call system(cmd .' &> '.shellescape(tmpFile).' & jobs -p %1 > '.p_e)
      let pid = readfile(pidFile)[0]
      call add(messages," restarted (".pid.", port : ".a:port.')')
      echom join(messages,' - ')
      exec 'command! KillNodejs !kill -9 '.pid
    endif
  endif
endf

" write tmp.hxml file to make completion work
" yes - this isn't the nicest solution.
fun! s:tmpHxml(args)
  let f='tmp.hxml'
  call writefile([join(a:args," ")], f)
  let g:haxe_build_hxml = f
  call haxe#HXMLChanged()
endf

fun! haxe#HXMLChanged()
  let parsed = haxe#BuildHXML()
  let words = split(parsed['ExtraCompletArgs'],'\s\+')
  if index(words,"-swf9") >= 0
    let subdir = "flash9"
  elseif index(words,"-swf-version") >= 0
    let subdir = "flash"
  else
    for i in ['cpp','php','neko','js']
      if index(words,"-".i) >= 0
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

  " Haxe extra classes
  call haxe#TagAndAdd(std.'/haxe', '.')

  for lib in values(parsed['libs'])
    call haxe#TagAndAdd(lib, '.')
  endfor

  let v = get(parsed,'flash_target_version',"")
  if v != ""
    call haxe#TagAndAdd(haxe#FlashSourcesByVersion(v),'.')
  endif

  " tag -cp sources
  for cp in parsed['cps']
    call haxe#TagAndAdd(cp,'.')
  endfor

endf

" TODO refactor, shared by vim-addon-ocaml, vim-addon-urweb ?
fun! haxe#TagAndAdd(d, pat)
  call vam#utils#ExecInDir([{'d': a:d, 'c': g:vim_haxe_ctags_command_recursive.' '.a:pat}])
  exec 'set tags+='.substitute(a:d,',','\\\\,','g').'/tags'
endf

fun! haxe#HaxeSourceDir()
  let srcdir = exists('g:vim_haxe_haxe_src_dir') ? g:vim_haxe_haxe_src_dir : s:c['haxe_src']
  if !isdirectory(srcdir.'/std')
    if input('trying to checkout haxe-src into '.srcdir.'. ok ? [y/n]') == 'y'
      call mkdir(srcdir,'p')
      " checking out std ony would suffice. disk is cheap today..
      call vcs_checkouts#Checkout(srcdir, {'type':'svn','url': 'http://haxe.googlecode.com/svn/trunk' })
    endif
  endif
  return srcdir
endfun

" create
" Dummy.hx (importing everything found in the current directory)
" dummy_php.hxml
" dummy_.. .hxml
"
" By compiling Dummy.hxml you can type check everything easily
"
" experimental code
fun! haxe#CreateDummyFiles()
  let imports = {}
  for f in split(glob("**/*.hx"),"\n")
    let info = cached_file_contents#CachedFileContents(f, s:c['f_scan_as'])
    if has_key(info, 'classes') && has_key(info, 'package')
      for k in keys(info.classes)
        let imports[info['package'].'.'.k] = 1
      endfor
    endif
  endfor
  let contents =
        \ join(map(keys(imports),'"import ".v:val."\n"'),"")
        \ . "class Dummy {"
        \ . "\n"
        \ . "  static function main() {\n"
        \ . "  }\n"
        \ . "}\n"
  call writefile(split(contents,"\n"), 'Dummy.hx')
  call writefile(["-neko neko","-main Dummy"] ,'dummy_neko.hxml')
endf


" second (fast) implementation of adding imports based on tags {{{1

fun! haxe#AddImportFromQuickfix() abort

  let list = getqflist()

  let did_thing = {}

  for item in list

    let thing = matchstr(item.text, 'Class not found : \zs.*\|Unknown identifier : \zs.*\|The definition of base class \zs[^ ]*\ze was not found')

    if thing == "" || has_key(did_thing, thing)
      continue
    endif

    " open file
    exec 'b '.item.bufnr

    " add import
    call haxe#AddImport(thing)

    " back to quickfix, select next error
    wincmd p
    silent! cnext

    let did_thing[thing] = 1
  endfor

endf

fun! haxe#AddImport(thing)
  let possiblePackages = []
  let sep = ' | ' 
  for t in taglist('^'.a:thing.'$')
    if t.filename =~ '\%(.hx\|.AS\)$'
      let scanned = cached_file_contents#CachedFileContents(t.filename, s:c['f_scan_as'])
      call add(possiblePackages, has_key(scanned, 'package') ? scanned.package : fnamemodify(t.filename,':t:r') .sep.t.filename)
    endif
  endfor
  let package = tlib#input#List("s","chose package to import '".a:thing."' from: ", possiblePackages)
  call haxe#DoImport(split(package.'.'.a:thing, sep)[0])
endf

fun! haxe#DoImport(package)
  let solution = a:package
  normal "G"

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
endf

fun! haxe#NekoTraceToHaXe(...)
  let cmd = a:0 > 0 ? 'cfile '.fnameescape(a:1) : 'cbuffer'
  set efm=Called\ from\ %f\ line\ %l
  exec cmd
  " try to find files
  let l = getqflist()
  let changed = 0
  for idx in range(0, len(l)-1)
    let i = l[idx]
    if i.valid
      let filename = bufname(i.bufnr)
      if !filereadable(filename)
        " try to find the file
        " was -debug used?
        if filename =~ '::' 
          " match a line like this:
          "Called from haxed.ClientMain::main line 178

          " try to find class by tagfiles
          let class = matchstr(filename,'[^.:]\+\ze:')

          for tag in taglist('^'.class.'$')
            if tag.kind == 'c'
              let i.filename = tag.filename | let changed = 1
              let i.text = filename
              unlet i.bufnr
              break
            endif
          endfor
        else
          " assume file can be found in a subdir
          let list = split(glob('**/'. filename),"\n")
          if len(list) >= 1
            let i.filename = list[0] | let changed = 1
            unlet i.bufnr
          endif
        endif
      endif
    endif
    let l[idx] = i
  endfor
  if changed
    call setqflist(l)
  endif
endf
