/* vi:set ts=4 sts=4 sw=4 foldmethod=marker:
 *
 * VIM - Vi IMproved        by Bram Moolenaar
 *              GUI/Motif support by Robert Webb
 *              Macintosh port by Dany St-Amant
 *                        and Axel Kielhorn
 *              Port to MPW by Bernhard Pruemmer
 *              Initial Carbon port by Ammon Skidmore
 *              Initial Cocoa port by Jjgod Jiang
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 *
 * TODO:
 *
 * 1. Toolbar.
 * 2. GUI Tab.
 * 3. Multiple Windows.
 */

#include "vim.h"
#import <Cocoa/Cocoa.h>
#import <PSMTabBarControl/PSMTabBarControl.h>

#define GUI_MAC_DEBUG     1

/* Internal Data Structures {{{ */

#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
typedef NSInteger long
#endif

/* Key mapping {{{2 */

static struct
{
    UniChar function_key;
    int     vim_key;
} function_key_mapping[] =
{
    { NSUpArrowFunctionKey,     K_UP    },
    { NSDownArrowFunctionKey,   K_DOWN  },
    { NSLeftArrowFunctionKey,   K_LEFT  },
    { NSRightArrowFunctionKey,  K_RIGHT },

    { NSF1FunctionKey,          K_F1    },
    { NSF2FunctionKey,          K_F2    },
    { NSF3FunctionKey,          K_F3    },
    { NSF4FunctionKey,          K_F4    },
    { NSF5FunctionKey,          K_F5    },
    { NSF6FunctionKey,          K_F6    },
    { NSF7FunctionKey,          K_F7    },
    { NSF8FunctionKey,          K_F8    },
    { NSF9FunctionKey,          K_F9    },
    { NSF10FunctionKey,         K_F10   },

    { NSF11FunctionKey,         K_F11   },
    { NSF12FunctionKey,         K_F12   },
    { NSF13FunctionKey,         K_F13   },
    { NSF14FunctionKey,         K_F14   },
    { NSF15FunctionKey,         K_F15   },

    { NSInsertFunctionKey,      K_INS   },
    { NSDeleteFunctionKey,      K_DEL   },
    { NSHomeFunctionKey,        K_HOME  },
    { NSEndFunctionKey,         K_END   },

    { NSPageUpFunctionKey,      K_PAGEUP    },
    { NSPageDownFunctionKey,    K_PAGEDOWN  },

    { '\t',     '\t'    },  /* tab */
    { '\r',     '\r'    },  /* return */
    { '\003',   '\003'  },  /* enter */
    { '\031',   K_S_TAB },  /* backtab */
    { '\033',   '\033'  },  /* escape */
    { '\177',   K_BS    },  /* backspace */

    /* End of list marker: */
    { 0, 0 },
};

/* 2}}} */

#define VIM_MAX_FONT_NAME_LEN   256
#define VIM_MAX_BUTTON_TITLE    256
#define VIM_DEFAULT_FONT_SIZE   9
#define VIM_DEFAULT_FONT_NAME   (char_u *) "Monaco:h12"
#define VIM_MAX_CHAR_WIDTH      2

#define VIM_UNDERLINE_OFFSET        (-2)
#define VIM_UNDERLINE_HEIGHT        1
#define VIM_UNDERCURL_HEIGHT        2
#define VIM_UNDERCURL_OFFSET        (-2)
#define VIM_UNDERCURL_DOT_WIDTH     2
#define VIM_UNDERCURL_DOT_DISTANCE  2

#define VIMDropFilesEventSubtype    10001

/* A simple view to make setting text area, scrollbar position inside
 * vim window easier */
@interface VIMContentView: NSView {
    NSTabView        *tabView;
    PSMTabBarControl *tabBarControl;
}

- (PSMTabBarControl *) tabBarControl;
- (NSTabViewItem *) addNewTabViewItem;
- (NSTabView *) tabView;

@end

@interface VIMTextView: NSView <NSTextInput>
{
    NSRange              markedRange;
    NSRange              selectedRange;
    NSAttributedString  *markedText;
    NSMutableDictionary *markedTextAttributes;

    NSImage             *contentImage;
    NSString            *lastSetTitle;
}

- (NSAttributedString *) markedText;
- (void) setMarkedTextAttribute:(id)value forKey:(NSString *)key;
- (void) mouseAction:(int)button repeated:(bool)repeated event:(NSEvent *)event;

- (void) synchronizeContentImage;
- (void) beginDrawing;
- (void) endDrawing;

- (void) clearAll;

@end

@interface VIMWindow: NSWindow {
    VIMTextView *textView;
}

- (VIMTextView *) textView;
- (void) setTextView: (VIMTextView *) view;

@end

@interface VIMScroller : NSScroller
{
    scrollbar_T *vimScrollBar;
}

- (id)initWithVimScrollbar:(scrollbar_T *)scrollBar
               orientation:(int)orientation;
- (scrollbar_T *) vimScrollBar;
- (void) setThumbValue:(long)value size:(long)size max:(long)max;

@end

static int VIMAlertTextFieldHeight = 22;

@interface VIMAlert : NSAlert {
    NSTextField *textField;
}

- (void) setTextFieldString:(NSString *)textFieldString;
- (NSTextField *) textField;

@end

@interface VimAppController: NSObject
- (void) alertDidEnd:(VIMAlert *)alert returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void) panelDidEnd:(NSSavePanel *)panel code:(int)code context:(void *)context;
- (void) initializeApplicationTimer:(NSTimer *)timer;
- (void) blinkCursorTimer:(NSTimer *)timer;
- (void) menuAction:(id)sender;
@end

enum gui_mac_debug_level {
    MSG_INFO  = 0,
    MSG_DEBUG = 1,
    MSG_WARN  = 2,
    MSG_ERROR = 3
};

struct gui_mac_data {
    NSColor    *fg_color, *bg_color, *sp_color;

    VIMWindow   *current_window;

    NSFont     *current_font;
    NSFont     *selected_font;

    int         app_is_running;
    float       bg_alpha;

    int         blink_state;
    long        blink_wait;
    long        blink_on;
    long        blink_off;
    NSTimer    *blink_timer;

    bool        input_received;
    bool        initialized;

    int         dialog_button;
    NSString   *selected_file;

    int         im_row, im_col;
    NSEvent    *last_mouse_down_event;

    int         debug_level;
    BOOL        showing_tabline;
    BOOL        selecting_tab;

    ATSUStyle   font_style[VIM_MAX_CHAR_WIDTH];

    VimAppController  *app_delegate;
    NSAutoreleasePool *app_pool;
} gui_mac;

#define FLIPPED_RECT(view, rect)    NSMakeRect(rect.origin.x, \
                                        [view frame].size.height - \
                                            rect.origin.y - rect.size.height, \
                                        rect.size.width, \
                                        rect.size.height)
#define FLIPPED_POINT(view, point)  NSMakePoint(point.x, \
                                        [view frame].size.height - point.y)

#define gui_mac_run_app()           gui_mac.app_is_running = TRUE
#define gui_mac_stop_app(yn)        { gui_mac.input_received = yn; gui_mac.app_is_running = FALSE; }
#define gui_mac_app_is_running()    (gui_mac.app_is_running == TRUE)
#define gui_mac_get_scroller(sb)    ((VIMScroller *) sb->scroller)

/* Data Structures }}}*/

/* Internal functions prototypes {{{ */

@interface NSApplication (VimAdditions)
- (void) setAppleMenu:(NSMenu *)aMenu;
@end

@interface NSFont (AppKitPrivate)
- (ATSUFontID) _atsFontID;
@end

NSColor     *NSColorFromGuiColor(guicolor_T color, float alpha);
NSAlertStyle NSAlertStyleFromVim(int type);
#define      NSStringFromVim(str)    ([NSString stringWithUTF8String: (const char *) str])
NSRect       NSRectFromVim(int row1, int col1, int row2, int col2);

NSWindow *gui_mac_get_window(NSRect rect);
int       gui_mac_create_window(NSRect rect);
void      gui_mac_open_window();
void      gui_mac_set_application_menu();
void      gui_mac_send_dummy_event();
void      gui_mac_update();

#define currentView                 ([gui_mac.current_window textView])
#define gui_mac_begin_drawing()     [currentView beginDrawing]
#define gui_mac_end_drawing()       [currentView endDrawing]
#define gui_mac_begin_tab_action()  (gui_mac.selecting_tab = YES)
#define gui_mac_end_tab_action()    (gui_mac.selecting_tab = NO)

int  gui_mac_hex_digit(int c);
void gui_mac_redraw();
void gui_mac_scroll_rect(NSRect rect, int lines);

void         print_vim_modifiers(unsigned int vim_modifiers);
unsigned int gui_mac_key_modifiers_to_vim(unsigned int mac_modifiers);
unsigned int gui_mac_mouse_modifiers_to_vim(unsigned int mac_modifiers);
int          gui_mac_function_key_to_vim(UniChar key_char, unsigned int vim_modifiers);
int          gui_mac_mouse_button_to_vim(int mac_button);

GuiFont   gui_mac_find_font(char_u *font_name);
int       gui_mac_points_to_pixels(char_u *str, char_u **end);
NSFont   *gui_mac_get_font(char_u *font_name, int size);
void      gui_mac_set_font_attributes(GuiFont font);
void      gui_mac_create_atsui_style();
void      gui_mac_dispose_atsui_style();
ATSUStyle gui_mac_atsui_style_from_width(int width);
void      gui_mac_atsui_style_set_value(ATSUStyle style, ATSUAttributeTag tag, void *value, int size);
void      gui_mac_atsui_style_set_boolean(ATSUStyle layout, ATSUAttributeTag tag, Boolean value);
void      gui_mac_atsui_style_set_int(ATSUStyle style, ATSUAttributeTag tag, UInt32 value);

int gui_mac_select_from_font_panel(char_u *font_name);
void gui_mac_update_scrollbar(scrollbar_T *sb);
void gui_mac_msg(int level, NSString *fmt, ...);

#define NSShowRect(msg, rect)        gui_mac_msg(MSG_DEBUG, @"%s: %g %g %g %g", msg, \
                                                 rect.origin.x, rect.origin.y, \
                                                 rect.size.width, rect.size.height)

/* Internal functions prototypes }}} */

/* Initializtion and Finalization {{{ */

int gui_mch_init()
{
    gui_mac_msg(MSG_INFO, @"gui_mch_init: %s", exe_name);

    gui_mac.app_pool = [NSAutoreleasePool new];

    [NSApplication sharedApplication];

    gui_mac.app_delegate = [VimAppController new];
    [NSApp setDelegate: gui_mac.app_delegate];

    [NSApp setMainMenu: [[NSMenu new] autorelease]];
    gui_mac_set_application_menu();

    gui.char_width = 0;
    gui.char_height = 0;
    gui.char_ascent = 0;
    gui.num_rows = 24;
    gui.num_cols = 80;
    gui.tabline_height = 22;
    gui.in_focus = TRUE;

    gui.norm_pixel = 0x00000000;
    gui.back_pixel = 0x00FFFFFF;
    set_normal_colors();

    gui_check_colors();
    gui.def_norm_pixel = gui.norm_pixel;
    gui.def_back_pixel = gui.back_pixel;

    /* Get the colors for the highlight groups (gui_check_colors() might have
     * changed them) */
    highlight_gui_started();

#ifdef FEAT_MENU
    gui.menu_height = 0;
#endif
    gui.scrollbar_height = gui.scrollbar_width = [VIMScroller scrollerWidth];
    gui.border_offset = gui.border_width = 2;

    gui_mac.bg_alpha = 1.0;

    gui_mac.current_window = nil;
    gui_mac.input_received = NO;
    gui_mac.initialized    = NO;
    gui_mac.showing_tabline = NO;
    gui_mac.selecting_tab  = NO;

    return OK;
}

int gui_mch_init_check()
{
    gui_mac_msg(MSG_INFO, @"gui_mch_init_check");

    /* see main.c for reason to disallow */
    if (disallow_gui)
        return FAIL;

    return OK;
}

void gui_mch_exit(int rc)
{
    gui_mac_msg(MSG_INFO, @"gui_mch_exit\n");

    [gui_mac.last_mouse_down_event release];
    [gui_mac.selected_file release];
    [gui_mac.app_delegate release];
    [gui_mac.app_pool release];

    [[NSUserDefaults standardUserDefaults] synchronize];

    exit(rc);
}

int gui_mch_open()
{
    gui_mac_msg(MSG_INFO, @"gui_mch_open: %d %d", gui_win_x, gui_win_y);

    gui_mac_open_window();

    if (gui_win_x != -1 && gui_win_y != -1)
        gui_mch_set_winpos(gui_win_x, gui_win_y);

    return OK;
}

void gui_mch_prepare(int *argc, char **argv)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    NSString *path = [[NSBundle mainBundle] executablePath];

    gui_mac.debug_level = MSG_DEBUG;
    gui_mac_msg(MSG_INFO, @"gui_mch_prepare: %@", path);

    exe_name = vim_strsave((char_u *) [path fileSystemRepresentation]);

    [pool release];
}

void gui_mch_set_shellsize(
    int width,
    int height,
    int min_width,
    int min_height,
    int base_width,
    int base_height,
    int direction)
{
    NSWindow *window = gui_mac_get_window(NSMakeRect(0, 0, width, height));
    NSRect contentRect = [window contentRectForFrameRect: [window frame]];

    /* keep the top left corner not change */
    contentRect.origin.y += contentRect.size.height - height;
    contentRect.size.width = width;
    contentRect.size.height = height;

    gui_mac_msg(MSG_INFO, @"gui_mch_set_shellsize: "
                "(%d, %d, %d, %d, %d, %d, %d)\n",
                width, height, min_width, min_height,
                base_width, base_height, direction);

    gui_mac_msg(MSG_INFO, @"gui.num_rows (%d) * gui.char_height (%d) = %d",
                gui.num_rows, gui.char_height, gui.num_rows * gui.char_height);

    gui_mac_msg(MSG_INFO, @"gui.num_cols (%d) * gui.char_width (%d) = %d",
                gui.num_cols, gui.char_width, gui.num_cols * gui.char_width);

    NSRect frame = [window frameRectForContentRect: contentRect];
    [window setFrame: frame display: NO];
}

void gui_mch_set_text_area_pos(int x, int y, int w, int h)
{
    gui_mac_msg(MSG_INFO, @"gui_mch_set_text_area_pos: "
                "%d, %d, %d, %d", x, y, w, h);

    NSRect viewRect = NSMakeRect(x, y, w, h);
    // If we don't have a text view yet, allocate it first
    if (! currentView)
    {
        // NSShowRect("create textView: ", viewRect);
        VIMTextView *textView = [[VIMTextView alloc] initWithFrame: viewRect];
        [textView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];

        [gui_mac.current_window setTextView: textView];
        [textView release];
    }
    else
    {
        if (! NSEqualRects([currentView frame], viewRect))
            [currentView setFrame: viewRect];

        [currentView synchronizeContentImage];

        if ([currentView inLiveResize])
            [gui_mac.current_window setTitle:
                [NSString stringWithFormat: @"%d×%d", gui.num_cols, gui.num_rows]];
    }
}

/* Initializtion and Finalization }}} */

/* Event related {{{ */

void gui_mch_update()
{
    // gui_mch_wait_for_chars(0);
}

/* wtime < 0: wait forever
 * wtime > 0: wait wtime milliseconds
 * wtime = 0: don't wait, only poll existing events
 */
int gui_mch_wait_for_chars(int wtime)
{
    NSEvent *event;
    NSAutoreleasePool *pool;
    NSDate  *date;

    pool = [[NSAutoreleasePool alloc] init];

    // TODO: only redraw modified part
    if (wtime != 0)
        gui_mac_redraw();

    if (wtime == 0)
    {
        // gui_mac_msg(MSG_DEBUG, @"gui_mch_wait_for_chars: don't wait");
        date = [NSDate distantPast];
    }
    else if (wtime > 0)
    {
        // gui_mac_msg(MSG_DEBUG, @"gui_mch_wait_for_chars: wait for %d ms", wtime);
        date = [NSDate dateWithTimeIntervalSinceNow: (double) wtime / 1000.0];
    }
    /* wtime < 0, wait forever */
    else
    {
        // gui_mac_msg(MSG_DEBUG, @"gui_mch_wait_for_chars: wait forever");
        date = [NSDate distantFuture];
    }

    /* It's tricky here: we don't want to use -[NSApplication run:]
     * all the time, but we need it to do some initialization for
     * the first time this app starts. So we install a timer to
     * stop: NSApp just after it runs.
     */
    if (gui_mac.initialized == NO)
    {
        // gui_mac_msg(MSG_DEBUG, @"first time, begin initialization...");
        [NSTimer scheduledTimerWithTimeInterval: 0.1
                                         target: gui_mac.app_delegate
                                       selector: @selector(initializeApplicationTimer:)
                                       userInfo: 0
                                        repeats: NO];
        [NSApp run];

        gui_mac.initialized = YES;
        // gui_mac_msg(MSG_DEBUG, @"end initialization.");
    }

    gui_mac_run_app();
    while (gui_mac_app_is_running() &&
           (event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                       untilDate: date
                                          inMode: NSDefaultRunLoopMode
                                         dequeue: YES]) != nil)
    {
        [NSApp sendEvent: event];
    }

    BOOL last_received = gui_mac.input_received;

    gui_mac.input_received = NO;

    [pool release];
    return last_received;
}

/* Event related }}} */

/* Input Method Handling {{{ */

int im_get_status()
{
    if (! gui.in_use)
            return 0;

    return 0;
}

void im_set_active(int active)
{
}

void im_set_position(int row, int col)
{
    gui_mac_msg(MSG_INFO, @"im_set_position: (%d, %d)", row, col);
    gui_mac.im_row = row;
    gui_mac.im_col = col;
}

/* Input Method Handling }}} */

/* Misc Stuff {{{ */

void gui_mch_get_screen_dimensions(int *screen_w, int *screen_h)
{
    CGRect rect;

    rect = CGDisplayBounds(CGMainDisplayID());

    *screen_w = (int) rect.size.width;
    *screen_h = (int) rect.size.height;

    gui_mac_msg(MSG_INFO, @"gui_mch_get_screen_dimensions: %d, %d",
                *screen_w, *screen_h);
}

#ifdef USE_MCH_ERRMSG

void display_errors()
{
    fflush(stderr);
}

#endif

int gui_mch_haskey(char_u *name)
{
    return OK;
}

void gui_mch_beep()
{
    NSBeep();
}

void gui_mch_toggle_tearoffs(int enable)
{
    /* no tearoff menus */
}

/* Misc Stuff }}} */

/* Font Handling {{{ */

int gui_mch_init_font(char_u *font_name, int fontset)
{
    NSAutoreleasePool *pool;
    NSFont  *mac_font;
    GuiFont  vim_font;
    NSSize   advance;
    char_u   used_font_name[VIM_MAX_FONT_NAME_LEN];

    gui_mac_create_atsui_style();

    if (font_name == NULL)
        font_name = VIM_DEFAULT_FONT_NAME;

    gui_mac_msg(MSG_INFO, @"gui_mch_init_font: %s", font_name);

    if (STRCMP(font_name, "*") == 0)
    {
        char_u *new_p_guifont;

        if (gui_mac_select_from_font_panel(font_name) != OK)
            return FAIL;

        /* Set guifont to the name of the selected font. */
        new_p_guifont = alloc(STRLEN(font_name) + 1);
        if (new_p_guifont != NULL)
        {
            STRCPY(new_p_guifont, font_name);
            vim_free(p_guifont);
            p_guifont = new_p_guifont;
            /* Replace spaces in the font name with underscores. */
            for ( ; *new_p_guifont; ++new_p_guifont)
            {
                if (*new_p_guifont == ' ')
                    *new_p_guifont = '_';
            }
        }
    }

    pool = [NSAutoreleasePool new];
    vim_font = gui_mac_find_font(font_name);

    if (vim_font == NOFONT)
    {
        gui_mac_msg(MSG_WARN, @"find_font failed");
        return FAIL;
    }

    gui.norm_font = vim_font;

    vim_strncpy(used_font_name, font_name, sizeof(used_font_name) - 1);

    gui_mac_msg(MSG_INFO, @"gui_mch_init_font: font_name: '%s'", font_name);

    hl_set_font_name(used_font_name);

    mac_font = (NSFont *) vim_font;
    advance  = [mac_font advancementForGlyph: (NSGlyph) '_'];

    /* in 72 DPI, 1 point = 1 pixel */
    gui.char_ascent = roundf([mac_font ascender]);
    gui.char_width  = roundf(advance.width);

    float height = [mac_font ascender] - [mac_font descender] + [mac_font leading];

#if 0
    NSLog(@"[%s] height1 = %g - %g + %g = %g\n",
          font_name, [mac_font ascender],
          [mac_font descender], [mac_font leading], height);
    NSLog(@"[%s] height2 = %g\n", font_name,
          [mac_font defaultLineHeightForFont]);
#endif

    gui.char_height = roundf([mac_font defaultLineHeightForFont]) + p_linespace;

    [gui_mac.current_window setResizeIncrements: NSMakeSize(gui.char_width, gui.char_height)];

    gui_mac_msg(MSG_INFO, @"ascent = %d, width = %d, height = %d, %f, %f",
                gui.char_ascent, gui.char_width, gui.char_height,
                [mac_font ascender], [mac_font descender]);
    [pool release];

    gui_mac_set_font_attributes(vim_font);
    return OK;
}

void gui_mch_free_font(GuiFont font)
{
    [(NSFont *) font release];
}

void gui_mch_set_font(GuiFont font)
{
    gui_mac.current_font = (NSFont *) font;
    [currentView setMarkedTextAttribute: gui_mac.current_font
                                 forKey: NSFontAttributeName];
}

GuiFont gui_mch_get_font(char_u *name, int giveErrorIfMissing)
{
    GuiFont font;

    gui_mac_msg(MSG_INFO, @"gui_mch_get_font: %s", name);
    font = gui_mac_find_font(name);

    if (font == NOFONT)
    {
        if (giveErrorIfMissing)
            EMSG2(_(e_font), name);
        return NOFONT;
    }
    /*
     * TODO : Accept only monospace
     */

    return font;
}

char_u *gui_mch_get_fontname(GuiFont font, char_u *name)
{
    if (name == NULL)
        return NULL;

    return vim_strsave(name);
}

int gui_mch_adjust_charheight()
{
    NSFont *mac_font = gui_mac.current_font;

    if (mac_font == nil)
        return OK;

    /* in 72 DPI, 1 point = 1 pixel */
    gui.char_ascent = roundf([mac_font ascender]);
    gui.char_height = roundf([mac_font ascender] - [mac_font descender]) + p_linespace;

    return OK;
}

/* Font Handling }}} */

/* Window Handling {{{ */

@implementation VIMWindow

- (id) initWithContentRect:(NSRect)contentRect
{
    unsigned int windowStyle = NSTitledWindowMask |
                       NSMiniaturizableWindowMask |
                             NSClosableWindowMask |
                            NSResizableWindowMask |
               NSUnifiedTitleAndToolbarWindowMask |
                   NSTexturedBackgroundWindowMask;

    // NSShowRect("VIMWindow initWithContentRect", contentRect);
    if ([super initWithContentRect: contentRect
                         styleMask: windowStyle
                           backing: NSBackingStoreBuffered
                             defer: YES])
    {
        // [self setBackgroundColor: [NSColor clearColor]];
        // [self setOpaque: YES];
        [self setViewsNeedDisplay: NO];
        [self setTitle: @"gVIM on Macintosh"];
        [self setResizeIncrements: NSMakeSize(gui.char_width, gui.char_height)];
        [self setDelegate: gui_mac.app_delegate];

        textView = nil;

        VIMContentView *contentView = [[VIMContentView alloc] initWithFrame: contentRect];
        [self setContentView: contentView];
        [contentView release];

        if ([self respondsToSelector: @selector(setBottomCornerRounded:)])
            [self setBottomCornerRounded: NO];

        [self makeFirstResponder: textView];
    }

    return self;
}

- (VIMTextView *) textView
{
    return textView;
}

- (void) setTextView: (VIMTextView *) view
{
    if (textView)
        [textView removeFromSuperview];

    textView = view;
    [[self contentView] addSubview: textView];
    // [textView setHidden: YES];
}

@end

void gui_mch_set_foreground()
{
    // gui_mac_msg(MSG_DEBUG, @"gui_mch_set_foreground");
    [gui_mac.current_window orderFront: nil];
}

void gui_mch_set_winpos(int x, int y)
{
    gui_mac_msg(MSG_INFO, @"gui_mch_set_winpos: %d, %d", x, y);

    /* Get the visiable area (excluding menubar and dock) of screen */
    NSRect visibleFrame = [[NSScreen mainScreen] visibleFrame];
    NSPoint topLeft = NSMakePoint(x + visibleFrame.origin.x,
                                  visibleFrame.origin.y + visibleFrame.size.height - y);
    [gui_mac.current_window setFrameTopLeftPoint: topLeft];
}

int gui_mch_get_winpos(int *x, int *y)
{
    NSRect windowRect = [gui_mac.current_window frame];
    NSRect visibleFrame = [[NSScreen mainScreen] visibleFrame];

    // NSShowRect("windowRect", windowRect);

    float X_vim = windowRect.origin.x - visibleFrame.origin.x;
    float Y_vim = visibleFrame.origin.y + visibleFrame.size.height -
                  (windowRect.origin.y + windowRect.size.height);

    gui_mac_msg(MSG_INFO, @"X_vim = %g - %g = %g", windowRect.origin.x,
                visibleFrame.origin.x, X_vim);
    gui_mac_msg(MSG_INFO, @"Y_vim = %g + %g - (%g + %g) = %g", visibleFrame.origin.y,
                visibleFrame.size.height, windowRect.origin.y, windowRect.size.height,
                Y_vim);

    if (X_vim < 0)
        X_vim = 0;
    if (X_vim > visibleFrame.size.width)
        X_vim = visibleFrame.size.width;

    if (Y_vim < 0)
        Y_vim = 0;
    if (Y_vim > visibleFrame.size.height)
        Y_vim = visibleFrame.size.height;

    *x = (int) X_vim;
    *y = (int) Y_vim;

    return OK;
}

void gui_mch_settitle(char_u *title, char_u *icon)
{
    gui_mac_msg(MSG_INFO, @"gui_mch_set_title: (%s, %s)", title, icon);

    [gui_mac.current_window setTitle: NSStringFromVim(title)];
}

void gui_mch_iconify()
{
    gui_mac_msg(MSG_INFO, @"gui_mch_iconify");
}

/* Window Handling }}} */

/* Menu Handling {{{ */

NSMenuItem *gui_mac_insert_menu_item(vimmenu_T *menu)
{
    vimmenu_T  *parent, *brother;
    NSMenu     *parent_menu = nil;
    NSMenuItem *mac_menu_item, *item;
    int         alloc = 0, index;

    brother = menu->next;
    /* My brother could be the PopUp, find my real brother */
    while ((brother != NULL) && (! menu_is_menubar(brother->name)))
        brother = brother->next;

    if (STRNCMP(menu->dname, "-SEP", 4) == 0 ||
        STRNCMP(menu->dname, "-sep", 4) == 0)
        mac_menu_item = [NSMenuItem separatorItem];
    else
    {
        NSString *title = NSStringFromVim(menu->dname);
        mac_menu_item = [[NSMenuItem alloc] initWithTitle: title
                                                   action: @selector(menuAction:)
                                            keyEquivalent: @""];
        [mac_menu_item setTarget: gui_mac.app_delegate];
        [mac_menu_item setTag: (int) menu];
        alloc = 1;

        if (menu->actext != NULL)
        {
            NSString *tooltip = NSStringFromVim(menu->actext);

            [mac_menu_item setToolTip: tooltip];
        }
    }
    menu->item_handle = (void *) mac_menu_item;

    parent = menu->parent;
    if (parent == NULL)
    {
        if (menu_is_menubar(menu->name))
            parent_menu = [NSApp mainMenu];
    }
    else
        parent_menu = (NSMenu *) parent->menu_handle;

    if (parent_menu)
    {
        /* If index == -1, means in parent menu we cannot find
         * this menu item, must be something wrong, but we still
         * need to handle this gracefully */
        if (brother != NULL &&
            (item = (NSMenuItem *) brother->item_handle) != NULL &&
            (index = [parent_menu indexOfItem: item]) != -1)
            [parent_menu insertItem: mac_menu_item
                            atIndex: index];
        else
            [parent_menu addItem: mac_menu_item];
    } else
        [mac_menu_item retain];

    if (alloc)
        [mac_menu_item release];

    return mac_menu_item;
}

void gui_mch_add_menu(vimmenu_T *menu, int idx)
{
    gui_mac_msg(MSG_INFO, @"gui_mch_add_menu: %s, %d", menu->dname, idx);

    NSString *title = NSStringFromVim(menu->dname);
    NSMenu *mac_menu = [[NSMenu alloc] initWithTitle: title];
    NSMenuItem *mac_menu_item = gui_mac_insert_menu_item(menu);

    [mac_menu_item setSubmenu: mac_menu];
    menu->menu_handle = (void *) mac_menu;

    [mac_menu release];
}

void gui_mch_add_menu_item(vimmenu_T *menu, int idx)
{
    gui_mac_msg(MSG_INFO, @"gui_mch_add_menu_item: %s, %d", menu->dname, idx);

    gui_mac_insert_menu_item(menu);
}

void gui_mch_destroy_menu(vimmenu_T *menu)
{
    NSMenu *parent_menu = nil;

    if (menu == NULL)
        return;

    if (menu->parent == NULL)
    {
        if (menu_is_menubar(menu->name))
            parent_menu = [NSApp mainMenu];
        else
            [(NSMenu *) menu->menu_handle release];
    }
    else
        parent_menu = (NSMenu *) menu->parent->menu_handle;

    if (parent_menu)
        [parent_menu removeItem: (NSMenuItem *) menu->item_handle];

    menu->item_handle = NULL;
}

void gui_mch_draw_menubar()
{
}

void gui_mch_menu_grey(vimmenu_T *menu, int grey)
{
    NSMenuItem *item;

    if (menu == NULL)
        return;

    item = (NSMenuItem *) menu->item_handle;
    [item setEnabled: grey ? NO : YES];
}

void gui_mch_menu_hidden(vimmenu_T *menu, int hidden)
{
    /* There's no hidden mode on MacOS */
    gui_mch_menu_grey(menu, hidden);
}

void gui_mch_show_popupmenu(vimmenu_T *menu)
{
    NSMenu *mac_menu = (NSMenu *) menu->menu_handle;
    NSEvent *event = gui_mac.last_mouse_down_event;

    [NSMenu popUpContextMenu: mac_menu
                   withEvent: event
                     forView: currentView];
}

void gui_make_popup(char_u *path_name, int mouse_pos)
{
    vimmenu_T *menu = gui_find_menu(path_name);

    if (menu == NULL)
        return;

    NSMenu *mac_menu = (NSMenu *) menu->menu_handle;
    NSEvent *event;
    NSPoint point;

    if (mouse_pos)
        point = [gui_mac.current_window convertScreenToBase: [NSEvent mouseLocation]];
    else
    {
        int row = curwin->w_wrow;
        int col = curwin->w_wcol;

        point = NSMakePoint(FILL_X(col), FILL_Y(row));
        point = [currentView convertPoint: point toView: nil];
    }

    event = [NSEvent mouseEventWithType: NSRightMouseDown
                               location: point
                          modifierFlags: 0
                              timestamp: 0
                           windowNumber: [gui_mac.current_window windowNumber]
                                context: nil
                            eventNumber: 0
                             clickCount: 0
                               pressure: 1.0];

    [NSMenu popUpContextMenu: mac_menu
                   withEvent: event
                     forView: currentView];
}

void gui_mch_enable_menu(int flag)
{
    /* menu is always active */
}

void gui_mch_set_menu_pos(int x, int y, int w, int h)
{
    /* menu position is fixed, always at the top */
}

/* Menu Handling }}} */

/* Dialog related {{{ */

char_u *gui_mch_browse(
    int saving,
    char_u *title,
    char_u *dflt,
    char_u *ext,
    char_u *initdir,
    char_u *filter)
{
    NSString *dir = nil, *file = nil;

    if (initdir != NULL)
        dir = NSStringFromVim(initdir);

    if (dflt != NULL)
        file = NSStringFromVim(dflt);

    gui_mac.selected_file = nil;
    if (saving)
    {
        NSSavePanel *panel = [NSSavePanel savePanel];

        [panel setTitle: NSStringFromVim(title)];
        [panel beginSheetForDirectory: dir
                                 file: file
                       modalForWindow: gui_mac.current_window
                        modalDelegate: gui_mac.app_delegate
                       didEndSelector: @selector(panelDidEnd:code:context:)
                          contextInfo: NULL];
    } else
    {
        NSOpenPanel *panel = [NSOpenPanel openPanel];

        [panel setTitle: NSStringFromVim(title)];
        [panel setAllowsMultipleSelection: NO];

        [panel beginSheetForDirectory: dir
                                 file: file
                                types: nil
                       modalForWindow: gui_mac.current_window
                        modalDelegate: gui_mac.app_delegate
                       didEndSelector: @selector(panelDidEnd:code:context:)
                          contextInfo: NULL];
    }

    [NSApp run];
    [gui_mac.current_window makeKeyAndOrderFront: nil];

    if (! gui_mac.selected_file)
        return NULL;

    char_u *s = vim_strsave((char_u *) [gui_mac.selected_file fileSystemRepresentation]);
    [gui_mac.selected_file release];
    gui_mac.selected_file = nil;

    return s;
}

int gui_mch_dialog(
    int     type,
    char_u  *title,
    char_u  *message,
    char_u  *buttons,
    int     dfltbutton,
    char_u  *textfield)
{
    gui_mac_redraw();

    VIMAlert *alert = [[VIMAlert alloc] init];
    char_u  *p, button_title[VIM_MAX_BUTTON_TITLE];
    int len;
    NSString *textFieldString = @"", *messageString;

    if (textfield)
    {
        if (textfield[0] != '\0')
            textFieldString = NSStringFromVim(textfield);

        [alert setTextFieldString: textFieldString];
    }

    [alert setAlertStyle: NSAlertStyleFromVim(type)];

    if (title)
        [alert setMessageText: NSStringFromVim(title)];

    if (message)
    {
        messageString = NSStringFromVim(message);

        if (! title)
        {
            // HACK! If there is a '\n\n' or '\n' sequence in the message, then
            // make the part up to there into the title.  We only do this
            // because Vim has lots of dialogs without a title and they look
            // ugly that way.
            // TODO: Fix the actual dialog texts.
            NSRange eolRange = [messageString rangeOfString: @"\n\n"];
            if (eolRange.location == NSNotFound)
                eolRange = [messageString rangeOfString: @"\n"];

            if (eolRange.location != NSNotFound)
            {
                [alert setMessageText: [messageString substringToIndex: eolRange.location]];

                messageString = [messageString substringFromIndex: NSMaxRange(eolRange)];
            }
        }

        [alert setInformativeText: messageString];
    } else if (textFieldString)
    {
        // Make sure there is always room for the input text field.
        [alert setInformativeText: @""];
    }

    for (p = buttons; *p != 0; p++)
    {
        len = 0;

        for (; *p != DLG_BUTTON_SEP && *p != '\0' && len < VIM_MAX_BUTTON_TITLE - 1; p++)
            if (*p != DLG_HOTKEY_CHAR)
                button_title[len++] = *p;

        button_title[len] = '\0';
        [alert addButtonWithTitle: NSStringFromVim(button_title)];

        if (*p == '\0')
            break;
    }

    [alert beginSheetModalForWindow: gui_mac.current_window
                      modalDelegate: gui_mac.app_delegate
                     didEndSelector: @selector(alertDidEnd:returnCode:contextInfo:)
                        contextInfo: (void *) textfield];

    /* Because vim runs it's own event loop, when it's calling gui_mch_dialog(),
     * maybe the event loop is stopped, then no one will receive and dispatch
     * events during the modal dialog opens, then button clicked event won't be
     * received, so here we must run an event loop and try to receive that event
     * inside this loop. */
    [NSApp run];
    [gui_mac.current_window makeKeyAndOrderFront: nil];

    [alert release];

    gui_mac_redraw();
    /* The result vim expected start from 1 */
    return gui_mac.dialog_button;
}

/* Dialog related }}} */

/* Color related {{{ */

/* Colors Macros */
#define RGB(r,g,b)  ((r) << 16) + ((g) << 8) + (b)
#define Red(c)      ((c & 0x00FF0000) >> 16)
#define Green(c)    ((c & 0x0000FF00) >>  8)
#define Blue(c)     ((c & 0x000000FF) >>  0)

long_u gui_mch_get_rgb(guicolor_T pixel)
{
    return (Red(pixel) << 16) + (Green(pixel) << 8) + Blue(pixel);
}

void gui_mch_new_colors()
{
}

guicolor_T gui_mch_get_color(char_u *name)
{
    typedef struct guicolor_tTable
    {
        char        *name;
        guicolor_T  color;
    } guicolor_tTable;

    /*
     * The comment at the end of each line is the source
     * (Mac, Window, Unix) and the number is the unix rgb.txt value
     */
    static guicolor_tTable table[] =
    {
    { "Black",      RGB(0x00, 0x00, 0x00) },
    { "darkgray",   RGB(0x80, 0x80, 0x80) }, /*W*/
    { "darkgrey",   RGB(0x80, 0x80, 0x80) }, /*W*/
    { "Gray",       RGB(0xC0, 0xC0, 0xC0) }, /*W*/
    { "Grey",       RGB(0xC0, 0xC0, 0xC0) }, /*W*/
    { "lightgray",  RGB(0xE0, 0xE0, 0xE0) }, /*W*/
    { "lightgrey",  RGB(0xE0, 0xE0, 0xE0) }, /*W*/
    { "gray10",     RGB(0x1A, 0x1A, 0x1A) }, /*W*/
    { "grey10",     RGB(0x1A, 0x1A, 0x1A) }, /*W*/
    { "gray20",     RGB(0x33, 0x33, 0x33) }, /*W*/
    { "grey20",     RGB(0x33, 0x33, 0x33) }, /*W*/
    { "gray30",     RGB(0x4D, 0x4D, 0x4D) }, /*W*/
    { "grey30",     RGB(0x4D, 0x4D, 0x4D) }, /*W*/
    { "gray40",     RGB(0x66, 0x66, 0x66) }, /*W*/
    { "grey40",     RGB(0x66, 0x66, 0x66) }, /*W*/
    { "gray50",     RGB(0x7F, 0x7F, 0x7F) }, /*W*/
    { "grey50",     RGB(0x7F, 0x7F, 0x7F) }, /*W*/
    { "gray60",     RGB(0x99, 0x99, 0x99) }, /*W*/
    { "grey60",     RGB(0x99, 0x99, 0x99) }, /*W*/
    { "gray70",     RGB(0xB3, 0xB3, 0xB3) }, /*W*/
    { "grey70",     RGB(0xB3, 0xB3, 0xB3) }, /*W*/
    { "gray80",     RGB(0xCC, 0xCC, 0xCC) }, /*W*/
    { "grey80",     RGB(0xCC, 0xCC, 0xCC) }, /*W*/
    { "gray90",     RGB(0xE5, 0xE5, 0xE5) }, /*W*/
    { "grey90",     RGB(0xE5, 0xE5, 0xE5) }, /*W*/
    { "white",      RGB(0xFF, 0xFF, 0xFF) },
    { "darkred",    RGB(0x80, 0x00, 0x00) }, /*W*/
    { "red",        RGB(0xDD, 0x08, 0x06) }, /*M*/
    { "lightred",   RGB(0xFF, 0xA0, 0xA0) }, /*W*/
    { "DarkBlue",   RGB(0x00, 0x00, 0x80) }, /*W*/
    { "Blue",       RGB(0x00, 0x00, 0xD4) }, /*M*/
    { "lightblue",  RGB(0xA0, 0xA0, 0xFF) }, /*W*/
    { "DarkGreen",  RGB(0x00, 0x80, 0x00) }, /*W*/
    { "Green",      RGB(0x00, 0x64, 0x11) }, /*M*/
    { "lightgreen", RGB(0xA0, 0xFF, 0xA0) }, /*W*/
    { "DarkCyan",   RGB(0x00, 0x80, 0x80) }, /*W ?0x307D7E */
    { "cyan",       RGB(0x02, 0xAB, 0xEA) }, /*M*/
    { "lightcyan",  RGB(0xA0, 0xFF, 0xFF) }, /*W*/
    { "darkmagenta",RGB(0x80, 0x00, 0x80) }, /*W*/
    { "magenta",    RGB(0xF2, 0x08, 0x84) }, /*M*/
    { "lightmagenta",RGB(0xF0, 0xA0, 0xF0) }, /*W*/
    { "brown",      RGB(0x80, 0x40, 0x40) }, /*W*/
    { "yellow",     RGB(0xFC, 0xF3, 0x05) }, /*M*/
    { "lightyellow",RGB(0xFF, 0xFF, 0xA0) }, /*M*/
    { "darkyellow", RGB(0xBB, 0xBB, 0x00) }, /*U*/
    { "SeaGreen",   RGB(0x2E, 0x8B, 0x57) }, /*W 0x4E8975 */
    { "orange",     RGB(0xFC, 0x80, 0x00) }, /*W 0xF87A17 */
    { "Purple",     RGB(0xA0, 0x20, 0xF0) }, /*W 0x8e35e5 */
    { "SlateBlue",  RGB(0x6A, 0x5A, 0xCD) }, /*W 0x737CA1 */
    { "Violet",     RGB(0x8D, 0x38, 0xC9) }, /*U*/
    };

    int r, g, b;
    int i;

    if (name[0] == '#' && strlen((char *) name) == 7)
    {
        /* Name is in "#rrggbb" format */
        r = gui_mac_hex_digit(name[1]) * 16 + gui_mac_hex_digit(name[2]);
        g = gui_mac_hex_digit(name[3]) * 16 + gui_mac_hex_digit(name[4]);
        b = gui_mac_hex_digit(name[5]) * 16 + gui_mac_hex_digit(name[6]);
        if (r < 0 || g < 0 || b < 0)
            return INVALCOLOR;
        return RGB(r, g, b);
    }
    else
    {
        if (STRICMP(name, "hilite") == 0)
        {
            float red, green, blue, alpha;
            [[NSColor highlightColor] getRed: &red
                                       green: &green
                                        blue: &blue
                                       alpha: &alpha];
            return (RGB(r, g, b));
        }

        /* Check if the name is one of the colors we know */
        for (i = 0; i < sizeof(table) / sizeof(table[0]); i++)
            if (STRICMP(name, table[i].name) == 0)
            return table[i].color;
    }

    /*
     * Last attempt. Look in the file "$VIM/rgb.txt".
     */
#define LINE_LEN 100
    FILE    *fd;
    char    line[LINE_LEN];
    char_u  *fname;

    fname = expand_env_save((char_u *)"$VIMRUNTIME/rgb.txt");
    if (fname == NULL)
        return INVALCOLOR;

    fd = fopen((char *)fname, "rt");
    vim_free(fname);
    if (fd == NULL)
        return INVALCOLOR;

    while (! feof(fd))
    {
        int     len;
        int     pos;
        char    *color;

        fgets(line, LINE_LEN, fd);
        len = strlen(line);

        if (len <= 1 || line[len-1] != '\n')
        continue;

        line[len-1] = '\0';

        i = sscanf(line, "%d %d %d %n", &r, &g, &b, &pos);
        if (i != 3)
        continue;

        color = line + pos;

        if (STRICMP(color, name) == 0)
        {
            fclose(fd);
            return (guicolor_T) RGB(r, g, b);
        }
    }

    fclose(fd);

    return INVALCOLOR;
}

void gui_mch_set_fg_color(guicolor_T color)
{
    gui_mac.fg_color = NSColorFromGuiColor(color, 1.0);

    // TODO: should set for all views
    [currentView setMarkedTextAttribute: gui_mac.fg_color
                                 forKey: NSForegroundColorAttributeName];
}

void gui_mch_set_bg_color(guicolor_T color)
{
    gui_mac.bg_color = NSColorFromGuiColor(color, gui_mac.bg_alpha);

    // TODO: should set for all views
    [currentView setMarkedTextAttribute: gui_mac.bg_color
                                 forKey: NSBackgroundColorAttributeName];
}

void gui_mch_set_sp_color(guicolor_T color)
{
    gui_mac.sp_color = NSColorFromGuiColor(color, 1.0);
}

/* Color related }}} */

/* Drawing related {{{ */

void gui_mch_flush()
{
    // gui_mac_msg(MSG_DEBUG, @"gui_mch_flush");
    // gui_mac_redraw();
}

static inline CGRect CGRectFromNSRect(NSRect nsRect) { return *(CGRect*)&nsRect; }

void gui_mch_invert_rectangle(int r, int c, int nr, int nc)
{
    NSRect rect;

    gui_mac_begin_drawing();

    rect = NSMakeRect(FILL_X(c),
                      FILL_Y(r),
                      FILL_X(nc),
                      FILL_Y(nr));

    CGContextRef context = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState (context);
    CGContextSetBlendMode(context, kCGBlendModeDifference);
    CGContextSetRGBFillColor (context, 1.0, 1.0, 1.0, 1.0);
    CGContextFillRect (context, CGRectFromNSRect(rect));
    CGContextRestoreGState (context);

    gui_mac_end_drawing();;
}

void gui_mch_flash(int msec)
{
}

void gui_mch_clear_all()
{
    [currentView clearAll];
}

void gui_mch_clear_block(int row1, int col1, int row2, int col2)
{
    NSRect rect;

    gui_mch_set_bg_color(gui.back_pixel);

    gui_mac_begin_drawing();

    [gui_mac.bg_color set];
    rect = NSRectFromVim(row1, col1, row2, col2);

    NSRectFill(rect);

    gui_mac_end_drawing();
}

void gui_mch_delete_lines(int row, int num_lines)
{
    NSRect src_rect;

    src_rect = NSRectFromVim(row + num_lines,            // row1
                             gui.scroll_region_left,     // col1
                             gui.scroll_region_bot,      // row2
                             gui.scroll_region_right);   // col2

    // move src_dest up for numlines
    gui_mac_scroll_rect(src_rect, -num_lines);

    gui_clear_block(gui.scroll_region_bot - num_lines + 1,
                    gui.scroll_region_left,
                    gui.scroll_region_bot,
                    gui.scroll_region_right);
}

void gui_mch_insert_lines(int row, int num_lines)
{
    NSRect src_rect;

    src_rect = NSRectFromVim(row,                               // row1
                             gui.scroll_region_left,            // col1
                             gui.scroll_region_bot - num_lines, // row2
                             gui.scroll_region_right);          // col2

    // move src_dest down for num_lines
    gui_mac_scroll_rect(src_rect, num_lines);

    /* Update gui.cursor_row if the cursor scrolled or copied over */
    if (gui.cursor_row >= gui.row
        && gui.cursor_col >= gui.scroll_region_left
        && gui.cursor_col <= gui.scroll_region_right)
    {
        if (gui.cursor_row <= gui.scroll_region_bot - num_lines)
            gui.cursor_row += num_lines;
        else if (gui.cursor_row <= gui.scroll_region_bot)
            gui.cursor_is_valid = FALSE;
    }

    gui_clear_block(row, gui.scroll_region_left,
                    row + num_lines - 1,
                    gui.scroll_region_right);
}

void gui_mch_draw_hollow_cursor(guicolor_T color)
{
}

void gui_mch_draw_part_cursor(int w, int h, guicolor_T color)
{
    NSRect rect;
    int    left;

#ifdef FEAT_RIGHTLEFT
    /* vertical line should be on the right of current point */
    if (CURSOR_BAR_RIGHT)
        left = FILL_X(gui.col + 1) - w;
    else
#endif
    left = FILL_X(gui.col);

    rect = NSMakeRect(left,
                      FILL_Y(gui.row) + gui.char_height - h,
                      w, h);

    gui_mac_begin_drawing();

    [NSColorFromGuiColor(color, 1.0) set];
    // gui_mac_msg(MSG_DEBUG, @"rect = %g %g %g %g",
    //      rect.origin.x, rect.origin.y,
    //      rect.size.width, rect.size.height);
    [NSBezierPath fillRect: rect];

    gui_mac_end_drawing();
}

void print_draw_flags(int flags)
{
    if (flags & DRAW_BOLD)
        fprintf(stderr, "bold, ");

    if (flags & DRAW_ITALIC)
        fprintf(stderr, "italic, ");

    if (flags & DRAW_UNDERL)
        fprintf(stderr, "underline");

    if (flags & DRAW_UNDERC)
        fprintf(stderr, "undercurl");

    if (flags && ! (flags & DRAW_TRANSP))
        fprintf(stderr, "\n");
}

void gui_mch_draw_string(int row, int col, char_u *s, int len, int flags)
{
    NSRect       rect;
    UniChar     *text;
    int          n;
    int          width_in_cell, last_width_in_cell = 1;

    // gui_mac_msg(MSG_DEBUG, "gui_mch_draw_string: %d, %d, %d", row, col, len);

    ATSUStyle          style = gui_mac.font_style[0];
    ATSUTextLayout     layout;
    UniCharArrayOffset offset = 0;
    UniCharCount       length, yet_to_draw = 0;

    ATSUCreateTextLayout(&layout);

    text = mac_enc_to_utf16(s, len, (size_t *) &length);
    length /= sizeof(UniChar);

    if (flags & DRAW_BOLD)
        gui_mac_atsui_style_set_boolean(style, kATSUQDBoldfaceTag, true);

    if (flags & DRAW_ITALIC)
    {
        CGAffineTransform theTransform = CGAffineTransformMakeScale(1.0, -1.0);
        theTransform.c = Fix2X(kATSItalicQDSkew);

        gui_mac_atsui_style_set_value(style, kATSUFontMatrixTag,
                                      (void *) &theTransform, sizeof(CGAffineTransform));
    }

    gui_mac_atsui_style_set_int(style, kATSUStyleRenderingOptionsTag,
                                p_antialias ? kATSStyleApplyAntiAliasing
                                            : kATSStyleNoAntiAliasing);

    ATSUSetTextPointerLocation(layout, text,
                               kATSUFromTextBeginning, kATSUToTextEnd,
                               length);

    /* Compute the length in display cells. */
    for (n = 0; n < len; n += MB_BYTE2LEN(s[n]))
    {
        width_in_cell = (*mb_ptr2cells)(s + n);

        /* probably we are switching from single byte character
         * to multibyte characters (which requires more than one
         * cell to draw) */
        if (width_in_cell != last_width_in_cell)
        {
            style = gui_mac_atsui_style_from_width(last_width_in_cell);

            ATSUSetRunStyle(layout, style, offset, yet_to_draw);
            offset += yet_to_draw;
            yet_to_draw = 0;
            last_width_in_cell = width_in_cell;
        }

        yet_to_draw++;
    }

    if (yet_to_draw)
    {
        style = gui_mac_atsui_style_from_width(width_in_cell);
        ATSUSetRunStyle(layout, style, offset, kATSUToTextEnd);
    }

    rect = NSMakeRect(FILL_X(col), FILL_Y(row),
                      gui.char_width * len,
                      gui.char_height);
    if (has_mbyte)
    {
        int cell_len = 0;
        int n;

        /* Compute the length in display cells. */
        for (n = 0; n < len; n += MB_BYTE2LEN(s[n]))
            cell_len += (*mb_ptr2cells)(s + n);

        rect.size.width = gui.char_width * cell_len;
    }

    gui_mac_begin_drawing();

    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];

    ATSUAttributeTag tags[] = { kATSUCGContextTag };
    ByteCount sizes[] = { sizeof(CGContextRef) };
    ATSUAttributeValuePtr values[] = { &context };
    ATSUSetLayoutControls(layout, 1, tags, sizes, values);

    if (! (flags & DRAW_TRANSP))
    {
        [gui_mac.bg_color set];
        NSRectFill(rect);
    }

    [gui_mac.fg_color set];

    ATSUSetTransientFontMatching(layout, TRUE);
    ATSUDrawText(layout,
                 kATSUFromTextBeginning,
                 kATSUToTextEnd,
                 X2Fix(rect.origin.x),
                 X2Fix(TEXT_Y(row)));

    if (flags & DRAW_UNDERL)
    {
        [gui_mac.sp_color set];
        NSRectFill(NSMakeRect(rect.origin.x, FILL_Y(row + 1) + VIM_UNDERLINE_OFFSET,
                              rect.size.width, VIM_UNDERLINE_HEIGHT));
    }

    if (flags & DRAW_UNDERC)
    {
        [gui_mac.sp_color set];

        float line_end_x = rect.origin.x + rect.size.width;
        int i = 0;
        NSRect line_rect = NSMakeRect(rect.origin.x,
                                      FILL_Y(row + 1) + VIM_UNDERCURL_OFFSET,
                                      VIM_UNDERCURL_DOT_WIDTH, VIM_UNDERCURL_HEIGHT);

        while (line_rect.origin.x < line_end_x)
        {
            if (i % 2)
                NSRectFill(line_rect);

            line_rect.origin.x += VIM_UNDERCURL_DOT_DISTANCE;
            i++;
        }
    }

    gui_mac_end_drawing();

    vim_free(text);
    ATSUDisposeTextLayout(layout);

    if (flags & DRAW_BOLD)
        gui_mac_atsui_style_set_boolean(style, kATSUQDBoldfaceTag, false);

    if (flags & DRAW_ITALIC)
    {
        // Reset the matrix
        CGAffineTransform theTransform = CGAffineTransformMakeScale(1.0, -1.0);

        gui_mac_atsui_style_set_value(style, kATSUFontMatrixTag,
                                     (void *) &theTransform, sizeof(CGAffineTransform));
        // gui_mac_atsui_style_set_boolean(style, kATSUQDItalicTag, false);
    }
}

/* Drawing related }}} */

/* Clipboard related {{{ */

void clip_mch_lose_selection(VimClipboard *cbd)
{
}

int clip_mch_own_selection(VimClipboard *cbd)
{
    return OK;
}

/* copy from system clipboard, paste to vim */
void clip_mch_set_selection(VimClipboard *cbd)
{
    // If the '*' register isn't already filled in, fill it in now.
    cbd->owned = TRUE;
    clip_get_selection(cbd);
    cbd->owned = FALSE;

    // Get the text to put on the pasteboard.
    long_u len = 0; char_u *str = 0;
    int type = clip_convert_selection(&str, &len, cbd);
    if (type < 0)
        return;

    NSString *string = [[NSString alloc] initWithBytes: str
                                                length: len
                                              encoding: NSUTF8StringEncoding];

    NSPasteboard *pb = [NSPasteboard generalPasteboard];

    [pb declareTypes: [NSArray arrayWithObject: NSStringPboardType] owner: nil];
    [pb setString: string
          forType: NSStringPboardType];

    [string release];
    vim_free(str);
}

/* copy from vim, paste to system clipboard */
void clip_mch_request_selection(VimClipboard *cbd)
{
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *type = [pb availableTypeFromArray: [NSArray arrayWithObject: NSStringPboardType]];

    if (type)
    {
        NSMutableString *string = [[pb stringForType: NSStringPboardType] mutableCopy];

        // Replace unrecognized end-of-line sequences with \x0a (line feed).
        NSRange range = NSMakeRange(0, [string length]);
        unsigned n = [string replaceOccurrencesOfString: @"\x0d\x0a"
                                             withString: @"\x0a"
                                                options: 0
                                                  range: range];
        if (n == 0)
            n = [string replaceOccurrencesOfString: @"\x0d"
                                        withString: @"\x0a"
                                           options: 0
                                             range: range];

        // Scan for newline character to decide whether the string should be
        // pasted linewise or characterwise.
        int char_type = MCHAR;
        if (0 < n || NSNotFound != [string rangeOfString: @"\n"].location)
            char_type = MLINE;

        const char *utf8chars = [string UTF8String];
        clip_yank_selection(char_type, (char_u*) utf8chars, strlen(utf8chars), cbd);
    }
}

/* Clipboard related }}} */

/* Scrollbar related {{{ */

const char *scrollbar_desc(scrollbar_T *sb)
{
    switch (sb->type)
    {
    case SBAR_LEFT:
        return "LEFT";

    case SBAR_RIGHT:
        return "RIGHT";

    case SBAR_BOTTOM:
        return "BOTTOM";

    default:
        return "NONE";
    }
}

void gui_mch_create_scrollbar(scrollbar_T *sb, int orient)
{
    gui_mac_msg(MSG_INFO, @"gui_mch_create_scrollbar: ident = %ld, "
                "type = %s, value = %ld, size = %ld, "
                "max = %ld, top = %d, height = %d, "
                "width = %d, status_height = %d, %s",
                sb->ident, scrollbar_desc(sb),
                sb->value, sb->size, sb->max,
                sb->top, sb->height, sb->width, sb->status_height,
                orient == SBAR_HORIZ ? "H" : "V");
    VIMScroller *scroller;

    scroller = [[VIMScroller alloc] initWithVimScrollbar: sb
                                             orientation: orient];
    sb->scroller = (void *) scroller;
}

void gui_mch_destroy_scrollbar(scrollbar_T *sb)
{
    VIMScroller *scroller = gui_mac_get_scroller(sb);

    gui_mac_msg(MSG_INFO, @"gui_mch_destroy_scrollbar: %s (%ld)",
                scrollbar_desc(sb), sb->ident);

    sb->enabled = FALSE;
    gui_mac_update_scrollbar(sb);

    if (scroller != nil)
        [scroller release];

    sb->scroller = NULL;
}

void gui_mch_enable_scrollbar(scrollbar_T *sb, int flag)
{
    gui_mac_msg(MSG_INFO, @"%s scrollbar: %s (%d)",
                flag == TRUE ? "enable" : "disable", scrollbar_desc(sb),
                sb->ident);

    sb->enabled = flag;
    gui_mac_update_scrollbar(sb);

    VIMScroller *scroller = gui_mac_get_scroller(sb);
    [scroller setHidden: flag == TRUE ? NO : YES];
}

void gui_mch_set_scrollbar_pos(
    scrollbar_T *sb,
    int x,
    int y,
    int w,
    int h)
{
    gui_mac_msg(MSG_INFO, @"set scrollbar pos: %s (%ld), (%d, %d, %d, %d)",
                scrollbar_desc(sb), sb->ident, x, y, w, h);

    gui_mac_update_scrollbar(sb);

    VIMScroller *scroller = gui_mac_get_scroller(sb);
    [scroller setFrame: NSMakeRect(x, y, w, h)];
}

void gui_mch_set_scrollbar_thumb(
    scrollbar_T *sb,
    long val,
    long size,
    long max)
{
    VIMScroller *scroller = (VIMScroller *) sb->scroller;
    [scroller setThumbValue: val
                       size: size
                        max: max];
}

/* Scrollbar related }}} */

/* Mouse related {{{ */

void gui_mch_getmouse(int *x, int *y)
{

}

void gui_mch_setmouse(int x, int y)
{
}

/* Mouse related }}} */

/* Cursor blinking stuff {{{ */

enum blink_state {
    BLINK_NONE,     /* not blinking at all */
    BLINK_OFF,      /* blinking, cursor is not shown */
    BLINK_ON        /* blinking, cursor is shown */
};

void gui_mch_set_blinking(long wait, long on, long off)
{
    gui_mac.blink_wait = wait;
    gui_mac.blink_on   = on;
    gui_mac.blink_off  = off;
}

void gui_mch_stop_blink()
{
    return;

    [gui_mac.blink_timer invalidate];

    if (gui_mac.blink_state == BLINK_OFF)
        gui_update_cursor(TRUE, FALSE);

    gui_mac.blink_state = BLINK_NONE;
    gui_mac.blink_timer = nil;
}

void gui_mch_start_blink()
{
    return;

    if (gui_mac.blink_timer != nil)
        [gui_mac.blink_timer invalidate];

    if (gui_mac.blink_wait && gui_mac.blink_on &&
        gui_mac.blink_off && gui.in_focus)
    {
        gui_mac.blink_timer = [NSTimer scheduledTimerWithTimeInterval: gui_mac.blink_wait / 1000.0
                                         target: gui_mac.app_delegate
                                       selector: @selector(blinkCursorTimer:)
                                       userInfo: nil
                                        repeats: NO];
        gui_mac.blink_state = BLINK_ON;
        gui_update_cursor(TRUE, FALSE);
    }
}

/* Cursor blinking stuff }}} */

/* GUI tab stuff {{{ */

void gui_mch_set_curtab(int nr)
{
    gui_mac_msg(MSG_INFO, @"gui_mch_set_curtab(%d)", nr);
}

void gui_mch_show_tabline(int showit)
{
    VIMContentView *view;

    gui_mac.showing_tabline = showit;

    gui_mac_msg(MSG_INFO, @"gui_mch_show_tabline: %s", showit ? "YES" : "NO");
    view = [gui_mac.current_window contentView];
    [[view tabBarControl] setHidden: (showit ? NO : YES)];
    // NSShowRect("tabBarControl", [[view tabBarControl] frame]);
}

int gui_mch_showing_tabline()
{
    return gui_mac.showing_tabline == YES;
}

void gui_mch_update_tabline()
{
    tabpage_T      *tp;
    VIMContentView *view = [gui_mac.current_window contentView];
    NSTabView      *tabView = [view tabView];
    NSArray        *tabViewItems = [[view tabBarControl] representedTabViewItems];
    int             i, j, originalTabCount = [tabViewItems count];
    NSTabViewItem  *item;
    int             currentTabIndex = tabpage_index(curtab) - 1;

    gui_mac_msg(MSG_INFO, @"gui_mch_update_tabline: cti = %d, otc = %d",
                currentTabIndex, originalTabCount);

    for (tp = first_tabpage, i = 0;
         tp != NULL;
         tp = tp->tp_next, i++)
    {
        // This function puts the label of the tab in the global 'NameBuff'.
        get_tabline_label(tp, FALSE);
        char_u *s = NameBuff;
        int len = STRLEN(s);
        if (len <= 0) continue;

        s = CONVERT_TO_UTF8(s);
        // gui_mac_msg(MSG_DEBUG, @"label (%d): %s", i, s);
        if (i >= originalTabCount)
        {
            gui_mac_begin_tab_action();
            item = [view addNewTabViewItem];
            gui_mac_end_tab_action();
        }
        else
            item = [tabViewItems objectAtIndex: i];

        [item setLabel: NSStringFromVim(s)];

        CONVERT_TO_UTF8_FREE(s);
    }

    // gui_mac_msg(MSG_DEBUG, @"total tab count = %d", i);
    for (j = originalTabCount - 1; j >= i; j--)
    {
        NSTabViewItem *item = [tabViewItems objectAtIndex: i];
        [tabView removeTabViewItem: item];
    }

    tabViewItems = [[view tabBarControl] representedTabViewItems];
    if (currentTabIndex < [tabViewItems count])
    {
        item = [tabViewItems objectAtIndex: currentTabIndex];

        gui_mac_begin_tab_action();
        [tabView selectTabViewItem: item];
        gui_mac_end_tab_action();
    }
}

/* GUI tab stuff }}} */

/* GUI popup menu stuff {{{ */

void gui_mch_pum_display(pumitem_T *array, int size, int selected)
{

}

/* GUI popup menu stuff }}} */

/* Private Functions {{{1 */

int gui_mac_hex_digit(int c)
{
    if (isdigit(c))
        return c - '0';

    c = TOLOWER_ASC(c);

    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;

    return -1000;
}

NSAlertStyle NSAlertStyleFromVim(int type)
{
    switch (type)
    {
    case VIM_GENERIC:
    case VIM_INFO:
    case VIM_QUESTION:
        return NSInformationalAlertStyle;

    case VIM_WARNING:
        return NSWarningAlertStyle;

    case VIM_ERROR:
        return NSCriticalAlertStyle;

    default:
        return NSInformationalAlertStyle;
    }
}

NSColor *NSColorFromGuiColor(guicolor_T color, float alpha)
{
    float red, green, blue;

    red   = (float) Red(color) / (float) 0xFF;
    green = (float) Green(color) / (float) 0xFF;
    blue  = (float) Blue(color) / (float) 0xFF;

    return [NSColor colorWithDeviceRed: red
                                 green: green
                                  blue: blue
                                 alpha: alpha];
}

NSRect NSRectFromVim(int row1, int col1, int row2, int col2)
{
    return NSMakeRect(FILL_X(col1), FILL_Y(row1),
                      FILL_X(col2 + 1) - FILL_X(col1),
                      FILL_Y(row2 + 1) - FILL_Y(row1));
}

void gui_mac_msg(int level, NSString *fmt, ...)
{
#if GUI_MAC_DEBUG
    if (level >= gui_mac.debug_level)
    {
        va_list ap;

        va_start(ap, fmt);
        NSLogv(fmt, ap);
        va_end(ap);
    }
#endif
}

/* Application Related Utilities {{{2 */

/* Force it to update instantly */
void gui_mac_update()
{
    gui_mac_send_dummy_event();
    gui_mac_stop_app(YES);
}

void gui_mac_send_dummy_event()
{
    NSEvent *event;
    event = [NSEvent otherEventWithType: NSApplicationDefined
                               location: NSZeroPoint
                          modifierFlags: 0
                              timestamp: 0
                           windowNumber: 0
                                context: nil
                                subtype: 0
                                  data1: 0
                                  data2: 0];
    [NSApp postEvent: event atStart: YES];
}

@implementation VimAppController

- (void) application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    char_u **fnames;
    unsigned int i, count;

    count = [filenames count];
    fnames = (char_u **) alloc(count * sizeof(char_u *));

    for (i = 0; i < count; i++)
    {
        NSString *filename = [filenames objectAtIndex: i];

        fnames[i] = vim_strsave((char_u *) [filename fileSystemRepresentation]);
    }

    shorten_filenames(fnames, count);

    /* if vim is starting, we can not use handle_drop, instead, we
     * put files into global alist, vim will open those files later
     * at appropriate time */
    if (starting > 0)
    {
        int i;
        char_u *p;

        /* these are the initial files dropped on the Vim icon */
        for (i = 0 ; i < count; i++)
        {
            if (ga_grow(&global_alist.al_ga, 1) == FAIL ||
                (p = vim_strsave(fnames[i])) == NULL)
                mch_exit(2);
            else
                alist_add(&global_alist, p, 2);
        }

        /* Change directory to the location of the first file. */
        if (GARGCOUNT > 0 && vim_chdirfile(alist_name(&GARGLIST[0])) == OK)
            shorten_fnames(TRUE);

        goto finish;
    }

    char_u *p = vim_strsave(fnames[0]);
    handle_drop(count, fnames, FALSE);

    if (p != NULL)
    {
        if (mch_isdir(p))
        {
            if (mch_chdir((char *)p) == 0)
                shorten_fnames(TRUE);
        }
        else if (vim_chdirfile(p) == OK)
            shorten_fnames(TRUE);

        vim_free(p);
    }

    /* Update the screen display */
    update_screen(NOT_VALID);
#ifdef FEAT_MENU
    gui_update_menus(0);
#endif
    setcursor();
    out_flush();

    gui_mac_redraw();

finish:
    [NSApp replyToOpenOrPrint: NSApplicationDelegateReplySuccess];
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

- (NSApplicationTerminateReply) applicationShouldTerminate:(NSApplication *)sender
{
    int reply = NSTerminateNow;
    BOOL modifiedBuffers = NO;

    buf_T *buf;
    for (buf = firstbuf; buf != NULL; buf = buf->b_next)
    {
        if (bufIsChanged(buf))
        {
            modifiedBuffers = YES;
            break;
        }
    }

    if (modifiedBuffers) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle: @"Quit"];
        [alert addButtonWithTitle: @"Cancel"];
        [alert setMessageText: @"Quit without saving?"];
        [alert setInformativeText: @"There are modified buffers, "
           " if you quit now all changes will be lost.  Quit anyway?"];
        [alert setAlertStyle: NSWarningAlertStyle];

        [alert beginSheetModalForWindow: gui_mac.current_window
                          modalDelegate: gui_mac.app_delegate
                         didEndSelector: @selector(alertDidEnd:returnCode:contextInfo:)
                            contextInfo: NULL];
        [NSApp run];

        if (gui_mac.dialog_button != 1) {
            reply = NSTerminateCancel;
            [gui_mac.current_window makeKeyAndOrderFront: nil];
        }

        [alert release];
    }

    return reply;
}

- (void) applicationDidFinishLaunching:(NSNotification *)aNotification
{
}

- (BOOL) windowShouldClose:(id)sender
{
    if ([sender isEqual: gui_mac.current_window])
    {
        gui_shell_closed();
        return NO;
    }

    return YES;
}

- (void) alertDidEnd:(VIMAlert *)alert returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    gui_mac.dialog_button = returnCode - NSAlertFirstButtonReturn + 1;

    if ([alert isKindOfClass: [VIMAlert class]] &&
        [alert textField] && contextInfo)
        STRCPY((char_u *) contextInfo, [[[alert textField] stringValue] UTF8String]);

    [NSApp stop: self];
}

- (void) panelDidEnd:(NSSavePanel *)panel code:(int)code context:(void *)context
{
    NSString *string = (code == NSOKButton) ? [panel filename] : nil;
    gui_mac.selected_file = [string copy];

    [NSApp stop: self];
}

- (void) initializeApplicationTimer:(NSTimer *)timer
{
    [NSApp stop: self];

    gui_mac_send_dummy_event();
}

- (void) blinkCursorTimer:(NSTimer *)timer
{
    NSTimeInterval on_time, off_time;

    gui_mac_msg(MSG_DEBUG, @"blinkCursorTimer: %s",
                gui_mac.blink_state == BLINK_ON ? "BLINK_ON"
                                                : (gui_mac.blink_state == BLINK_OFF ? "BLINK_OFF"
                                                                                    : "BLINK_NONE"));

    [gui_mac.blink_timer invalidate];
    if (gui_mac.blink_state == BLINK_ON)
    {
        gui_undraw_cursor();
        gui_mac.blink_state = BLINK_OFF;

        off_time = gui_mac.blink_off / 1000.0;
        gui_mac.blink_timer = [NSTimer scheduledTimerWithTimeInterval: off_time
                                         target: gui_mac.app_delegate
                                       selector: @selector(blinkCursorTimer:)
                                       userInfo: nil
                                        repeats: NO];
    }
    else if (gui_mac.blink_state == BLINK_OFF)
    {
        gui_update_cursor(TRUE, FALSE);
        gui_mac.blink_state = BLINK_ON;

        on_time = gui_mac.blink_on / 1000.0;
        gui_mac.blink_timer = [NSTimer scheduledTimerWithTimeInterval: on_time
                                         target: gui_mac.app_delegate
                                       selector: @selector(blinkCursorTimer:)
                                       userInfo: nil
                                        repeats: NO];
    }
}

- (void) menuAction:(id)sender
{
    NSMenuItem *item = (NSMenuItem *) sender;
    vimmenu_T *menu;

    /* NSMenuItem does not have a specifically
     * made "user data" to contain vimmenu_T,
     * so we have to use this trick, cast an
     * int to a pointer, hopefully in all Macs
     * they are in the same length */
    if ((menu = (vimmenu_T *)[item tag]) == NULL)
        return;

    if (menu->cb != NULL)
        gui_menu_cb(menu);

    // gui_mac_redraw();

    /* HACK: NSApp won't react directly until some event comes,
     * while clicking a menu item does not send any event */
    gui_mac_update();
}

- (void) applicationWillTerminate:(NSNotification *)aNotification
{
    // [gui_mac.app_pool release];
    mch_exit(0);
}

- (void) windowWillClose:(NSNotification *)aNotification
{
    if ([aNotification object] != [NSFontPanel sharedFontPanel])
        return;

    NSFont *selected_font = [[NSFontManager sharedFontManager] selectedFont];
    // gui_mac_msg(MSG_DEBUG, @"font panel will close: %@", selected_font);

    gui_mac.selected_font = selected_font;
    [NSApp stop: self];
}

- (void) windowDidResize:(NSNotification *)aNotification
{
    NSSize size;
    int width, height;

    if ([aNotification object] != gui_mac.current_window)
        return;

    // if the textView is not allocated yet, it means initialization
    // code from vim is not executed, so we don't need to pass this
    // windowDidResize event to vim
    if (! [gui_mac.current_window textView])
        return;

    size   = [[gui_mac.current_window contentView] frame].size;
    width  = (int) size.width;
    height = (int) size.height;

    // gui_mac_msg(MSG_DEBUG, @"windowDidResize: (%d, %d)", width, height);
    gui_resize_shell(width, height);

    gui_mac_update();
}

- (void) windowDidMove:(NSNotification *)notification
{
    NSRect frame = [gui_mac.current_window frame];
    NSPoint topLeft = NSMakePoint(frame.origin.x, NSMaxY(frame));
    NSString *topLeftString = NSStringFromPoint(topLeft);

    [[NSUserDefaults standardUserDefaults]
        setObject: topLeftString forKey: @"VIMTopLeftPoint"];
}

@end

/* Application Related Utilities 2}}} */

/* Menu Related Utilities {{{2 */

void gui_mac_set_application_menu()
{
    NSMenu *appleMenu, *services;
    NSMenuItem *menuItem;
    NSString *title;
    NSString *appName;

    appName = @"Vim";
    appleMenu = [[NSMenu alloc] initWithTitle: @""];

    /* Add menu items */
    title = [@"About " stringByAppendingString: appName];
    [appleMenu addItemWithTitle: title
                         action: @selector(orderFrontStandardAboutPanel:)
                  keyEquivalent: @""];

    [appleMenu addItem:[NSMenuItem separatorItem]];

    // Services Menu
    services = [[[NSMenu alloc] init] autorelease];
    [appleMenu addItemWithTitle: @"Services"
                         action: nil
                  keyEquivalent: @""];
    [appleMenu setSubmenu: services forItem: [appleMenu itemWithTitle: @"Services"]];

    // Hide AppName
    title = [@"Hide " stringByAppendingString:appName];
    [appleMenu addItemWithTitle: title action: @selector(hide:) keyEquivalent: @"h"];

    // Hide Others
    menuItem = (NSMenuItem *)[appleMenu addItemWithTitle: @"Hide Others"
                                                  action: @selector(hideOtherApplications:)
                                           keyEquivalent: @"h"];
    [menuItem setKeyEquivalentModifierMask: (NSAlternateKeyMask | NSCommandKeyMask)];

    // Show All
    [appleMenu addItemWithTitle: @"Show All"
                         action: @selector(unhideAllApplications:)
                  keyEquivalent: @""];

    [appleMenu addItem: [NSMenuItem separatorItem]];

    // Quit AppName
    title = [@"Quit " stringByAppendingString: appName];
    [appleMenu addItemWithTitle: title
                         action: @selector(terminate:)
                  keyEquivalent: @"q"];

    /* Put menu into the menubar */
    menuItem = [[NSMenuItem alloc] initWithTitle: @""
                                          action: nil
                                   keyEquivalent: @""];
    [menuItem setSubmenu: appleMenu];
    [[NSApp mainMenu] addItem: menuItem];

    /* Tell the application object that this is now the application menu */
    [NSApp setAppleMenu: appleMenu];
    [NSApp setServicesMenu: services];

    /* Finally give up our references to the objects */
    [appleMenu release];
    [menuItem release];
}

/* Menu Related Utilities 2}}} */

/* Window related Utilities {{{2 */

int gui_mac_create_window(NSRect rect)
{
    VIMWindow *window;

    window = [[VIMWindow alloc] initWithContentRect: rect];
    gui_mac.current_window = window;

    [NSApp activateIgnoringOtherApps: YES];

    return OK;
}

NSWindow *gui_mac_get_window(NSRect rect)
{
    if (gui_mac.current_window == nil)
        gui_mac_create_window(rect);

    return gui_mac.current_window;
}

void gui_mac_open_window()
{
    NSWindow *window = gui_mac.current_window;
    NSPoint topLeft = NSZeroPoint;

    NSString *topLeftString =
        [[NSUserDefaults standardUserDefaults] stringForKey: @"VIMTopLeftPoint"];
    if (topLeftString)
        topLeft = NSPointFromString(topLeftString);

    if (NSEqualPoints(topLeft, NSZeroPoint))
        [window center];
    else
        [window setFrameTopLeftPoint: topLeft];

    [window makeKeyAndOrderFront: nil];
}

/* Window related Utilities 2}}} */

/* View related Utilities 2{{{ */

@implementation VIMContentView

- (id) initWithFrame:(NSRect)rect
{
    if ([super initWithFrame: rect])
    {
        // NSShowRect("VIMContentView initWithFrame", rect);
        tabView = [[NSTabView alloc] initWithFrame:NSZeroRect];
        NSRect tabFrame = NSMakeRect(0, 0,
                                     rect.size.width, gui.tabline_height);
        tabBarControl = [[PSMTabBarControl alloc] initWithFrame: tabFrame];
        [tabView setDelegate: tabBarControl];

        [tabBarControl setTabView: tabView];
        [tabBarControl setDelegate: self];
        [tabBarControl setHidden: YES];

        [tabBarControl setCellMinWidth: 64];
        [tabBarControl setCellMaxWidth: 64 * 6];
        [tabBarControl setCellOptimumWidth: 132];

        [tabBarControl setAutoresizingMask: NSViewWidthSizable | NSViewMaxYMargin];

        [tabBarControl awakeFromNib];
        [self addSubview: tabBarControl];
    }

    return self;
}

- (void) dealloc
{
    [tabBarControl release];
    [tabView release];

    [super dealloc];
}

- (PSMTabBarControl *) tabBarControl
{
    return tabBarControl;
}

- (NSTabView *) tabView
{
    return tabView;
}

- (NSTabViewItem *) addNewTabViewItem
{
    NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier: nil];
    [tabView addTabViewItem: item];
    [item release];
    return item;
}

- (BOOL) isFlipped
{
    return YES;
}

- (void) drawRect:(NSRect)rect
{
    [[NSColor whiteColor] set];
    NSRectFill(rect);
}

/* PSMTabBarControl delegate {{{2 */

-        (BOOL) tabView: (NSTabView *) theTabView
shouldSelectTabViewItem: (NSTabViewItem *) tabViewItem
{
    gui_mac_msg(MSG_INFO, @"tabView:shouldSelectTabViewItem: %@, %s",
                tabViewItem, gui_mac.selecting_tab == YES ? "YES" : "NO");

    if (gui_mac.selecting_tab == NO)
    {
        NSArray *tabViewItems = [tabBarControl representedTabViewItems];
        int idx = [tabViewItems indexOfObject: tabViewItem] + 1;

        send_tabline_event(idx);
        gui_mac_update();
    }

    return gui_mac.selecting_tab;
}

-       (BOOL) tabView: (NSTabView *) theTabView
shouldCloseTabViewItem: (NSTabViewItem *) tabViewItem
{
    NSArray *tabViewItems = [tabBarControl representedTabViewItems];
    int idx = [tabViewItems indexOfObject: tabViewItem] + 1;

    send_tabline_menu_event(idx, TABLINE_MENU_CLOSE);
    gui_mac_update();

    return NO;
}

-   (void) tabView: (NSTabView *) theTabView
didDragTabViewItem: (NSTabViewItem *) tabViewItem
           toIndex: (int) idx
{
    gui_mac_msg(MSG_INFO, @"tabView:didDragTabViewItem: %@ toIndex: %d",
                tabViewItem, idx);
    tabpage_move(idx);
    gui_mac_update();
}

/* PSMTabBarControl delegate 2}}} */

@end

@implementation VIMTextView

- (id) initWithFrame:(NSRect)rect
{
    if ((self = [super initWithFrame: rect])) {
        markedText = nil;
        markedTextAttributes = [[NSMutableDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithInt: (NSUnderlineStyleSingle |
                                                              NSUnderlinePatternSolid)],
                                    NSUnderlineStyleAttributeName,
                                    nil] retain];

        [self registerForDraggedTypes: [NSArray arrayWithObjects:
                    NSFilenamesPboardType, NSStringPboardType, nil]];

        if (! NSEqualRects(rect, NSZeroRect))
        {
            contentImage = [[NSImage alloc] initWithSize: rect.size];
            [contentImage setFlipped: YES];
        }
        else contentImage = nil;
    }

    return self;
}

- (void) synchronizeContentImage
{
    NSSize size = [self frame].size;

    if (! NSEqualSizes([contentImage size], size))
    {
        gui_mac_msg(MSG_INFO, @"REALLOCATE content image to: (%g, %g)",
                    size.width, size.height);
        [contentImage release];
        contentImage = [[NSImage alloc] initWithSize: size];
        [contentImage setFlipped: YES];
    }
}

- (void) viewWillStartLiveResize
{
    lastSetTitle = [[gui_mac.current_window title] retain];
    [super viewWillStartLiveResize];
}

- (void) viewDidEndLiveResize
{
    [gui_mac.current_window setTitle: lastSetTitle];
    [lastSetTitle release];
    lastSetTitle = nil;

    [super viewDidEndLiveResize];
}

- (void) dealloc
{
    [markedTextAttributes release];
    [markedText release];
    [contentImage release];
    [lastSetTitle release];

    [super dealloc];
}

- (void) beginDrawing
{
    [contentImage lockFocus];
}

- (void) endDrawing
{
    [contentImage unlockFocus];
}

- (void) clearAll
{
    gui_mch_set_bg_color(gui.back_pixel);

    [contentImage lockFocus];

    [gui_mac.bg_color set];
    NSRectFill([self bounds]);
    // NSShowRect("clearAll", [self bounds]);

    [contentImage unlockFocus];
}

- (NSAttributedString *) markedText
{
    return markedText;
}

- (void) setMarkedTextAttribute:(id)value forKey:(NSString *)key
{
    [markedTextAttributes setObject: value
                             forKey: key];
}

- (BOOL) isOpaque
{
    return YES;
}

- (BOOL) hasMarkedText
{
    return markedRange.length > 0 ? YES : NO;
}

- (NSRange) markedRange
{
    return markedRange;
}

- (NSRange) selectedRange
{
    return NSMakeRange(NSNotFound, 0);
}

- (void) setMarkedText:(id)aString selectedRange:(NSRange)selRange
{
    // gui_mac_msg(MSG_DEBUG, @"setMarkedText: %@ (%u, %u)", aString,
    //             selRange.location, selRange.length);

    markedRange = NSMakeRange(0, [aString length]);

    [markedText release];
    if ([aString isKindOfClass: [NSAttributedString class]])
        markedText = [[NSAttributedString alloc] initWithString: [aString string]
                                                     attributes: markedTextAttributes];
    else
        markedText = [[NSAttributedString alloc] initWithString: aString
                                                     attributes: markedTextAttributes];

    if (markedRange.length > 0)
    {
    } else
    {
        // gui_mac_msg(MSG_DEBUG, @"clear markedText");
        gui_update_cursor(TRUE, FALSE);
    }

    gui_mac_redraw();
}

- (void) unmarkText
{
    markedRange = NSMakeRange(NSNotFound, 0);

    // gui_mac_msg(MSG_DEBUG, @"unmarkText");
}

- (NSArray *) validAttributesForMarkedText
{
    return nil;
}

- (NSAttributedString *) attributedSubstringFromRange:(NSRange)theRange
{
    return nil;
}

- (unsigned int) characterIndexForPoint:(NSPoint)thePoint
{
    // gui_mac_msg(MSG_DEBUG, @"characterIndexForPoint: x = %g, y = %g", thePoint.x, thePoint.y);
    return NSNotFound;
}

- (NSRect) firstRectForCharacterRange:(NSRange)theRange
{
    NSRect rect = NSMakeRect(FILL_X(gui_mac.im_col),
                             FILL_Y(gui_mac.im_row + 1),
                             theRange.length * gui.char_width,
                             gui.char_height);

    rect.origin = FLIPPED_POINT(self, rect.origin);
    rect.origin = [[self window] convertBaseToScreen:
                    [self convertPoint: rect.origin toView: nil]];

    return rect;
}

- (NSInteger) conversationIdentifier
{
    return (NSInteger) self;
}

- (void) doCommandBySelector:(SEL)aSelector
{

}

#define INLINE_KEY_BUFFER_SIZE                      256
#define add_to_key_buffer(buf, len, k1, k2, k3)     { buf[len++] = k1; buf[len++] = k2; buf[len++] = k3; }

- (void) insertText:(id)aString
{
    char_u *to;
    unichar *text;
    int     i;
    size_t  u16_len, enc_len, result_len = 0;
    char_u  result[INLINE_KEY_BUFFER_SIZE];

    // gui_mac_msg(MSG_DEBUG, @"insertText: %@", aString);

    u16_len = [aString length] * 2;
    text = (unichar *) alloc(u16_len);
    if (! text)
        return;

    [aString getCharacters: text];
    to = mac_utf16_to_enc(text, u16_len, &enc_len);

    if (! to)
        return;

    /* This is basically add_to_input_buf_csi() */
    for (i = 0; i < enc_len && result_len < (INLINE_KEY_BUFFER_SIZE - 1); ++i)
    {
        result[result_len++] = to[i];
        if (to[i] == CSI)
        {
            result[result_len++] = KS_EXTRA;
            result[result_len++] = (int)KE_CSI;
        }
    }
    vim_free(to);

    /* clear marked text */
    markedRange = NSMakeRange(NSNotFound, 0);
    [markedText release];
    markedText = nil;

    if (result_len > 0)
    {
        add_to_input_buf(result, result_len);
        gui_mac_stop_app(YES);
    }
}

#define LIGHT_WEIGHT_LIVE_RESIZE    0

- (void) drawRect:(NSRect)rect
{
#if 0
    gui_mac_msg(MSG_INFO, @"drawRect: (%f, %f), (%f, %f)",
                rect.origin.x, rect.origin.y,
                rect.size.width, rect.size.height);
#endif
#if LIGHTWEIDHT_LIVE_RESIZE
    if ([self inLiveResize])
    {
        NSFont *font;
        NSString *size_desc;
        NSDictionary *attrib;

        [NSColorFromGuiColor(gui.back_pixel, gui_mac.bg_alpha) set];
        [NSBezierPath fillRect: rect];

        font = [NSFont boldSystemFontOfSize: 48.0];

        size_desc = [NSString stringWithFormat: @"%d x %d (%d x %d)",
                        (int) rect.size.width,
                        (int) rect.size.height,
                        (int) rect.size.width / gui.char_width,
                        (int) rect.size.height / gui.char_height];
        attrib = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSColor whiteColor], NSForegroundColorAttributeName,
                    font, NSFontAttributeName, nil];

        NSSize desc_size = [size_desc sizeWithAttributes: attrib];

        [size_desc drawAtPoint: NSMakePoint(rect.size.width / 2 - desc_size.width / 2,
                                            rect.size.height / 2 - desc_size.height / 2)
                withAttributes: attrib];
        return;
    }
    else
    {
#endif
        [contentImage drawInRect: rect
                        fromRect: rect
                       operation: NSCompositeCopy
                        fraction: 1.0];

        if ([self hasMarkedText])
        {
            // gui_mac_msg(MSG_DEBUG, @"redraw: %@", markedText);
            NSPoint cursorPoint = NSMakePoint(FILL_X(gui_mac.im_col), FILL_Y(gui_mac.im_row + 1));
            [markedText drawAtPoint: FLIPPED_POINT(self, cursorPoint)];
        }
#if LIGHTWEIDHT_LIVE_RESIZE
    }
#endif
}

- (BOOL) wantsDefaultClipping
{
    return NO;
}

- (BOOL) isFlipped
{
    return NO;
}

- (BOOL) acceptsFirstResponder
{
    return YES;
}

- (void) scrollWheel:(NSEvent *)event
{
    if ([event deltaY] == 0)
        return;

    [self mouseAction: [event deltaY] > 0 ? MOUSE_4 : MOUSE_5
             repeated: NO
                event: event];
}

- (void) mouseAction:(int)button repeated:(bool)repeated event:(NSEvent *)event
{
    NSPoint point = [self convertPoint: [event locationInWindow]
                              fromView: nil];

    point = FLIPPED_POINT(self, point);

    int flags = gui_mac_mouse_modifiers_to_vim([event modifierFlags]);
    gui_send_mouse_event(button, point.x, point.y, repeated, flags);
    gui_mac_stop_app(YES);
}

- (void) mouseDown:(NSEvent *)event
{
    int button = gui_mac_mouse_button_to_vim([event buttonNumber]);

    gui_mac.last_mouse_down_event = [event copy];

    // gui_mac_msg(MSG_DEBUG, @"mouseDown: %s",
    //             button == MOUSE_LEFT ? "MOUSE_LEFT" : "MOUSE_RIGHT");

    [self mouseAction: button
             repeated: [event clickCount] != 0
                event: event];
}

- (void) rightMouseDown:(NSEvent *)event
{
    [self mouseDown: event];
}

- (void) otherMouseDown:(NSEvent *)event
{
    [self mouseDown: event];
}

- (void) mouseUp:(NSEvent *)event
{
    [self mouseAction: MOUSE_RELEASE
             repeated: NO
                event: event];
}

- (void) rightMouseUp:(NSEvent *)event
{
    [self mouseUp: event];
}

- (void) otherMouseUp:(NSEvent *)event
{
    [self mouseUp: event];
}

- (void) mouseDragged:(NSEvent *)event
{
    [self mouseAction: MOUSE_DRAG
             repeated: NO
                event: event];
}

- (void) rightMouseDragged:(NSEvent *)event
{
    [self mouseDragged: event];
}

- (void) otherMouseDragged:(NSEvent *)event
{
    [self mouseDragged: event];
}

- (NSDragOperation) draggingEntered:(id <NSDraggingInfo>)sender
{
    NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];
    NSPasteboard *pboard = [sender draggingPasteboard];

    if (([[pboard types] containsObject: NSFilenamesPboardType] ||
         [[pboard types] containsObject: NSStringPboardType]) &&
        (sourceDragMask & NSDragOperationCopy))
        return NSDragOperationCopy;

    return NSDragOperationNone;
}

- (NSDragOperation) draggingUpdated:(id <NSDraggingInfo>)sender
{
    return [self draggingEntered: sender];
}

- (BOOL) performDragOperation:(id <NSDraggingInfo>)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];

    if ([[pboard types] containsObject: NSFilenamesPboardType])
    {
        NSArray *files = [pboard propertyListForType: NSFilenamesPboardType];
        int i, count   = [files count];
        NSPoint point  = [self convertPoint: [sender draggingLocation]
                                   fromView: nil];

        point = FLIPPED_POINT(self, point);

        char_u **fnames = (char_u **) alloc(count * sizeof(char_u *));
        for (i = 0; i < count; ++i)
        {
            NSString *file = [files objectAtIndex: i];

            fnames[i] = vim_strsave((char_u *)[file fileSystemRepresentation]);
        }

        gui_handle_drop(point.x, point.y, 0, fnames, count);
        gui_mac_update();
        return YES;
    }

    else if ([[pboard types] containsObject: NSStringPboardType])
    {
#ifdef FEAT_DND
        NSString *dragString = [pboard stringForType: NSStringPboardType];
        char_u  dropkey[3] = { CSI, KS_EXTRA, (char_u) KE_DROP };

        NSMutableString *string = [NSMutableString stringWithString: dragString];

        // Replace unrecognized end-of-line sequences with \x0a (line feed).
        NSRange range = NSMakeRange(0, [string length]);
        unsigned n = [string replaceOccurrencesOfString: @"\x0d\x0a"
                                             withString: @"\x0a"
                                                options: 0
                                                  range: range];
        if (n == 0)
            [string replaceOccurrencesOfString: @"\x0d"
                                    withString: @"\x0a"
                                       options: 0
                                         range: range];

        dnd_yank_drag_data((char_u *)[string UTF8String],
                           [string lengthOfBytesUsingEncoding: NSUTF8StringEncoding]);
        add_to_input_buf(dropkey, sizeof(dropkey));

        gui_mac_redraw();
        gui_mac_update();
#endif
        return YES;
    }

    return NO;
}

- (BOOL) performKeyEquivalent:(NSEvent *)event
{
    // Called for Cmd+key keystrokes, function keys, arrow keys, page
    // up/down, home, end.
    if ([event type] != NSKeyDown)
        return NO;

    // HACK!  Let the main menu try to handle any key down event, before
    // passing it on to vim, otherwise key equivalents for menus will
    // effectively be disabled.
    if ([[NSApp mainMenu] performKeyEquivalent: event])
        return YES;

    // HACK!  KeyCode 50 represent the key which switches between windows
    // within an application (like Cmd+Tab is used to switch between
    // applications).  Return NO here, else the window switching does not work.
    //
    // Will this hack work for all languages / keyboard layouts?
    if ([event keyCode] == 50)
        return NO;

    if ([event modifierFlags] & NSCommandKeyMask)
    {
        [self keyDown: event];
        return YES;
    }

    return NO;
}

- (void) keyDown:(NSEvent *)event
{
    UniChar         modified_char, original_char;
    unsigned int    mac_modifiers, vim_modifiers;
    char_u          result[INLINE_KEY_BUFFER_SIZE];
    int             len = 0;
    int             vim_key_char;

    [NSCursor setHiddenUntilMouseMoves: YES];

    /* get key code and modifier flags from event */
    mac_modifiers  = [event modifierFlags];

    /* convert NS* style modifier flags to vim style */
    vim_modifiers = gui_mac_key_modifiers_to_vim(mac_modifiers);

    // gui_mac_msg(MSG_DEBUG, @"keyDown: characters = %d", [[event characters] length]);

    if ([[event characters] length] == 1)
    {
        modified_char = [[event characters] characterAtIndex: 0];
        original_char = [[event charactersIgnoringModifiers] characterAtIndex: 0];

        /* Intercept CMD-. and CTRL-c */
        if ((modified_char == Ctrl_C && ctrl_c_interrupts) ||
            (modified_char == intr_char && intr_char != Ctrl_C))
        {
            trash_input_buf();
            got_int = TRUE;
        }

        // gui_mac_msg(MSG_DEBUG, @"original_char %d, modified_char: %d",
        //            original_char, modified_char);

        vim_key_char = gui_mac_function_key_to_vim(original_char, vim_modifiers);
        // gui_mac_msg(MSG_DEBUG, @"vim_key_char: %d", vim_key_char);

        switch (vim_modifiers)
        {
        case MOD_MASK_ALT:
        case MOD_MASK_SHIFT:
            if (vim_key_char == 0)
                goto insert_text;
            break;

        case MOD_MASK_CTRL:
            result[len++] = modified_char;
            add_to_input_buf(result, len);
            // gui_mac_msg(MSG_DEBUG, @"CTRL-%c, add_to_input_buf: %d", original_char, len);

            gui_mac_stop_app(YES);
            return;
        }

        /* if it's normal key, not special one, then Shift is already applied */
        if (vim_key_char == 0 ||
            ! (vim_key_char == ' '  ||
               vim_key_char == 0xa0 ||
               (vim_modifiers & MOD_MASK_CMD) ||
               vim_key_char == 0x9  ||
               vim_key_char == 0xd  ||
               vim_key_char == ESC))
            vim_modifiers &= ~MOD_MASK_SHIFT;

        if (vim_modifiers)
        {
            add_to_key_buffer(result, len, CSI, KS_MODIFIER, vim_modifiers);

            // gui_mac_msg(MSG_DEBUG, "vim_modifiers: ");
            // print_vim_modifiers(vim_modifiers);
        }

        if (IS_SPECIAL(vim_key_char) || vim_key_char > 0)
        {
            if ([self hasMarkedText])
                goto insert_text;

            /* must be enter, esc, backspace, tab, add to input buffer directly */
            if (vim_key_char > 0)
                result[len++] = vim_key_char;

            else
                add_to_key_buffer(result, len, CSI,
                                  K_SECOND(vim_key_char),
                                  K_THIRD(vim_key_char));

            // gui_mac_msg(MSG_DEBUG, @"IS_SPECIAL, add_to_input_buf: %d", len);
        }

        /* now here are normal characters */
        else if (vim_modifiers)
        {
            result[len++] = original_char;
            // gui_mac_msg(MSG_DEBUG, @"original_char %c, add_to_input_buf: %d",
            //             original_char, len);
        }

        if (len > 0)
        {
            add_to_input_buf(result, len);
            gui_mac_stop_app(YES);
            return;
        }
    }

insert_text:
    [self interpretKeyEvents: [NSArray arrayWithObject: event]];
}

@end

/* View related Utilities 2}}} */

/* Drawing related Utilities {{{2 */

void gui_mac_scroll_rect(NSRect rect, int lines)
{
    NSPoint dest_point = rect.origin;
    dest_point.y += lines * gui.char_height;

    gui_mac_begin_drawing();
    NSCopyBits(0, rect, dest_point);
    gui_mac_end_drawing();
}

void gui_mac_redraw()
{
    [currentView setNeedsDisplay: YES];
}

/* Drawing related Utilities 2}}} */

/* Keyboard Related Utilities 2{{{ */

int gui_mac_function_key_to_vim(UniChar key_char, unsigned int vim_modifiers)
{
    int i;

    for (i = 0; function_key_mapping[i].function_key != 0; i++)
        if (key_char == function_key_mapping[i].function_key)
            return simplify_key(function_key_mapping[i].vim_key,
                                (int *) &vim_modifiers);

    return 0;
}

unsigned int gui_mac_key_modifiers_to_vim(unsigned int mac_modifiers)
{
    unsigned int vim_modifiers = 0;

    if (mac_modifiers & NSShiftKeyMask)
        vim_modifiers |= MOD_MASK_SHIFT;
    if (mac_modifiers & NSControlKeyMask)
        vim_modifiers |= MOD_MASK_CTRL;
    if (mac_modifiers & NSAlternateKeyMask)
        vim_modifiers |= MOD_MASK_ALT;
    if (mac_modifiers & NSCommandKeyMask)
        vim_modifiers |= MOD_MASK_CMD;

    return vim_modifiers;
}

void print_vim_modifiers(unsigned int vim_modifiers)
{
    if (vim_modifiers & MOD_MASK_SHIFT)
        fprintf(stderr, "SHIFT-");

    if (vim_modifiers & MOD_MASK_CMD)
        fprintf(stderr, "CMD-");

    if (vim_modifiers & MOD_MASK_ALT)
        fprintf(stderr, "ALT-");

    if (vim_modifiers & MOD_MASK_CTRL)
        fprintf(stderr, "CTRL-");
}

unsigned int gui_mac_mouse_modifiers_to_vim(unsigned int mac_modifiers)
{
    unsigned int vim_modifiers = 0;

    if (mac_modifiers & NSShiftKeyMask)
        vim_modifiers |= MOUSE_SHIFT;
    if (mac_modifiers & NSControlKeyMask)
        vim_modifiers |= MOUSE_CTRL;
    if (mac_modifiers & NSAlternateKeyMask)
        vim_modifiers |= MOUSE_ALT;

    return vim_modifiers;
}

int gui_mac_mouse_button_to_vim(int mac_button)
{
    static int vim_buttons[] = { MOUSE_LEFT, MOUSE_RIGHT,
                                 MOUSE_MIDDLE, MOUSE_X1,
                                 MOUSE_X2 };

    return vim_buttons[mac_button < 5 ? mac_button : 0];
}

/* Keyboard Related Utilities 2}}} */

/* Font Related Utilities 2{{{ */

NSFont *gui_mac_get_font(char_u *font_name, int size)
{
    // gui_mac_msg(MSG_DEBUG, @"get_font: %s", font_name);
    NSString *mac_font_name = NSStringFromVim(font_name);

    // gui_mac_msg(MSG_DEBUG, @"fontWithName: %@, %d", mac_font_name, size);

    return [NSFont fontWithName: mac_font_name
                           size: size];
}

GuiFont gui_mac_find_font(char_u *font_spec)
{
    int       len = 0, size = VIM_DEFAULT_FONT_SIZE;
    NSFont   *font;
    char_u   *font_style, *p;
    char_u    font_name[VIM_MAX_FONT_NAME_LEN];

    // gui_mac_msg(MSG_DEBUG, @"find_font: %s", font_spec);

    font_style = vim_strchr(font_spec, ':');
    len = font_style - font_spec;

    if (len < 0 || len >= VIM_MAX_FONT_NAME_LEN)
        return NOFONT;

    vim_strncpy(font_name, font_spec, len);
    font_name[len] = '\0';

    if (*font_style == ':')
    {
        p = font_style + 1;
        /* Set the values found after ':' */
        while (*p)
        {
            switch (*p++)
            {
            case 'h':
                size = gui_mac_points_to_pixels(p, &p);
                break;
                /*
                 * TODO: Maybe accept width and styles
                 */
            }

            while (*p == ':')
                p++;
        }
    }

    font = gui_mac_get_font(font_name, size);
    if (font == nil)
    {
        /*
         * Try again, this time replacing underscores in the font name
         * with spaces (:set guifont allows the two to be used
         * interchangeably; the Font Manager doesn't).
         */
        int i, changed = FALSE;

        for (i = font_name[0]; i > 0; --i)
        {
            if (font_name[i] == '_')
            {
                font_name[i] = ' ';
                changed = TRUE;
            }
        }

        if (changed)
            font = gui_mac_get_font(font_name, size);
    }

    if (font == nil)
        return NOFONT;

    [font retain];
    return (long_u) font;
}

int gui_mac_points_to_pixels(char_u *str, char_u **end)
{
    int pixels;
    int points = 0;
    int divisor = 0;

    while (*str)
    {
        if (*str == '.' && divisor == 0)
        {
            /* Start keeping a divisor, for later */
            divisor = 1;
            continue;
        }

        if (! isdigit(*str))
            break;

        points *= 10;
        points += *str - '0';
        divisor *= 10;

        ++str;
    }

    if (divisor == 0)
        divisor = 1;

    pixels = points / divisor;
    *end = str;
    return pixels;
}

void gui_mac_create_atsui_style()
{
    int i;

    for (i = 0; i < VIM_MAX_CHAR_WIDTH; i++)
        if (gui_mac.font_style[i] == NULL)
        {
            if (ATSUCreateStyle(&(gui_mac.font_style[i])) != noErr)
                gui_mac.font_style[i] = NULL;
        }
}

void gui_mac_dispose_atsui_style()
{
    int i;

    for (i = 0; i < VIM_MAX_CHAR_WIDTH; i++)
        if (gui_mac.font_style[i] == NULL)
        {
            if (ATSUDisposeStyle(gui_mac.font_style[i]) != noErr)
                gui_mac.font_style[i] = NULL;
        }
}

ATSUStyle gui_mac_atsui_style_from_width(int width)
{
    if (width >= VIM_MAX_CHAR_WIDTH)
        return gui_mac.font_style[VIM_MAX_CHAR_WIDTH - 1];

    return gui_mac.font_style[width - 1];
}

void gui_mac_set_font_attributes(GuiFont vim_font)
{
    int               i;
    NSFont           *mac_font;
    ATSUFontID        fontID;
    Fixed             fontSize;
    Fixed             fontWidth;
    CGAffineTransform transform = CGAffineTransformMakeScale(1, -1);
    ATSStyleRenderingOptions options;

    mac_font  = (NSFont *) vim_font;
    fontID    = [mac_font _atsFontID];
    fontSize  = Long2Fix([mac_font pointSize]);
    fontWidth = Long2Fix(gui.char_width);
    options   = p_antialias ? kATSStyleApplyAntiAliasing : kATSStyleNoAntiAliasing;

    ATSUAttributeTag attribTags[] =
    {
        kATSUFontTag, kATSUSizeTag, kATSUImposeWidthTag,
        kATSUFontMatrixTag, kATSUStyleRenderingOptionsTag,
        kATSUMaxATSUITagValue + 1
    };

    ByteCount attribSizes[] =
    {
        sizeof(ATSUFontID), sizeof(Fixed), sizeof(fontWidth),
        sizeof(CGAffineTransform), sizeof(ATSStyleRenderingOptions),
        sizeof(vim_font)
    };

    ATSUAttributeValuePtr attribValues[] =
    {
        &fontID, &fontSize, &fontWidth, &transform, &options, &vim_font
    };

    for (i = 0; i < VIM_MAX_CHAR_WIDTH; i++)
    {
        fontWidth = Long2Fix(gui.char_width * (i + 1));

        if (ATSUSetAttributes(gui_mac.font_style[i],
                              (sizeof attribTags) / sizeof(ATSUAttributeTag),
                              attribTags, attribSizes, attribValues) != noErr)
        {
            ATSUDisposeStyle(gui_mac.font_style[i]);
            gui_mac.font_style[i] = NULL;
        }
    }
}

void gui_mac_atsui_style_set_value(ATSUStyle style, ATSUAttributeTag tag, void *value, int size)
{
    ATSUAttributeTag attribTags[1];
    ByteCount attribSizes[] = { size };
    ATSUAttributeValuePtr attribValues[] = { value };

    attribTags[0] = tag;
    ATSUSetAttributes(style, 1, attribTags, attribSizes, attribValues);
}

void gui_mac_atsui_style_set_boolean(ATSUStyle style, ATSUAttributeTag tag, Boolean value)
{
    ATSUAttributeTag attribTags[1];
    ByteCount attribSizes[] = { sizeof(Boolean) };
    ATSUAttributeValuePtr attribValues[] = { &value };

    attribTags[0] = tag;
    ATSUSetAttributes(style, 1, attribTags, attribSizes, attribValues);
}

void gui_mac_atsui_style_set_int(ATSUStyle style, ATSUAttributeTag tag, UInt32 value)
{
    ATSUAttributeTag attribTags[1];
    ByteCount attribSizes[] = { sizeof(UInt32) };
    ATSUAttributeValuePtr attribValues[] = { &value };

    attribTags[0] = tag;
    ATSUSetAttributes(style, 1, attribTags, attribSizes, attribValues);
}

/* Font Related Utilities 2}}} */

/* Dialog Related Utilities {{{2 */

int gui_mac_select_from_font_panel(char_u *font_name)
{
    char fontSizeString[VIM_MAX_FONT_NAME_LEN];
    NSFontPanel *fontPanel = [NSFontPanel sharedFontPanel];

    if (gui_mac.current_font)
        [[NSFontManager sharedFontManager] setSelectedFont: gui_mac.current_font
                                                isMultiple: NO];;

    [fontPanel setDelegate: gui_mac.app_delegate];
    [fontPanel orderFront: nil];

    gui_mac.selected_font = nil;
    [NSApp run];
    if (! gui_mac.selected_font)
        return FAIL;

    STRCPY(font_name, [[gui_mac.selected_font fontName] UTF8String]);
    STRCAT(font_name, ":h");
    sprintf(fontSizeString, "%d", (int) [gui_mac.selected_font pointSize]);
    STRCAT(font_name, fontSizeString);

    return OK;
}

@implementation VIMAlert

- (void) dealloc
{
    [textField release];
    [super dealloc];
}

- (void) setTextFieldString: (NSString *)textFieldString
{
    [textField release];
    textField = [[NSTextField alloc] init];
    [textField setStringValue: textFieldString];
}

- (NSTextField *) textField
{
    return textField;
}

- (void) setInformativeText:(NSString *)text
{
    if (textField)
    {
        // HACK! Add some space for the text field.
        [super setInformativeText: [text stringByAppendingString: @"\n\n\n"]];
    } else
    {
        [super setInformativeText: text];
    }
}

- (void) beginSheetModalForWindow:(NSWindow *)window
                    modalDelegate:(id)delegate
                   didEndSelector:(SEL)didEndSelector
                      contextInfo:(void *)contextInfo
{
    [super beginSheetModalForWindow: window
                      modalDelegate: delegate
                     didEndSelector: didEndSelector
                        contextInfo: contextInfo];

    // HACK! Place the input text field at the bottom of the informative text
    // (which has been made a bit larger by adding newline characters).
    NSView *contentView = [[self window] contentView];
    NSRect rect = [contentView frame];
    rect.origin.y = rect.size.height;

    NSArray *subviews = [contentView subviews];
    unsigned i, count = [subviews count];
    for (i = 0; i < count; ++i)
    {
        NSView *view = [subviews objectAtIndex: i];

        if ([view isKindOfClass: [NSTextField class]] &&
            [view frame].origin.y < rect.origin.y) {
            // NOTE: The informative text field is the lowest NSTextField in
            // the alert dialog.
            rect = [view frame];
        }
    }

    rect.size.height = VIMAlertTextFieldHeight;
    [textField setFrame: rect];
    [contentView addSubview: textField];
    [textField becomeFirstResponder];
}

@end

/* Dialog Related Utilities 2}}} */

/* Scroll Bar Related Utilities {{{2 */

@implementation VIMScroller

- (id)initWithVimScrollbar:(scrollbar_T *)scrollBar
               orientation:(int)orientation
{
    unsigned int mask = 0;
    NSRect frame = orientation == SBAR_HORIZ ? NSMakeRect(0, 0, 1, 0)
                                             : NSMakeRect(0, 0, 0, 1);

    if ((self = [super initWithFrame: frame]))
    {
        vimScrollBar = scrollBar;

        [self setEnabled: YES];
        [self setAction: @selector(scroll:)];
        [self setTarget: self];

        switch (vimScrollBar->type)
        {
        case SBAR_LEFT:
            mask = NSViewHeightSizable | NSViewMaxXMargin;
            break;

        case SBAR_RIGHT:
            mask = NSViewHeightSizable | NSViewMinXMargin;
            break;

        case SBAR_BOTTOM:
            mask = NSViewWidthSizable | NSViewMaxYMargin;
            break;
        }

        [self setAutoresizingMask: mask];
    }

    return self;
}

- (void) scroll:(id)sender
{
    scrollbar_T *sb = [sender vimScrollBar];
    int hitPart = [sender hitPart];
    float fval = [sender floatValue];

    if (sb == NULL)
        return;

    scrollbar_T *sb_info = sb->wp ? &sb->wp->w_scrollbars[0] : sb;
    long value = sb_info->value;
    long size = sb_info->size;
    long max = sb_info->max;
    BOOL isStillDragging = NO;
    BOOL updateKnob = YES;

    switch (hitPart) {
    case NSScrollerDecrementPage:
        value -= (size > 2 ? size - 2 : 1);
        break;
    case NSScrollerIncrementPage:
        value += (size > 2 ? size - 2 : 1);
        break;
    case NSScrollerDecrementLine:
        --value;
        break;
    case NSScrollerIncrementLine:
        ++value;
        break;
    case NSScrollerKnob:
        isStillDragging = YES;
        // fall through ...
    case NSScrollerKnobSlot:
        value = (long)(fval * (max - size + 1));
        // fall through ...
    default:
        updateKnob = NO;
        break;
    }

    //gui_mac_msg(MSG_DEBUG, @"value %d -> %d", sb_info->value, value);
    gui_drag_scrollbar(sb, value, isStillDragging);
    gui_mac_redraw();
    if (updateKnob)
    {
        // Dragging the knob or option + clicking automatically updates
        // the knob position (on the actual NSScroller), so we only
        // need to set the knob position in the other cases.
        if (sb->wp)
        {
            // Update both the left & right vertical scrollbars.
            VIMScroller *leftScroller = (VIMScroller *) sb->wp->w_scrollbars[SBAR_LEFT].scroller;
            VIMScroller *rightScroller = (VIMScroller *) sb->wp->w_scrollbars[SBAR_RIGHT].scroller;
            [leftScroller setThumbValue: value size: size max: max];
            [rightScroller setThumbValue: value size: size max: max];
        } else
        {
            // Update the horizontal scrollbar.
            VIMScroller *scroller = (VIMScroller *) sb->scroller;
            [scroller setThumbValue: value size: size max: max];
        }
    }
}

- (void) setThumbValue:(long)value size:(long)size max:(long)max
{
    float fval = max - size + 1 > 0 ? (float) value / (max - size + 1) : 0;
    float prop = (float) size / (max + 1);

    if (fval < 0) fval = 0;
    else if (fval > 1.0f) fval = 1.0f;
    if (prop < 0) prop = 0;
    else if (prop > 1.0f) prop = 1.0f;

    [self setFloatValue: fval knobProportion: prop];
}

- (scrollbar_T *) vimScrollBar
{
    return vimScrollBar;
}

@end

void gui_mac_update_scrollbar(scrollbar_T *sb)
{
    VIMScroller *scroller = gui_mac_get_scroller(sb);

    /* check if we need to add this scroller onto content view */
    if (sb->enabled == TRUE && [scroller superview] != [gui_mac.current_window contentView])
    {
        [[gui_mac.current_window contentView] addSubview: scroller];
        // gui_mac_msg(MSG_DEBUG, @"addSubview: %s", scrollbar_desc(sb));
    }

    if (sb->enabled == FALSE && [scroller superview] == [gui_mac.current_window contentView])
    {
        [scroller removeFromSuperview];
        // gui_mac_msg(MSG_DEBUG, @"removeFromSuperview: %s", scrollbar_desc(sb));
    }
}

/* Scroll Bar Related Utilities 2}}} */

/* Private Functions 1}}} */
