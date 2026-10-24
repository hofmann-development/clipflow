# ClipFlow Rules (Code Style and Win64)

Use these rules to avoid Win64 pitfalls and keep the codebase consistent.

## 1. Build and Assembler Basics

- Build JWasm with: -win64 -Zp8.
  - -Zp8 is mandatory for correct Win32/Win64 structure packing.
- Build Free and Pro with matching switches:
  - Assembler: with or without -DFREE_VERSION
  - Resource compiler: with or without /dFREE_VERSION

## 2. Win64 ABI Handling

- win64:1 plus mandatory proc frame/invoke covers most ABI handling.
- Avoid manual stack/register call setup unless necessary.
- If you use manual push/pop, keep 16-byte stack alignment at every call site.

## 3. Project-Specific Assembly Style

- These assembler options are load-bearing and must not be changed:
  - option casemap:none
  - option scoped
  - option frame:auto
  - option win64:1
- Mandatory style:
  - Procedures use proc frame with named parameters.
  - Local variables use local.
  - API calls use invoke.
- Manual register-based calling is not allowed for normal API calls.

## 4. Error Handling and Ownership

- Keep cleanup explicit and in reverse acquire order.
- When adding allocations, update all downstream error paths.
- Keep ownership rules intact:
  - Clipboard-bound text in GMEM_MOVEABLE.
  - Other heap memory via GetProcessHeap plus HeapAlloc/HeapFree.

## 5. Structure and Naming

- Keep bottom-up order: leaf helpers first, entry point last.
- Keep procedure comments in this format:
  - short description
  - Parameters:
  - Returns:
- Naming:
  - Procedures and global data: PascalCase
  - Parameters, locals, and labels: camelCase
- Labels should read like clear statements.
- Keep equ constants in UPPER_CASE_WITH_UNDERSCORES near the top.
- Avoid unclear abbreviations.

## 6. Resources and Coupling

- Change duplicated IDs in assembly and resource files together.
- Add missing Win32 definitions to compat.inc, not external include sets.
- Keep project-owned helper macros in util.inc.

## 7. Text, Encoding, Line Endings

- User-facing strings are full English sentences.
- Keep the existing WSTR style.
- Use UTF-8 for repository text files.
- Use CRLF line endings.

## 8. Practical Pre-Commit Checklist

- Build flags are correct, including -Zp8 and consistent FREE_VERSION usage.
- If resources or IDs changed, all coupled files were updated.
- Error paths and ownership handling are fully updated.
- Style conventions (proc frame/local/invoke, naming, comments) are preserved.
