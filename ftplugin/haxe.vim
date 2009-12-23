if !exists('g:vim_haxe_no_abbrevs')
  " some abbreviations I find useful
  abbrev spf static public function
fi

if !exists('g:vim_haxe_no_indentation')
  " setlocal autoindent
  setlocal cindent
fi

if !exists('g:vim_haxe_no_completion')
  setlocal completeopt=preview,menu,menuone
fi
