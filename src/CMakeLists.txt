# CMakeLists.txt: cmake config file for vim-cocoa build

cmake_minimum_required(VERSION 2.6.2)
project(VIM)

if (NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Debug")
endif (NOT CMAKE_BUILD_TYPE)

if (APPLE)
  set(PROGNAME Vim)

  # Only build Universal Binary when it's release build
  if (CMAKE_BUILD_TYPE STREQUAL "Release")
      set(CMAKE_OSX_ARCHITECTURES i386;ppc)
  endif (CMAKE_BUILD_TYPE STREQUAL "Release")
else (NOT APPLE)
  set(PROGNAME vim)
endif (APPLE)

if (CMAKE_COMPILER_IS_GNUCC)
  set(CMAKE_C_FLAGS_DEBUG "-g -Wall -Werror")
  set(CMAKE_C_FLAGS_RELEASE "-O2 -pipe -fomit-frame-pointer")
endif (CMAKE_COMPILER_IS_GNUCC)

find_path(PYTHON_INCLUDE_DIR Python.h)
message(${PYTHON_INCLUDE_DIR})

find_path(COCOA_INCLUDE_DIR Cocoa/Cocoa.h)
message(${COCOA_INCLUDE_DIR})

find_path(PSMTBC_INCLUDE_DIR PSMTabBarControl/PSMTabBarControl.h ${VIM_SOURCE_DIR}/mac/build/Release)
message(${PSMTBC_INCLUDE_DIR})

include_directories(${VIM_SOURCE_DIR} ${VIM_SOURCE_DIR}/proto
    ${PYTHON_INCLUDE_DIR} ${COCOA_INCLUDE_DIR} ${PSMTBC_INCLUDE_DIR})

# -DHAVE_CONFIG_H -DFEAT_GUI_MAC -DFEAT_GUI_COCOA
add_definitions(-DHAVE_CONFIG_H -DFEAT_GUI_MAC -DFEAT_GUI_COCOA -DMACOS_X_UNIX
                -D_FORTIFY_SOURCE=1)

set(VIM_SOURCES version.c buffer.c charset.c diff.c digraph.c edit.c eval.c
        ex_cmds.c ex_cmds2.c ex_docmd.c ex_eval.c ex_getln.c fileio.c fold.c
	    getchar.c hardcopy.c hashtab.c if_cscope.c if_xcmdsrv.c main.c mark.c
	    memfile.c memline.c menu.c message.c misc1.c misc2.c move.c mbyte.c
	    normal.c ops.c option.c os_unix.c pdef.c popupmnu.c quickfix.c
	    regexp.c screen.c search.c spell.c syntax.c tag.c term.c ui.c undo.c
        window.c pty.c os_macosx.c os_mac_conv.c if_python.c gui.c gui_mac.m)

find_library(m m)
find_library(ncurses ncurses)
find_library(iconv iconv)

find_library(cocoa Cocoa)
find_library(python Python)
find_library(psmtab PSMTabBarControl ${VIM_SOURCE_DIR}/mac/build/Release)

set(VIM_LIBRARIES ${m} ${ncurses} ${iconv} ${cocoa} ${psmtab} ${python})
message(${VIM_LIBRARIES})

add_executable(${PROGNAME} ${VIM_SOURCES})
target_link_libraries(${PROGNAME} ${VIM_LIBRARIES})
