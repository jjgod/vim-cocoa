# CMakeLists.txt: cmake config file for vim-cocoa build

cmake_minimum_required(VERSION 2.6)
project(VIM)

set(VIMMAJOR 7)
set(VIMMINOR 2)
set(VIM_VERSION "${VIMMAJOR}.${VIMMINOR}")

if (NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Debug")
    set(CMAKE_C_COMPILER "clang")
endif (NOT CMAKE_BUILD_TYPE)

if (NOT GUI)
    if (APPLE)
        set(GUI "Cocoa")
    endif(APPLE)
endif(NOT GUI)

if (APPLE)
  set(PROGNAME      Vim)
  set(VIM_PREFIX    "/Applications")

  # Only build Universal Binary when it's release build
  if (CMAKE_BUILD_TYPE STREQUAL "Release")
      set(CMAKE_OSX_ARCHITECTURES x86_64;i386;ppc)
  endif (CMAKE_BUILD_TYPE STREQUAL "Release")

  set(OS_EXTRA_SOURCES os_macosx.m os_mac_conv.c)
  set(PYTHON_INTERP 1)
  set(RUBY_INTERP 1)
else (NOT APPLE)
  set(PROGNAME vim)
endif (APPLE)

if (CMAKE_COMPILER_IS_GNUCC)
  set(CMAKE_C_FLAGS_DEBUG "-Wall -Werror -mmacosx-version-min=10.5")
  set(CMAKE_C_FLAGS_RELEASE "-O2 -pipe -fomit-frame-pointer -Wall -mmacosx-version-min=10.5")
  set(CMAKE_OSX_SYSROOT "/Developer/SDKs/MacOSX10.5.sdk")
  # cmake will pass CFLAGS to linker, so we need clang to omit warnings for -Wall, -Werror, etc.
  set(CMAKE_EXE_LINKER_FLAGS "-Qunused-arguments")
endif (CMAKE_COMPILER_IS_GNUCC)

find_path(PYTHON_INCLUDE_DIR Python.h)
find_path(RUBY_INCLUDE_DIR   ruby.h HINTS "/System/Library/Frameworks")

include_directories(${CMAKE_CURRENT_BINARY_DIR}
                    ${VIM_SOURCE_DIR} ${VIM_SOURCE_DIR}/proto
                    ${PYTHON_INCLUDE_DIR} ${RUBY_INCLUDE_DIR})

# -DHAVE_CONFIG_H -DFEAT_GUI_MAC -DFEAT_GUI_COCOA
add_definitions(-DHAVE_CONFIG_H -DFEAT_GUI_MAC -DFEAT_GUI_COCOA -DMACOS_X_UNIX
                -D_FORTIFY_SOURCE=1)

set(PYTHON_INTERP_SOURCES   if_python.c)
set(RUBY_INTERP_SOURCES     if_ruby.c)
if (PYTHON_INTERP)
    set(INTERP_SOURCES ${INTERP_SOURCES} ${PYTHON_INTERP_SOURCES})
endif (PYTHON_INTERP)
if (RUBY_INTERP)
    set(INTERP_SOURCES ${INTERP_SOURCES} ${RUBY_INTERP_SOURCES})
endif (RUBY_INTERP)

set(COCOA_GUI_SOURCES       pty.c gui.c gui_mac.m)

if (GUI STREQUAL "Cocoa")
    set(GUI_SOURCES ${COCOA_GUI_SOURCES})
endif(GUI STREQUAL "Cocoa")

set(VIM_DIR_PATH                "/Resources/vim")
set(PATHDEF_SOURCE              "${CMAKE_CURRENT_BINARY_DIR}/pathdef.c")
set(CONFIG_H                    "${CMAKE_CURRENT_BINARY_DIR}/auto/config.h")

set(VIM_SOURCES version.c buffer.c charset.c diff.c digraph.c edit.c eval.c
                ex_cmds.c ex_cmds2.c ex_docmd.c ex_eval.c ex_getln.c fileio.c
                fold.c getchar.c hardcopy.c hashtab.c if_cscope.c if_xcmdsrv.c
                main.c mark.c memfile.c memline.c menu.c message.c misc1.c
                misc2.c move.c mbyte.c normal.c ops.c option.c os_unix.c
                popupmnu.c quickfix.c regexp.c screen.c search.c spell.c
                syntax.c tag.c term.c ui.c undo.c window.c
                ${PATHDEF_SOURCE}
                ${OS_EXTRA_SOURCES}
                ${INTERP_SOURCES}
                ${GUI_SOURCES})

# Simply treat it as C source should be fine, otherwise cmake will choose
# a C++ compiler to build it
set_source_files_properties(gui_mac.m os_macosx.m PROPERTIES LANGUAGE C)

find_library(m m)
find_library(ncurses ncurses)
find_library(iconv iconv)

find_library(COCOA_FRAMEWORK  Cocoa)
find_library(CARBON_FRAMEWORK Carbon)
find_library(PYTHON_FRAMEWORK Python)
find_library(RUBY_FRAMEWORK   Ruby)

set(PSMTBC_PATH ${VIM_SOURCE_DIR}/mac)
find_library(PSMTBC_FRAMEWORK PSMTabBarControl ${PSMTBC_PATH})

set(VIM_LIBRARIES ${m} ${ncurses} ${iconv}
    ${COCOA_FRAMEWORK} ${PSMTBC_FRAMEWORK} ${CARBON_FRAMEWORK} ${PYTHON_FRAMEWORK} ${RUBY_FRAMEWORK})

file(GLOB ICON_FILES os_mac_rsrc/*.icns)
set_source_files_properties(${ICON_FILES} PROPERTIES
    MACOSX_PACKAGE_LOCATION Resources)

set_source_files_properties(PSMTabBarControl.framework PROPERTIES
    MACOSX_PACKAGE_LOCATION Frameworks)

add_executable(${PROGNAME} MACOSX_BUNDLE ${VIM_SOURCES} ${ICON_FILES})
target_link_libraries(${PROGNAME} ${VIM_LIBRARIES})

# Variables used in pathdef.c.in
set(VIM_DEFAULT_VIM_DIR         "${VIM_PREFIX}/${PROGNAME}${VIM_DIR_PATH}")
set(VIM_DEFAULT_VIMRUNTIME_DIR  "")

# How to get these two variables remains to be a question
set(VIM_ALL_CFLAGS              "<Not available in cmake build>")
set(VIM_ALL_LFLAGS              "<Not available in cmake build>")

set(VIM_COMPILED_USER           ${COMPILED_BY})
if (NOT COMPILED_BY)
    site_name(VIM_COMPILED_SYS)
endif(NOT COMPILED_BY)

# Create pathdef.c, which describes the configuration of this build
configure_file(pathdef.c.in ${PATHDEF_SOURCE} ESCAPE_QUOTES)

# Create config.h like configure does
configure_file(config.h.cmakein ${CONFIG_H} ESCAPE_QUOTES)

# Variables for app bundle Info.plist generation
set(MACOSX_BUNDLE_BUNDLE_VERSION ${VIM_VERSION})
set(MACOSX_BUNDLE_GUI_IDENTIFIER "org.vim.Vim-${VIM_VERSION}")
set(MACOSX_BUNDLE_BUNDLE_NAME    "Vim")
set(MACOSX_BUNDLE_ICON_FILE      "app.icns")

set_target_properties(${PROGNAME} PROPERTIES
                      MACOSX_BUNDLE_INFO_PLIST ${VIM_SOURCE_DIR}/Info.plist.in)

# Completes the Vim.app bundle by copying necessary frameworks and runtime
# files into it. Here is the trick: we don't need to actually *copy* them,
# instead we just make a symlink from the source code position to here for
# testing purpose. When we need to 'make install', another procedure will
# be used to ensure these resource files and frameworks are correctly copied.
get_target_property(VIMEXE_LOCATION ${PROGNAME} LOCATION)

string(REPLACE "/MacOS/Vim" "" VIMAPP_LOCATION "${VIMEXE_LOCATION}")

set(VIM_BUNDLE_FRAMEWORK_PATH       "${VIMAPP_LOCATION}/Frameworks")
set(PSMTBC_FRAMEWORK_PATH_IN_BUNDLE "${VIM_BUNDLE_FRAMEWORK_PATH}/PSMTabBarControl.framework")

set(VIM_RUNTIME_PATH                "${VIM_SOURCE_DIR}/../runtime")
set(VIM_BUNDLE_VIM_PATH             "${VIMAPP_LOCATION}${VIM_DIR_PATH}")
set(VIM_RUNTIME_PATH_IN_BUNDLE      "${VIM_BUNDLE_VIM_PATH}/runtime")

add_custom_command(TARGET ${PROGNAME}
                   POST_BUILD
                   COMMAND mkdir -p ${VIM_BUNDLE_FRAMEWORK_PATH}
                   COMMAND mkdir -p ${VIM_BUNDLE_VIM_PATH}
                   COMMAND cmake -E remove -f ${PSMTBC_FRAMEWORK_PATH_IN_BUNDLE}
                   COMMAND cmake -E remove -f ${VIM_RUNTIME_PATH_IN_BUNDLE}
                   COMMAND cmake -E copy_directory ${PSMTBC_FRAMEWORK} ${PSMTBC_FRAMEWORK_PATH_IN_BUNDLE}
                   COMMAND cmake -E copy_directory ${VIM_RUNTIME_PATH} ${VIM_RUNTIME_PATH_IN_BUNDLE}
                   COMMAND sh -c "cd ${VIM_RUNTIME_PATH_IN_BUNDLE}/doc && vim -u NONE -esX -c 'helptags ++t .' -c quit"
                   COMMENT "Adding ${PSMTBC_FRAMEWORK} to ${VIM_BUNDLE_FRAMEWORK_PATH}" VERBATIM)

install(TARGETS ${PROGNAME} BUNDLE DESTINATION /Applications)
install(PROGRAMS mac/gvim DESTINATION bin)
