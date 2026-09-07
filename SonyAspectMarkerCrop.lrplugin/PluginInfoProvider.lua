--[[
Plug-in Manager UI: ExifTool status and location, the opt-in toggle for
background auto-crop, and a live status line for the watcher.
]]

local LrView = import 'LrView'
local LrPrefs = import 'LrPrefs'
local LrTasks = import 'LrTasks'
local LrDialogs = import 'LrDialogs'

local Core = require 'AspectMarkerCropCore'

return {
	sectionsForTopOfDialog = function(f, _)
		local prefs = LrPrefs.prefsForPlugin()
		if prefs.autoEnabled == nil then prefs.autoEnabled = false end
		if prefs.exiftoolPath == nil then prefs.exiftoolPath = '' end
		-- prefs persist across sessions, so a status string there may be
		-- last session's; only the watcher's in-memory flag says whether
		-- LrInitPlugin ran this session
		if not Core.watcherStarted then
			prefs.autoStatus = 'Not running. Restart Lightroom.'
		end
		local bind = LrView.bind

		local function recheck()
			LrTasks.startAsyncTask(Core.refreshExiftoolStatus)
		end
		prefs.exiftoolStatus = 'Checking…'
		recheck()

		local function browse()
			local picked = LrDialogs.runOpenPanel {
				title = 'Locate ExifTool',
				prompt = 'Choose',
				canChooseFiles = true,
				canChooseDirectories = false,
				allowsMultipleSelection = false,
				canCreateDirectories = false,
				fileTypes = Core.isWindows and { 'exe' } or nil,
			}
			if picked and picked[1] then
				prefs.exiftoolPath = picked[1]
				recheck()
			end
		end

		local locationHelp
		if Core.isWindows then
			locationHelp = 'Leave the location empty and ExifTool is found automatically. Fill it in only if the\n'
				.. 'status says it was not found: pick exiftool.exe, then click Check again.'
		else
			locationHelp = 'Leave the location empty and ExifTool is found automatically. Fill it in only if the\n'
				.. 'status says it was not found. In the file dialog, press Cmd+Shift+G and type a path\n'
				.. 'such as /usr/local/bin/exiftool or /opt/homebrew/bin/exiftool, then click Check again.'
		end

		return {
			{
				title = 'ExifTool',
				bind_to_object = prefs,

				f:static_text {
					title = 'The plugin reads the aspect marker from your photos with ExifTool, a free tool\n'
						.. 'that you install separately. See step 1 in the README.',
				},
				f:row {
					f:static_text { title = 'Status:', font = '<system/bold>' },
					f:static_text {
						title = bind 'exiftoolStatus',
						fill_horizontal = 1,
						width_in_chars = 60,
						height_in_lines = 2,
					},
				},
				f:row {
					f:static_text { title = 'Location:' },
					f:edit_field {
						value = bind 'exiftoolPath',
						immediate = true,
						fill_horizontal = 1,
						width_in_chars = 40,
					},
					f:push_button { title = 'Browse…', action = browse },
					f:push_button { title = 'Check again', action = recheck },
				},
				f:static_text { title = locationHelp },
			},
			{
				title = 'Background Auto-Crop',
				bind_to_object = prefs,

				f:checkbox {
					title = 'Crop new photos automatically as they arrive',
					value = bind 'autoEnabled',
				},
				f:static_text {
					title = 'For travelling. Lightroom mobile has no plugins, so the crops have to be made here.\n'
						.. 'Leave Lightroom Classic running at home with sync on, and the crops reach your phone\n'
						.. 'or tablet through sync. Every 5 minutes the plugin checks for photos taken in the\n'
						.. 'last 30 days and crops the new ones. Photos that already have a crop are never touched.',
				},
				f:row {
					f:static_text { title = 'Status:', font = '<system/bold>' },
					-- On/Off comes straight from the checkbox, so it changes the
					-- moment the box is ticked; the watcher fills in the rest
					f:static_text {
						title = bind {
							key = 'autoEnabled',
							transform = function(on) return on and 'On.' or 'Off.' end,
						},
					},
					f:static_text { title = bind 'autoStatus', fill_horizontal = 1, width_in_chars = 50 },
				},
			},
		}
	end,
}
