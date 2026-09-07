--[[
Shared logic for reading Sony aspect-marker tag 0x2049 and applying crops.
Used by both the menu command and the background auto-watch task.

ExifTool bridge, macOS and Windows. Where ExifTool is looked for, in order:
  1. the location the user set in the Plug-in Manager (prefs.exiftoolPath);
     when it is set, nothing else is tried, so a wrong one gets reported
  2. the last auto-detected location (prefs.exiftoolDetected), if still there
  3. the usual install folders of each OS
  4. the PATH: `where` on Windows; a login shell on macOS, because GUI apps
     get a minimal PATH that lacks Homebrew's folders

Non-ASCII paths on Windows (a user called Väinö, a folder called Työ):
Lightroom hands the plugin UTF-8, and cmd.exe takes UTF-8 command lines
fine, but ExifTool's own arguments are limited to the system code page, so
  - photo paths go through a UTF-8 arg file with -charset filename=utf8,
    which is what the ExifTool manual recommends;
  - the command runs from inside the temp folder, and the arg file, a copy
    of the config file and the output files are named relatively, so no
    folder path is ever an ExifTool argument (John R. Ellis's pattern);
  - files are read back with LrFileUtils, which is UTF-8 safe; Lua's own
    io.open is only used for writing, with ASCII fallback folders in case
    it refuses the user's temp folder.
]]

local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'
local LrPrefs = import 'LrPrefs'
local LrDate = import 'LrDate'

local Core = {}

Core.isWindows = (WIN_ENV == true)

-- Set by AutoWatch.lua when the background task starts, so the Plug-in
-- Manager can tell "off" from "never started" (prefs persist across
-- sessions, so a stale status string there proves nothing).
Core.watcherStarted = false

local PLUGIN_PATH = _PLUGIN and _PLUGIN.path
local CONFIG_FILE = 'AspectMarkerCrop.config'
local EXE_NAMES = { 'exiftool.exe', 'exiftool(-k).exe' }
local KEYWORD_PREFIX = 'AspectMarker ' -- every keyword the plugin writes starts with this
local DEFAULT_ACTION = 'Apply Aspect Marker Crops'

-- ---------------------------------------------------------------------------
-- small helpers

local function env(name)
	local ok, v = pcall(function() return os.getenv(name) end)
	if ok and v and v ~= '' then return v end
	return nil
end

-- Quote one argument for the shell line. macOS: single quotes, which stop
-- every expansion ($, backticks, backslashes); an embedded single quote is
-- closed, escaped and reopened. Windows: cmd.exe only knows double quotes.
local function q(s)
	if Core.isWindows then return '"' .. s .. '"' end
	return "'" .. (s:gsub("'", "'\\''")) .. "'"
end

local function trim(s)
	return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- "1 photo", "12 photos"; for user-facing counts
function Core.plural(n, singular, pluralForm)
	return string.format('%d %s', n, n == 1 and singular or (pluralForm or singular .. 's'))
end

-- Whole file as a string, or nil. LrFileUtils rather than io.open: the SDK
-- notes recommend it whenever the path may hold non-ASCII characters.
local function readAll(path)
	local ok, s = pcall(LrFileUtils.readFile, path)
	if ok and type(s) == 'string' then return s end
	return nil
end

local function splitLines(s)
	local out = {}
	for line in (s .. '\n'):gmatch('(.-)\r?\n') do
		out[#out + 1] = line
	end
	return out
end

local tempCounter = 0
local function tempName(tag, ext)
	tempCounter = tempCounter + 1
	return string.format('aspectmarker_%s_%d_%d_%d.%s',
		tag, math.floor(LrDate.currentTime()), math.random(1000000), tempCounter, ext or 'txt')
end

-- The folder for the temporary files, chosen once per session. Windows gets
-- ASCII fallbacks (always writable by everyone) in case Lua's io.open cannot
-- open files in a temp folder whose path holds non-ASCII characters.
local tempDirChosen
local function tempDir()
	if tempDirChosen then return tempDirChosen end
	local dirs = { LrPathUtils.getStandardFilePath('temp') }
	if Core.isWindows then
		dirs[#dirs + 1] = env('PUBLIC') or 'C:\\Users\\Public'
		dirs[#dirs + 1] = (env('SystemRoot') or 'C:\\Windows') .. '\\Temp'
	end
	for _, d in ipairs(dirs) do
		local probe = LrPathUtils.child(d, tempName('probe'))
		local f = io.open(probe, 'wb')
		if f then
			f:close()
			LrFileUtils.delete(probe)
			tempDirChosen = d
			return d
		end
	end
	return dirs[1]
end

-- Turn a Lightroom path and an ExifTool-reported path into the same key.
-- ExifTool prints forward slashes even on Windows, and Windows paths are
-- case-insensitive. Repeated slashes are collapsed because ExifTool prints
-- "E://photo.ARW" for a file directly at a drive root.
function Core.pathKey(p)
	p = p:gsub('\\', '/'):gsub('/+', '/')
	if Core.isWindows then p = p:lower() end
	return p
end

-- Runs `parts` from inside the temp folder, with stdin closed and stdout and
-- stderr captured to files there. Returns stdout, stderr, exit code.
-- Running from inside the folder is what keeps every file name ExifTool sees
-- a plain relative name (see the header comment).
-- Windows: cmd.exe strips the first and last quote of a line that starts with
-- a quote and contains more than two, which would break paths with spaces, so
-- the whole line is wrapped in one extra pair of quotes. Closing stdin also
-- makes an un-renamed "exiftool(-k).exe" return instead of waiting for Enter.
local function run(parts)
	local dir = tempDir()
	local outName, errName = tempName('out'), tempName('err')
	local cmd = table.concat(parts, ' ')
	local line
	if Core.isWindows then
		line = '"cd /d ' .. q(dir) .. ' && ' .. cmd .. ' < NUL > ' .. q(outName) .. ' 2> ' .. q(errName) .. '"'
	else
		line = 'cd ' .. q(dir) .. ' && ' .. cmd .. ' < /dev/null > ' .. q(outName) .. ' 2> ' .. q(errName)
	end
	local rc = LrTasks.execute(line)
	local outFile, errFile = LrPathUtils.child(dir, outName), LrPathUtils.child(dir, errName)
	local out, err = readAll(outFile), readAll(errFile)
	LrFileUtils.delete(outFile)
	LrFileUtils.delete(errFile)
	return out or '', err or '', rc
end

-- ---------------------------------------------------------------------------
-- finding ExifTool

local function candidates()
	if not Core.isWindows then
		return {
			'/opt/homebrew/bin/exiftool', -- Homebrew on Apple Silicon
			'/usr/local/bin/exiftool',    -- Homebrew on Intel, and the official .pkg installer
			'/opt/local/bin/exiftool',    -- MacPorts
		}
	end
	-- Per-user folders are derived from Lightroom's own (UTF-8) idea of the
	-- home folder; os.getenv would give code-page bytes for a user name with
	-- non-ASCII characters, which never match on disk.
	local home = LrPathUtils.getStandardFilePath('home')
	local dirs = {}
	local function add(base, sub)
		if base then dirs[#dirs + 1] = sub and (base .. sub) or base end
	end
	add(env('SystemRoot') or 'C:\\Windows')                            -- where exiftool.org tells people to put it
	add(env('ProgramFiles') or 'C:\\Program Files', '\\ExifTool')
	add(env('ProgramFiles(x86)') or 'C:\\Program Files (x86)', '\\ExifTool')
	add(home, '\\AppData\\Local\\Programs\\ExifTool')                   -- Oliver Betz's per-user installer
	add(env('ProgramData') or 'C:\\ProgramData', '\\chocolatey\\bin')
	add(home, '\\scoop\\shims')
	add('C:\\ExifTool')
	local out = {}
	for _, d in ipairs(dirs) do
		for _, n in ipairs(EXE_NAMES) do out[#out + 1] = d .. '\\' .. n end
	end
	return out
end

local function looksLikePath(s)
	return s:match('^/') or s:match('^%a:[\\/]')
end

local function lookupOnPath()
	local attempts
	if Core.isWindows then
		-- chcp 65001 first, so `where` writes its answer as UTF-8 rather
		-- than in the console code page
		attempts = { { 'chcp', '65001', '>', 'NUL', '&&', 'where', 'exiftool' } }
	else
		-- login shells, so ~/.zprofile or ~/.bash_profile (where Homebrew
		-- puts its PATH setup) are read
		attempts = {
			{ '/bin/zsh', '-l', '-c', "'command -v exiftool'" },
			{ '/bin/bash', '-l', '-c', "'command -v exiftool'" },
		}
	end
	for _, parts in ipairs(attempts) do
		local out = run(parts)
		for _, line in ipairs(splitLines(out)) do
			line = trim(line)
			if line ~= '' and looksLikePath(line) and LrFileUtils.exists(line) == 'file' then
				return line
			end
		end
	end
	return nil
end

-- A user-entered location may be the folder rather than the program itself.
local function resolveManual(p)
	local kind = LrFileUtils.exists(p)
	if kind == 'file' then return p end
	if kind == 'directory' then
		local names = Core.isWindows and EXE_NAMES or { 'exiftool' }
		for _, n in ipairs(names) do
			local c = LrPathUtils.child(p, n)
			if LrFileUtils.exists(c) == 'file' then return c end
		end
	end
	return nil
end

-- Returns path, 'manual' | 'auto'; or nil, message, 'manual_missing' | 'not_found'.
function Core.findExiftool()
	local prefs = LrPrefs.prefsForPlugin()
	local manual = trim(prefs.exiftoolPath or '')
	if manual ~= '' then
		-- a location the user set wins outright; a wrong one is reported
		-- rather than papered over with whatever auto-detection finds
		local p = resolveManual(manual)
		if p then return p, 'manual' end
		return nil, 'ExifTool not found at the location set in the Plug-in Manager (' .. manual .. ')', 'manual_missing'
	end
	local cached = prefs.exiftoolDetected
	if cached and cached ~= '' and LrFileUtils.exists(cached) == 'file' then
		return cached, 'auto'
	end
	for _, p in ipairs(candidates()) do
		if LrFileUtils.exists(p) == 'file' then
			prefs.exiftoolDetected = p
			return p, 'auto'
		end
	end
	local p = lookupOnPath()
	if p then
		prefs.exiftoolDetected = p
		return p, 'auto'
	end
	prefs.exiftoolDetected = nil
	return nil, 'ExifTool not found', 'not_found'
end

-- True for the error codes that mean ExifTool could not be found.
function Core.isExiftoolMissing(code)
	return code == 'not_found' or code == 'manual_missing'
end

-- Runs "exiftool -ver". Returns the version string, or nil and why not.
function Core.exiftoolVersion(exiftool)
	local out, err, rc = run({ q(exiftool), '-ver' })
	local ver = out:match('(%d+%.%d+)')
	if ver then return ver end
	err = trim(err)
	if err == '' then err = 'no output, exit code ' .. tostring(rc) end
	return nil, err
end

-- Install instructions for the current OS, for the "not found" dialog.
function Core.installHint()
	local tail = '\n\nThen restart Lightroom. Already installed somewhere unusual? Set its location '
		.. 'under File > Plug-in Manager > Sony Aspect Marker Crop.'
	if Core.isWindows then
		return 'Download the Windows 64-bit zip from exiftool.org, unzip it, rename '
			.. '"exiftool(-k).exe" to "exiftool.exe", and move it together with its '
			.. '"exiftool_files" folder into C:\\Windows.' .. tail
	end
	return 'Install the ExifTool macOS package from exiftool.org, or run '
		.. '"brew install exiftool" if you use Homebrew.' .. tail
end

-- What to do about a findExiftool failure, by its error code; for dialogs.
function Core.exiftoolHint(code)
	if code == 'manual_missing' then
		return 'Correct the location under File > Plug-in Manager > Sony Aspect Marker Crop, '
			.. 'or clear it to have ExifTool found automatically.'
	end
	return Core.installHint()
end

-- Re-detects ExifTool and updates prefs.exiftoolStatus for the Plug-in
-- Manager panel. Must run inside a task. Returns true when ExifTool works.
function Core.refreshExiftoolStatus()
	local prefs = LrPrefs.prefsForPlugin()
	prefs.exiftoolStatus = 'Checking…'
	prefs.exiftoolDetected = nil
	local path, info, code = Core.findExiftool()
	if not path then
		if code == 'manual_missing' then
			prefs.exiftoolStatus = 'Not found at the location below. Correct it, or clear it to search automatically.'
		else
			prefs.exiftoolStatus = 'Not found. Install ExifTool (step 1 in the README) and restart Lightroom. '
				.. 'Already installed? Set its location below.'
		end
		return false
	end
	local ver, err = Core.exiftoolVersion(path)
	if ver then
		prefs.exiftoolStatus = string.format('OK: ExifTool %s at %s%s',
			ver, path, info == 'manual' and ' (location set below)' or '')
		return true
	end
	prefs.exiftoolStatus = string.format('Found ExifTool at %s, but it did not run: %s', path, err)
	return false
end

-- ---------------------------------------------------------------------------
-- reading the marker

-- Runs ExifTool over all paths at once. Returns a map pathKey -> outcome for
-- every path ExifTool printed a line for; or nil, reason when the run failed
-- as a whole. Outcomes:
--   { kind = 'marker', value = '2.35 1' }   a numeric marker, for cropForMarker
--   { kind = 'none' }                        marker off, or no such tag
--   { kind = 'odd', value = '…' }            a value the plugin does not understand
--   { kind = 'error', message = '…' }        ExifTool could not read the file
-- A path with no entry got no line at all (file gone, or ExifTool stopped
-- early); treat it as not read.
--
-- The tag is asked for under two names: "AspectMarker", which the shipped
-- config file defines for tag 0x2049, and "Sony_0x2049", ExifTool's own name
-- for it while it is still an unknown tag. Whichever is present wins, so the
-- plugin keeps working if the config file goes missing or ExifTool starts
-- decoding the tag itself one day. "$Error" is ExifTool's per-file error
-- ("File is empty", "Error opening file"), "-" when there was none.
function Core.readMarkers(exiftool, paths)
	local dir = tempDir()
	local argsName = tempName('args')
	local f = io.open(LrPathUtils.child(dir, argsName), 'wb')
	if not f then return nil, 'could not write a temporary file in ' .. dir end
	f:write('-u\n-q\n-f\n')
	f:write('-p\n$Directory/$FileName|$Sony:AspectMarker|$Sony:Sony_0x2049|$Error\n')
	for _, p in ipairs(paths) do
		f:write(p, '\n')
	end
	f:close()

	local parts = { q(exiftool) }
	-- ExifTool requires -config before all other arguments. A copy of the
	-- config file goes next to the arg file, so that it too is a plain
	-- relative name and the plugin folder's path never reaches ExifTool.
	local cfgName
	local config = PLUGIN_PATH and LrPathUtils.child(PLUGIN_PATH, CONFIG_FILE)
	if config and LrFileUtils.exists(config) == 'file' then
		cfgName = tempName('cfg', 'config')
		LrFileUtils.copy(config, LrPathUtils.child(dir, cfgName))
		if LrFileUtils.exists(LrPathUtils.child(dir, cfgName)) == 'file' then
			parts[#parts + 1] = '-config'
			parts[#parts + 1] = q(cfgName)
		else
			cfgName = nil
		end
	end
	if Core.isWindows then
		-- Lightroom hands us UTF-8 paths; ExifTool must be told so, and the
		-- manual says this option has to come before -@ to count
		parts[#parts + 1] = '-charset'
		parts[#parts + 1] = 'filename=utf8'
	end
	parts[#parts + 1] = '-@'
	parts[#parts + 1] = q(argsName)

	local out, err = run(parts)
	LrFileUtils.delete(LrPathUtils.child(dir, argsName))
	if cfgName then LrFileUtils.delete(LrPathUtils.child(dir, cfgName)) end

	local wanted = {}
	for _, p in ipairs(paths) do wanted[Core.pathKey(p)] = true end

	local results, seen, matched, stray = {}, 0, 0, nil
	for _, line in ipairs(splitLines(out)) do
		local path, named, unknown, problem = line:match('^(.*)|([^|]*)|([^|]*)|([^|]*)$')
		if path then
			seen = seen + 1
			local key = Core.pathKey(path)
			if wanted[key] then matched = matched + 1 else stray = stray or path end
			local outcome
			if problem ~= '-' and problem ~= '' then
				outcome = { kind = 'error', message = problem }
			else
				-- whichever name ExifTool knew; "-" is a missing tag,
				-- "undef undef" is the marker switched off
				local value = named ~= '-' and named or unknown
				if value:match('^[%d%.]+%s+[%d%.]+$') then
					outcome = { kind = 'marker', value = value }
				elseif value == '-' or value:match('^undef') then
					outcome = { kind = 'none' }
				else
					outcome = { kind = 'odd', value = value }
				end
			end
			results[key] = outcome
		end
	end
	if seen == 0 then
		err = trim(err)
		return nil, 'ExifTool produced no output' .. (err ~= '' and (': ' .. err) or '')
	end
	if matched == 0 then
		-- every line was for a path we did not ask about: the path forms
		-- differ, and silently reporting "no marker" for everything would hide it
		return nil, string.format('ExifTool reported on "%s", which matches none of the photos', stray or '?')
	end
	return results
end

-- ---------------------------------------------------------------------------
-- crop maths

-- Sony's marker choices, for tidy keyword labels whatever the camera's exact
-- encoding (16:9 could come back as 16/9 or as 178/100, for example).
local KNOWN_RATIOS = {
	{ 1, 1, '1:1' }, { 5, 4, '5:4' }, { 4, 3, '4:3' }, { 16, 9, '16:9' },
	{ 1.91, 1, '1.91:1' }, { 2.35, 1, '2.35:1' },
}

local function ratioLabel(ratio, num, den)
	for _, k in ipairs(KNOWN_RATIOS) do
		if math.abs(ratio - k[1] / k[2]) < 0.005 then return k[3] end
	end
	return string.format('%g:%g', num, den)
end

-- "2.35 1" -> crop table in sensor coordinates + keyword label,
-- or nil if nothing to crop (native ratio or unparseable)
function Core.cropForMarker(value, dims)
	local num, den = value:match('^([%d%.]+)%s+([%d%.]+)$')
	num, den = tonumber(num), tonumber(den)
	if not num or not den or den == 0 then return nil, nil end
	local ratio = num / den

	local sensorAspect = 1.5
	if dims and dims.width and dims.height and dims.height > 0 then
		local a = dims.width / dims.height
		if a < 1 then a = 1 / a end
		sensorAspect = a
	end

	if math.abs(ratio - sensorAspect) < 0.01 then return nil, nil end

	local label = KEYWORD_PREFIX .. ratioLabel(ratio, num, den)
	local crop
	if ratio > sensorAspect then
		local m = (1 - sensorAspect / ratio) / 2
		crop = { CropTop = m, CropBottom = 1 - m, CropLeft = 0, CropRight = 1 }
	else
		local m = (1 - ratio / sensorAspect) / 2
		crop = { CropTop = 0, CropBottom = 1, CropLeft = m, CropRight = 1 - m }
	end
	crop.CropAngle = 0
	return crop, label
end

-- A crop or a straighten the user (or something else) already made. The
-- angle counts too, since applying our crop would reset it to 0.
function Core.hasExistingCrop(settings)
	if not settings then return false end
	local function differs(v, default) return v ~= nil and math.abs(v - default) > 0.001 end
	return differs(settings.CropTop, 0) or differs(settings.CropLeft, 0)
		or differs(settings.CropBottom, 1) or differs(settings.CropRight, 1)
		or differs(settings.CropAngle, 0)
end

-- ---------------------------------------------------------------------------
-- applying to the catalog

-- The plugin's keyword by name, wherever the user may have moved it in the
-- keyword list; nil when there is none yet. createKeyword's returnExisting
-- only finds keywords under the given parent, so a keyword nested somewhere
-- else would otherwise get a top-level duplicate on every run.
local function findKeyword(catalog, name)
	local function search(list)
		for _, kw in ipairs(list) do
			if kw:getName() == name then return kw end
		end
		for _, kw in ipairs(list) do
			local found = search(kw:getChildren())
			if found then return found end
		end
		return nil
	end
	return search(catalog:getKeywords())
end

-- Path and keywords of every photo: one catalog call where the SDK allows
-- it, one call per photo otherwise.
local function pathsAndKeywords(catalog, photos)
	local ok, byPhoto = LrTasks.pcall(function()
		return catalog:batchGetRawMetadata(photos, { 'path', 'keywords' })
	end)
	if ok and type(byPhoto) == 'table' then return byPhoto end
	byPhoto = {}
	for _, photo in ipairs(photos) do
		byPhoto[photo] = { path = photo:getRawMetadata('path'), keywords = photo:getRawMetadata('keywords') }
	end
	return byPhoto
end

-- The plugin's keyword is also its memory: a photo that carries one has
-- been handled before and is left alone, whatever its crop looks like now.
-- That keeps a crop the user removed removed. (An undone background write
-- takes the keyword with it, so that photo is simply done again.)
local function hasMarkerKeyword(keywords)
	for _, kw in ipairs(keywords or {}) do
		local name = kw:getName()
		if type(name) == 'string' and name:sub(1, #KEYWORD_PREFIX) == KEYWORD_PREFIX then
			return true
		end
	end
	return false
end

--[[
Apply marker crops/keywords to an array of LrPhoto.

writeParams: nil for a normal blocking write, or e.g. {timeout = 10} for
background use (returns nil, message, 'busy' if access can't be obtained).
progressFn: optional callback(done, total).
actionName: the Edit > Undo label; a string, or a function of the number of
photos about to be written. Defaults to 'Apply Aspect Marker Crops'.

Returns res table on success:
  cropped, keyworded, alreadyCropped, unmarked, missing (counts)
  alreadyHandled                    photos skipped for carrying the keyword already
  unreadable, unreadableExample     files ExifTool could not read, and one reason
  unrecognised, unrecognisedExample marker values the plugin does not understand
  processedPhotos  array of LrPhoto whose files ExifTool actually read
  unmarkedPhotos   those of them that got no keyword (no marker, native
    ratio, or a value not understood); the only ones a caller has to
    remember, since keyworded photos announce themselves next time
or nil, errorMessage, errorCode ('not_found' / 'manual_missing' when ExifTool
is missing, see Core.isExiftoolMissing; 'busy' when catalog write access
timed out).

The same file can be behind several photos (virtual copies); each photo gets
its own crop and keyword, the file is read once.
]]
function Core.apply(catalog, photos, writeParams, progressFn, actionName)
	local exiftool, why, code = Core.findExiftool()
	if not exiftool then
		return nil, why, code
	end

	local res = {
		cropped = 0, keyworded = 0, alreadyCropped = 0, unmarked = 0, missing = 0,
		alreadyHandled = 0,
		unreadable = 0, unreadableExample = nil,
		unrecognised = 0, unrecognisedExample = nil,
		processedPhotos = {}, unmarkedPhotos = {},
	}

	local meta = pathsAndKeywords(catalog, photos)
	local items, paths, listed = {}, {}, {}
	for _, photo in ipairs(photos) do
		local m = meta[photo] or {}
		if hasMarkerKeyword(m.keywords) then
			res.alreadyHandled = res.alreadyHandled + 1
		elseif m.path and LrFileUtils.exists(m.path) then
			items[#items + 1] = { photo = photo, key = Core.pathKey(m.path) }
			if not listed[m.path] then
				listed[m.path] = true
				paths[#paths + 1] = m.path
			end
		else
			res.missing = res.missing + 1
		end
	end
	if #items == 0 then return res end

	local results, readErr = Core.readMarkers(exiftool, paths)
	if not results then return nil, 'ExifTool failed: ' .. readErr end

	-- Work out what each photo needs. The catalog reads happen here, before
	-- the write lock is taken.
	local work = {}
	for _, it in ipairs(items) do
		local r = results[it.key]
		if not r then
			-- no line for it: gone since we looked, or ExifTool stopped
			-- early; not processed, so a later run tries again
			res.missing = res.missing + 1
		elseif r.kind == 'error' then
			res.unreadable = res.unreadable + 1
			res.unreadableExample = res.unreadableExample or r.message
		else
			res.processedPhotos[#res.processedPhotos + 1] = it.photo
			local crop, label
			if r.kind == 'marker' then
				crop, label = Core.cropForMarker(r.value, it.photo:getRawMetadata('dimensions'))
			end
			if crop then
				work[#work + 1] = {
					photo = it.photo, crop = crop, label = label,
					hasCrop = Core.hasExistingCrop(it.photo:getDevelopSettings()),
				}
			else
				res.unmarkedPhotos[#res.unmarkedPhotos + 1] = it.photo
				if r.kind == 'odd' then
					res.unrecognised = res.unrecognised + 1
					res.unrecognisedExample = res.unrecognisedExample or r.value
				else
					res.unmarked = res.unmarked + 1 -- marker off, or the sensor's own ratio
				end
			end
		end
	end
	if #work == 0 then return res end

	local total = #work
	local done = 0
	if type(actionName) == 'function' then actionName = actionName(total) end
	local status = catalog:withWriteAccessDo(actionName or DEFAULT_ACTION, function()
		local keywords = {} -- label -> LrKeyword, looked up once per run
		for _, w in ipairs(work) do
			done = done + 1
			if progressFn then progressFn(done, total) end
			local kw = keywords[w.label]
			if not kw then
				kw = findKeyword(catalog, w.label) or catalog:createKeyword(w.label, {}, true, nil, true)
				keywords[w.label] = kw
			end
			w.photo:addKeyword(kw)
			res.keyworded = res.keyworded + 1
			if w.hasCrop then
				res.alreadyCropped = res.alreadyCropped + 1
			else
				w.photo:applyDevelopSettings(w.crop)
				res.cropped = res.cropped + 1
			end
		end
	end, writeParams)

	if status == 'aborted' then
		return nil, 'Lightroom was busy', 'busy'
	end
	return res
end

return Core
