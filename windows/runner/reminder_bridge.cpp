#include "reminder_bridge.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <windows.h>
#include <memory>
#include <string>
#include "resource.h"

namespace {
constexpr UINT kTrayMsg = WM_APP + 47;
constexpr UINT kTrayId = 41;
constexpr UINT kTimerId = 42;
HWND main_window = nullptr;
HWND reminder_window = nullptr;
bool keep_in_tray = false;
bool red_note = false;
std::wstring reminder_title;
std::string reminder_bubble;
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;

std::wstring ToWide(const std::string& value) {
  int n = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (n <= 0) return L"";
  std::wstring output(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, output.data(), n);
  output.resize(n - 1);
  return output;
}
std::string StringArg(const flutter::EncodableMap& args, const char* key) {
  auto i = args.find(flutter::EncodableValue(key));
  if (i == args.end()) return "";
  auto* v = std::get_if<std::string>(&i->second);
  return v ? *v : "";
}
bool BoolArg(const flutter::EncodableMap& args, const char* key) {
  auto i = args.find(flutter::EncodableValue(key));
  return i != args.end() && std::get_if<bool>(&i->second) &&
         *std::get_if<bool>(&i->second);
}
int IntArg(const flutter::EncodableMap& args, const char* key) {
  auto i = args.find(flutter::EncodableValue(key));
  return i != args.end() && std::get_if<int>(&i->second)
      ? *std::get_if<int>(&i->second) : 10;
}
void Tray(bool enabled) {
  if (enabled == keep_in_tray) return;
  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon);
  icon.hWnd = main_window;
  icon.uID = kTrayId;
  icon.uCallbackMessage = kTrayMsg;
  if (enabled) {
    icon.uFlags = NIF_ICON | NIF_TIP | NIF_MESSAGE;
    icon.hIcon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
    wcscpy_s(icon.szTip, L"MindBubble 浮念");
    Shell_NotifyIconW(NIM_ADD, &icon);
  } else {
    Shell_NotifyIconW(NIM_DELETE, &icon);
  }
  keep_in_tray = enabled;
}
void Open() {
  if (main_window) {
    ShowWindow(main_window, SW_RESTORE);
    SetForegroundWindow(main_window);
  }
  if (channel && !reminder_bubble.empty()) {
    channel->InvokeMethod("opened", std::make_unique<flutter::EncodableValue>(reminder_bubble));
  }
  if (reminder_window) {
    DestroyWindow(reminder_window);
    reminder_window = nullptr;
  }
}
LRESULT CALLBACK Popup(HWND hwnd, UINT msg, WPARAM w, LPARAM l) {
  if (msg == WM_LBUTTONUP) { Open(); return 0; }
  if (msg == WM_TIMER && w == kTimerId) {
    DestroyWindow(hwnd);
    reminder_window = nullptr;
    return 0;
  }
  if (msg == WM_PAINT) {
    PAINTSTRUCT ps{};
    auto dc = BeginPaint(hwnd, &ps);
    RECT rect{}; GetClientRect(hwnd, &rect);
    auto fill = CreateSolidBrush(red_note ? RGB(250,248,246) : RGB(28,112,152));
    FillRect(dc, &rect, fill);
    DeleteObject(fill);
    if (red_note) {
      RECT strip{0,0,5,rect.bottom};
      auto color = CreateSolidBrush(RGB(255,36,66));
      FillRect(dc, &strip, color);
      DeleteObject(color);
    }
    InflateRect(&rect, -22, -20);
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, red_note ? RGB(37,37,37) : RGB(248,252,255));
    auto font = CreateFontW(20,0,0,0,FW_SEMIBOLD,FALSE,FALSE,FALSE,DEFAULT_CHARSET,
                            OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,
                            CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Microsoft YaHei");
    auto old = SelectObject(dc, font);
    DrawTextW(dc, reminder_title.c_str(), -1, &rect,
              DT_CENTER | DT_VCENTER | DT_WORDBREAK | DT_END_ELLIPSIS);
    SelectObject(dc, old);
    DeleteObject(font);
    EndPaint(hwnd, &ps);
    return 0;
  }
  if (msg == WM_DESTROY) reminder_window = nullptr;
  return DefWindowProcW(hwnd, msg, w, l);
}
void ShowPopup(const flutter::EncodableMap& args) {
  if (reminder_window) DestroyWindow(reminder_window);
  reminder_bubble = StringArg(args, "bubbleId");
  reminder_title = ToWide(StringArg(args, "title"));
  red_note = BoolArg(args, "redNote");
  int seconds = IntArg(args, "seconds");
  auto corner = StringArg(args, "corner");
  WNDCLASSW wc{};
  wc.lpfnWndProc = Popup;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = L"MindBubbleReminderPopup";
  wc.hCursor = LoadCursorW(nullptr, IDC_HAND);
  RegisterClassW(&wc);
  int width = red_note ? 340 : 205;
  int height = red_note ? 100 : 205;
  RECT work{}; SystemParametersInfoW(SPI_GETWORKAREA,0,&work,0);
  int x = corner.find("Right") != std::string::npos ? work.right-width-28 : work.left+28;
  int y = corner.find("bottom") != std::string::npos ? work.bottom-height-28 : work.top+28;
  reminder_window = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      wc.lpszClassName,L"MindBubble Reminder",WS_POPUP,x,y,width,height,
      nullptr,nullptr,GetModuleHandleW(nullptr),nullptr);
  if (reminder_window) {
    SetWindowRgn(reminder_window,CreateRoundRectRgn(0,0,width,height,
        red_note ? 22 : 205,red_note ? 22 : 205),TRUE);
    ShowWindow(reminder_window,SW_SHOWNOACTIVATE);
    SetTimer(reminder_window,kTimerId,(seconds > 0 ? seconds : 10)*1000,nullptr);
  }
}
}

void InstallReminderBridge(flutter::BinaryMessenger* messenger, HWND hwnd) {
  main_window = hwnd;
  channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "mindbubble/reminder", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const auto* args = call.arguments()
            ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
        if (call.method_name()=="setKeepInTray" && args) {
          Tray(BoolArg(*args,"enabled"));
          result->Success();
        } else if (call.method_name()=="showOverlay" && args) {
          ShowPopup(*args);
          result->Success();
        } else if (call.method_name()=="consumeLaunchBubble") {
          result->Success(flutter::EncodableValue());
        } else {
          result->NotImplemented();
        }
      });
}
bool ReminderHandleMessage(HWND hwnd, UINT message, WPARAM w, LPARAM l) {
  if (message == WM_CLOSE && keep_in_tray) {
    ShowWindow(hwnd, SW_HIDE);
    return true;
  }
  if (message != kTrayMsg) return false;
  if (l == WM_LBUTTONUP || l == WM_LBUTTONDBLCLK) {
    ShowWindow(hwnd, SW_RESTORE);
    SetForegroundWindow(hwnd);
  } else if (l == WM_RBUTTONUP) {
    POINT point; GetCursorPos(&point);
    auto menu = CreatePopupMenu();
    AppendMenuW(menu,MF_STRING,1,L"打开浮念");
    AppendMenuW(menu,MF_STRING,2,L"退出浮念");
    SetForegroundWindow(hwnd);
    auto selected = TrackPopupMenu(menu,TPM_RETURNCMD | TPM_NONOTIFY,
                                   point.x,point.y,0,hwnd,nullptr);
    DestroyMenu(menu);
    if (selected == 1) { ShowWindow(hwnd,SW_RESTORE); SetForegroundWindow(hwnd); }
    if (selected == 2) { Tray(false); DestroyWindow(hwnd); }
  }
  return true;
}
void ShutdownReminderBridge() {
  Tray(false);
  if (reminder_window) DestroyWindow(reminder_window);
  reminder_window = nullptr;
  channel.reset();
  main_window = nullptr;
}
