" read .as files (or .hx files ??) keeping track of which classes and
" interfaces are defined in which packages

exec scriptmanager#DefineAndBind('s:c','g:vim_haxe', '{}')

let s:c['regex_interface']  = get(s:c, 'regex_interface',  'interface\s\+\zs[^ ]*\ze')
let s:c['regex_class']      = get(s:c, 'regex_class', 'class\s\+\zs[^ ]*\ze')
let s:c['regex_package']    = get(s:c, 'regex_package', '^package\s\+\zs[^\n\r ]*\ze') 

let s:thisFile=expand('<sfile>')

fun! flashlibdata#ASSources()
  let srcDir = get(s:c, 'as-sources', '')
  if srcDir == ''
    throw "you have to set g:vim_haxe_flashlib
  endif
endf

fun! flashlibdata#CreateData(path_to_flashdevelop_checkout)
  let dirs=split(glob(a:path_to_flashdevelop_checkout.'/FD3/FlashDevelop/Bin/Debug/Library/*/*'),"\n")
  let dict = {}

  for dir in dirs
    let sdict = {}
    for f in split(glob(dir.'/**/*.as'),"\n")
      if f ~= '\.svn'
        continue
      endif
      echo "parsing file ".f
      let contents = readfile(f)
      let package = filter(clone(contents),'v:val =~'.string('
    endfor
  endfor
  call writefile([string(dict)], flashlibdata#DataFile())
  let g:vim_haxe_flashlib_data = dict
endf

fun! flashlibdata#FlashLibVersion()
  if !exists('g:vim_haxe_flash_lib_version')
    " TODO improve this!
    throw "you have to set the flashlib version using SetFlashLibVersion (use tab completion)"
  endif
  return g:vim_haxe_flash_lib_version
endf


let s:classregex='interface\s\+'
let s:packageregex='^package\s\+\([^\n\r ]*\)'

fun! flashlibdata#ScanASFile(file_lines)
  let d = {}
  for item in ['package', 'class', 'interface']
    let r = s:c['regex_'.item]
    let list = filter(copy(a:file_lines), 'v:val =~'.string(r))
    let list = filter(list, 'v:val !~ '.string('^\s*//'))
    if !empty(list)
      let d[item] = matchstr(list[0], r)
    endif
  endfor
  return d
endf
