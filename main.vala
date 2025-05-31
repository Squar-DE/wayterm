using Gtk;
using Adw;
using Vte;

public class WayTerm : Adw.Application {
    private const double FONT_WIDTH_SCALE = 0.55; // Perfect balance for text/icons
    
    public WayTerm() {
        Object(application_id: "org.SquarDE.wayterm");
    }

    public override void activate() {
        var window = new Adw.ApplicationWindow(this) {
            title = "WayTerm",
            default_width = 800,
            default_height = 600
        };

        // Add custom CSS class to window
        window.get_style_context().add_class("wayterm-window");

        // Create header bar with controls
        var header = new Adw.HeaderBar() {
            title_widget = new Adw.WindowTitle("WayTerm", "")
        };

        // Create terminal with perfect proportions
        var terminal = new Vte.Terminal() {
            scrollback_lines = 1000
        };
        
        terminal.child_exited.connect((status) => {
          window.close();
        });

        // Enable mouse autohide
        terminal.set_mouse_autohide(true);

        // Add custom CSS class to terminal
        terminal.get_style_context().add_class("wayterm-terminal");

        // Font settings that prevent stretching
        try {
            var font = new Pango.FontDescription();
    
            string font_family = "monospace"; // Default fallback
    
            // Get the user's configured monospace font from system settings
            try {
                var settings = new GLib.Settings("org.gnome.desktop.interface");
                string system_monospace = settings.get_string("monospace-font-name");
                if (system_monospace != "") {
                    // Parse the font string to extract family name
                    var font_desc = Pango.FontDescription.from_string(system_monospace);
                    string family = font_desc.get_family();
                    if (family != null && family != "") {
                      font_family = family + ", Symbols Nerd Font Mono, monospace";
                    }
                }
            } catch (Error e) {
              // If we can't get system settings, fall back to generic monospace
              warning("Could not get system monospace font, using default: %s", e.message);
              font_family = "monospace, Symbols Nerd Font Mono";
            }
    
            font.set_family(font_family);
            font.set_size(11 * Pango.SCALE);
            font.set_stretch(Pango.Stretch.SEMI_CONDENSED);
            terminal.set_font(font);
        } catch (Error e) {
          warning("Font error: %s", e.message);
        }
        // Cell scaling that maintains proportions
        terminal.set_cell_height_scale(1.0);
        terminal.set_cell_width_scale(FONT_WIDTH_SCALE);

        // Libadwaita color management
        var style_manager = Adw.StyleManager.get_default();
        update_terminal_colors(terminal, style_manager);
        style_manager.notify["dark"].connect(() => {
            update_terminal_colors(terminal, style_manager);
        });
        
        var key_controller = new Gtk.EventControllerKey();
        key_controller.key_pressed.connect((keyval, keycode, state) => {
            // Handle Ctrl+Backspace (delete word backwards)
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 && keyval == Gdk.Key.BackSpace) {
                // Send Ctrl+W sequence (standard terminal delete word backwards)
                terminal.feed_child("\x17".data);
                return true;
            }
    
            // Handle Ctrl+C
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 && keyval == Gdk.Key.c) {
                terminal.feed_child("\x03".data);
                return true;
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
        terminal.grab_focus();


        // Wayland environment setup
        var env = Environ.get();
        env = Environ.set_variable(env, "TERM", "xterm-256color");
        env = Environ.set_variable(env, "COLORTERM", "truecolor");
        env = Environ.set_variable(env, "GDK_BACKEND", "wayland");

        // Spawn shell (corrected spawn_async call with all required arguments)
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

        // Main layout with Libadwaita styling
        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        box.get_style_context().add_class("wayterm-box");
        box.append(header);
        
        var scrolled = new Gtk.ScrolledWindow() {
            child = terminal,
            hexpand = true,
            vexpand = true
        };
        box.append(scrolled);
        
        // Apply custom CSS
        load_css();
        
        window.content = box;
        window.present();
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
            provider.load_from_data((uint8[])"""
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

    public static int main(string[] args) {
        // Force Wayland mode
        Environment.set_variable("GDK_BACKEND", "wayland", true);
        Environment.set_variable("VTE_WAYLAND", "1", true);
        
        var app = new WayTerm();
        return app.run(args);
    }
}
