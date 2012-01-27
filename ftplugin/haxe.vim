" exec vam#DefineAndBind('s:c','g:vim_haxe','{}')
if !exists('g:vim_haxe') | let g:vim_haxe = {} | endif | let s:c = g:vim_haxe

" TODO move this setting to s:c
if !exists('g:vim_haxe_no_indentation')
  " setlocal autoindent
  setlocal cindent
endif

" TODO move this setting to s:c
if !exists('g:vim_haxe_no_mappings')
  " define local var
  inoremap <buffer> <c-l> <c-r>=haxe#DefineLocalVar()<cr>
endif

call on_thing_handler#AddOnThingHandler('b', funcref#Function('haxe#gfHandler'))

let b:match_words='#if:#else\>:#elif\>:#end\>'

call vim_addon_completion#InoremapCompletions(s:c, [
   \ { 'setting_keys' : ['complete_lhs_haxe'], 'fun': 'haxe#CompleteHAXE'},
   \ { 'setting_keys' : ['complete_lhs_tags'], 'fun': 'haxe#CompleteClassNames'}
   \ ] )


" TODO move this setting to s:c
if !exists('did_import_mapping') && !exists('g:codefellow_no_import_mapping')
  let did_import_mapping = 1
  " note: codefellow is using something similar as well.
  " So if you open a .hx file first you'll get the wrong import hook!
  autocmd Filetype qf noremap <buffer> i :call<space>haxe#AddImportFromQuickfix()<cr>


  noremap \i :call<space>haxe#AddImportFromQuickfix()<cr>
endif

let b:match_words='function.*{:return:},switch.*{:case:},\<if\>:\<else\>'

setlocal comments=s1:/*,mb:*,ex:*/,://
