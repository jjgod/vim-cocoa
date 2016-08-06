vim-cocoa
=========

What is vim-cocoa?
------------------

vim-cocoa is a Mac OS X native vim GUI implementation in Cocoa, it started
as a Google Summer of Code 2007 project, it's now maintaining by Jjgod Jiang
<gzjjgod@gmail.com>.

Build instructions
------------------

  git clone https://github.com/jjgod/vim-cocoa.git
  cd vim-cocoa
  mkdir build
  cd build
  cmake ../src
  make
  ./Vim.app/Contents/MacOS/Vim -g

What's the differences between the original vim, MacVim and vim-cocoa?
----------------------------------------------------------------------

The original [vim](http://www.vim.org) (checkout from vim official Subversion
repository) only provides a Classic/Carbon based GUI for Mac OS X users, it
lacks some important features and does not give us the best GUI experiences.

Thus, both [MacVim](http://code.google.com/p/MacVim) and vim-cocoa started
to alleviate this problem by reimplement the whole Mac GUI with Cocoa,
MacVim started earlier, in 2006, but the author (Björn Winkler) didn't
announce it at that time. After it's matured enough to be announced, vim-cocoa
is already accepted as a Google Summer of Code project and I (Jjgod Jiang)
already started coding, although these two projects started with the same
goal, there are a lot of differences in their design decisions, which made
their code base not so possible to merge together.

In short, MacVim is a more feature-rich, more Mac-integrated version, while
vim-cocoa follows a more simple, lightweight and fast approach.

Nico Weber has a nice
[introduction](http://groups.google.com/group/vim_mac/browse_thread/thread/c16868aa7dcad59b)
on which MacVim does but vim-cocoa doesn't (I discussed a bit about my design
goals for vim-cocoa too).

What's New?
-----------

### 0.10

* Update to vim 7.4.2156.
* Support macOS 10.12.

### 0.5

* Update to vim 7.3
* Fix an issue caused by sudden termination support
* Fix max window size calculation problem. (Reported by hupple)

### 0.4.2

* Fix a drawing buffer overflow issue (reported by fishy)
* Fix an issue on ASCII capable input source switching (reported by xiedebao)
* Show vim-cocoa version in `:version` and About dialog.
* Updated vim to 7.2.411.

### 0.4

* Improve input method switching support
* Fix Ctrl key handling

### 0.4 beta 2

* Support sudden termination in Snow Leopard
* Fix font selection issue introduced in previous build
* Fix some text input and keyboard handling issues (reported by riobard)
* Fix various clear/redraw issues
* Fix a memory leak in string drawing

### 0.4 beta 1

* Greatly improved performance, especially visible in Snow Leopard
* Improve startup experience
* Launch 64-bit binary on 10.6, 32-bit binaries on 10.5
* Fix Ctrl key handling issue in some cases like Ctrl-Tab (reported by riobard)
* Tune resize behavior on window zoom (report by riobard)

### 0.3.2

* Fix frame height calculation when GUI tabline is enabled
* Add back missing helptags

### 0.3.1

* Fix crashing on loading non-UTF-8 menu translations (reported by ducksteven and dyroro)
* Fix delayed refreshing (reported by fishy)

### 0.3

* Update vim to 7.2.245
* **Rewrote** part of the rendering process to increase performance, especially on Mac OS X 10.6
* Add clipboard support for console mode (running without `-g`)
* Use cmake to support out-of-directory build, see BuildInstructions for detail
* Build with `+ruby` and `+cscope` by default

### 0.3 beta 1

* Updated vim to 7.2.49
* Use Core Text to replace ATSUI for text rendering
* Optimize program startup
* Support transparency option to control background transparency
* Fix cursor redraw on right clicking
* Fix CTRL + SHIFT + ? key handling (Issue 35)
* Mac OS X 10.5 only (Since Core Text is a 10.5 only framework)

### 0.2

* Updated vim to 7.2
* Fix shift key combination problem (Issue 30)
* Fix Shift-Tab problem (Issue 29)
* Fix fake italic angle problem
* Fix a reset transform problem
* Show text area size (col x rows) in title on live resize
* Fix menu separator issue (Issue 24)
* Fix a issue adding duplicate entries into file list (Issue 23)

### 0.2 beta 3

* Fix some packaging issues (Thanks hzhr to point these out.)
* Enlarge default font size from 9pt to 12pt.
* Fix resize box at bottom right with an undocumented API (Thanks Nico).

### 0.2 beta 1

* Add GUI Tab feature (Using PSMTabBarControl)
* A lot of view refactoring

### 0.1

* Initial release
