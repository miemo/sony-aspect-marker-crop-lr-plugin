---
name: Something doesn't work
about: The plugin didn't crop, showed an error, or can't find ExifTool
---

**What happened, and what you expected**



**Your setup**

- Camera model and firmware:
- Operating system and version:
- Lightroom Classic version:
- ExifTool version (shown in the Plug-in Manager, or run `exiftool -ver`):
- How ExifTool was installed (macOS package / Homebrew / Windows zip / winget / other):

**If a photo wasn't cropped**, run this on it in Terminal (macOS) or Command Prompt (Windows) and paste the output:

```
exiftool -u -Sony:Sony_0x2049 -Model -Software photo.ARW
```

```
(paste here)
```
