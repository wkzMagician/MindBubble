#include "reminder_bridge.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <gdiplus.h>
#include <objidl.h>
#include <shellapi.h>
#include <windows.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include "resource.h"

namespace {
constexpr UINT kTrayMsg = WM_APP + 47;
constexpr UINT kTrayId = 41;
constexpr UINT kFrameTimer = 42;
constexpr DWORD kFadeInMs = 320;
constexpr DWORD kFadeOutMs = 340;

HWND main_window = nullptr;
HWND reminder_window = nullptr;
bool keep_in_tray = false;
std::string reminder_bubble;
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;
std::unique_ptr<Gdiplus::Bitmap> artwork_image;
ULONG_PTR gdiplus_token = 0;
ULONGLONG show_started = 0;
DWORD visibility_ms = 10000;
int artwork_width = 0;
int artwork_height = 0;

std::string StringArg(const flutter::EncodableMap& args, const char* key) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) return "";
  const auto* value = std::get_if<std::string>(&it->second);
  return value == nullptr ? "" : *value;
}
bool BoolArg(const flutter::EncodableMap& args, const char* key) {
  const auto it = args.find(flutter::EncodableValue(key));
  const auto* value = it != args.end() ? std::get_if<bool>(&it->second) : nullptr;
  return value != nullptr && *value;
}
int IntArg(const flutter::EncodableMap& args, const char* key, int fallback = 10) {
  const auto it = args.find(flutter::EncodableValue(key));
  const auto* value = it != args.end() ? std::get_if<int>(&it->second) : nullptr;
  return value == nullptr ? fallback : *value;
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
    channel->InvokeMethod(
        "opened", std::make_unique<flutter::EncodableValue>(reminder_bubble));
  }
  if (reminder_window) {
    DestroyWindow(reminder_window);
    reminder_window = nullptr;
  }
}

bool DecodeArtwork(const flutter::EncodableMap& args) {
  auto it = args.find(flutter::EncodableValue("artwork"));
  if (it == args.end()) return false;
  const auto* png = std::get_if<std::vector<uint8_t>>(&it->second);
  if (png == nullptr || png->empty() || png->size() > 8 * 1024 * 1024) return false;
  if (gdiplus_token == 0) {
    Gdiplus::GdiplusStartupInput startup;
    if (Gdiplus::GdiplusStartup(&gdiplus_token, &startup, nullptr) !=
        Gdiplus::Ok) {
      gdiplus_token = 0;
      return false;
    }
  }

  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, png->size());
  if (!memory) return false;
  void* buffer = GlobalLock(memory);
  if (!buffer) { GlobalFree(memory); return false; }
  memcpy(buffer, png->data(), png->size());
  GlobalUnlock(memory);

  IStream* stream = nullptr;
  if (FAILED(CreateStreamOnHGlobal(memory, TRUE, &stream))) {
    GlobalFree(memory);
    return false;
  }
  // Clone while the PNG's IStream is alive. GDI+ otherwise lazily accesses
  // bytes after the stream has been released.
  Gdiplus::Bitmap decoded(stream);
  std::unique_ptr<Gdiplus::Bitmap> image;
  if (decoded.GetLastStatus() == Gdiplus::Ok &&
      decoded.GetWidth() > 0 && decoded.GetWidth() <= 1024 &&
      decoded.GetHeight() > 0 && decoded.GetHeight() <= 1024) {
    image.reset(decoded.Clone(0, 0, decoded.GetWidth(), decoded.GetHeight(),
                              PixelFormat32bppPARGB));
  }
  stream->Release();
  if (!image || image->GetLastStatus() != Gdiplus::Ok) return false;
  artwork_width = static_cast<int>(image->GetWidth());
  artwork_height = static_cast<int>(image->GetHeight());
  artwork_image = std::move(image);
  return true;
}

void RenderFrame(HWND window) {
  if (!artwork_image || !window) return;
  const ULONGLONG elapsed = GetTickCount64() - show_started;
  if (elapsed >= visibility_ms) {
    DestroyWindow(window);
    return;
  }
  const double entering = std::min(1.0, elapsed / static_cast<double>(kFadeInMs));
  const double leaving = std::min(
      1.0, (visibility_ms - elapsed) / static_cast<double>(kFadeOutMs));
  const double visible = std::min(entering, leaving);
  const double eased = 1.0 - std::pow(1.0 - entering, 3.0);
  const double scale = .955 + eased * .045;
  const int dw = static_cast<int>(std::round(artwork_width * scale));
  const int dh = static_cast<int>(std::round(artwork_height * scale));
  const int dx = (artwork_width - dw) / 2;
  const int dy = (artwork_height - dh) / 2 -
                 static_cast<int>(std::sin(elapsed / 790.0) * 2.0);

  Gdiplus::Bitmap surface(artwork_width, artwork_height, PixelFormat32bppPARGB);
  {
  Gdiplus::Graphics graphics(&surface);
  graphics.SetCompositingMode(Gdiplus::CompositingModeSourceOver);
  graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
  graphics.DrawImage(artwork_image.get(), dx, dy, dw, dh);
  graphics.Flush();
  }  // Release the graphics context before LockBits on the same bitmap.

  HDC screen = GetDC(nullptr);
  if (!screen) return;
  HDC memory = CreateCompatibleDC(screen);
  if (!memory) { ReleaseDC(nullptr, screen); return; }
  BITMAPINFO bmp{};
  bmp.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmp.bmiHeader.biWidth = artwork_width;
  bmp.bmiHeader.biHeight = -artwork_height;
  bmp.bmiHeader.biPlanes = 1;
  bmp.bmiHeader.biBitCount = 32;
  bmp.bmiHeader.biCompression = BI_RGB;
  void* dib_pixels = nullptr;
  HBITMAP dib = CreateDIBSection(screen, &bmp, DIB_RGB_COLORS,
                                  &dib_pixels, nullptr, 0);
  if (dib && dib_pixels) {
    Gdiplus::BitmapData pixels{};
    Gdiplus::Rect rect(0, 0, artwork_width, artwork_height);
    if (surface.LockBits(&rect, Gdiplus::ImageLockModeRead,
                         PixelFormat32bppPARGB, &pixels) == Gdiplus::Ok) {
      for (int y = 0; y < artwork_height; ++y) {
        const auto* src = static_cast<const unsigned char*>(pixels.Scan0) +
                          y * pixels.Stride;
        auto* dst = static_cast<unsigned char*>(dib_pixels) +
                    y * artwork_width * 4;
        memcpy(dst, src, artwork_width * 4);
      }
      surface.UnlockBits(&pixels);
      HGDIOBJ old = SelectObject(memory, dib);
      RECT wr{};
      GetWindowRect(window, &wr);
      POINT dst{wr.left, wr.top};
      POINT origin{0, 0};
      SIZE size{artwork_width, artwork_height};
      BLENDFUNCTION blend{AC_SRC_OVER, 0,
                          static_cast<BYTE>(std::round(255 * visible)),
                          AC_SRC_ALPHA};
      UpdateLayeredWindow(window, screen, &dst, &size, memory, &origin,
                          0, &blend, ULW_ALPHA);
      SelectObject(memory, old);
    }
    DeleteObject(dib);
  }
  DeleteDC(memory);
  ReleaseDC(nullptr, screen);
}

LRESULT CALLBACK Popup(HWND window, UINT message, WPARAM w, LPARAM l) {
  if (message == WM_LBUTTONUP) { Open(); return 0; }
  if (message == WM_TIMER && w == kFrameTimer) {
    RenderFrame(window);
    return 0;
  }
  if (message == WM_ERASEBKGND) return 1;
  if (message == WM_DESTROY) {
    KillTimer(window, kFrameTimer);
    if (window == reminder_window) reminder_window = nullptr;
    return 0;
  }
  return DefWindowProcW(window, message, w, l);
}

bool ShowPopup(const flutter::EncodableMap& args) {
  if (reminder_window) DestroyWindow(reminder_window);
  reminder_window = nullptr;
  artwork_image.reset();
  if (!DecodeArtwork(args)) return false;

  reminder_bubble = StringArg(args, "bubbleId");
  const int seconds = IntArg(args, "seconds");
  const std::string corner = StringArg(args, "corner");

  WNDCLASSW wc{};
  wc.lpfnWndProc = Popup;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = L"MindBubbleReminderPopup";
  wc.hCursor = LoadCursorW(nullptr, IDC_HAND);
  RegisterClassW(&wc);

  RECT work{};
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  const bool right = corner.find("Right") != std::string::npos;
  const bool bottom = corner.find("bottom") != std::string::npos;
  const int x = right ? work.right - artwork_width - 14 : work.left + 14;
  const int y = bottom ? work.bottom - artwork_height - 14 : work.top + 14;
  reminder_window = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED,
      wc.lpszClassName, L"MindBubble Reminder", WS_POPUP,
      x, y, artwork_width, artwork_height, nullptr, nullptr,
      GetModuleHandleW(nullptr), nullptr);
  if (!reminder_window) return false;
  visibility_ms = static_cast<DWORD>(std::max(1, seconds)) * 1000;
  show_started = GetTickCount64();
  RenderFrame(reminder_window);
  ShowWindow(reminder_window, SW_SHOWNOACTIVATE);
  SetTimer(reminder_window, kFrameTimer, 16, nullptr);
  return true;
}
}  // namespace

void InstallReminderBridge(flutter::BinaryMessenger* messenger, HWND hwnd) {
  main_window = hwnd;
  channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "mindbubble/reminder", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const auto* args = call.arguments()
            ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
        if (call.method_name() == "setKeepInTray" && args) {
          Tray(BoolArg(*args, "enabled"));
          result->Success();
        } else if (call.method_name() == "showOverlay" && args) {
          if (ShowPopup(*args)) {
            result->Success();
          } else {
            result->Error("ARTWORK_INVALID", "Cannot display floating bubble artwork");
          }
        } else if (call.method_name() == "consumeLaunchBubble") {
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
    POINT point;
    GetCursorPos(&point);
    HMENU menu = CreatePopupMenu();
    AppendMenuW(menu, MF_STRING, 1, L"打开浮念");
    AppendMenuW(menu, MF_STRING, 2, L"退出浮念");
    SetForegroundWindow(hwnd);
    const int chosen = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY,
                                      point.x, point.y, 0, hwnd, nullptr);
    DestroyMenu(menu);
    if (chosen == 1) {
      ShowWindow(hwnd, SW_RESTORE);
      SetForegroundWindow(hwnd);
    }
    if (chosen == 2) {
      Tray(false);
      DestroyWindow(hwnd);
    }
  }
  return true;
}

void ShutdownReminderBridge() {
  Tray(false);
  if (reminder_window) DestroyWindow(reminder_window);
  reminder_window = nullptr;
  artwork_image.reset();
  channel.reset();
  main_window = nullptr;
  if (gdiplus_token != 0) {
    Gdiplus::GdiplusShutdown(gdiplus_token);
    gdiplus_token = 0;
  }
}
