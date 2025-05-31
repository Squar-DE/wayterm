using Gtk;
using Adw;
using Vte;

public class TerminalTest : Adw.Application {
    public TerminalTest() {
        Object(application_id: "org.SquarDE.wayterm");
    }

    public override void activate() {
        var window = new Adw.ApplicationWindow(this) {
            title = "WayTerm",
            default_width = 800,
            default_height = 600
        };

        // Create header bar
        var header = new Adw.HeaderBar() {
            title_widget = new Adw.WindowTitle("WayTerm", "")
        };
        
        // Create VTE terminal
        var terminal = new Vte.Terminal() {
            scrollback_lines = 1000,
        };
        
        // Set terminal colors to match libadwaita theme
        var style_manager = Adw.StyleManager.get_default();
        update_terminal_colors(terminal, style_manager);
        
        // Connect style change signal
        style_manager.notify["dark"].connect(() => {
            update_terminal_colors(terminal, style_manager);
        });

        // Spawn the user's default shell
        try {
            string? shell = Environment.get_variable("SHELL");
            if (shell == null || shell == "") {
                shell = "/bin/bash"; // fallback
            }
            
            string[] argv = { shell };
            terminal.spawn_sync(
                Vte.PtyFlags.DEFAULT,
                null, // working directory
                argv,
                null, // environment
                SpawnFlags.SEARCH_PATH,
                null, // child setup
                null  // child pid
            );
        } catch (Error e) {
            print("Failed to spawn shell: %s\n", e.message);
        }

        // Create main box with header and terminal
        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        box.append(header);
        
        var scrolled = new Gtk.ScrolledWindow() {
            child = terminal,
            hexpand = true,
            vexpand = true
        };
        box.append(scrolled);
        
        window.content = box;
        window.present();
    }

    private void update_terminal_colors(Vte.Terminal terminal, Adw.StyleManager style_manager) {
        var background = style_manager.dark ? "#242424" : "#fafafa";
        var foreground = style_manager.dark ? "#ffffff" : "#000000";
        
        // Create RGBA objects
        var fg = Gdk.RGBA();
        fg.parse(foreground);
        
        var bg = Gdk.RGBA();
        bg.parse(background);
        
        // Create palette
        Gdk.RGBA[] palette = new Gdk.RGBA[16];
        
        palette[0] = create_rgba("#000000");  // black
        palette[1] = create_rgba("#cc0000");  // red
        palette[2] = create_rgba("#4e9a06");  // green
        palette[3] = create_rgba("#c4a000");  // yellow
        palette[4] = create_rgba("#3465a4");  // blue
        palette[5] = create_rgba("#75507b");  // magenta
        palette[6] = create_rgba("#06989a");  // cyan
        palette[7] = create_rgba("#d3d7cf");  // white
        palette[8] = create_rgba("#555753");  // bright black
        palette[9] = create_rgba("#ef2929");  // bright red
        palette[10] = create_rgba("#8ae234"); // bright green
        palette[11] = create_rgba("#fce94f"); // bright yellow
        palette[12] = create_rgba("#729fcf"); // bright blue
        palette[13] = create_rgba("#ad7fa8"); // bright magenta
        palette[14] = create_rgba("#34e2e2"); // bright cyan
        palette[15] = create_rgba("#eeeeec"); // bright white
        
        terminal.set_colors(fg, bg, palette);
    }

    private Gdk.RGBA create_rgba(string color) {
        var rgba = Gdk.RGBA();
        rgba.parse(color);
        return rgba;
    }

    public static int main(string[] args) {
        var app = new TerminalTest();
        return app.run(args);
    }
}
