# How we would like patches made

## Size and scope of a fix
- Fix the root cause where all callers route through it. If several endpoints share an access or sanitising helper (`Test-CIPPAccess`, `ConvertTo-CIPPSafePwshArg`, `ConvertTo-CIPPODataFilterValue`, `getCippFormatting`), fix the helper, not one call site.
- No refactoring or renaming beyond what the fix needs. No new shared frontend components.

## Code style
- PowerShell: never use `+=` on arrays or strings, and never concatenate arrays with `@(a) + @(b)`. Use `[System.Collections.Generic.List[object]]`, `-join` or a StringBuilder. Use full cmdlet names, not aliases.
- Comments: one or two lines stating the constraint the code enforces, with no history and no reference to this report.
- Frontend: match the surrounding code and do not reformat untouched lines.

## Tests
- Add a Pester 5 test under the nearest folder in `backend/Tests/` (e.g. `Tests/Security`, `Tests/Endpoint`, `Tests/CIPP`), following the existing pattern: dot-source the function and stub Graph and Table Storage calls. The test must fail without the fix.
- Frontend fixes get a vitest unit test under `frontend/tests/`, mirroring the `src/` path.

## Branch and commit message
- Against the `dev` branch. Conventional Commits subject, e.g. `fix(auth): enforce tenant scope on bulk user endpoints`.
