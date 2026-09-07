--[[
Menu command: apply aspect-marker crops to the selected photos.
See AspectMarkerCropCore.lua for the shared logic.
]]

local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'
local LrDialogs = import 'LrDialogs'
local LrProgressScope = import 'LrProgressScope'

local Core = require 'AspectMarkerCropCore'
local plural = Core.plural

LrTasks.startAsyncTask(function()
	local catalog = LrApplication.activeCatalog()
	-- getTargetPhotos() falls back to every photo in the current view when
	-- nothing is selected, like Lightroom's own commands. getTargetPhoto()
	-- is nil in that case, so ask before running through the whole view.
	local photos = catalog:getTargetPhotos()
	if #photos == 0 then
		LrDialogs.message('No photos to crop',
			'Open a folder or collection, select the photos you want to crop, then choose Apply Aspect Marker Crops again.',
			'info')
		return
	end
	if catalog:getTargetPhoto() == nil and #photos > 1 then
		local answer = LrDialogs.confirm(
			'No photos selected. Crop all ' .. plural(#photos, 'photo') .. ' in the current view?',
			'Photos that already have a crop are left alone, and you can undo afterwards.',
			'Crop all', 'Cancel')
		if answer ~= 'ok' then return end
	end

	-- Whatever happens inside, the progress bar must be taken down and the
	-- user told, or Lightroom shows an "internal error" and the bar stays.
	local progress = LrProgressScope { title = 'Reading Sony aspect markers…' }
	local ok, res, err, code = LrTasks.pcall(function()
		return Core.apply(catalog, photos, { timeout = 60 }, function(done, total)
			progress:setPortionComplete(done, total)
		end)
	end)
	progress:done()

	if not ok then
		LrDialogs.message('Could not apply the aspect marker crops', tostring(res), 'critical')
		return
	end
	if not res then
		if Core.isExiftoolMissing(code) then
			LrDialogs.message(err, Core.exiftoolHint(code), 'critical')
		elseif code == 'busy' then
			LrDialogs.message('Lightroom is busy',
				'Something else is writing to the catalog (background auto-crop, perhaps). Wait a moment, then try again.',
				'warning')
		else
			LrDialogs.message('Could not read the aspect markers', err, 'critical')
		end
		return
	end

	-- headline: the outcome; details: only the lines that apply
	local headline = res.cropped == 0 and 'No photos cropped' or (plural(res.cropped, 'photo') .. ' cropped')
	local lines = {}
	if res.alreadyCropped > 0 then
		lines[#lines + 1] = plural(res.alreadyCropped, 'photo') .. ' already had a crop, so only the keyword was added.'
	end
	if res.unmarked > 0 then
		lines[#lines + 1] = plural(res.unmarked, 'photo') .. ' had no aspect marker.'
	end
	if res.alreadyHandled > 0 then
		lines[#lines + 1] = plural(res.alreadyHandled, 'photo') .. ' already had an AspectMarker keyword from an earlier run, so '
			.. (res.alreadyHandled == 1 and 'it was' or 'they were') .. ' left alone. Remove the keyword to redo.'
	end
	if res.unrecognised > 0 then
		lines[#lines + 1] = plural(res.unrecognised, 'photo')
			.. ' had an aspect marker value this plugin does not understand ("' .. res.unrecognisedExample
			.. '"). Please report it on GitHub, with your camera model.'
	end
	if res.unreadable > 0 then
		lines[#lines + 1] = plural(res.unreadable, 'photo')
			.. ' could not be read (' .. res.unreadableExample .. '). Try again later.'
	end
	if res.missing > 0 then
		lines[#lines + 1] = plural(res.missing, 'photo')
			.. ' skipped because the original file is not available (offline drive, or not downloaded yet).'
	end
	LrDialogs.message(headline, #lines > 0 and table.concat(lines, '\n') or nil, 'info')
end)
