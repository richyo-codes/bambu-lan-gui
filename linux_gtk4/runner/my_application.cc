#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gdk/gdk.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  gboolean hide_titlebar;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static FlMethodChannel* window_drag_channel = nullptr;

static gboolean has_cli_flag(char** argv, const char* flag) {
  if (argv == nullptr || flag == nullptr) {
    return FALSE;
  }
  for (gint i = 0; argv[i] != nullptr; i++) {
    if (g_strcmp0(argv[i], flag) == 0) {
      return TRUE;
    }
  }
  return FALSE;
}

static gboolean env_enabled(const char* key) {
  const gchar* value = g_getenv(key);
  if (value == nullptr) {
    return FALSE;
  }
  return g_strcmp0(value, "1") == 0 || g_ascii_strcasecmp(value, "true") == 0;
}

static void window_drag_method_call_cb(FlMethodChannel* channel,
                                       FlMethodCall* method_call,
                                       gpointer user_data) {
  (void)channel;
  const gchar* method = fl_method_call_get_name(method_call);
  GtkWindow* window = GTK_WINDOW(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "startDrag") == 0) {
    GtkNative* native = gtk_widget_get_native(GTK_WIDGET(window));
    GdkSurface* surface = native != nullptr ? gtk_native_get_surface(native)
                                            : nullptr;
    GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
    GdkSeat* seat =
        display != nullptr ? gdk_display_get_default_seat(display) : nullptr;
    GdkDevice* pointer =
        seat != nullptr ? gdk_seat_get_pointer(seat) : nullptr;

    if (surface != nullptr && GDK_IS_TOPLEVEL(surface) && pointer != nullptr) {
      double x = 0.0;
      double y = 0.0;
      gdk_device_get_surface_at_position(pointer, &x, &y);
      gdk_toplevel_begin_move(
          GDK_TOPLEVEL(surface), pointer, 1, x, y, GDK_CURRENT_TIME);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "minimize") == 0) {
    gtk_window_minimize(window);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "maximize") == 0) {
    gtk_window_maximize(window);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "toggleMaximize") == 0) {
    gboolean is_maximized = FALSE;
    GtkNative* native = gtk_widget_get_native(GTK_WIDGET(window));
    GdkSurface* surface = native != nullptr ? gtk_native_get_surface(native)
                                            : nullptr;
    if (surface != nullptr && GDK_IS_TOPLEVEL(surface)) {
      const GdkToplevelState state = gdk_toplevel_get_state(GDK_TOPLEVEL(surface));
      is_maximized = (state & GDK_TOPLEVEL_STATE_MAXIMIZED) != 0;
    }
    if (is_maximized) {
      gtk_window_unmaximize(window);
    } else {
      gtk_window_maximize(window);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "close") == 0) {
    gtk_window_close(window);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond on app/window_drag channel: %s", error->message);
  }
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  (void)self;
  GtkRoot* root = gtk_widget_get_root(GTK_WIDGET(view));
  if (root == nullptr) {
    return;
  }
  gtk_window_present(GTK_WINDOW(root));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  gtk_window_set_title(window, "Bambu Printer Manager");
  if (self->hide_titlebar) {
    gtk_window_set_decorated(window, FALSE);
    gtk_window_set_titlebar(window, nullptr);
  } else {
    gtk_window_set_decorated(window, TRUE);
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_header_bar_set_show_title_buttons(header_bar, TRUE);
    GtkWidget* title_label = gtk_label_new("Bambu Printer Manager");
    gtk_header_bar_set_title_widget(header_bar, title_label);
    gtk_widget_set_visible(GTK_WIDGET(header_bar), TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);

  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  if (window_drag_channel == nullptr) {
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    window_drag_channel =
        fl_method_channel_new(messenger, "app/window_drag", FL_METHOD_CODEC(codec));
  }
  fl_method_channel_set_method_call_handler(
      window_drag_channel, window_drag_method_call_cb, window, nullptr);

  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_set_focusable(GTK_WIDGET(view), TRUE);
  gtk_widget_set_visible(GTK_WIDGET(view), TRUE);
  gtk_window_set_child(window, GTK_WIDGET(view));

  gtk_window_present(window);

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Hide native titlebar by default for GTK4 so Flutter header acts as CSD.
  self->hide_titlebar = !has_cli_flag(*arguments, "--show-titlebar") &&
                        !env_enabled("RND_SHOW_TITLEBAR");
  if (has_cli_flag(*arguments, "--hide-titlebar") ||
      env_enabled("RND_HIDE_TITLEBAR")) {
    self->hide_titlebar = TRUE;
  }

  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->hide_titlebar = TRUE;
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
