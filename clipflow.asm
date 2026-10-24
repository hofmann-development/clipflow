;
; ClipFlow Version 1.0.0
; Copyright (C) Stefan Hofmann, 2026
;
; Assemble:
;   jwasm -nologo -I%USERPROFILE%\WinInc\Include -win64 -Zp8 [-DFREE_VERSION] clipflow.asm
;
; Resource compile:
;   rc /nologo /dFREE_VERSION clipflow.rc
;
; Link with LINK.EXE from the Windows SDK:
;   link /nologo /subsystem:windows clipflow.obj clipflow.res
;
option casemap:none
option scoped
option frame:auto
option win64:1

WIN32_LEAN_AND_MEAN equ 1

.nolist
.nocref
include windows.inc
include commdlg.inc
include compat.inc
include util.inc
.list
.cref

includelib comdlg32.lib
includelib kernel32.lib
includelib shell32.lib
includelib user32.lib

IDI_APPICON equ 1

HOTKEY_MODIFIERS equ MOD_CONTROL or MOD_ALT or MOD_NOREPEAT
LOAD_HOTKEY_ID equ 2
LOAD_VIRTUAL_KEY equ 'L'
SAVE_HOTKEY_ID equ 1
SAVE_VIRTUAL_KEY equ 'S'

FILE_PATH_CHARACTER_COUNT equ 32768
MAXIMUM_TEXT_FILE_BYTES equ 16777216

TRAY_CALLBACK_MESSAGE equ WM_APP + 1
TRAY_EXIT_COMMAND_ID equ 1001
TRAY_ICON_ID equ 1
TRAY_TOOLTIP_CHARACTER_COUNT equ 128

TEMPLATE_MULTILINE_DIALOG_ID equ 102
TEMPLATE_NAME_CONTROL_ID equ 1101
TEMPLATE_SINGLE_LINE_DIALOG_ID equ 101
TEMPLATE_VALUE_EDIT_ID equ 1102

MAXIMUM_EXPANDED_TEXT_CHARACTERS equ 16777216
ifdef FREE_VERSION
    MAXIMUM_TEMPLATE_FIELDS equ 1
else
    MAXIMUM_TEMPLATE_FIELDS equ 32
endif
MAXIMUM_TEMPLATE_NAME_CHARACTERS equ 128
MAXIMUM_TEMPLATE_VALUE_CHARACTERS equ 1048576
TEMPLATE_FIELD_MULTILINE equ 2
TEMPLATE_FIELD_SINGLE_LINE equ 1

TEMPLATE_COLLECTION_MEMORY_ERROR equ -1
TEMPLATE_COLLECTION_TOO_MANY_FIELDS equ -2
TEMPLATE_COLLECTION_TYPE_CONFLICT equ -3

TemplateField struct
    namePointer LPWSTR ?
    valuePointer LPWSTR ?
    nameLength DWORD ?
    valueLength DWORD ?
    fieldType DWORD ?
TemplateField ends

TemplateFieldPointer typedef ptr TemplateField

TemplatePlaceholder struct
    namePointer LPCWSTR ?
    endPointer LPCWSTR ?
    nameLength DWORD ?
    fieldType DWORD ?
TemplatePlaceholder ends

TemplatePlaceholderPointer typedef ptr TemplatePlaceholder

.data

WSTR ApplicationName, <ClipFlow>
WSTR MainWindowClassName, <ClipFlow>

WSTR TrayTooltip, <ClipFlow - Ctrl+Alt+S save, Ctrl+Alt+L load>
WSTR TrayExitText, <Exit>
WSTR DefaultExtension, <cf>
WSTR TaskbarCreatedText, <TaskbarCreated>

FileFilter label WCHAR
    WSTR , <*.cf>
    WSTR , <*.cf>
    WSTR , <*.txt>
    WSTR , <*.txt>
    WCHAR 0

WSTR InitializationFailedText, <ClipFlow could not be initialized.>
WSTR SaveHotkeyFailedText, <The Ctrl+Alt+S hotkey is already in use.>
WSTR LoadHotkeyFailedText, <The Ctrl+Alt+L hotkey is already in use.>
WSTR TrayIconFailedText, <The notification area icon could not be created.>

WSTR NoClipboardTextText, <The clipboard does not contain Unicode text.>
WSTR OpenClipboardFailedText, <The clipboard could not be opened.>
WSTR ReadClipboardFailedText, <The text could not be read from the clipboard.>
WSTR SetClipboardFailedText, <The text could not be placed on the clipboard.>

WSTR MemoryAllocationFailedText, <Not enough memory could be allocated.>

WSTR CreateFileFailedText, <The file could not be created.>
WSTR WriteFileFailedText, <The file could not be written completely.>
WSTR OpenFileFailedText, <The file could not be opened.>
WSTR ReadFileFailedText, <The file could not be read completely.>
WSTR FileTooLargeText, <The file is larger than 16 MiB.>

WSTR UnsupportedEncodingText, <UTF-16BE and malformed UTF-16 files are not supported.>
WSTR ConversionFailedText, <The text file could not be converted to Unicode.>

ifdef FREE_VERSION
    WSTR TooManyTemplateFieldsText, <This template contains more than one distinct field.>
else
    WSTR TooManyTemplateFieldsText, <This template contains more than 32 distinct fields.>
endif

WSTR TemplateFieldTypeConflictText, <A template field is used as both single-line and multiline.>
WSTR TemplateDialogFailedText, <The template input dialog could not be created.>
WSTR TemplateProcessingFailedText, <The template could not be processed.>
WSTR TemplateExpansionFailedText, <The expanded text is too large or could not be allocated.>

.data?

ApplicationInstance HINSTANCE ?
MainWindow HWND ?
TaskbarCreatedMessage UINT ?
OperationInProgress BOOL ?

MainWindowClass WNDCLASSEXW <>
TrayIconData NOTIFYICONDATAW <>
FileDialog OPENFILENAMEW <>
FilePath WCHAR FILE_PATH_CHARACTER_COUNT dup(?)
TemporaryDirectoryPath WCHAR FILE_PATH_CHARACTER_COUNT dup(?)
TemporaryFilePath WCHAR FILE_PATH_CHARACTER_COUNT dup(?)

.code

; Clears a memory range with zero bytes.
;
; Parameters:
;   rcx/destination - Address of the memory range
;   rdx/byteCount - Number of bytes to clear
;
; Returns:
;   Nothing
ClearBytes proc frame uses rdi destination:LPVOID, byteCount:SIZE_T
    cld
    mov rdi, destination
    mov rcx, byteCount
    xor eax, eax
    rep stosb
    ret
ClearBytes endp

; Copies a memory range.
;
; Parameters:
;   rcx/destination - Destination address
;   rdx/source - Source address
;   r8/byteCount - Number of bytes to copy
;
; Returns:
;   Nothing
CopyBytes proc frame uses rsi rdi destination:LPVOID, source:LPCVOID, byteCount:SIZE_T
    cld
    mov rdi, destination
    mov rsi, source
    mov rcx, byteCount
    rep movsb
    ret
CopyBytes endp

; Checks whether a byte range contains a zero byte.
;
; Parameters:
;   rcx/sourcePointer - Address of the byte range
;   edx/byteCount - Number of bytes to inspect
;
; Returns:
;   eax/BOOL - TRUE if a zero byte was found, otherwise FALSE
ByteRangeContainsZero proc frame uses rsi sourcePointer:LPCVOID, byteCount:DWORD
    mov rsi, sourcePointer
    mov ecx, byteCount

    test ecx, ecx
    jz byteRangeDoesNotContainZero

checkNextByte:
    cmp byte ptr [rsi], 0
    je byteRangeContainsZero

    inc rsi
    dec ecx
    jnz checkNextByte

byteRangeDoesNotContainZero:
    xor eax, eax
    ret

byteRangeContainsZero:
    mov eax, TRUE
    ret
ByteRangeContainsZero endp

; Checks whether a UTF-16 byte range contains a null character.
;
; Parameters:
;   rcx/sourcePointer - Address of the UTF-16 byte range
;   edx/byteCount - Number of bytes to inspect
;
; Returns:
;   eax/BOOL - TRUE if a null character was found, otherwise FALSE
WideRangeContainsZero proc frame uses rsi sourcePointer:LPCVOID, byteCount:DWORD
    mov rsi, sourcePointer
    mov ecx, byteCount
    shr ecx, 1

    test ecx, ecx
    jz wideRangeDoesNotContainZero

checkNextWideCharacter:
    cmp word ptr [rsi], 0
    je wideRangeContainsZero

    add rsi, 2
    dec ecx
    jnz checkNextWideCharacter

wideRangeDoesNotContainZero:
    xor eax, eax
    ret

wideRangeContainsZero:
    mov eax, TRUE
    ret
WideRangeContainsZero endp

; Writes a complete byte range to a file.
;
; Parameters:
;   rcx/fileHandle - Destination file handle
;   rdx/sourcePointer - Address of the byte range
;   r8d/byteCount - Number of bytes to write
;
; Returns:
;   eax/BOOL - TRUE if all bytes were written, otherwise FALSE
WriteAllBytes proc frame uses rsi fileHandle:HANDLE, sourcePointer:LPCVOID, byteCount:DWORD
    local remainingByteCount:DWORD
    local bytesWritten:DWORD

    mov rsi, sourcePointer
    mov eax, byteCount
    mov remainingByteCount, eax

writeNextBytes:
    .if remainingByteCount == 0
        mov eax, TRUE
        ret
    .endif

    mov bytesWritten, 0
    invoke WriteFile, fileHandle, rsi, remainingByteCount, addr bytesWritten, 0
    .if eax == 0
        xor eax, eax
        ret
    .endif

    .if bytesWritten == 0
        xor eax, eax
        ret
    .endif

    mov eax, bytesWritten
    add rsi, rax
    sub remainingByteCount, eax
    jmp writeNextBytes
WriteAllBytes endp

; Displays an error message box.
;
; Parameters:
;   rcx/ownerWindow - Owner window handle
;   rdx/textPointer - Address of the null-terminated error text
;
; Returns:
;   Nothing
ShowError proc frame ownerWindow:HWND, textPointer:LPCWSTR
    invoke MessageBoxW, ownerWindow, textPointer, addr ApplicationName, MB_OK or MB_ICONERROR
    ret
ShowError endp

; Initializes the shared OPENFILENAMEW structure.
;
; Parameters:
;   rcx/ownerWindow - Owner window handle
;   edx/dialogFlags - OPENFILENAMEW flags
;
; Returns:
;   Nothing
PrepareFileDialog proc frame ownerWindow:HWND, dialogFlags:DWORD
    invoke ClearBytes, addr FileDialog, sizeof OPENFILENAMEW
    mov word ptr [FilePath], 0

    mov FileDialog.lStructSize, sizeof OPENFILENAMEW

    mov rax, ownerWindow
    mov FileDialog.hwndOwner, rax

    lea rax, [FileFilter]
    mov FileDialog.lpstrFilter, rax
    mov FileDialog.nFilterIndex, 1

    lea rax, [FilePath]
    mov FileDialog.lpstrFile, rax
    mov FileDialog.nMaxFile, FILE_PATH_CHARACTER_COUNT

    mov FileDialog.lpstrTitle, 0

    mov eax, dialogFlags
    mov FileDialog.Flags, eax

    lea rax, [DefaultExtension]
    mov FileDialog.lpstrDefExt, rax
    ret
PrepareFileDialog endp

; Displays the file dialog used to select the destination file.
;
; Parameters:
;   rcx/ownerWindow - Owner window handle
;
; Returns:
;   eax/BOOL - Nonzero if a file was selected, otherwise zero
ShowSaveDialog proc frame ownerWindow:HWND
    invoke PrepareFileDialog, \
        ownerWindow, \
        OFN_EXPLORER or OFN_PATHMUSTEXIST or OFN_OVERWRITEPROMPT or OFN_HIDEREADONLY or OFN_NOCHANGEDIR

    invoke GetSaveFileNameW, addr FileDialog
    ret
ShowSaveDialog endp

; Displays the file dialog used to select the source file.
;
; Parameters:
;   rcx/ownerWindow - Owner window handle
;
; Returns:
;   eax/BOOL - Nonzero if a file was selected, otherwise zero
ShowOpenDialog proc frame ownerWindow:HWND
    invoke PrepareFileDialog, \
        ownerWindow, \
        OFN_EXPLORER or OFN_PATHMUSTEXIST or OFN_FILEMUSTEXIST or OFN_HIDEREADONLY or OFN_NOCHANGEDIR

    invoke GetOpenFileNameW, addr FileDialog
    ret
ShowOpenDialog endp

; Compares two UTF-16 character sequences with the same length.
;
; Parameters:
;   rcx/firstPointer - Address of the first character sequence
;   rdx/secondPointer - Address of the second character sequence
;   r8d/characterCount - Number of UTF-16 characters to compare
;
; Returns:
;   eax/BOOL - TRUE if the character sequences are equal, otherwise FALSE
WideStringPartsEqual proc frame uses rsi rdi firstPointer:LPCWSTR, secondPointer:LPCWSTR, characterCount:DWORD
    cld
    mov rsi, firstPointer
    mov rdi, secondPointer
    mov ecx, characterCount
    repe cmpsw
    sete al
    movzx eax, al
    ret
WideStringPartsEqual endp

; Parses a template field that starts with two dollar signs.
;
; Parameters:
;   rcx/startPointer - Address of the opening dollar signs
;   rdx/placeholderPointer - Address of the result structure
;
; Returns:
;   eax/BOOL - TRUE if a valid template field was parsed, otherwise FALSE
ParseTemplatePlaceholder proc frame uses rsi startPointer:LPCWSTR, placeholderPointer:TemplatePlaceholderPointer
    local nameStart:LPCWSTR
    local nameEnd:LPCWSTR
    local closingPointer:LPCWSTR
    local fieldType:DWORD

    mov rsi, startPointer

    cmp word ptr [rsi], '$'
    jne invalidPlaceholder
    cmp word ptr [rsi + 2], '$'
    jne invalidPlaceholder

    add rsi, 4
    mov fieldType, TEMPLATE_FIELD_SINGLE_LINE

    cmp word ptr [rsi], '#'
    jne trimLeadingWhitespace

    mov fieldType, TEMPLATE_FIELD_MULTILINE
    add rsi, 2

trimLeadingWhitespace:
    mov ax, word ptr [rsi]

    cmp ax, ' '
    je skipLeadingWhitespace
    cmp ax, 9
    jne leadingWhitespaceFinished

skipLeadingWhitespace:
    add rsi, 2
    jmp trimLeadingWhitespace

leadingWhitespaceFinished:
    mov nameStart, rsi

findClosingDelimiter:
    mov ax, word ptr [rsi]

    test ax, ax
    jz invalidPlaceholder
    cmp ax, 13
    je invalidPlaceholder
    cmp ax, 10
    je invalidPlaceholder
    cmp ax, '$'
    jne continueDelimiterSearch
    cmp word ptr [rsi + 2], '$'
    je closingDelimiterFound

continueDelimiterSearch:
    add rsi, 2
    jmp findClosingDelimiter

closingDelimiterFound:
    mov closingPointer, rsi
    mov nameEnd, rsi

trimTrailingWhitespace:
    mov rax, nameEnd
    cmp rax, nameStart
    jbe invalidPlaceholder

    mov cx, word ptr [rax - 2]

    cmp cx, ' '
    je removeTrailingWhitespace
    cmp cx, 9
    jne placeholderNameReady

removeTrailingWhitespace:
    sub rax, 2
    mov nameEnd, rax
    jmp trimTrailingWhitespace

placeholderNameReady:
    mov rax, nameEnd
    sub rax, nameStart
    shr rax, 1

    test eax, eax
    jz invalidPlaceholder
    cmp eax, MAXIMUM_TEMPLATE_NAME_CHARACTERS
    ja invalidPlaceholder

    mov rdx, placeholderPointer

    mov rcx, nameStart
    mov [rdx].TemplatePlaceholder.namePointer, rcx

    mov rcx, closingPointer
    add rcx, 4
    mov [rdx].TemplatePlaceholder.endPointer, rcx

    mov [rdx].TemplatePlaceholder.nameLength, eax

    mov eax, fieldType
    mov [rdx].TemplatePlaceholder.fieldType, eax

    mov eax, TRUE
    ret

invalidPlaceholder:
    xor eax, eax
    ret
ParseTemplatePlaceholder endp

; Finds a template field by its case-sensitive name.
;
; Parameters:
;   rcx/fieldsPointer - Address of the template field array
;   edx/fieldCount - Number of template fields
;   r8/namePointer - Address of the field name
;   r9d/nameLength - Number of UTF-16 characters in the field name
;
; Returns:
;   rax/TemplateFieldPointer - Matching field, or zero if no field matches
FindTemplateFieldByName proc frame \
    fieldsPointer:TemplateFieldPointer, \
    fieldCount:DWORD, \
    namePointer:LPCWSTR, \
    nameLength:DWORD
    local fieldIndex:DWORD
    local fieldPointer:TemplateFieldPointer

    mov fieldIndex, 0

findNextField:
    mov eax, fieldIndex
    cmp eax, fieldCount
    jae fieldNotFound

    imul rax, rax, sizeof TemplateField
    add rax, fieldsPointer
    mov fieldPointer, rax

    mov rdx, fieldPointer
    mov eax, [rdx].TemplateField.nameLength
    cmp eax, nameLength
    jne continueFieldSearch

    mov rax, [rdx].TemplateField.namePointer
    invoke WideStringPartsEqual, rax, namePointer, nameLength

    .if eax != 0
        mov rax, fieldPointer
        ret
    .endif

continueFieldSearch:
    inc fieldIndex
    jmp findNextField

fieldNotFound:
    xor eax, eax
    ret
FindTemplateFieldByName endp

; Finds a template field by name and field type.
;
; Parameters:
;   rcx/fieldsPointer - Address of the template field array
;   edx/fieldCount - Number of template fields
;   r8/namePointer - Address of the field name
;   r9d/nameLength - Number of UTF-16 characters in the field name
;   stack/fieldType - Template field type
;
; Returns:
;   rax/TemplateFieldPointer - Matching field, or zero if no field matches
FindTemplateField proc frame \
    fieldsPointer:TemplateFieldPointer, \
    fieldCount:DWORD, \
    namePointer:LPCWSTR, \
    nameLength:DWORD, \
    fieldType:DWORD
    invoke FindTemplateFieldByName, fieldsPointer, fieldCount, namePointer, nameLength
    .if rax == 0
        ret
    .endif

    mov edx, [rax].TemplateField.fieldType
    cmp edx, fieldType
    jne fieldTypeDoesNotMatch

    ret

fieldTypeDoesNotMatch:
    xor eax, eax
    ret
FindTemplateField endp

; Frees all names and values stored in a template field array.
;
; Parameters:
;   rcx/processHeap - Process heap handle
;   rdx/fieldsPointer - Address of the template field array
;   r8d/fieldCount - Number of template fields
;
; Returns:
;   Nothing
FreeTemplateFields proc frame processHeap:HANDLE, fieldsPointer:TemplateFieldPointer, fieldCount:DWORD
    local fieldIndex:DWORD
    local fieldPointer:TemplateFieldPointer

    mov fieldIndex, 0

freeNextField:
    mov eax, fieldIndex
    cmp eax, fieldCount
    jae fieldsFreed

    imul rax, rax, sizeof TemplateField
    add rax, fieldsPointer
    mov fieldPointer, rax

    mov rdx, fieldPointer
    mov rax, [rdx].TemplateField.namePointer

    .if rax != 0
        invoke HeapFree, processHeap, 0, rax
    .endif

    mov rdx, fieldPointer
    mov rax, [rdx].TemplateField.valuePointer

    .if rax != 0
        invoke HeapFree, processHeap, 0, rax
    .endif

    inc fieldIndex
    jmp freeNextField

fieldsFreed:
    ret
FreeTemplateFields endp

; Collects the different fields contained in a template.
;
; Parameters:
;   rcx/processHeap - Process heap handle
;   rdx/templatePointer - Address of the null-terminated template text
;   r8/fieldsPointer - Address of the template field array
;   r9/hasEscapedDelimiterPointer - Address that receives whether an escaped delimiter was found
;
; Returns:
;   eax/SDWORD - Number of fields, or a negative template collection error
CollectTemplateFields proc frame uses rsi \
    processHeap:HANDLE, \
    templatePointer:LPCWSTR, \
    fieldsPointer:TemplateFieldPointer, \
    hasEscapedDelimiterPointer:LPBOOL
    local fieldCount:DWORD
    local placeholderData:TemplatePlaceholder
    local nameMemory:LPWSTR

    mov fieldCount, 0

    mov rdx, hasEscapedDelimiterPointer
    mov dword ptr [rdx], FALSE

    mov rsi, templatePointer

scanTemplate:
    mov ax, word ptr [rsi]
    test ax, ax
    jz templateScanned

    cmp ax, '\'
    jne checkTemplateField

    cmp word ptr [rsi + 2], '$'
    jne continueTemplateScan
    cmp word ptr [rsi + 4], '$'
    jne continueTemplateScan

    mov rdx, hasEscapedDelimiterPointer
    mov dword ptr [rdx], TRUE

    add rsi, 6
    jmp scanTemplate

checkTemplateField:
    cmp ax, '$'
    jne continueTemplateScan
    cmp word ptr [rsi + 2], '$'
    jne continueTemplateScan

    invoke ParseTemplatePlaceholder, rsi, addr placeholderData

    .if eax == 0
        jmp continueTemplateScan
    .endif

    invoke FindTemplateFieldByName, fieldsPointer, fieldCount, placeholderData.namePointer, placeholderData.nameLength

    .if rax != 0
        mov rdx, rax
        mov eax, [rdx].TemplateField.fieldType
        cmp eax, placeholderData.fieldType
        jne templateFieldTypeConflict

        mov rsi, placeholderData.endPointer
        jmp scanTemplate
    .endif

    mov eax, fieldCount
    cmp eax, MAXIMUM_TEMPLATE_FIELDS
    jae tooManyTemplateFields

    mov eax, placeholderData.nameLength
    inc rax
    shl rax, 1

    invoke HeapAlloc, processHeap, HEAP_ZERO_MEMORY, rax
    .if rax == 0
        jmp templateCollectionMemoryError
    .endif
    mov nameMemory, rax

    mov eax, placeholderData.nameLength
    shl rax, 1

    invoke CopyBytes, nameMemory, placeholderData.namePointer, rax

    mov rdx, nameMemory
    mov eax, placeholderData.nameLength
    mov word ptr [rdx + rax * 2], 0

    mov eax, fieldCount
    imul rax, rax, sizeof TemplateField
    add rax, fieldsPointer

    mov rdx, rax

    mov rax, nameMemory
    mov [rdx].TemplateField.namePointer, rax

    mov eax, placeholderData.nameLength
    mov [rdx].TemplateField.nameLength, eax

    mov eax, placeholderData.fieldType
    mov [rdx].TemplateField.fieldType, eax

    inc fieldCount

    mov rsi, placeholderData.endPointer
    jmp scanTemplate

continueTemplateScan:
    add rsi, 2
    jmp scanTemplate

templateScanned:
    mov eax, fieldCount
    ret

templateCollectionMemoryError:
    invoke FreeTemplateFields, processHeap, fieldsPointer, fieldCount

    mov eax, TEMPLATE_COLLECTION_MEMORY_ERROR
    ret

tooManyTemplateFields:
    invoke FreeTemplateFields, processHeap, fieldsPointer, fieldCount

    mov eax, TEMPLATE_COLLECTION_TOO_MANY_FIELDS
    ret

templateFieldTypeConflict:
    invoke FreeTemplateFields, processHeap, fieldsPointer, fieldCount

    mov eax, TEMPLATE_COLLECTION_TYPE_CONFLICT
    ret
CollectTemplateFields endp

; Dialog procedure used to obtain a value for one template field.
;
; Parameters:
;   rcx/dialogWindow - Dialog window handle
;   edx/message - Message
;   r8/parameter1 - First message parameter
;   r9/parameter2 - Second message parameter
;
; Returns:
;   rax/INT_PTR - TRUE if the message was processed, otherwise FALSE
TemplateInputDialogProcedure proc frame dialogWindow:HWND, message:UINT, parameter1:WPARAM, parameter2:LPARAM
    local fieldPointer:TemplateFieldPointer
    local editWindow:HWND
    local processHeap:HANDLE
    local oldValuePointer:LPVOID
    local valuePointer:LPWSTR
    local valueLength:DWORD
    local valueCapacity:DWORD
    local allocationSize:SIZE_T

    mov eax, message

    .if eax == WM_INITDIALOG
        invoke SetWindowLongPtrW, dialogWindow, GWLP_USERDATA, parameter2
        mov rdx, parameter2
        mov fieldPointer, rdx

        mov rax, [rdx].TemplateField.namePointer

        invoke SetDlgItemTextW, dialogWindow, TEMPLATE_NAME_CONTROL_ID, rax

        invoke GetDlgItem, dialogWindow, TEMPLATE_VALUE_EDIT_ID
        mov editWindow, rax

        invoke SendMessageW, editWindow, EM_SETLIMITTEXT, MAXIMUM_TEMPLATE_VALUE_CHARACTERS, 0

        mov rdx, fieldPointer
        mov rax, [rdx].TemplateField.valuePointer
        .if rax != 0
            invoke SetWindowTextW, editWindow, rax
        .endif

        invoke SetFocus, editWindow

        xor eax, eax
        ret
    .elseif eax == WM_COMMAND
        mov rax, parameter1
        and eax, 0FFFFh

        .if eax == IDOK
            invoke GetWindowLongPtrW, dialogWindow, GWLP_USERDATA
            mov fieldPointer, rax

            .if rax == 0
                invoke ShowError, dialogWindow, addr TemplateProcessingFailedText

                mov eax, TRUE
                ret
            .endif

            invoke GetDlgItem, dialogWindow, TEMPLATE_VALUE_EDIT_ID
            mov editWindow, rax

            invoke GetWindowTextLengthW, editWindow
            mov valueLength, eax
            inc eax
            mov valueCapacity, eax

            shl rax, 1
            mov allocationSize, rax

            invoke GetProcessHeap
            mov processHeap, rax

            invoke HeapAlloc, processHeap, HEAP_ZERO_MEMORY, allocationSize
            .if rax == 0
                invoke ShowError, dialogWindow, addr MemoryAllocationFailedText

                mov eax, TRUE
                ret
            .endif
            mov valuePointer, rax

            invoke GetWindowTextW, editWindow, valuePointer, valueCapacity

            mov ecx, valueLength
            .if ecx != 0
                .if eax == 0
                    invoke HeapFree, processHeap, 0, valuePointer

                    invoke ShowError, dialogWindow, addr TemplateProcessingFailedText

                    mov eax, TRUE
                    ret
                .endif
            .endif

            mov rdx, fieldPointer
            mov rax, [rdx].TemplateField.valuePointer
            mov oldValuePointer, rax

            .if oldValuePointer != 0
                invoke HeapFree, processHeap, 0, oldValuePointer
            .endif

            mov rdx, fieldPointer

            mov rax, valuePointer
            mov [rdx].TemplateField.valuePointer, rax

            mov eax, valueLength
            mov [rdx].TemplateField.valueLength, eax

            invoke SetWindowLongPtrW, dialogWindow, GWLP_USERDATA, 0
            invoke EndDialog, dialogWindow, IDOK

            mov eax, TRUE
            ret
        .elseif eax == IDCANCEL
            invoke SetWindowLongPtrW, dialogWindow, GWLP_USERDATA, 0
            invoke EndDialog, dialogWindow, IDCANCEL
            mov eax, TRUE
            ret
        .endif
    .elseif eax == WM_CLOSE
        invoke SetWindowLongPtrW, dialogWindow, GWLP_USERDATA, 0
        invoke EndDialog, dialogWindow, IDCANCEL
        mov eax, TRUE
        ret
    .endif

    xor eax, eax
    ret
TemplateInputDialogProcedure endp

; Displays the template input dialog for every collected template field.
;
; Parameters:
;   rcx/ownerWindow - Owner window handle
;   rdx/fieldsPointer - Address of the template field array
;   r8d/fieldCount - Number of template fields
;
; Returns:
;   eax/BOOL - TRUE if all values were entered, otherwise FALSE
PromptTemplateFields proc frame ownerWindow:HWND, fieldsPointer:TemplateFieldPointer, fieldCount:DWORD
    local fieldIndex:DWORD
    local fieldPointer:TemplateFieldPointer
    local resourcePointer:LPCWSTR

    mov fieldIndex, 0

promptNextField:
    mov eax, fieldIndex
    cmp eax, fieldCount
    jae allFieldsEntered

    imul rax, rax, sizeof TemplateField
    add rax, fieldsPointer
    mov fieldPointer, rax

    mov rdx, rax
    mov eax, [rdx].TemplateField.fieldType

    .if eax == TEMPLATE_FIELD_MULTILINE
        mov eax, TEMPLATE_MULTILINE_DIALOG_ID
    .else
        mov eax, TEMPLATE_SINGLE_LINE_DIALOG_ID
    .endif
    mov resourcePointer, rax

    invoke DialogBoxParamW, \
        ApplicationInstance, \
        resourcePointer, \
        ownerWindow, \
        addr TemplateInputDialogProcedure, \
        fieldPointer

    .if rax == -1
        invoke ShowError, ownerWindow, addr TemplateDialogFailedText

        xor eax, eax
        ret
    .elseif eax != IDOK
        xor eax, eax
        ret
    .endif

    inc fieldIndex
    jmp promptNextField

allFieldsEntered:
    mov eax, TRUE
    ret
PromptTemplateFields endp

; Expands all fields in a null-terminated UTF-16 template.
;
; Parameters:
;   rcx/templatePointer - Address of the template text
;   rdx/fieldsPointer - Address of the template field array
;   r8d/fieldCount - Number of template fields
;
; Returns:
;   rax/HGLOBAL - Expanded text memory, or zero on failure
ExpandTemplateText proc frame uses rsi rdi templatePointer:LPCWSTR, fieldsPointer:TemplateFieldPointer, fieldCount:DWORD
    local placeholderData:TemplatePlaceholder
    local targetCharacterCount:SIZE_T
    local targetMemory:HGLOBAL
    local valuePointer:LPCVOID
    local valueByteCount:SIZE_T

    mov targetCharacterCount, 0
    mov rsi, templatePointer

calculateExpandedLength:
    mov ax, word ptr [rsi]
    test ax, ax
    jz expandedLengthCalculated

    cmp ax, '\'
    jne checkFieldForLength

    cmp word ptr [rsi + 2], '$'
    jne countLiteralCharacter
    cmp word ptr [rsi + 4], '$'
    jne countLiteralCharacter

    mov rax, targetCharacterCount
    add rax, 2
    jc expandedTextTooLarge
    cmp rax, MAXIMUM_EXPANDED_TEXT_CHARACTERS
    ja expandedTextTooLarge
    mov targetCharacterCount, rax

    add rsi, 6
    jmp calculateExpandedLength

checkFieldForLength:
    cmp ax, '$'
    jne countLiteralCharacter
    cmp word ptr [rsi + 2], '$'
    jne countLiteralCharacter

    invoke ParseTemplatePlaceholder, rsi, addr placeholderData

    .if eax == 0
        jmp countLiteralCharacter
    .endif

    invoke FindTemplateField, \
        fieldsPointer, \
        fieldCount, \
        placeholderData.namePointer, \
        placeholderData.nameLength, \
        placeholderData.fieldType

    .if rax == 0
        jmp countLiteralCharacter
    .endif

    mov eax, [rax].TemplateField.valueLength

    mov rcx, targetCharacterCount
    add rcx, rax
    jc expandedTextTooLarge
    cmp rcx, MAXIMUM_EXPANDED_TEXT_CHARACTERS
    ja expandedTextTooLarge
    mov targetCharacterCount, rcx

    mov rsi, placeholderData.endPointer
    jmp calculateExpandedLength

countLiteralCharacter:
    mov rax, targetCharacterCount
    cmp rax, MAXIMUM_EXPANDED_TEXT_CHARACTERS
    jae expandedTextTooLarge

    inc rax
    mov targetCharacterCount, rax

    add rsi, 2
    jmp calculateExpandedLength

expandedLengthCalculated:
    mov rax, targetCharacterCount
    inc rax
    shl rax, 1

    invoke GlobalAlloc, GMEM_MOVEABLE or GMEM_ZEROINIT, rax
    .if rax == 0
        ret
    .endif
    mov targetMemory, rax

    invoke GlobalLock, targetMemory
    .if rax == 0
        invoke GlobalFree, targetMemory
        xor eax, eax
        ret
    .endif
    mov rdi, rax
    mov rsi, templatePointer

copyExpandedText:
    mov ax, word ptr [rsi]
    test ax, ax
    jz expandedTextCopied

    cmp ax, '\'
    jne checkFieldForCopy

    cmp word ptr [rsi + 2], '$'
    jne copyLiteralCharacter
    cmp word ptr [rsi + 4], '$'
    jne copyLiteralCharacter

    mov word ptr [rdi], '$'
    mov word ptr [rdi + 2], '$'
    add rsi, 6
    add rdi, 4
    jmp copyExpandedText

checkFieldForCopy:
    cmp ax, '$'
    jne copyLiteralCharacter
    cmp word ptr [rsi + 2], '$'
    jne copyLiteralCharacter

    invoke ParseTemplatePlaceholder, rsi, addr placeholderData

    .if eax == 0
        jmp copyLiteralCharacter
    .endif

    invoke FindTemplateField, \
        fieldsPointer, \
        fieldCount, \
        placeholderData.namePointer, \
        placeholderData.nameLength, \
        placeholderData.fieldType

    .if rax == 0
        jmp copyLiteralCharacter
    .endif

    mov rdx, rax
    mov rax, [rdx].TemplateField.valuePointer
    mov valuePointer, rax

    mov eax, [rdx].TemplateField.valueLength
    shl rax, 1
    mov valueByteCount, rax

    .if valueByteCount != 0
        invoke CopyBytes, rdi, valuePointer, valueByteCount

        add rdi, valueByteCount
    .endif

    mov rsi, placeholderData.endPointer
    jmp copyExpandedText

copyLiteralCharacter:
    mov ax, word ptr [rsi]
    mov word ptr [rdi], ax
    add rsi, 2
    add rdi, 2
    jmp copyExpandedText

expandedTextCopied:
    mov word ptr [rdi], 0
    invoke GlobalUnlock, targetMemory
    mov rax, targetMemory
    ret

expandedTextTooLarge:
    xor eax, eax
    ret
ExpandTemplateText endp

; Processes the template fields contained in a Unicode global memory object. The procedure consumes the original memory
; object unless it returns it unchanged.
;
; Parameters:
;   rcx/ownerWindow - Owner window handle
;   rdx/textMemory - Global memory containing null-terminated UTF-16 text
;
; Returns:
;   rax/HGLOBAL - Original or expanded text memory, or zero if processing was cancelled or failed
ProcessTemplateText proc frame ownerWindow:HWND, textMemory:HGLOBAL
    local processHeap:HANDLE
    local fieldsPointer:TemplateFieldPointer
    local templatePointer:LPWSTR
    local expandedMemory:HGLOBAL
    local fieldCount:SDWORD
    local hasEscapedDelimiter:BOOL

    invoke GetProcessHeap
    mov processHeap, rax

    invoke HeapAlloc, processHeap, HEAP_ZERO_MEMORY, sizeof TemplateField * MAXIMUM_TEMPLATE_FIELDS
    .if rax == 0
        invoke ShowError, ownerWindow, addr MemoryAllocationFailedText

        invoke GlobalFree, textMemory
        xor eax, eax
        ret
    .endif
    mov fieldsPointer, rax

    invoke GlobalLock, textMemory
    .if rax == 0
        invoke ShowError, ownerWindow, addr TemplateProcessingFailedText

        invoke HeapFree, processHeap, 0, fieldsPointer

        invoke GlobalFree, textMemory
        xor eax, eax
        ret
    .endif
    mov templatePointer, rax

    invoke CollectTemplateFields, processHeap, templatePointer, fieldsPointer, addr hasEscapedDelimiter
    mov fieldCount, eax

    invoke GlobalUnlock, textMemory

    .if fieldCount == TEMPLATE_COLLECTION_MEMORY_ERROR
        invoke ShowError, ownerWindow, addr MemoryAllocationFailedText

        jmp templateProcessingFailed
    .elseif fieldCount == TEMPLATE_COLLECTION_TOO_MANY_FIELDS
        invoke ShowError, ownerWindow, addr TooManyTemplateFieldsText

        jmp templateProcessingFailed
    .elseif fieldCount == TEMPLATE_COLLECTION_TYPE_CONFLICT
        invoke ShowError, ownerWindow, addr TemplateFieldTypeConflictText

        jmp templateProcessingFailed
    .endif

    .if fieldCount == 0
        .if hasEscapedDelimiter == FALSE
            invoke HeapFree, processHeap, 0, fieldsPointer

            mov rax, textMemory
            ret
        .endif
    .else
        invoke PromptTemplateFields, ownerWindow, fieldsPointer, fieldCount
        .if eax == 0
            invoke FreeTemplateFields, processHeap, fieldsPointer, fieldCount

            invoke HeapFree, processHeap, 0, fieldsPointer

            invoke GlobalFree, textMemory
            xor eax, eax
            ret
        .endif
    .endif

    invoke GlobalLock, textMemory
    .if rax == 0
        invoke ShowError, ownerWindow, addr TemplateProcessingFailedText

        invoke FreeTemplateFields, processHeap, fieldsPointer, fieldCount

        invoke HeapFree, processHeap, 0, fieldsPointer

        invoke GlobalFree, textMemory
        xor eax, eax
        ret
    .endif
    mov templatePointer, rax

    invoke ExpandTemplateText, templatePointer, fieldsPointer, fieldCount
    mov expandedMemory, rax

    invoke GlobalUnlock, textMemory

    invoke FreeTemplateFields, processHeap, fieldsPointer, fieldCount

    invoke HeapFree, processHeap, 0, fieldsPointer

    .if expandedMemory == 0
        invoke ShowError, ownerWindow, addr TemplateExpansionFailedText

        invoke GlobalFree, textMemory
        xor eax, eax
        ret
    .endif

    invoke GlobalFree, textMemory
    mov rax, expandedMemory
    ret

templateProcessingFailed:
    invoke HeapFree, processHeap, 0, fieldsPointer

    invoke GlobalFree, textMemory
    xor eax, eax
    ret
ProcessTemplateText endp

; Creates movable global memory that contains null-terminated UTF-16LE text.
;
; Parameters:
;   rcx/sourcePointer - Address of UTF-16LE text without a byte order mark
;   edx/sourceByteCount - Number of source bytes
;
; Returns:
;   rax/HGLOBAL - Global memory handle, or zero on failure
CreateUnicodeGlobalFromUtf16Bytes proc frame sourcePointer:LPCVOID, sourceByteCount:DWORD
    local textMemory:HGLOBAL
    local destinationPointer:LPWSTR

    mov eax, sourceByteCount
    and eax, 1
    .if eax != 0
        xor eax, eax
        ret
    .endif

    mov eax, sourceByteCount
    add rax, 2

    invoke GlobalAlloc, GMEM_MOVEABLE or GMEM_ZEROINIT, rax
    .if rax == 0
        ret
    .endif
    mov textMemory, rax

    invoke GlobalLock, textMemory
    .if rax == 0
        invoke GlobalFree, textMemory
        xor eax, eax
        ret
    .endif
    mov destinationPointer, rax

    .if sourceByteCount != 0
        invoke CopyBytes, destinationPointer, sourcePointer, sourceByteCount
    .endif

    mov rdx, destinationPointer
    mov eax, sourceByteCount
    mov word ptr [rdx + rax], 0

    invoke GlobalUnlock, textMemory
    mov rax, textMemory
    ret
CreateUnicodeGlobalFromUtf16Bytes endp

; Converts multibyte text to UTF-16 and stores it in movable global memory.  UTF-8 is attempted first. The active
; Windows code page is used as a fallback unless strict UTF-8 conversion was requested.
;
; Parameters:
;   rcx/sourcePointer - Address of the multibyte text
;   edx/sourceByteCount - Number of source bytes
;   r8d/strictUtf8 - TRUE to reject malformed UTF-8 instead of using a fallback
;
; Returns:
;   rax/HGLOBAL - Global memory handle, or zero on failure
CreateUnicodeGlobalFromMultiByte proc frame sourcePointer:LPCVOID, sourceByteCount:DWORD, strictUtf8:BOOL
    local textMemory:HGLOBAL
    local destinationPointer:LPWSTR
    local characterCount:SDWORD
    local codePage:UINT
    local conversionFlags:DWORD

    mov characterCount, 0
    mov codePage, CP_UTF8
    mov conversionFlags, MB_ERR_INVALID_CHARS

    .if sourceByteCount != 0
        invoke MultiByteToWideChar, codePage, conversionFlags, sourcePointer, sourceByteCount, 0, 0
        .if eax == 0
            .if strictUtf8 != FALSE
                ret
            .endif

            mov codePage, CP_ACP
            mov conversionFlags, 0

            invoke MultiByteToWideChar, codePage, conversionFlags, sourcePointer, sourceByteCount, 0, 0
            .if eax == 0
                ret
            .endif
        .endif

        mov characterCount, eax
    .endif

    mov eax, characterCount
    lea rax, [rax * 2 + 2]

    invoke GlobalAlloc, GMEM_MOVEABLE or GMEM_ZEROINIT, rax
    .if rax == 0
        ret
    .endif
    mov textMemory, rax

    invoke GlobalLock, textMemory
    .if rax == 0
        invoke GlobalFree, textMemory
        xor eax, eax
        ret
    .endif
    mov destinationPointer, rax

    .if sourceByteCount != 0
        invoke MultiByteToWideChar, \
            codePage, \
            conversionFlags, \
            sourcePointer, \
            sourceByteCount, \
            destinationPointer, \
            characterCount
        .if eax == 0
            invoke GlobalUnlock, textMemory
            invoke GlobalFree, textMemory
            xor eax, eax
            ret
        .endif
    .endif

    mov rdx, destinationPointer
    mov eax, characterCount
    mov word ptr [rdx + rax * 2], 0

    invoke GlobalUnlock, textMemory

    mov rax, textMemory
    ret
CreateUnicodeGlobalFromMultiByte endp

; Places a global memory object containing Unicode text on the clipboard. The procedure consumes the memory object.
; Windows owns it after a successful call.
;
; Parameters:
;   rcx/ownerWindow - Owner window handle
;   rdx/textMemory - Movable global memory containing null-terminated UTF-16 text
;
; Returns:
;   eax/BOOL - TRUE on success, otherwise FALSE
PlaceUnicodeTextOnClipboard proc frame ownerWindow:HWND, textMemory:HGLOBAL
    local previousMemory:HGLOBAL
    local previousPointer:LPCVOID
    local previousCopyMemory:HGLOBAL
    local previousByteCount:SIZE_T

    mov previousCopyMemory, 0

    invoke OpenClipboard, ownerWindow
    .if eax == 0
        invoke GlobalFree, textMemory
        xor eax, eax
        ret
    .endif

    invoke GetClipboardData, CF_UNICODETEXT
    mov previousMemory, rax

    .if rax != 0
        invoke GlobalSize, previousMemory
        .if rax == 0
            invoke CloseClipboard
            invoke GlobalFree, textMemory
            xor eax, eax
            ret
        .endif
        mov previousByteCount, rax

        invoke GlobalAlloc, GMEM_MOVEABLE, previousByteCount
        .if rax == 0
            invoke CloseClipboard
            invoke GlobalFree, textMemory
            xor eax, eax
            ret
        .endif
        mov previousCopyMemory, rax

        invoke GlobalLock, previousMemory
        .if rax == 0
            invoke GlobalFree, previousCopyMemory
            invoke CloseClipboard
            invoke GlobalFree, textMemory
            xor eax, eax
            ret
        .endif
        mov previousPointer, rax

        invoke GlobalLock, previousCopyMemory
        .if rax == 0
            invoke GlobalUnlock, previousMemory
            invoke GlobalFree, previousCopyMemory
            invoke CloseClipboard
            invoke GlobalFree, textMemory
            xor eax, eax
            ret
        .endif
        
        invoke CopyBytes, rax, previousPointer, previousByteCount

        invoke GlobalUnlock, previousCopyMemory
        invoke GlobalUnlock, previousMemory
    .endif

    invoke EmptyClipboard
    .if eax == 0
        .if previousCopyMemory != 0
            invoke GlobalFree, previousCopyMemory
        .endif

        invoke CloseClipboard
        invoke GlobalFree, textMemory
        xor eax, eax
        ret
    .endif

    invoke SetClipboardData, CF_UNICODETEXT, textMemory
    .if rax == 0
        .if previousCopyMemory != 0
            invoke SetClipboardData, CF_UNICODETEXT, previousCopyMemory
            .if rax != 0
                mov previousCopyMemory, 0
            .endif
        .endif

        invoke CloseClipboard

        .if previousCopyMemory != 0
            invoke GlobalFree, previousCopyMemory
        .endif

        invoke GlobalFree, textMemory
        xor eax, eax
        ret
    .endif

    invoke CloseClipboard

    .if previousCopyMemory != 0
        invoke GlobalFree, previousCopyMemory
    .endif

    mov eax, TRUE
    ret
PlaceUnicodeTextOnClipboard endp

; Saves the current Unicode clipboard text as a UTF-16LE file with a byte order mark.
;
; Parameters:
;   rcx/ownerWindow - Owner window handle
;
; Returns:
;   Nothing
SaveClipboardText proc frame uses rsi ownerWindow:HWND
    local processHeap:HANDLE
    local clipboardMemory:HGLOBAL
    local clipboardPointer:LPWSTR
    local clipboardByteCount:SIZE_T
    local snapshotPointer:LPWSTR
    local snapshotByteCount:SIZE_T
    local textByteCount:DWORD
    local fileNamePointer:LPWSTR
    local fileHandle:HANDLE
    local byteOrderMark:WCHAR

    invoke IsClipboardFormatAvailable, CF_UNICODETEXT
    .if eax == 0
        invoke ShowError, ownerWindow, addr NoClipboardTextText
        ret
    .endif

    invoke OpenClipboard, ownerWindow
    .if eax == 0
        invoke ShowError, ownerWindow, addr OpenClipboardFailedText
        ret
    .endif

    invoke GetClipboardData, CF_UNICODETEXT
    .if rax == 0
        invoke CloseClipboard
        invoke ShowError, ownerWindow, addr ReadClipboardFailedText
        ret
    .endif
    mov clipboardMemory, rax

    invoke GlobalLock, clipboardMemory
    .if rax == 0
        invoke CloseClipboard
        invoke ShowError, ownerWindow, addr ReadClipboardFailedText
        ret
    .endif
    mov clipboardPointer, rax

    invoke GlobalSize, clipboardMemory
    mov clipboardByteCount, rax

    cmp rax, 2
    jb invalidClipboardText
    cmp rax, MAXIMUM_TEXT_FILE_BYTES + 2
    ja invalidClipboardText

    mov rcx, rax
    and ecx, 1
    jnz invalidClipboardText

    mov rsi, clipboardPointer
    mov rcx, clipboardByteCount
    shr rcx, 1

findClipboardTerminator:
    cmp word ptr [rsi], 0
    je clipboardTerminatorFound

    add rsi, 2
    dec rcx
    jnz findClipboardTerminator
    jmp invalidClipboardText

clipboardTerminatorFound:
    mov rax, rsi
    sub rax, clipboardPointer
    mov textByteCount, eax

    add rax, 2
    mov snapshotByteCount, rax

    invoke GetProcessHeap
    mov processHeap, rax

    invoke HeapAlloc, processHeap, 0, snapshotByteCount
    .if rax == 0
        invoke GlobalUnlock, clipboardMemory
        invoke CloseClipboard
        invoke ShowError, ownerWindow, addr MemoryAllocationFailedText
        ret
    .endif
    mov snapshotPointer, rax

    invoke CopyBytes, snapshotPointer, clipboardPointer, snapshotByteCount

    invoke GlobalUnlock, clipboardMemory
    invoke CloseClipboard

    invoke ShowSaveDialog, ownerWindow
    .if eax == 0
        invoke HeapFree, processHeap, 0, snapshotPointer
        ret
    .endif

    invoke GetFullPathNameW, addr FilePath, FILE_PATH_CHARACTER_COUNT, addr TemporaryDirectoryPath, addr fileNamePointer

    .if eax == 0
        invoke ShowError, ownerWindow, addr CreateFileFailedText
        invoke HeapFree, processHeap, 0, snapshotPointer
        ret
    .elseif eax >= FILE_PATH_CHARACTER_COUNT
        invoke ShowError, ownerWindow, addr CreateFileFailedText
        invoke HeapFree, processHeap, 0, snapshotPointer
        ret
    .endif

    mov rdx, fileNamePointer
    .if rdx == 0
        invoke ShowError, ownerWindow, addr CreateFileFailedText
        invoke HeapFree, processHeap, 0, snapshotPointer
        ret
    .endif
    mov word ptr [rdx], 0

    invoke GetTempFileNameW, addr TemporaryDirectoryPath, addr ApplicationName, 0, addr TemporaryFilePath

    .if eax == 0
        invoke ShowError, ownerWindow, addr CreateFileFailedText
        invoke HeapFree, processHeap, 0, snapshotPointer
        ret
    .endif

    invoke CreateFileW, addr TemporaryFilePath, GENERIC_WRITE, 0, 0, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0

    .if rax == INVALID_HANDLE_VALUE
        invoke DeleteFileW, addr TemporaryFilePath
        invoke ShowError, ownerWindow, addr CreateFileFailedText
        invoke HeapFree, processHeap, 0, snapshotPointer
        ret
    .endif
    mov fileHandle, rax

    mov byteOrderMark, 0FEFFh

    invoke WriteAllBytes, fileHandle, addr byteOrderMark, 2
    .if eax == 0
        jmp temporaryFileWriteFailed
    .endif

    invoke WriteAllBytes, fileHandle, snapshotPointer, textByteCount
    .if eax == 0
        jmp temporaryFileWriteFailed
    .endif

    invoke FlushFileBuffers, fileHandle
    .if eax == 0
        jmp temporaryFileWriteFailed
    .endif

    invoke CloseHandle, fileHandle
    .if eax == 0
        invoke DeleteFileW, addr TemporaryFilePath
        invoke ShowError, ownerWindow, addr WriteFileFailedText
        invoke HeapFree, processHeap, 0, snapshotPointer
        ret
    .endif

    invoke MoveFileExW, addr TemporaryFilePath, addr FilePath, MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH

    .if eax == 0
        invoke DeleteFileW, addr TemporaryFilePath
        invoke ShowError, ownerWindow, addr WriteFileFailedText
        invoke HeapFree, processHeap, 0, snapshotPointer
        ret
    .endif

    invoke HeapFree, processHeap, 0, snapshotPointer
    ret

invalidClipboardText:
    invoke GlobalUnlock, clipboardMemory
    invoke CloseClipboard
    invoke ShowError, ownerWindow, addr ReadClipboardFailedText
    ret

temporaryFileWriteFailed:
    invoke CloseHandle, fileHandle
    invoke DeleteFileW, addr TemporaryFilePath
    invoke ShowError, ownerWindow, addr WriteFileFailedText
    invoke HeapFree, processHeap, 0, snapshotPointer
    ret
SaveClipboardText endp

; Loads a text file and places its contents on the clipboard as Unicode text.
;
; Parameters:
;   rcx/ownerWindow - Owner window handle
;
; Returns:
;   Nothing
LoadClipboardText proc frame ownerWindow:HWND
    local processHeap:HANDLE
    local fileHandle:HANDLE
    local fileSize:LARGE_INTEGER
    local allocationSize:SIZE_T
    local fileBuffer:LPVOID
    local fileByteCount:DWORD
    local bytesRead:DWORD
    local sourcePointer:LPVOID
    local sourceByteCount:DWORD
    local textMemory:HGLOBAL
    local unicodeEncodingDetected:BOOL
    local utf8EncodingDetected:BOOL

    invoke ShowOpenDialog, ownerWindow
    .if eax == 0
        ret
    .endif

    invoke CreateFileW, addr FilePath, GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0
    .if rax == INVALID_HANDLE_VALUE
        invoke ShowError, ownerWindow, addr OpenFileFailedText
        ret
    .endif
    mov fileHandle, rax

    mov fileSize.QuadPart, 0
    invoke GetFileSizeEx, fileHandle, addr fileSize
    .if eax == 0
        invoke ShowError, ownerWindow, addr ReadFileFailedText
        invoke CloseHandle, fileHandle
        ret
    .endif

    mov rax, fileSize.QuadPart
    .if rax > MAXIMUM_TEXT_FILE_BYTES
        invoke ShowError, ownerWindow, addr FileTooLargeText
        invoke CloseHandle, fileHandle
        ret
    .endif

    mov eax, fileSize.LowPart
    mov fileByteCount, eax

    mov rax, fileSize.QuadPart
    add rax, 2
    mov allocationSize, rax

    invoke GetProcessHeap
    mov processHeap, rax

    invoke HeapAlloc, processHeap, HEAP_ZERO_MEMORY, allocationSize
    .if rax == 0
        invoke ShowError, ownerWindow, addr MemoryAllocationFailedText
        invoke CloseHandle, fileHandle
        ret
    .endif
    mov fileBuffer, rax

    mov bytesRead, 0
    invoke ReadFile, fileHandle, fileBuffer, fileByteCount, addr bytesRead, 0
    .if eax == 0
        invoke ShowError, ownerWindow, addr ReadFileFailedText
        invoke CloseHandle, fileHandle
        invoke HeapFree, processHeap, 0, fileBuffer
        ret
    .endif

    mov eax, fileByteCount
    .if bytesRead != eax
        invoke ShowError, ownerWindow, addr ReadFileFailedText
        invoke CloseHandle, fileHandle
        invoke HeapFree, processHeap, 0, fileBuffer
        ret
    .endif

    invoke CloseHandle, fileHandle

    mov rax, fileBuffer
    mov sourcePointer, rax
    mov eax, fileByteCount
    mov sourceByteCount, eax
    mov textMemory, 0
    mov unicodeEncodingDetected, FALSE
    mov utf8EncodingDetected, FALSE

    .if fileByteCount >= 2
        mov rdx, fileBuffer
        mov ax, word ptr [rdx]

        .if ax == 0FEFFh
            mov unicodeEncodingDetected, TRUE
            add sourcePointer, 2
            sub sourceByteCount, 2

            mov eax, sourceByteCount
            and eax, 1
            .if eax != 0
                invoke ShowError, ownerWindow, addr UnsupportedEncodingText
                invoke HeapFree, processHeap, 0, fileBuffer
                ret
            .endif

            invoke WideRangeContainsZero, sourcePointer, sourceByteCount
            .if eax != 0
                invoke ShowError, ownerWindow, addr UnsupportedEncodingText
                invoke HeapFree, processHeap, 0, fileBuffer
                ret
            .endif

            invoke CreateUnicodeGlobalFromUtf16Bytes, sourcePointer, sourceByteCount
            mov textMemory, rax
        .elseif ax == 0FFFEh
            invoke ShowError, ownerWindow, addr UnsupportedEncodingText
            invoke HeapFree, processHeap, 0, fileBuffer
            ret
        .endif
    .endif

    .if unicodeEncodingDetected == FALSE
        .if fileByteCount >= 3
            mov rdx, fileBuffer
            mov al, byte ptr [rdx]

            .if al == 0EFh
                mov al, byte ptr [rdx + 1]

                .if al == 0BBh
                    mov al, byte ptr [rdx + 2]

                    .if al == 0BFh
                        mov utf8EncodingDetected, TRUE
                        add sourcePointer, 3
                        sub sourceByteCount, 3
                    .endif
                .endif
            .endif
        .endif

        invoke ByteRangeContainsZero, sourcePointer, sourceByteCount
        .if eax != 0
            invoke ShowError, ownerWindow, addr ConversionFailedText
            invoke HeapFree, processHeap, 0, fileBuffer
            ret
        .endif

        invoke CreateUnicodeGlobalFromMultiByte, sourcePointer, sourceByteCount, utf8EncodingDetected
        mov textMemory, rax
    .endif

    .if textMemory == 0
        invoke ShowError, ownerWindow, addr ConversionFailedText
        invoke HeapFree, processHeap, 0, fileBuffer
        ret
    .endif

    invoke ProcessTemplateText, ownerWindow, textMemory
    .if rax == 0
        invoke HeapFree, processHeap, 0, fileBuffer
        ret
    .endif
    mov textMemory, rax

    invoke PlaceUnicodeTextOnClipboard, ownerWindow, textMemory
    .if eax == 0
        invoke ShowError, ownerWindow, addr SetClipboardFailedText
    .endif

    invoke HeapFree, processHeap, 0, fileBuffer
    ret
LoadClipboardText endp

; Registers the two global application hotkeys.
;
; Parameters:
;   rcx/ownerWindow - Window that receives WM_HOTKEY messages
;
; Returns:
;   eax/BOOL - TRUE on success, otherwise FALSE
RegisterHotkeys proc frame ownerWindow:HWND
    invoke RegisterHotKey, ownerWindow, SAVE_HOTKEY_ID, HOTKEY_MODIFIERS, SAVE_VIRTUAL_KEY
    .if eax == 0
        invoke ShowError, ownerWindow, addr SaveHotkeyFailedText
        xor eax, eax
        ret
    .endif

    invoke RegisterHotKey, ownerWindow, LOAD_HOTKEY_ID, HOTKEY_MODIFIERS, LOAD_VIRTUAL_KEY
    .if eax == 0
        invoke UnregisterHotKey, ownerWindow, SAVE_HOTKEY_ID
        invoke ShowError, ownerWindow, addr LoadHotkeyFailedText
        xor eax, eax
        ret
    .endif

    mov eax, TRUE
    ret
RegisterHotkeys endp

; Unregisters the two global application hotkeys.
;
; Parameters:
;   rcx/ownerWindow - Window used when the hotkeys were registered
;
; Returns:
;   Nothing
UnregisterHotkeys proc frame ownerWindow:HWND
    invoke UnregisterHotKey, ownerWindow, SAVE_HOTKEY_ID
    invoke UnregisterHotKey, ownerWindow, LOAD_HOTKEY_ID
    ret
UnregisterHotkeys endp

; Adds the application icon to the notification area.
;
; Parameters:
;   rcx/ownerWindow - Window that receives notification area messages
;
; Returns:
;   eax/BOOL - Nonzero on success, otherwise zero
AddTrayIcon proc frame ownerWindow:HWND
    invoke ClearBytes, addr TrayIconData, sizeof NOTIFYICONDATAW

    mov TrayIconData.cbSize, sizeof NOTIFYICONDATAW

    mov rax, ownerWindow
    mov TrayIconData.hWnd, rax

    mov TrayIconData.uID, TRAY_ICON_ID
    mov TrayIconData.uFlags, NIF_MESSAGE or NIF_ICON or NIF_TIP
    mov TrayIconData.uCallbackMessage, TRAY_CALLBACK_MESSAGE

    invoke LoadIconW, ApplicationInstance, IDI_APPICON
    .if rax == 0
        ret
    .endif
    mov TrayIconData.hIcon, rax

    invoke lstrcpynW, addr TrayIconData.szTip, addr TrayTooltip, TRAY_TOOLTIP_CHARACTER_COUNT

    invoke Shell_NotifyIconW, NIM_ADD, addr TrayIconData
    ret
AddTrayIcon endp

; Removes the application icon from the notification area.
;
; Parameters:
;   None
;
; Returns:
;   eax/BOOL - Nonzero on success, otherwise zero
RemoveTrayIcon proc frame
    invoke Shell_NotifyIconW, NIM_DELETE, addr TrayIconData
    ret
RemoveTrayIcon endp

; Displays the notification area context menu.
;
; Parameters:
;   rcx/ownerWindow - Owner window handle
;
; Returns:
;   Nothing
ShowTrayMenu proc frame ownerWindow:HWND
    local menuHandle:HMENU
    local selectedCommand:UINT
    local cursorPosition:POINT

    invoke CreatePopupMenu
    .if rax == 0
        ret
    .endif
    mov menuHandle, rax

    invoke AppendMenuW, menuHandle, MF_STRING, TRAY_EXIT_COMMAND_ID, addr TrayExitText

    invoke GetCursorPos, addr cursorPosition
    invoke SetForegroundWindow, ownerWindow

    invoke TrackPopupMenu, \
        menuHandle, \
        TPM_RIGHTBUTTON or TPM_RETURNCMD or TPM_NONOTIFY, \
        cursorPosition.x, \
        cursorPosition.y, \
        0, \
        ownerWindow, \
        0
    mov selectedCommand, eax

    invoke PostMessageW, ownerWindow, WM_NULL, 0, 0

    invoke DestroyMenu, menuHandle

    .if selectedCommand == TRAY_EXIT_COMMAND_ID
        invoke DestroyWindow, ownerWindow
    .endif
    ret
ShowTrayMenu endp

; Registers the hidden main window class.
;
; Parameters:
;   None
;
; Returns:
;   ax/ATOM - Window class atom, or zero on failure
RegisterMainWindowClass proc frame
    invoke ClearBytes, addr MainWindowClass, sizeof WNDCLASSEXW

    mov MainWindowClass.cbSize, sizeof WNDCLASSEXW
    mov MainWindowClass.style, 0

    lea rax, [WindowProcedure]
    mov MainWindowClass.lpfnWndProc, rax

    mov rax, ApplicationInstance
    mov MainWindowClass.hInstance, rax

    invoke LoadIconW, ApplicationInstance, IDI_APPICON
    mov MainWindowClass.hIcon, rax
    mov MainWindowClass.hIconSm, rax

    invoke LoadCursorW, 0, IDC_ARROW
    mov MainWindowClass.hCursor, rax

    mov MainWindowClass.hbrBackground, 0
    mov MainWindowClass.lpszMenuName, 0

    lea rax, [MainWindowClassName]
    mov MainWindowClass.lpszClassName, rax

    invoke RegisterClassExW, addr MainWindowClass
    ret
RegisterMainWindowClass endp

; Window procedure of the hidden window that receives hotkey and notification area messages.
;
; Parameters:
;   rcx/windowHandle - Window handle
;   edx/message - Message
;   r8/parameter1 - First message parameter
;   r9/parameter2 - Second message parameter
;
; Returns:
;   rax/LRESULT - 0 if the message was processed, otherwise the result from DefWindowProcW
WindowProcedure proc frame windowHandle:HWND, message:UINT, parameter1:WPARAM, parameter2:LPARAM
    mov eax, message
    mov ecx, TaskbarCreatedMessage

    .if ecx != 0
        .if eax == ecx
            invoke AddTrayIcon, windowHandle
            xor eax, eax
            ret
        .endif
    .endif

    mov eax, message

    .if eax == WM_HOTKEY
        .if OperationInProgress == FALSE
            mov OperationInProgress, TRUE
            mov eax, dword ptr parameter1

            .if eax == SAVE_HOTKEY_ID
                invoke SaveClipboardText, windowHandle
            .elseif eax == LOAD_HOTKEY_ID
                invoke LoadClipboardText, windowHandle
            .endif

            mov OperationInProgress, FALSE
        .endif

        xor eax, eax
        ret
    .elseif eax == TRAY_CALLBACK_MESSAGE
        mov eax, dword ptr parameter2

        .if eax == WM_RBUTTONUP
            invoke ShowTrayMenu, windowHandle
        .elseif eax == WM_CONTEXTMENU
            invoke ShowTrayMenu, windowHandle
        .endif

        xor eax, eax
        ret
    .elseif eax == WM_COMMAND
        mov rax, parameter1
        and eax, 0FFFFh

        .if eax == TRAY_EXIT_COMMAND_ID
            invoke DestroyWindow, windowHandle
        .endif

        xor eax, eax
        ret
    .elseif eax == WM_CLOSE
        invoke DestroyWindow, windowHandle
        xor eax, eax
        ret
    .elseif eax == WM_DESTROY
        invoke UnregisterHotkeys, windowHandle
        invoke RemoveTrayIcon
        invoke PostQuitMessage, 0
        xor eax, eax
        ret
    .endif

    invoke DefWindowProcW, windowHandle, message, parameter1, parameter2
    ret
WindowProcedure endp

; Initializes the application and runs the message loop.
;
; Parameters:
;   None
;
; Returns:
;   eax/SDWORD - Process exit code
RunApplication proc frame
    local messageData:MSG

    invoke GetModuleHandleW, 0
    .if rax == 0
        invoke ShowError, 0, addr InitializationFailedText
        mov eax, 1
        ret
    .endif
    mov ApplicationInstance, rax

    invoke RegisterWindowMessageW, addr TaskbarCreatedText
    mov TaskbarCreatedMessage, eax

    invoke RegisterMainWindowClass
    .if eax == 0
        invoke ShowError, 0, addr InitializationFailedText
        mov eax, 1
        ret
    .endif

    invoke CreateWindowExW, \
        0, \
        addr MainWindowClassName, \
        addr ApplicationName, \
        0, \
        0, \
        0, \
        0, \
        0, \
        0, \
        0, \
        ApplicationInstance, \
        0
    .if rax == 0
        invoke ShowError, 0, addr InitializationFailedText
        mov eax, 1
        ret
    .endif
    mov MainWindow, rax

    invoke RegisterHotkeys, MainWindow
    .if eax == 0
        invoke DestroyWindow, MainWindow
        mov eax, 1
        ret
    .endif

    invoke AddTrayIcon, MainWindow
    .if eax == 0
        invoke ShowError, MainWindow, addr TrayIconFailedText
        invoke DestroyWindow, MainWindow
        mov eax, 1
        ret
    .endif

messageLoop:
    invoke GetMessageW, addr messageData, 0, 0, 0
    .if eax == -1
        jmp messageLoopFailed
    .elseif eax == 0
        jmp messageLoopFinished
    .endif

    invoke TranslateMessage, addr messageData
    invoke DispatchMessageW, addr messageData
    jmp messageLoop

messageLoopFailed:
    invoke ShowError, MainWindow, addr InitializationFailedText
    invoke DestroyWindow, MainWindow
    mov eax, 1
    ret

messageLoopFinished:
    mov rax, messageData.wParam
    ret
RunApplication endp

start:
    and rsp, -16
    invoke RunApplication
    invoke ExitProcess, eax

end start
