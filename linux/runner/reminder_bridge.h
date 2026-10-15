#ifndef MINDBUBBLE_LINUX_REMINDER_BRIDGE_H_
#define MINDBUBBLE_LINUX_REMINDER_BRIDGE_H_
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
void install_reminder_bridge(FlView* view, GtkWidget* window);
gboolean reminder_window_delete(GtkWidget* widget, GdkEvent* event, gpointer data);
#endif
