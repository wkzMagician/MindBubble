#include "reminder_bridge.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <stdint.h>

static FlMethodChannel* method_channel = nullptr;
static GtkWidget* main_widget = nullptr;
static GtkWidget* floating_widget = nullptr;
static GtkStatusIcon* tray_icon = nullptr;
static gboolean keep_in_tray = FALSE;
static gchar* current_bubble = nullptr;
static guint floating_timer_id = 0;

static void open_main(GtkWidget*, gpointer) {
  if (!main_widget) return;
  gtk_widget_show(main_widget);
  gtk_window_present(GTK_WINDOW(main_widget));
}

static void open_bubble(GtkWidget*, gpointer) {
  open_main(nullptr, nullptr);
  if (method_channel && current_bubble) {
    g_autoptr(FlValue) value = fl_value_new_string(current_bubble);
    fl_method_channel_invoke_method(
        method_channel, "opened", value, nullptr, nullptr, nullptr);
  }
  if (floating_widget) {
    gtk_widget_destroy(floating_widget);
    floating_widget = nullptr;
  }
}

static void exit_app(GtkWidget*, gpointer) {
  keep_in_tray = FALSE;
  if (main_widget) gtk_widget_destroy(main_widget);
}

static void tray_popup(GtkStatusIcon* icon, guint button, guint time, gpointer) {
  GtkWidget* menu = gtk_menu_new();
  GtkWidget* show = gtk_menu_item_new_with_label("打开浮念");
  GtkWidget* quit = gtk_menu_item_new_with_label("退出浮念");
  g_signal_connect(show, "activate", G_CALLBACK(open_main), nullptr);
  g_signal_connect(quit, "activate", G_CALLBACK(exit_app), nullptr);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), show);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), quit);
  gtk_widget_show_all(menu);
  gtk_menu_popup(GTK_MENU(menu), nullptr, nullptr,
                 gtk_status_icon_position_menu, icon, button, time);
}

static void set_tray(gboolean enabled) {
  if (keep_in_tray == enabled) return;
  keep_in_tray = enabled;
  if (enabled && !tray_icon) {
    tray_icon = gtk_status_icon_new_from_icon_name("dialog-information");
    gtk_status_icon_set_tooltip_text(tray_icon, "MindBubble 浮念");
    g_signal_connect(tray_icon, "activate", G_CALLBACK(open_main), nullptr);
    g_signal_connect(tray_icon, "popup-menu", G_CALLBACK(tray_popup), nullptr);
  } else if (!enabled && tray_icon) {
    gtk_status_icon_set_visible(tray_icon, FALSE);
    g_object_unref(tray_icon);
    tray_icon = nullptr;
  }
}

static gboolean popup_timeout(gpointer) {
  floating_timer_id = 0;
  if (floating_widget) {
    gtk_widget_destroy(floating_widget);
    floating_widget = nullptr;
  }
  return G_SOURCE_REMOVE;
}

static const gchar* arg_string(FlValue* args, const gchar* key) {
  FlValue* item = fl_value_lookup_string(args, key);
  return item && fl_value_get_type(item) == FL_VALUE_TYPE_STRING
      ? fl_value_get_string(item) : "";
}
static gboolean arg_bool(FlValue* args, const gchar* key) {
  FlValue* item = fl_value_lookup_string(args, key);
  return item && fl_value_get_type(item) == FL_VALUE_TYPE_BOOL
      ? fl_value_get_bool(item) : FALSE;
}
static gint arg_int(FlValue* args, const gchar* key, gint fallback) {
  FlValue* item = fl_value_lookup_string(args, key);
  return item && fl_value_get_type(item) == FL_VALUE_TYPE_INT
      ? fl_value_get_int(item) : fallback;
}

static void show_overlay(FlValue* args) {
  if (floating_timer_id != 0) {
    g_source_remove(floating_timer_id);
    floating_timer_id = 0;
  }
  popup_timeout(nullptr);
  FlValue* art = fl_value_lookup_string(args, "artwork");
  if (!art || fl_value_get_type(art) != FL_VALUE_TYPE_UINT8_LIST) return;
  const uint8_t* png = fl_value_get_uint8_list(art);
  const size_t length = fl_value_get_length(art);
  if (!png || length == 0 || length > 8 * 1024 * 1024) return;
  g_autoptr(GdkPixbufLoader) loader = gdk_pixbuf_loader_new();
  if (!gdk_pixbuf_loader_write(loader, png, length, nullptr) ||
      !gdk_pixbuf_loader_close(loader, nullptr)) return;
  GdkPixbuf* image_pixels = gdk_pixbuf_loader_get_pixbuf(loader);
  if (!image_pixels) return;
  g_object_ref(image_pixels);

  g_free(current_bubble);
  current_bubble = g_strdup(arg_string(args, "bubbleId"));
  const gchar* corner = arg_string(args, "corner");
  const gint seconds = arg_int(args, "seconds", 10);
  const gint width = gdk_pixbuf_get_width(image_pixels);
  const gint height = gdk_pixbuf_get_height(image_pixels);

  floating_widget = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  GtkWindow* popup = GTK_WINDOW(floating_widget);
  gtk_window_set_decorated(popup, FALSE);
  gtk_window_set_keep_above(popup, TRUE);
  gtk_window_set_skip_taskbar_hint(popup, TRUE);
  gtk_window_set_type_hint(popup, GDK_WINDOW_TYPE_HINT_NOTIFICATION);
  gtk_window_set_default_size(popup, width, height);
  gtk_widget_set_app_paintable(floating_widget, TRUE);
  GdkScreen* screen = gtk_window_get_screen(popup);
  GdkVisual* rgba_visual = gdk_screen_get_rgba_visual(screen);
  if (rgba_visual) gtk_widget_set_visual(floating_widget, rgba_visual);

  GtkWidget* button = gtk_button_new();
  GtkWidget* image = gtk_image_new_from_pixbuf(image_pixels);
  g_object_unref(image_pixels);
  GtkStyleContext* style = gtk_widget_get_style_context(button);
  GtkCssProvider* css = gtk_css_provider_new();
  gtk_css_provider_load_from_data(
      css,
      "button {background:transparent;border:0;box-shadow:none;"
      "border-radius:0;padding:0;} button:hover {background:transparent;}",
      -1, nullptr);
  gtk_style_context_add_provider(
      style, GTK_STYLE_PROVIDER(css),
      GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  g_object_unref(css);
  gtk_container_add(GTK_CONTAINER(button), image);
  gtk_container_add(GTK_CONTAINER(popup), button);
  g_signal_connect(button, "clicked", G_CALLBACK(open_bubble), nullptr);

  GdkRectangle area{};
  gdk_screen_get_monitor_workarea(
      screen, gdk_screen_get_primary_monitor(screen), &area);
  const gint x = g_str_has_suffix(corner, "Right")
      ? area.x + area.width - width - 14 : area.x + 14;
  const gint y = g_str_has_prefix(corner, "bottom")
      ? area.y + area.height - height - 14 : area.y + 14;
  gtk_window_move(popup, x, y);
  gtk_widget_show_all(floating_widget);
  floating_timer_id = g_timeout_add_seconds(
      seconds > 0 ? seconds : 10, popup_timeout, nullptr);
}

static void method_call(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (g_strcmp0(method, "setKeepInTray") == 0 && args) {
    set_tray(arg_bool(args, "enabled"));
  } else if (g_strcmp0(method, "showOverlay") == 0 && args) {
    show_overlay(args);
  } else if (g_strcmp0(method, "consumeLaunchBubble") != 0) {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(call, response, nullptr);
    return;
  }
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  fl_method_call_respond(call, response, nullptr);
}

void install_reminder_bridge(FlView* view, GtkWidget* window) {
  main_widget = window;
  FlEngine* engine = fl_view_get_engine(view);
  method_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine),
      "mindbubble/reminder",
      FL_METHOD_CODEC(fl_standard_method_codec_new()));
  fl_method_channel_set_method_call_handler(
      method_channel, method_call, nullptr, nullptr);
}

gboolean reminder_window_delete(GtkWidget* widget, GdkEvent*, gpointer) {
  if (!keep_in_tray) return FALSE;
  gtk_widget_hide(widget);
  return TRUE;
}
