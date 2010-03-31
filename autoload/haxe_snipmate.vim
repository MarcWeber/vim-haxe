fun! haxe_snipmate#GetterSetter(action)
  " create private var and property
  " I hope this is what most people need most of the time (?)
  let varName = input('var name: ')
  let type = input('type: ', 'Int')

  let str  =''
  let str .= "// property ".varName." {{{1\n" 
  let str .= "private var PN: type;\n"
  let str .= "public var name(getName, setName) : type;\n"
  let str .= "private function getName(): type\n"
  let str .= "{\n"
  let str .= "\treturn PN;\n"
  let str .= "}\n"
  let str .= "private function setName(value : type): type\n"
  let str .= "{\n"
  let str .= "\tif (PN == value) return PN;\n"
  if a:action
    let str .= "\tif (PN != null)\n"
    let str .= "\t\t;\n"
    let str .= "\tif (value != null)\n"
    let str .= "\t\t;\n"
  endif
  let str .= "\treturn PN = value;\n"
  let str .= "}\n"
  let str .= "// }}}"

  let u = substitute(varName,'^\(.\)','\U\1','')
  let replace = {
    \ 'name': varName,
    \ 'Name': u,
    \ 'type': type,
    \ 'PN': '_'.varName
    \}

  for [k,v] in items(replace)
    let str = substitute(str, k, v, 'g')
  endfor
  return str
endf

" completes super(); or super.name(args)
fun! haxe_snipmate#Super()
  let res = search('.*function.*', 'b', 'n')
  let line = line('.')
  if line > 0
    let line = getline(line)
    if line =~ 'function\s\+new('
      return 'super();'
    else
      let args = matchstr(line, '(\zs[^)].*\ze)')
      let l = []
      for arg in split(args, ',')
        call add(l, matchstr(arg, '\zs[^ \t:]\+\ze'))
      endfor
      return 'super.'.matchstr(line,'\zs[^ (:]\+\ze(').'('.join(l,', ').');'
    endif
  else
    return '''
  endif
endf
