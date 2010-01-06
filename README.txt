haxeOmnicomplete vim plugin README

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

_______________________________________________
INSTALLATION

Install this plugin: http://github.com/MarcWeber/vim-addon-manager

run once:
call scriptmanager#Activate(["vim-haxe"])

Then add to your .vimrc:
call scriptmanager#Activate(["vim-haxe"])

Use <c-x><c-o> to get completion
Use <c-l> to define a local command

place cursor on error line in Quikfix Window then type i to add a missing flash
import

You should svn checkout http://flashdevelop.googlecode.com/svn/trunk
and set in your .vimrc:

  let g:vim_haxe = {}
  let g:vim_haxe['flash_develop_checkout'] = '~/path-to/flashdevelop_trunk'

_______________________________________________
CONFIGURATION:

TODO, get a list of options by:
grep -r  vim_haxe .

_______________________________________________
USAGE (QUICK AND DIRTY)

To get completions: CTRL-X CTRL-O after a dot.

To add classpaths: call HaxeAddClasspath() or <LocalLeader>p

To add a haxelib: call HaxeAddLibs() or <LocalLeader>l

To navigate to errors: use vim quickfix commands.

_______________________________________________
EXPLANATION

Of course, using the compiler has its cons. If you have
syntax or other kind of errors in you code, the omnicompletion
will not work and an exception will be raised. I have managed
a simplistic error handling that will fill the errors in the
buffer errorfile (this will create a new temporary file) so
you can navigate easily to them using the quickfix commands.
(:cl, cfirst, cnext, etc...).

Also, if your hx file uses classes that are not available, 
you must declare them by calling HaxeAddClasspath(). This
is conveniently mapped to <LocalLeader>p (by default \p).
You will get a prompt asking for a path. You must provide the
full path to the other classes files, without the last slash.
Those paths will be appended to the comand line calling the
compiler using -cp flags.

If you use haxelib libs, you must also declare them by
calling HaxeAddLib(), this one mapped to <LocalLeader>l
(again, usually \l). You will get a prompt asking for the
name of the lib, for example hxJSON, (great lib BD!).
Those libs will be appended to the command line calling the
compiler using -lib flags.

The haxeLibs and haxeClasspath variables holding that
data are declared as buffer variables, so you must 
declare them for each hx you are editing. This can be 
royal pain, so you can set g:globalHaxeLibs and
g:globalHaxeClasspath in your vimrc file to declare
a list of paths and libraries to use for all you haxe
files. For example, to set a list of classpaths for your
hx's files you write this in your vimrc:

let g:globalHaxeClasspath = ['C:\Path\to\some\dir\with\classes','C:\Another\path']

and for the libs:

let g:globalHaxeLibs = ['hxJSON','otherLib']

Note that this variables must be declared as vim Lists,
so even if you only add one element, you must use 
the square brackets syntax.

Note also that this variables must be declared BEFORE
the sourcing of the plugin in your vimrc.

_______________________________________________
BUGS

None so far, but they will surface!

