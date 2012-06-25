_______________________________________________
INSTALLATION

I highly recommend using VAM (vim-addon-manager): 
  http://github.com/MarcWeber/vim-addon-manager
  Then put into your ~/.vimrc:
  call scriptmanager#Activate(["vim-haxe"])

alternative way (Pathogen, manual, ...):
  See vim-haxe-addon-info.txt
  See key "dependencies". Install all those plugins in some (manual?) way.
  You'll find all those plugins on my github page.


If you have any trouble contact me.

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

ctags language support see:

  http://haxe.org/com/ide

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
The fastest way to do so is just type "hxml" or "cpp" or "neko" or "php"
and the list will be filtered.
If you select the hxml target you can choose a custom target.
c-tags will be generated for you automatically - and tags are added to &tags
depending on target which is the reason that --next will never be supported.
When using "hxml" you have to choose the .hxml file completion depends on (tab
completion supported). The other default targets write a tmp.hxml temporary
file.

Use snipmate and snippets/haxe_hxml.snippets snippets to write .hxml files faster.


Additional notes:
This VimL lib also contains a very basic .hx file parser. At the beginning I
based some of the completions on it. But it was too slow. Using tagfiles and
HaXe only now. Its still used to get the package name.


-----------------------------------------------------------------------
related work:
* vaxe:
  (requires python, was written for the sake of writing something new)
  https://github.com/jdonaldson/vaxe
  https://groups.google.com/forum/#!searchin/haxelang/vim/haxelang/xJm78HCwc0Y/7kX1JCBD18oJ

  collaborative work is going on. See thread "Vihxen: Vim + Haxe"
  Vihxen is the initial name and was renamed to vaxe.
