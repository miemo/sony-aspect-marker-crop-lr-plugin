return {
	LrSdkVersion = 10.0,
	LrSdkMinimumVersion = 10.0,
	LrToolkitIdentifier = 'net.miemo.sonyaspectmarkercrop',
	LrPluginName = 'Sony Aspect Marker Crop',
	LrPluginInfoUrl = 'https://github.com/miemo/sony-aspect-marker-crop-lr-plugin',

	LrInitPlugin = 'AutoWatch.lua',
	LrPluginInfoProvider = 'PluginInfoProvider.lua',

	-- register in both Plug-in Extras menus (File and Library)
	LrExportMenuItems = {
		{
			title = 'Apply Aspect Marker Crops',
			file = 'ApplyAspectMarkerCrops.lua',
		},
	},
	LrLibraryMenuItems = {
		{
			title = 'Apply Aspect Marker Crops',
			file = 'ApplyAspectMarkerCrops.lua',
		},
	},

	VERSION = { major = 1, minor = 3, revision = 0 },
}
