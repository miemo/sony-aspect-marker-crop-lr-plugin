--[[
Background auto-crop task (LrInitPlugin).

When enabled in the Plug-in Manager (off by default), polls the catalog every
few minutes for recently captured photos and applies aspect-marker crops to
new arrivals — e.g. photos coming in via cloud sync from Lightroom mobile
while traveling.

What counts as new: a recent photo without an AspectMarker keyword that this
session has not already found to be unmarked. The keyword is the durable
record (see Core.apply), so a photo the plugin handled in an earlier session
is left alone, and a crop the user removed stays removed. Photos whose
originals aren't on disk yet, or whose files ExifTool could not read, are
retried on later cycles. An accidental Edit > Undo of a background write
takes the keyword with it, so those photos are simply done again at the
next check.

prefs.autoStatus is the detail part of the status line in the Plug-in
Manager. The panel prefixes it with "On." or "Off." from the checkbox itself,
so the detail never repeats that.
]]

local LrTasks = import 'LrTasks'
local LrPrefs = import 'LrPrefs'
local LrDate = import 'LrDate'
local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'

local Core = require 'AspectMarkerCropCore'
local plural = Core.plural

local TICK_SECONDS = 5       -- how often the loop wakes to check the toggle
local POLL_SECONDS = 300     -- how often to actually scan when enabled
local LOOKBACK_DAYS = 30     -- capture-date window to scan

local STATUS_WAITING = 'Waiting for the first check…'

local function timestamp()
	return LrDate.timeToUserFormat(LrDate.currentTime(), '%H:%M')
end

-- The Edit > Undo label for a background write, so it is obvious in the
-- Edit menu which entry is the plugin's.
local function undoLabel(n)
	return 'Auto-crop ' .. plural(n, 'photo') .. ' (background)'
end

-- Recently captured photos; tries a few searchDesc spellings since the
-- smart-collection grammar is underdocumented. Returns array or nil.
local function findRecent(catalog)
	local shapes = {
		{ criteria = 'captureTime', operation = 'inLast', value = LOOKBACK_DAYS, value_units = 'days' },
		{ criteria = 'captureTime', operation = 'inLast', value = LOOKBACK_DAYS, valueUnits = 'days' },
		{ criteria = 'captureTime', operation = 'inLast', value = LOOKBACK_DAYS },
	}
	for _, sd in ipairs(shapes) do
		local ok, photos = LrTasks.pcall(function()
			return catalog:findPhotos { searchDesc = sd }
		end)
		if ok and type(photos) == 'table' then return photos end
	end
	return nil
end

LrTasks.startAsyncTask(function()
	local prefs = LrPrefs.prefsForPlugin()
	if prefs.autoEnabled == nil then prefs.autoEnabled = false end
	Core.watcherStarted = true -- lets the Plug-in Manager tell "off" from "never started"

	-- generation guard: if the plugin is reloaded, any older watcher task
	-- notices the bumped generation and exits instead of double-running
	local myGeneration = (prefs.watchGeneration or 0) + 1
	prefs.watchGeneration = myGeneration

	prefs.autoStatus = prefs.autoEnabled and STATUS_WAITING or ''

	-- localIdentifier -> true for photos this session found to have no
	-- usable marker; keyworded photos need no remembering
	local unmarked = {}
	local lastPoll = 0
	local wasEnabled = prefs.autoEnabled
	local keepDetail = false -- set just before the watcher switches itself off

	-- Reflect the checkbox in the status line the moment it is ticked or
	-- unticked; the loop below is the fallback and would otherwise leave a
	-- stale "Waiting…" or "Last check…" next to "Off." for a few seconds.
	pcall(function()
		prefs:addObserver('autoEnabled', function()
			if prefs.watchGeneration ~= myGeneration then return end
			if prefs.autoEnabled then
				prefs.autoStatus = STATUS_WAITING
			elseif keepDetail then
				keepDetail = false -- the watcher's own switch-off message stays
			else
				prefs.autoStatus = ''
			end
		end)
	end)

	while true do
		LrTasks.sleep(TICK_SECONDS)
		if prefs.watchGeneration ~= myGeneration then
			return -- a newer watcher has taken over
		end

		local enabled = prefs.autoEnabled
		if enabled and not wasEnabled then
			-- switched on in the Plug-in Manager: check right away
			lastPoll = 0
			prefs.autoStatus = STATUS_WAITING
		elseif wasEnabled and not enabled then
			-- switched off in the Plug-in Manager (when the watcher switches
			-- itself off it updates wasEnabled, so its message stays)
			prefs.autoStatus = ''
		end
		wasEnabled = enabled

		if enabled then
			local now = LrDate.currentTime()
			if now - lastPoll >= POLL_SECONDS then
				lastPoll = now
				local ok, err = LrTasks.pcall(function()
					local catalog = LrApplication.activeCatalog()
					local recent = findRecent(catalog)
					if not recent then
						prefs.autoStatus = 'The catalog search failed, so auto-crop switched itself off. Please report this on GitHub.'
						keepDetail = true
						wasEnabled = false
						prefs.autoEnabled = false
						return
					end

					local candidates = {}
					for _, p in ipairs(recent) do
						if not unmarked[p.localIdentifier] then
							candidates[#candidates + 1] = p
						end
					end

					local noNews = string.format('Last check %s: no new photos (%s from the last %d days)',
						timestamp(), plural(#recent, 'photo'), LOOKBACK_DAYS)
					if #candidates == 0 then
						prefs.autoStatus = noNews
						return
					end

					local res, applyErr, code = Core.apply(catalog, candidates, { timeout = 10 }, nil, undoLabel)
					if not res then
						-- catalog busy or exiftool trouble: nothing is
						-- remembered, so the next cycle retries them
						if Core.isExiftoolMissing(code) then
							applyErr = applyErr .. '. See the ExifTool section above.'
						elseif code == 'busy' then
							applyErr = applyErr .. ', will try again at the next check'
						end
						prefs.autoStatus = string.format('Last check %s: %s', timestamp(), applyErr)
						return
					end

					for _, p in ipairs(res.unmarkedPhotos) do
						unmarked[p.localIdentifier] = true
					end

					-- photos already carrying the keyword were only glanced at
					local newCount = #candidates - res.alreadyHandled
					if newCount == 0 then
						prefs.autoStatus = noNews
						return
					end

					if res.cropped > 0 then
						LrDialogs.showBezel('Aspect Marker Crop: ' .. plural(res.cropped, 'photo') .. ' cropped')
					end
					local summary = string.format('%s checked, %d cropped', plural(newCount, 'new photo'), res.cropped)
					if res.missing > 0 then
						summary = summary .. string.format(', %d waiting for originals to download', res.missing)
					end
					if res.unreadable > 0 then
						summary = summary .. string.format(', %d could not be read yet', res.unreadable)
					end
					prefs.autoStatus = string.format('Last check %s: %s', timestamp(), summary)
				end)
				if not ok then
					prefs.autoStatus = string.format('Last check %s: failed (%s)', timestamp(), tostring(err))
				end
			end
		end
	end
end)
