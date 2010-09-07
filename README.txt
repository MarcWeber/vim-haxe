_______________________________________________
INSTALLATION

Install this plugin: http://github.com/MarcWeber/vim-addon-manager

run once:
call scriptmanager#Activate(["vim-haxe"])

Then add to your .vimrc:
call scriptmanager#Activate(["vim-haxe"])

Use <c-x><c-o> to get completion (based on HaXe)
  Example: this. -> this.addChild(

Use <c-x><c-u> to get completion (based on tags. This completes both: class
                                  names and functions)

  Example: gC -> haxe.io.File.getContents(

Use <c-l> to define a local command

place cursor on error line in Quikfix Window then type i to add a missing flash
import

vim-haxe will ask you to checkout sources for both:
haxe and flash_develop lazily.
_______________________________________________
CONFIGURATION:

TODO, get a list of options by:
grep -r  vim_haxe .

let g:vim_haxe_haxe_src_dir='directory' if you don't like the default
PLUGIN_ROOT.'/haxe-src'

ctags language support:
~/.ctags:

  --langdef=haxe
  --langmap=haxe:.hx
  --regex-haxe=/^package[ \t]+([A-Za-z0-9_.]+)/\1/p,package/
  --regex-haxe=/^[ \t]*[(private|public|static|override|inline|dynamic)( \t)]*function[ \t]+([A-Za-z0-9_]+)/\1/f,function/
  --regex-haxe=/^[ \t]*([private|public|static|protected|inline][ \t]*)+var[ \t]+([A-Za-z0-9_]+)/\2/v,variable/ 
  --regex-haxe=/^[ \t]*package[ \t]*([A-Za-z0-9_]+)/\1/p,package/
  --regex-haxe=/^[ \t]*(extern[ \t]+)?class[ \t]+([A-Za-z0-9_]+)[ \t]*[^\{]*/\2/c,class/
  --regex-haxe=/^[ \t]*(extern[ \t]+)?interface[ \t]+([A-Za-z0-9_]+)/\2/i,interface/
  --regex-haxe=/^[ \t]*typedef[ \t]+([A-Za-z0-9_]+)/\1/t,typedef/
  --regex-haxe=/^[ \t]*enum[ \t]+([A-Za-z0-9_]+)/\1/t,typedef/


Vim will then automatically checkout haxe sources and tag the std .hx files for you

EXPLANATION


-----------------------------------------------------------------------
QUICKFIX DETAILS:

See vim-addon-actions. (Eg use :ActionOnBufWrite or <s-f2> to assign an action such as
compile to 
  -js
  -neko
  -cpp
  -php
(this will create a tmp.hxml file)

compile using hxml (you'll be asked for the .hxml file). Use tab completion to
select the one you want to work with.

Additional notes:
This VimL lib also contains a very basic .hx file parser. At the beginning I
based some of the completions on it. But it was too slow. Using tagfiles and
HaXe only now. Its still used to get the package name.

-----------------------------------------------------------------------
original: haxeOmnicomplete vim plugin README

Hello people!

This is my first try at giving something back to the comunity, 
so please bear with my errors!

This plugin enables the use of omnicomplete in haxe files 
in vim. After a dot you press CTRL-X CTRL-O (your custom 
mappings could have changed those bindings) and this
plugin will call the haxe compiler and return a list of
the methods and properties of the word before the dot.
You can navigate the list with CTRL-N and CTRL-P.
It that word has no properties nor methods, nothing will be
returned. Simple, huh?
