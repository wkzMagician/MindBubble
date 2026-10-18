#ifndef MINDBUBBLE_REMINDER_BRIDGE_H_
#define MINDBUBBLE_REMINDER_BRIDGE_H_
#include <flutter/binary_messenger.h>
#include <windows.h>
void InstallReminderBridge(flutter::BinaryMessenger* messenger, HWND hwnd);
bool ReminderHandleMessage(HWND hwnd, UINT message, WPARAM w, LPARAM l);
void ShutdownReminderBridge();
#endif
