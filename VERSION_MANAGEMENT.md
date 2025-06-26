# Version Management in Nimhawk

## Single Source of Truth

The project version is managed centrally using the `server/admin_web_ui/package.json` file as the single source of truth.

## Files Using Version

### Frontend (Automatic)
- `server/admin_web_ui/version.ts` - Automatically reads from package.json
- `server/admin_web_ui/pages/login.tsx` - Uses getDisplayVersion()
- `server/admin_web_ui/pages/index.tsx` - Uses getDisplayVersion()

### Backend/Implant (Manual)
- `implant/implant.nimble` - Nim implant version
- `implant/NimHawk.nim` - Version banner shown by implant

### Documentation (Manual)
- `README.md` - Version badge
- `DEVELOPERS.md` - Version badge

## How to Update Version

1. **Update main version:**
   ```bash
   cd server/admin_web_ui
   npm version [patch|minor|major]
   # Or manually edit package.json
   ```

2. **Update manual files:**
   - `implant/implant.nimble`: Change line `version = "X.X.X"`
   - `implant/NimHawk.nim`: Change `const version: string = "=== Nimhawk vX.X.X ==="`
   - `README.md`: Update badge `Version-X.X.X-red.svg`
   - `DEVELOPERS.md`: Update badge `Version-X.X.X-red.svg`

## Verification

To verify all versions are synchronized:

```bash
# Check version in package.json
grep '"version"' server/admin_web_ui/package.json

# Check version in implant
grep 'version.*=' implant/implant.nimble
grep 'const version' implant/NimHawk.nim

# Check badges in documentation
grep 'Version-' README.md DEVELOPERS.md
```

## Notes

- Frontend automatically uses full version from package.json (X.X.X)
- All components now use the complete version format (X.X.X) for consistency
- The .nimble file uses full version "X.X.X" 