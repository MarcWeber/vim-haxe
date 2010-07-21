if !exists('g:vim_haxe_no_abbrevs')
  " some abbreviations I find useful
  abbrev spf static public function
  abbrev sv static var
  abbrev pf public function
endif

if !exists('g:vim_haxe_no_indentation')
  " setlocal autoindent
  setlocal cindent
endif

if !exists('g:vim_haxe_no_mappings')
  " define local var
  inoremap <buffer> <c-l> <c-r>=haxe#DefineLocalVar()<cr>
endif

call on_thing_handler#AddOnThingHandler('b', funcref#Function('haxe#gfHandler'))

let b:match_words='#if:#else\>:#elif\>:#end\>'


if !exists('did_import_mapping') && !exists('g:codefellow_no_import_mapping')
  let did_import_mapping = 1
  " note: codefellow is using something similar as well.
  " So if you open a .hx file first you'll get the wrong import hook!
  autocmd Filetype qf noremap <buffer> i :call<space>haxe#FindImportFromQuickFix()<cr>
endif
