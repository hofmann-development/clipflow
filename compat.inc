ifndef COMPAT_INC
COMPAT_INC equ 1

MOD_NOREPEAT equ 4000h

NIF_ICON equ 00000002h
NIF_MESSAGE equ 00000001h
NIF_TIP equ 00000004h

NIM_ADD equ 00000000h
NIM_DELETE equ 00000002h

NOTIFYICONDATAW struct
    cbSize DWORD ?
    hWnd HWND ?
    uID UINT ?
    uFlags UINT ?
    uCallbackMessage UINT ?
    hIcon HICON ?
    szTip WCHAR 128 dup(?)
    dwState DWORD ?
    dwStateMask DWORD ?
    szInfo WCHAR 256 dup(?)
    timeoutOrVersion UINT ?
    szInfoTitle WCHAR 64 dup(?)
    dwInfoFlags DWORD ?
    guidItem GUID <>
    hBalloonIcon HICON ?
NOTIFYICONDATAW ends

PNOTIFYICONDATAW typedef ptr NOTIFYICONDATAW

Shell_NotifyIconW proto notificationMessage:DWORD, notificationIconData:PNOTIFYICONDATAW

endif
