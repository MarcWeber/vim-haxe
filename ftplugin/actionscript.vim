if !exists('g:vim_as_no_abbrevs')
  " some abbreviations I find useful
  abbrev spf static public function
  abbrev sv static var
  abbrev pf public function
endif

if !exists('g:vim_as_no_indentation')
  " setlocal autoindent
  setlocal cindent
endif

if !exists('g:vim_as_no_completion')
  setlocal completeopt=preview,menu,menuone
  setlocal omnifunc=haxe#Complete
endif

if !exists('g:vim_as_no_mappings')
  " define local var
  inoremap <buffer> <c-l> <c-r>=haxe#DefineLocalVar()<cr>
  setlocal completeopt=preview,menu,menuone
  setlocal omnifunc=haxe#Complete
endif

call on_thing_handler#AddOnThingHandler('b', funcref#Function('haxe#gfHandler'))
