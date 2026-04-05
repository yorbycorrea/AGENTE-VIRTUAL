// windows/win32_helper.dart
// ─────────────────────────────────────────────────────────────────────────────
// Llamadas directas a user32.dll via dart:ffi.
// Necesario porque window_manager no funciona en ventanas secundarias
// (su plugin nativo no se registra en el Flutter engine secundario).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

// ── Cargar DLLs ─────────────────────────────────────────────────────────────
final _user32  = DynamicLibrary.open('user32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');

// ── Funciones nativas ────────────────────────────────────────────────────────

final _FindWindowExW = _user32.lookupFunction<
    IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
    int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)>('FindWindowExW');

final _GetForegroundWindow = _user32
    .lookupFunction<IntPtr Function(), int Function()>('GetForegroundWindow');

final _GetWindowLongPtrW = _user32.lookupFunction<
    IntPtr Function(IntPtr, Int32),
    int Function(int, int)>('GetWindowLongPtrW');

final _SetWindowLongPtrW = _user32.lookupFunction<
    IntPtr Function(IntPtr, Int32, IntPtr),
    int Function(int, int, int)>('SetWindowLongPtrW');

final _SetWindowPos = _user32.lookupFunction<
    Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
    int Function(int, int, int, int, int, int, int)>('SetWindowPos');

final _SetLayeredWindowAttributes = _user32.lookupFunction<
    Int32 Function(IntPtr, Uint32, Uint8, Uint32),
    int Function(int, int, int, int)>('SetLayeredWindowAttributes');

final _GetSystemMetrics = _user32.lookupFunction<
    Int32 Function(Int32), int Function(int)>('GetSystemMetrics');

final _ReleaseCapture = _user32
    .lookupFunction<Int32 Function(), int Function()>('ReleaseCapture');

final _SendMessageW = _user32.lookupFunction<
    IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr),
    int Function(int, int, int, int)>('SendMessageW');

final _ShowWindow = _user32.lookupFunction<
    Int32 Function(IntPtr, Int32),
    int Function(int, int)>('ShowWindow');

final _EnumWindows = _user32.lookupFunction<
    Int32 Function(Pointer<NativeFunction<Int32 Function(IntPtr, IntPtr)>>, IntPtr),
    int Function(Pointer<NativeFunction<Int32 Function(IntPtr, IntPtr)>>, int)>('EnumWindows');

final _GetWindowThreadProcessId = _user32.lookupFunction<
    Uint32 Function(IntPtr, Pointer<Uint32>),
    int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');

final _GetClassNameW = _user32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Utf16>, Int32),
    int Function(int, Pointer<Utf16>, int)>('GetClassNameW');

final _GetWindowTextW = _user32.lookupFunction<
    Int32 Function(IntPtr, Pointer<Utf16>, Int32),
    int Function(int, Pointer<Utf16>, int)>('GetWindowTextW');

final _GetCurrentProcessId = _kernel32.lookupFunction<
    Uint32 Function(), int Function()>('GetCurrentProcessId');

final _IsWindowVisible = _user32.lookupFunction<
    Int32 Function(IntPtr), int Function(int)>('IsWindowVisible');

// ── Constantes Win32 ─────────────────────────────────────────────────────────
const _GWL_STYLE       = -16;
const _GWL_EXSTYLE     = -20;
const _WS_CAPTION      = 0x00C00000;
const _WS_THICKFRAME   = 0x00040000;
const _WS_SYSMENU      = 0x00080000;
const _WS_EX_LAYERED   = 0x00080000;
const _WS_EX_TOOLWINDOW = 0x00000080;
const _HWND_TOPMOST    = -1;
const _SWP_NOMOVE      = 0x0002;
const _SWP_NOSIZE      = 0x0001;
const _SWP_FRAMECHANGED = 0x0020;
const _LWA_COLORKEY    = 0x00000001;
const _SM_CXSCREEN     = 0;
const _SM_CYSCREEN     = 1;
const _WM_NCLBUTTONDOWN = 0x00A1;
const _HTCAPTION       = 2;
const _SW_SHOW         = 5;

// ── API pública ──────────────────────────────────────────────────────────────

// Lista global para recoger HWNDs durante EnumWindows callback
final List<int> _hwndsCandidatos = [];
int _miPid = 0;

// Callback para EnumWindows — se llama una vez por cada ventana top-level
int _enumCallback(int hwnd, int lParam) {
  final pidPtr = calloc<Uint32>();
  _GetWindowThreadProcessId(hwnd, pidPtr);
  final pid = pidPtr.value;
  calloc.free(pidPtr);

  if (pid != _miPid) return 1; // continuar enumerando

  // Obtener clase y título de TODAS las ventanas de nuestro proceso
  final classNameBuf = calloc<Uint16>(256).cast<Utf16>();
  final len = _GetClassNameW(hwnd, classNameBuf, 256);
  final className = len > 0 ? classNameBuf.toDartString() : '';
  calloc.free(classNameBuf);

  final titleBuf = calloc<Uint16>(256).cast<Utf16>();
  final titleLen = _GetWindowTextW(hwnd, titleBuf, 256);
  final title = titleLen > 0 ? titleBuf.toDartString() : '';
  calloc.free(titleBuf);

  final visible = _IsWindowVisible(hwnd);
  debugPrint('[Win32] PID=$pid HWND=$hwnd clase="$className" titulo="$title" visible=$visible');

  // Recoger ventanas Flutter de nuestro proceso
  if (className == 'FLUTTER_RUNNER_WIN32_WINDOW' ||
      className == 'FLUTTER_MULTI_WINDOW_WIN32_WINDOW') {
    _hwndsCandidatos.add(hwnd);
  }

  return 1; // continuar enumerando
}

/// Busca el HWND de la ventana del AGENTE.
/// Enumera todas las ventanas del proceso y busca la que NO sea la principal.
int _obtenerHwndAgente() {
  _hwndsCandidatos.clear();
  _miPid = _GetCurrentProcessId();
  debugPrint('[Win32] Mi PID: $_miPid');

  // Crear puntero al callback nativo
  final callbackPtr = Pointer.fromFunction<Int32 Function(IntPtr, IntPtr)>(
    _enumCallback, 0,
  );
  _EnumWindows(callbackPtr, 0);

  debugPrint('[Win32] Ventanas del proceso encontradas: ${_hwndsCandidatos.length}');

  if (_hwndsCandidatos.isEmpty) return 0;

  // Buscar la ventana que NO sea la principal (title != "mobile" y != "Agenda App")
  // y que NO sea una ventana de sistema/framework (GDI+, IME, etc.)
  for (final hwnd in _hwndsCandidatos) {
    final titleBuf = calloc<Uint16>(256).cast<Utf16>();
    final titleLen = _GetWindowTextW(hwnd, titleBuf, 256);
    final title = titleLen > 0 ? titleBuf.toDartString() : '';
    calloc.free(titleBuf);

    final classNameBuf = calloc<Uint16>(256).cast<Utf16>();
    final clsLen = _GetClassNameW(hwnd, classNameBuf, 256);
    final cls = clsLen > 0 ? classNameBuf.toDartString() : '';
    calloc.free(classNameBuf);

    // Ignorar la ventana principal
    if (title == 'mobile' || title == 'Agenda App') continue;
    // Ignorar ventanas de sistema
    if (cls.contains('IME') || cls.contains('GDI') || cls == 'MSCTFIME UI') continue;

    debugPrint('[Win32] → Candidata: HWND=$hwnd clase="$cls" titulo="$title"');
    return hwnd;
  }

  return 0;
}

/// Configura la ventana como flotante:
/// sin bordes, siempre encima, pixel negro = transparente.
void hacerVentanaFlotante() {
  final hwnd = _obtenerHwndAgente();
  debugPrint('[Win32] HWND encontrado: $hwnd (0 = no encontrado)');
  if (hwnd == 0) return;

  // 1. Quitar bordes (title bar, resize, sys menu)
  final style = _GetWindowLongPtrW(hwnd, _GWL_STYLE);
  _SetWindowLongPtrW(
    hwnd, _GWL_STYLE,
    style & ~_WS_CAPTION & ~_WS_THICKFRAME & ~_WS_SYSMENU,
  );

  // 2. Layered + ToolWindow (no taskbar, no Alt+Tab)
  final exStyle = _GetWindowLongPtrW(hwnd, _GWL_EXSTYLE);
  _SetWindowLongPtrW(
    hwnd, _GWL_EXSTYLE,
    exStyle | _WS_EX_LAYERED | _WS_EX_TOOLWINDOW,
  );

  // 3. Siempre encima + refrescar marco
  _SetWindowPos(hwnd, _HWND_TOPMOST, 0, 0, 0, 0,
      _SWP_NOMOVE | _SWP_NOSIZE | _SWP_FRAMECHANGED);

  // 4. Hacer transparente: color key = negro puro (0x000000)
  //    Scaffold con backgroundColor: Colors.transparent renderiza negro
  //    → esos pixeles se vuelven invisibles
  _SetLayeredWindowAttributes(hwnd, 0x00000000, 255, _LWA_COLORKEY);

  // 5. Asegurar que se muestre
  _ShowWindow(hwnd, _SW_SHOW);
}

/// Mover y redimensionar la ventana.
void moverVentana(int x, int y, int ancho, int alto) {
  final hwnd = _obtenerHwndAgente();
  if (hwnd == 0) return;
  _SetWindowPos(hwnd, _HWND_TOPMOST, x, y, ancho, alto, 0);
}

/// Obtener tamaño de pantalla principal.
(int ancho, int alto) obtenerTamanoPantalla() {
  return (_GetSystemMetrics(_SM_CXSCREEN), _GetSystemMetrics(_SM_CYSCREEN));
}

/// Iniciar arrastre de la ventana (simula drag de title bar).
void iniciarArrastre() {
  final hwnd = _obtenerHwndAgente();
  if (hwnd == 0) return;
  _ReleaseCapture();
  _SendMessageW(hwnd, _WM_NCLBUTTONDOWN, _HTCAPTION, 0);
}
