" read .as files (or .hx files ??) keeping track of which classes and
" interfaces are defined in which packages

exec scriptmanager#DefineAndBind('s:c','g:vim_haxe', '{}')

let s:thisFile=expand('<sfile>')

fun! flashlibdata#ASSources()
  let srcDir = get(s:c, 'as-sources', '')
  if srcDir == ''
    throw "you have to set g:vim_haxe_flashlib
  endif
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


" very simple .as / .hx 'parser'
" It only stores function names, class names and the line numbers where those
" functions occur. This way it can be used as tag replacement
fun! flashlibdata#ScanASFile(file_lines)
  let d = {
        \ 'functions' : {},
        \ 'consts' : {}
        \ }

  let regex = join([
    \ '\(interface\)\s\+\([^ ]*\)',
    \ '\(class\)\s\+\([^ ]*\)\s\+\%(extends\s\+\([^ ]*\)\)',
    \ '^\(package\)\s\+\([^\n\r ]*\)',
    \ '\(function\)\s\+\([^\n\r ]*\)'
    \ ], '\|')

  let regex2 = '\(public\)\%(\s\+\%(static\|const\)\)*\s\+\([^\n\r ]*\)\%(\s\+:\s\+\([^\n\r ]*\)\)\?'

  let g:r = regex

  let nr = 1
  while nr < len(a:file_lines)
    let l = a:file_lines[nr-1]
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
        let d['functions'][m[9]] = nr
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
