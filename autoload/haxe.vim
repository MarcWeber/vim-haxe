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
