using Gtk;
using Adw;
using Vte;

public class WayTerm : Adw.Application {
    private const double FONT_WIDTH_SCALE = 0.55; // Perfect balance for text/icons
    private Adw.TabView tab_view;
    private KeyFile config;
    private string config_path;
    private Adw.ApplicationWindow window;
    private new Adw.StyleManager style_manager;
    private GLib.Settings settings;
    
    public WayTerm() {
        Object(application_id: "org.SquarDE.wayterm");
        
        // Initialize config file path
        config_path = Path.build_filename(
            Environment.get_user_config_dir(), 
            "wayterm", 
            "config.ini"
        );
        
        // Load configuration
        config = new KeyFile();
        try {
            if (FileUtils.test(config_path, FileTest.EXISTS)) {
                config.load_from_file(config_path, KeyFileFlags.NONE);
            }
        } catch (Error e) {
            warning("Could not load config: %s", e.message);
        }
    }

    public override void activate() {
        // Apply GPU acceleration settings before creating windows
        apply_gpu_settings();
        
        window = new Adw.ApplicationWindow(this) {
            title = "WayTerm",
            default_width = get_int_setting("window-width", 800),
            default_height = get_int_setting("window-height", 600)
        };

        // Add custom CSS class to window
        window.add_css_class("wayterm-window");

        // Create header bar with controls
        var header = new Adw.HeaderBar() {
            title_widget = new Adw.WindowTitle("WayTerm", "")
        };

        // Add new tab button to header
        var new_tab_button = new Gtk.Button.from_icon_name("tab-new-symbolic") {
            tooltip_text = "New Tab (Alt+T)"
        };
        new_tab_button.clicked.connect(() => create_new_tab());
        header.pack_start(new_tab_button);

        // Add settings button to header
        var settings_button = new Gtk.Button.from_icon_name("preferences-system-symbolic") {
            tooltip_text = "Settings"
        };
        settings_button.clicked.connect(() => show_settings_dialog());
        header.pack_end(settings_button);

        // Create tab view
        tab_view = new Adw.TabView() {
            hexpand = true,
            vexpand = true
        };

        // Connect tab view signals
        tab_view.close_page.connect(on_tab_close);
        tab_view.page_attached.connect(on_page_attached);
        tab_view.page_detached.connect(on_page_detached);

        // Create tab bar
        var tab_bar = new Adw.TabBar() {
            view = tab_view,
            autohide = get_bool_setting("autohide-tabs", false)
        };

        // Style manager for color updates
        style_manager = Adw.StyleManager.get_default();

        // Main layout with Libadwaita styling
        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        box.add_css_class("wayterm-box");
        box.append(header);
        box.append(tab_bar);
        box.append(tab_view);
        
        // Wrap everything in a ToastOverlay for notifications
        var toast_overlay = new Adw.ToastOverlay() {
            child = box
        };
        
        // Apply custom CSS
        load_css();
        
        window.content = toast_overlay;

        // Set up keyboard shortcuts
        setup_shortcuts();

        // Create initial tab
        create_new_tab();
        
        // Save window size on close
        window.close_request.connect(() => {
            int width, height;
            window.get_default_size(out width, out height);
            set_int_setting("window-width", width);
            set_int_setting("window-height", height);
            return false;
        });
        
        window.present();
    }

    private void show_settings_dialog() {
        var dialog = new Adw.PreferencesWindow() {
            title = "Settings",
            modal = true,
            transient_for = window,
            default_width = 600,
            default_height = 500
        };

        // Track if restart is needed
        bool restart_needed = false;

        // Performance page
        var perf_page = new Adw.PreferencesPage() {
            title = "Performance",
            icon_name = "applications-graphics-symbolic"
        };

        var perf_group = new Adw.PreferencesGroup() {
            title = "Graphics Acceleration"
        };

        // GPU acceleration toggle
        var gpu_row = new Adw.SwitchRow() {
            title = "Hardware Acceleration",
            subtitle = "Use GPU rendering for better performance"
        };
        gpu_row.active = get_bool_setting("gpu-acceleration", true);
        gpu_row.notify["active"].connect(() => {
            set_bool_setting("gpu-acceleration", gpu_row.active);
            restart_needed = true;
        });
        perf_group.add(gpu_row);

        // VSync toggle
        var vsync_row = new Adw.SwitchRow() {
            title = "Vertical Sync",
            subtitle = "Synchronize rendering with display refresh rate"
        };
        vsync_row.active = get_bool_setting("vsync", true);
        vsync_row.notify["active"].connect(() => {
            set_bool_setting("vsync", vsync_row.active);
            restart_needed = true;
        });
        perf_group.add(vsync_row);

        perf_page.add(perf_group);
        dialog.add(perf_page);

        // Appearance page
        var appearance_page = new Adw.PreferencesPage() {
            title = "Appearance",
            icon_name = "applications-graphics-symbolic"
        };

        var appearance_group = new Adw.PreferencesGroup() {
            title = "Interface"
        };

        // Auto-hide tabs
        var autohide_row = new Adw.SwitchRow() {
            title = "Auto-hide Tab Bar",
            subtitle = "Hide tab bar when only one tab is open"
        };
        autohide_row.active = get_bool_setting("autohide-tabs", false);
        autohide_row.notify["active"].connect(() => {
            set_bool_setting("autohide-tabs", autohide_row.active);
            var tab_bar = get_tab_bar();
            if (tab_bar != null) {
                tab_bar.autohide = autohide_row.active;
            }
        });
        appearance_group.add(autohide_row);

        // Font size adjustment
        var font_row = new Adw.SpinRow(new Gtk.Adjustment(11, 8, 24, 1, 1, 0), 1.0, 0) {
            title = "Font Size",
            subtitle = "Terminal font size in points"
        };
        font_row.value = get_int_setting("font-size", 11);
        font_row.notify["value"].connect(() => {
            set_int_setting("font-size", (int)font_row.value);
            restart_needed = true;
        });
        appearance_group.add(font_row);

        // Scrollback lines
        var scrollback_row = new Adw.SpinRow(new Gtk.Adjustment(1000, 100, 10000, 100, 500, 0), 100.0, 0) {
            title = "Scrollback Lines",
            subtitle = "Number of lines to keep in terminal history"
        };
        scrollback_row.value = get_int_setting("scrollback-lines", 1000);
        scrollback_row.notify["value"].connect(() => {
            set_int_setting("scrollback-lines", (int)scrollback_row.value);
            restart_needed = true;
        });
        appearance_group.add(scrollback_row);

        appearance_page.add(appearance_group);
        dialog.add(appearance_page);

        // Terminal page
        var terminal_page = new Adw.PreferencesPage() {
            title = "Terminal",
            icon_name = "utilities-terminal-symbolic"
        };

        var terminal_group = new Adw.PreferencesGroup() {
            title = "Behavior"
        };

        // Mouse autohide
        var mouse_row = new Adw.SwitchRow() {
            title = "Auto-hide Mouse Cursor",
            subtitle = "Hide mouse cursor when typing in terminal"
        };
        mouse_row.active = get_bool_setting("mouse-autohide", true);
        mouse_row.notify["active"].connect(() => {
            set_bool_setting("mouse-autohide", mouse_row.active);
            restart_needed = true;
        });
        terminal_group.add(mouse_row);

        terminal_page.add(terminal_group);
        dialog.add(terminal_page);

        // Handle dialog close to show restart notification
        dialog.close_request.connect(() => {
            if (restart_needed) {
                show_restart_notification();
            }
            return false;
        });

        dialog.present();
    }

    private void show_restart_notification() {
        var toast = new Adw.Toast("Settings saved. Restart WayTerm to apply changes.") {
            timeout = 5
        };
        
        // Get the toast overlay (you'll need to add this to your main layout)
        var toast_overlay = get_toast_overlay();
        if (toast_overlay != null) {
            toast_overlay.add_toast(toast);
        } else {
            // Fallback: show a simple dialog
            var restart_dialog = new Adw.MessageDialog(window, "Settings Saved", 
                "Please restart WayTerm to apply the changes.");
            restart_dialog.add_response("ok", "OK");
            restart_dialog.present();
        }
    }

    private Adw.ToastOverlay? get_toast_overlay() {
        return window.content as Adw.ToastOverlay;
    }

    private Adw.TabBar? get_tab_bar() {
        var toast_overlay = window.content as Adw.ToastOverlay;
        if (toast_overlay != null) {
            var box = toast_overlay.child as Gtk.Box;
            if (box != null) {
                var child = box.get_first_child();
                while (child != null) {
                    if (child is Adw.TabBar) {
                        return child as Adw.TabBar;
                    }
                    child = child.get_next_sibling();
                }
            }
        }
        return null;
    }

    private void apply_gpu_settings() {
        bool gpu_enabled = get_bool_setting("gpu-acceleration", true);
        bool vsync_enabled = get_bool_setting("vsync", true);

        if (gpu_enabled) {
            // Enable GPU acceleration
            Environment.set_variable("GSK_RENDERER", "vulkan", true);
            // Fallback to OpenGL if Vulkan isn't available
            if (Environment.get_variable("GSK_RENDERER") == null) {
                Environment.set_variable("GSK_RENDERER", "gl", true);
            }
        } else {
            // Force software rendering
            Environment.set_variable("GSK_RENDERER", "cairo", true);
        }

        // VSync setting
        if (!vsync_enabled) {
            Environment.set_variable("vblank_mode", "0", true);
        }
    }

    private void create_new_tab(string? title = null) {
        // Create terminal with perfect proportions
        var terminal = new Vte.Terminal() {
            scrollback_lines = get_int_setting("scrollback-lines", 1000)
        };

        // Enable mouse autohide
        terminal.set_mouse_autohide(get_bool_setting("mouse-autohide", true));

        // Add custom CSS class to terminal
        terminal.add_css_class("wayterm-terminal");

        // Configure terminal
        configure_terminal(terminal);

        // Handle terminal exit
        terminal.child_exited.connect((status) => {
            var page = get_page_for_terminal(terminal);
            if (page != null) {
                tab_view.close_page(page);
            }
        });

        // Create scrolled window for terminal
        var scrolled = new Gtk.ScrolledWindow() {
            child = terminal,
            hexpand = true,
            vexpand = true
        };

        // Add tab to tab view
        string tab_title = title ?? "Terminal";
        var page = tab_view.add_page(scrolled, null);
        page.title = tab_title;
        page.icon = new ThemedIcon("utilities-terminal-symbolic");

        // Set as current page
        tab_view.selected_page = page;

        // Focus the terminal
        terminal.grab_focus();

        // Spawn shell
        spawn_shell(terminal);

        // Update tab title based on terminal title changes
        terminal.notify["window-title"].connect(() => {
            string? window_title = terminal.window_title;
            if (window_title != null && window_title.length > 0) {
                page.title = window_title;
            }
        });
    }

    private void configure_terminal(Vte.Terminal terminal) {
        // Font settings that prevent stretching
        try {
            var font = new Pango.FontDescription();
    
            string font_family = "monospace"; // Default fallback
    
            // Get the user's configured monospace font from system settings
            try {
                var system_settings = new GLib.Settings("org.gnome.desktop.interface");
                string system_monospace = system_settings.get_string("monospace-font-name");
                if (system_monospace != "") {
                    // Parse the font string to extract family name
                    var font_desc = Pango.FontDescription.from_string(system_monospace);
                    string family = font_desc.get_family();
                    if (family != null && family != "") {
                      font_family = family + ", monospace";
                    }
                }
            } catch (Error e) {
              // If we can't get system settings, fall back to generic monospace
              warning("Could not get system monospace font, using default: %s", e.message);
              font_family = "monospace, Symbols Nerd Font Mono";
            }
    
            font.set_family(font_family);
            font.set_size(get_int_setting("font-size", 11) * Pango.SCALE);
            font.set_stretch(Pango.Stretch.SEMI_CONDENSED);
            terminal.set_font(font);
        } catch (Error e) {
          warning("Font error: %s", e.message);
        }

        // Cell scaling that maintains proportions
        terminal.set_cell_height_scale(1.0);
        terminal.set_cell_width_scale(FONT_WIDTH_SCALE);

        // Color management
        update_terminal_colors(terminal, style_manager);
        style_manager.notify["dark"].connect(() => {
            update_terminal_colors(terminal, style_manager);
        });
        
        // Setup context menu for copy/paste
        setup_context_menu(terminal);
        
        // Keyboard handling
        var key_controller = new Gtk.EventControllerKey();
        key_controller.key_pressed.connect((keyval, keycode, state) => {
            // Handle Ctrl+Shift+C (copy)
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 && 
                (state & Gdk.ModifierType.SHIFT_MASK) != 0 && 
                keyval == Gdk.Key.C) {
                copy_selection(terminal);
                return true;
            }
            
            // Handle Ctrl+Shift+V (paste)
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 && 
                (state & Gdk.ModifierType.SHIFT_MASK) != 0 && 
                keyval == Gdk.Key.V) {
                paste_clipboard(terminal);
                return true;
            }
            
            // Handle Ctrl+Backspace (delete word backwards)
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 && keyval == Gdk.Key.BackSpace) {
                // Send Ctrl+W sequence (standard terminal delete word backwards)
                terminal.feed_child("\x17".data);
                return true;
            }
    
            // Handle Ctrl+C (interrupt)
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 && keyval == Gdk.Key.c) {
                // Only send interrupt if no text is selected
                if (!terminal.get_has_selection()) {
                    terminal.feed_child("\x03".data);
                    return true;
                }
            }
    
            // Handle Ctrl+D
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 && keyval == Gdk.Key.d) {
                terminal.feed_child("\x04".data);
                return true;
            }
    
            return false;
        });
        terminal.add_controller(key_controller);
        terminal.can_focus = true;
    }

    private void setup_context_menu(Vte.Terminal terminal) {
    // Create a menu model
    var menu = new GLib.Menu();
    
    // Create sections for better organization (acts as separators)
    var section1 = new GLib.Menu();
    var section2 = new GLib.Menu();
    
    // Copy action
    var copy_action = new GLib.SimpleAction("copy", null);
    copy_action.activate.connect(() => copy_selection(terminal));
    this.add_action(copy_action);
    section1.append("Copy", "app.copy");
    
    // Paste action  
    var paste_action = new GLib.SimpleAction("paste", null);
    paste_action.activate.connect(() => paste_clipboard(terminal));
    this.add_action(paste_action);
    section1.append("Paste", "app.paste");
    
    // Select all action
    var select_all_action = new GLib.SimpleAction("select_all", null);
    select_all_action.activate.connect(() => terminal.select_all());
    this.add_action(select_all_action);
    section2.append("Select All", "app.select_all");
    
    // Add sections to main menu
    menu.append_section(null, section1);
    menu.append_section(null, section2);
    
    // Create popover menu
    var context_menu = new Gtk.PopoverMenu.from_model(menu);
    
    // Right click gesture for context menu
    var right_click = new Gtk.GestureClick() {
        button = Gdk.BUTTON_SECONDARY
    };
    
    right_click.pressed.connect((n_press, x, y) => {
        // Update action states
        copy_action.set_enabled(terminal.get_has_selection());
        
        // Check clipboard content
        var clipboard = terminal.get_clipboard();
        clipboard.read_text_async.begin(null, (obj, res) => {
            try {
                string? text = clipboard.read_text_async.end(res);
                paste_action.set_enabled(text != null && text.length > 0);
            } catch (Error e) {
                paste_action.set_enabled(false);
            }
        });
        
        // Position and show menu
        var rect = Gdk.Rectangle() {
            x = (int)x,
            y = (int)y,
            width = 1,
            height = 1
        };
        context_menu.set_pointing_to(rect);
        context_menu.set_parent(terminal);
        context_menu.popup();
    });
    
    terminal.add_controller(right_click);
}
    private void copy_selection(Vte.Terminal terminal) {
        if (terminal.get_has_selection()) {
            terminal.copy_clipboard_format(Vte.Format.TEXT);
            
            // Show a subtle notification
            show_copy_notification();
        }
    }
    
    private void paste_clipboard(Vte.Terminal terminal) {
        var clipboard = terminal.get_clipboard();
        clipboard.read_text_async.begin(null, (obj, res) => {
            try {
                string? text = clipboard.read_text_async.end(res);
                if (text != null && text.length > 0) {
                    // Check if text contains newlines and warn user for multi-line pastes
                    if ("\n" in text || "\r" in text) {
                        string[] lines = text.split("\n");
                        if (lines.length > 1) {
                            show_multiline_paste_dialog(terminal, text, lines.length);
                            return;
                        }
                    }
                    
                    // Safe to paste directly
                    terminal.paste_clipboard();
                }
            } catch (Error e) {
                warning("Failed to paste from clipboard: %s", e.message);
            }
        });
    }
    
    private void show_copy_notification() {
        var toast = new Adw.Toast("Copied to clipboard") {
            timeout = 2
        };
        
        var toast_overlay = get_toast_overlay();
        if (toast_overlay != null) {
            toast_overlay.add_toast(toast);
        }
    }
    
    private void show_multiline_paste_dialog(Vte.Terminal terminal, string text, int line_count) {
        var dialog = new Adw.MessageDialog(
            window,
            "Paste Multiple Lines?",
            "You are about to paste %d lines of text. This might execute multiple commands.".printf(line_count)
        );
        
        dialog.add_response("cancel", "Cancel");
        dialog.add_response("paste", "Paste Anyway");
        dialog.set_response_appearance("paste", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.set_default_response("cancel");
        
        dialog.response.connect((response_id) => {
            if (response_id == "paste") {
                terminal.paste_clipboard();
            }
            dialog.destroy();
        });
        
        dialog.present();
    }

    private void spawn_shell(Vte.Terminal terminal) {
        // Wayland environment setup
        var env = Environ.get();
        env = Environ.set_variable(env, "TERM", "xterm-256color");
        env = Environ.set_variable(env, "COLORTERM", "truecolor");
        env = Environ.set_variable(env, "GDK_BACKEND", "wayland");

        // Spawn shell
        try {
            string? shell = Environment.get_variable("SHELL") ?? "/bin/bash";
            string[] argv = { shell };
            terminal.spawn_async(
                Vte.PtyFlags.DEFAULT,
                Environment.get_current_dir(),
                argv,
                env,
                GLib.SpawnFlags.SEARCH_PATH,
                null,      // child_setup
                -1,        // timeout
                null,      // cancellable
                null       // callback
            );
        } catch (Error e) {
            print("Shell error: %s\n", e.message);
        }
    }

    private void setup_shortcuts() {
        // Create shortcut controller for application-level shortcuts
        var shortcuts = new Gtk.ShortcutController();
        shortcuts.set_scope(Gtk.ShortcutScope.MANAGED);
        window.add_controller(shortcuts);

        // Alt+T - New tab
        var new_tab_shortcut = new Gtk.Shortcut(
            Gtk.ShortcutTrigger.parse_string("<Alt>t"),
            new Gtk.CallbackAction((widget, args) => {
                create_new_tab();
                return true;
            })
        );
        shortcuts.add_shortcut(new_tab_shortcut);

        // Alt+W - Close current tab
        var close_tab_shortcut = new Gtk.Shortcut(
            Gtk.ShortcutTrigger.parse_string("<Alt>w"),
            new Gtk.CallbackAction((widget, args) => {
                if (tab_view.selected_page != null) {
                    tab_view.close_page(tab_view.selected_page);
                }
                return true;
            })
        );
        shortcuts.add_shortcut(close_tab_shortcut);

        // Alt+Left Arrow - Previous tab
        var prev_tab_shortcut = new Gtk.Shortcut(
            Gtk.ShortcutTrigger.parse_string("<Alt>Left"),
            new Gtk.CallbackAction((widget, args) => {
                var current_pos = tab_view.get_page_position(tab_view.selected_page);
                var n_pages = tab_view.get_n_pages();
                if (n_pages > 1) {
                    var prev_pos = (current_pos - 1 + n_pages) % n_pages;
                    tab_view.selected_page = tab_view.get_nth_page(prev_pos);
                }
                return true;
            })
        );
        shortcuts.add_shortcut(prev_tab_shortcut);

        // Alt+Right Arrow - Next tab
        var next_tab_shortcut = new Gtk.Shortcut(
            Gtk.ShortcutTrigger.parse_string("<Alt>Right"),
            new Gtk.CallbackAction((widget, args) => {
                var current_pos = tab_view.get_page_position(tab_view.selected_page);
                var n_pages = tab_view.get_n_pages();
                if (n_pages > 1) {
                    var next_pos = (current_pos + 1) % n_pages;
                    tab_view.selected_page = tab_view.get_nth_page(next_pos);
                }
                return true;
            })
        );
        shortcuts.add_shortcut(next_tab_shortcut);

        // Ctrl+Comma - Settings
        var settings_shortcut = new Gtk.Shortcut(
            Gtk.ShortcutTrigger.parse_string("<Control>comma"),
            new Gtk.CallbackAction((widget, args) => {
                show_settings_dialog();
                return true;
            })
        );
        shortcuts.add_shortcut(settings_shortcut);
    }

    private bool on_tab_close(Adw.TabPage page) {
        // If this is the last tab, close the window
        if (tab_view.get_n_pages() <= 1) {
            window.close();
            return false;
        }
        return false; // Allow the tab to be closed
    }

    private void on_page_attached(Adw.TabPage page, int position) {
        // Update window title when tabs change
        update_window_title();
    }

    private void on_page_detached(Adw.TabPage page, int position) {
        // Update window title when tabs change
        update_window_title();
    }

    private void update_window_title() {
        var n_pages = tab_view.get_n_pages();
        if (n_pages == 1) {
            window.title = "WayTerm";
        } else {
            window.title = "WayTerm (%d tabs)".printf(n_pages);
        }
    }

    private Adw.TabPage? get_page_for_terminal(Vte.Terminal terminal) {
        for (int i = 0; i < tab_view.get_n_pages(); i++) {
            var page = tab_view.get_nth_page(i);
            var scrolled = page.child as Gtk.ScrolledWindow;
            if (scrolled != null && scrolled.child == terminal) {
                return page;
            }
        }
        return null;
    }

    private void update_terminal_colors(Vte.Terminal terminal, Adw.StyleManager style_manager) {
        var background = style_manager.dark ? "#242424" : "#fafafa";
        var foreground = style_manager.dark ? "#ffffff" : "#000000";
        
        var fg = Gdk.RGBA(); fg.parse(foreground);
        var bg = Gdk.RGBA(); bg.parse(background);
        
        terminal.set_colors(fg, bg, null);
    }

    private void load_css() {
        var provider = new Gtk.CssProvider();
        try {
            provider.load_from_string("""
                .wayterm-window {
                    background-color: @window_bg_color;
                }
                .wayterm-terminal {
                    padding: 12px;
                    background-color: @terminal_bg_color;
                }
                .wayterm-box {
                    background-color: @window_bg_color;
                }
                .tab-button {
                    min-width: 20px;
                    min-height: 20px;
                }
            """);
            
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        } catch (Error e) {
            warning("Failed to load CSS: %s", e.message);
        }
    }

    // Settings helper methods
    private bool get_bool_setting(string key, bool default_value) {
        try {
            return config.get_boolean("Settings", key);
        } catch (Error e) {
            return default_value;
        }
    }

    private void set_bool_setting(string key, bool value) {
        try {
            config.set_boolean("Settings", key, value);
            save_config();
        } catch (Error e) {
            warning("Could not save setting %s: %s", key, e.message);
        }
    }

    private int get_int_setting(string key, int default_value) {
        try {
            return config.get_integer("Settings", key);
        } catch (Error e) {
            return default_value;
        }
    }

    private void set_int_setting(string key, int value) {
        try {
            config.set_integer("Settings", key, value);
            save_config();
        } catch (Error e) {
            warning("Could not save setting %s: %s", key, e.message);
        }
    }

    private void save_config() {
        try {
            // Ensure config directory exists
            var config_dir = Path.get_dirname(config_path);
            DirUtils.create_with_parents(config_dir, 0755);
            
            // Save to file
            string data = config.to_data();
            FileUtils.set_contents(config_path, data);
        } catch (Error e) {
            warning("Could not save config: %s", e.message);
        }
    }

    public static int main(string[] args) {
        // Force Wayland mode
        Environment.set_variable("GDK_BACKEND", "wayland", true);
        Environment.set_variable("VTE_WAYLAND", "1", true);
        
        var app = new WayTerm();
        return app.run(args);
    }
}
