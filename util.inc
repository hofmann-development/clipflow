ifndef UTIL_INC
UTIL_INC equ 1

WSTR macro symbolName, symbolText
    ifnb <symbolName>
        symbolName label WCHAR
    endif
    forc WideStringCharacter, <&symbolText>
        WCHAR '&WideStringCharacter&'
    endm
    WCHAR 0
endm

endif
