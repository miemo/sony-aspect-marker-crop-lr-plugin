# Sony Aspect Marker Crop for Lightroom Classic

A free plugin for Lightroom Classic. It finds the photos you shot with your Sony camera's **Aspect Marker** on and crops them to that marker for you.

![Plugin in action](https://cloud.miemo.net/sony-aspect-marker-crop-lr-plugin/explainer.webp)

## Why

Recent Sony cameras can show an **Aspect Marker** in the viewfinder: guide lines for 2.35:1, 1.91:1, 16:9, 4:3, 5:4 or 1:1. You compose inside the lines, but the camera still saves the full 3:2 frame. Afterwards the lines show up only on the camera's own playback screen. Lightroom knows nothing about them, so you end up making the same crop by hand, photo after photo.

The camera does write the marker into every ARW and JPEG, though. **This plugin reads it and makes the crop.**

## What it does

- **Crops each marked photo to its marker, exactly where the guide lines were.** Portrait shots too.
- The result is an **ordinary Lightroom crop**. Move it, change it or remove it like any other – the plugin won't put it back, even if you run it again.
- Adds a keyword such as `AspectMarker 2.35:1`, so marked photos are easy to find later.
- Leaves photos you have already cropped alone. They get the keyword only.
- Can also crop new photos in the background as they arrive, which is how the crops reach Lightroom mobile. See [Background auto-crop](#background-auto-crop).

The plugin never changes your image files, never touches your other edits, and never uses the internet.

## What you need

- **Lightroom Classic** 10 or newer, on Mac or Windows. Not the cloud-based Lightroom or Lightroom mobile, but see the [FAQ](#faq).
- A **Sony camera with the still-image Aspect Marker** (MENU > Shooting > Marker Display). Tested with the A7C II. The A7CR, A1 (firmware 2.0 or later), ZV-E1 and ZV-E10 II have it too, and probably other recent bodies.
- **ExifTool**, a free tool that you install once. Step 1 below.

Windows should work but is untested, as I only have a Mac. Reports from Windows users are very welcome.

## Installation

### 1. Install ExifTool

**The plugin reads the marker from your files with [ExifTool](https://exiftool.org)**, Phil Harvey's free and widely used metadata tool.

**Mac:** download the *MacOS Package* from [exiftool.org](https://exiftool.org) and run it. If macOS refuses to open it, go to *System Settings > Privacy & Security* and click *Open Anyway*. Homebrew users can run `brew install exiftool` instead.

**Windows:** download the *Windows Executable* (the 64-bit zip) from [exiftool.org](https://exiftool.org) and unzip it. Rename `exiftool(-k).exe` to `exiftool.exe`, then move it **together with** the `exiftool_files` folder into `C:\Windows`. Winget users can run `winget install OliverBetz.ExifTool` instead.

If Lightroom was open, restart it.

### 2. Install the plugin

1. **Download the zip from the [latest release](../../releases/latest).**
2. Unzip it (Safari usually does this for you). You get `SonyAspectMarkerCrop.lrplugin`.
3. Move it somewhere permanent, for example a *Lightroom Plugins* folder in Documents – or wherever you keep any other Lightroom plugins. Don't leave it in Downloads, where it might get deleted.
4. In Lightroom Classic, open **File > Plug-in Manager**, click **Add**, choose `SonyAspectMarkerCrop.lrplugin` in the folder you moved it to, and click **Done**.

To update later, replace it with the new version and restart Lightroom.

### 3. Check that it found ExifTool

In **File > Plug-in Manager**, select **Sony Aspect Marker Crop**. The *ExifTool* status at the top should say **OK**.

If it says *not found*, restart Lightroom and look again. Still not found? Click **Browse…**, pick ExifTool yourself, then click **Check again**. On a Mac, press ⌘⇧G in the file dialog and type `/usr/local/bin/exiftool` (the package installer) or `/opt/homebrew/bin/exiftool` (Homebrew on Apple Silicon). On Windows, pick `exiftool.exe`.

### 4. Try it on one photo

Select a photo you shot with the marker on, then choose **Library > Plug-in Extras > Apply Aspect Marker Crops**. The photo gets cropped and a summary appears.

## Using it

**Cropping:** select any number of photos, then **Library > Plug-in Extras > Apply Aspect Marker Crops**. With nothing selected, it asks before going through every photo in the current view. The summary tells you how many were cropped, and what happened to the rest.

**Undo:** ⌘Z / Ctrl+Z right afterwards takes back the whole run, and the next run will crop those photos again. To get rid of one crop for good, use *Reset* in the Develop module's Crop tool, or move the crop where you want it. It won't come back: the plugin never re-crops a photo that already carries its `AspectMarker` keyword. Want it cropped again after all? Remove the keyword and rerun.

**Finding marked photos:** make a smart collection with *Keywords contains "AspectMarker"*. The keyword includes the ratio, so *"AspectMarker 2.35:1"* finds only the 2.35:1 shots.

### Background auto-crop

Lightroom mobile has no plugins, so it can't make these crops. They have to be made in Lightroom Classic, on your computer. Auto-crop is for exactly that: leave Classic running at home with sync on, shoot and import on the road into Lightroom mobile, and the crops appear on your phone or iPad through sync. The computer has to stay on and awake with Lightroom Classic open. Nothing happens while it sleeps.

It's off by default. Turn it on under **File > Plug-in Manager > Sony Aspect Marker Crop > Background Auto-Crop**. While it's on, the plugin checks every five minutes for photos taken in the last 30 days and crops the new ones. Photos whose originals haven't downloaded yet are picked up on a later check. The status line in the same panel shows what the last check did.

One thing to know while it's on: the crops it makes in the background land in your undo history, so ⌘Z / Ctrl+Z may undo a batch of those instead of your own last change. The Edit menu tells you what ⌘Z would undo: *Undo Auto-crop 3 photos (background)* is the plugin's, anything else is yours. If you undo the plugin's by accident, the next check simply crops them again. It's also why, at the desk, it's better to leave auto-crop off and use the menu command.

## FAQ

**"ExifTool not found."** Install it (step 1), restart Lightroom, and check the Plug-in Manager again. Installed somewhere unusual? Use *Browse…* there.

**Nothing was cropped, the summary says "no aspect marker".** The marker was off when the photo was taken, the file was re-saved by software that dropped the Sony metadata, or your camera doesn't store the marker. To look inside a file yourself, see [How it works](#how-it-works).

**A photo got a crop I don't want.** Reset or move the crop in the Develop module's Crop tool, like any other crop. The plugin won't crop that photo again. Photos you've cropped or straightened yourself are never cropped in the first place.

**Lightroom (the cloud version) or Lightroom mobile?** Plugins exist only in Lightroom Classic. If Classic syncs with your cloud library, the plugin's crops sync like any other edit. That's what [background auto-crop](#background-auto-crop) is for.

**Capture One, DxO, Photoshop?** No, Lightroom Classic only. The marker is in the files, though, so anyone could build the same for another tool. See [How it works](#how-it-works).

**HEIF?** ARW and JPEG are tested. HEIF probably works, but hasn't been tested.

**A black window flashes on Windows.** That's ExifTool running. It's harmless, and Lightroom offers no way to hide it.

**Does it read or send anything else?** It reads the metadata of the selected files, nothing else, and it never connects anywhere.

**My JPEG's modified date changed, or a new .xmp file appeared.** That's Lightroom, not the plugin. With *Automatically write changes into XMP* turned on in Catalog Settings, Lightroom saves every edit, this crop and keyword included, into a sidecar file next to a raw photo or into the JPEG itself.

## Feedback

Found a problem, or want your camera added to the list? Open an [issue](../../issues/new/choose).

| Camera | Firmware | Status | Reported by |
| --- | --- | --- | --- |
| A7C II (ILCE-7CM2) | 2.01 | Works, ARW and JPEG | author |

## How it works

The camera stores the marker in every ARW and JPEG, in a Sony MakerNote tag that ExifTool doesn't decode yet: **0x2049**. The plugin asks ExifTool for that tag, works out the crop and writes it into the catalog as a normal Lightroom crop, plus the keyword.

To look inside a file yourself, with ExifTool installed, in Terminal (Mac) or Command Prompt (Windows):

```
exiftool -u -Sony:Sony_0x2049 photo.ARW
```

This prints `Sony 0x2049 : 2.35 1` for a 2.35:1 marker, `undef undef` if the marker was off, and nothing if the file has no such tag.

<details>
<summary><strong>More detail, for developers</strong></summary>

The tag holds a pair of rationals, for example `235/100 1/1`, which ExifTool prints as `2.35 1`. With the marker off the tag is still there but holds `0/0 0/0`, printed as `undef undef`, so the plugin requires a numeric value rather than the tag merely existing. The value is identical in the ARW and JPEG of the same shot and travels with the file, surviving copying, offloading and cloud sync. It isn't in the memory card's `DATABASE.BIN`.

The plugin ships a small ExifTool config file, `AspectMarkerCrop.config`, that names tag 0x2049 `AspectMarker`. It asks for the tag under that name and under ExifTool's generic unknown-tag name, so it keeps working whichever ExifTool version is installed, and also if ExifTool starts decoding the tag one day.

The crop is computed in sensor coordinates, because the marker is fixed relative to the sensor: a ratio wider than the sensor's gives bars top and bottom, a narrower one bars left and right. That's what makes portrait shots come out right. A marker equal to the sensor's own ratio is skipped. The crop and keyword are written with normal Lightroom SDK calls in a single catalog write. The keyword doubles as the plugin's memory: a photo carrying one is skipped on later runs, which keeps a removed crop removed. An undo takes the keyword with it, so a background write undone by accident is simply done again on the next check.

ExifTool is looked for in the usual install folders of each OS, then on the PATH; the location can be overridden in the Plug-in Manager. On Windows, ExifTool's command line can't carry characters outside the system code page. So the photo paths go through a UTF-8 arg file with `-charset filename=utf8`, as the ExifTool manual recommends, and ExifTool runs from inside the temp folder with relative file names. A user name such as Väinö never appears in its arguments.

| File | Role |
| --- | --- |
| `Info.lua` | Plugin manifest: menu entries, startup hook, version |
| `AspectMarkerCropCore.lua` | Finding and running ExifTool, reading the tag, crop maths, catalog writes |
| `ApplyAspectMarkerCrops.lua` | The menu command |
| `AutoWatch.lua` | Background auto-crop task |
| `PluginInfoProvider.lua` | The Plug-in Manager panel |
| `AspectMarkerCrop.config` | ExifTool config naming tag 0x2049 |

</details>

## About the author

![Some photos I've taken with 2.35:1 aspect ratio](https://cloud.miemo.net/sony-aspect-marker-crop-lr-plugin/samples.jpg)
*Some photos I've taken with 2.35:1 aspect ratio – © Miemo Penttinen 2026*

**I'm [Miemo Penttinen](https://miemo.net), a designer & photographer based in Finland.** I recently started shooting with a Sony A7C II and was drawn to the cinematic 2.35:1 aspect ratio for stills. What annoyed me was that the crop didn't carry over to Lightroom, where all my photos end up. So, with the help of Claude Code, I built this plugin to fix that for myself – and figured other Sony shooters might find it useful too. **Hope that you do!**

You can see more of my photos at [miemo.net](https://miemo.net/photo), [Instagram](https://instagram.com/miemo) and [Flickr](https://flickr.com/miemo). A follow is always appreciated.

## Licence and credits

The plugin is free software under the MIT licence, see [LICENSE](LICENSE). Use it, share it, change it.

The sample photos in this README are © Miemo Penttinen, all rights reserved. They are here to show what the plugin does and are **not** covered by the MIT licence.

[ExifTool](https://exiftool.org) is by Phil Harvey and is a separate program with its own licence. Sony, Alpha and the camera names are trademarks of Sony Group Corporation; Lightroom is a trademark of Adobe. This project is not affiliated with either company.
