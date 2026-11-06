-- TBag Remake: settings panel (Game Menu > Options > AddOns > TBag Remake).
local ADDON, ns = ...

local category

local function Register()
	category = Settings.RegisterVerticalLayoutCategory("TBag Remake")

	local function OnChanged()
		ns.RefreshAll()
	end

	local function Checkbox(key, label, tooltip, onChange)
		local setting = Settings.RegisterAddOnSetting(category, "TBAGREMAKE_" .. key, key, ns.settings,
			Settings.VarType.Boolean, label, ns.defaults[key])
		setting:SetValueChangedCallback(onChange or OnChanged)
		Settings.CreateCheckbox(category, setting, tooltip)
	end

	local function Slider(key, label, tooltip, min, max, step, fmt)
		local setting = Settings.RegisterAddOnSetting(category, "TBAGREMAKE_" .. key, key, ns.settings,
			Settings.VarType.Number, label, ns.defaults[key])
		setting:SetValueChangedCallback(OnChanged)
		local options = Settings.CreateSliderOptions(min, max, step)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
		Settings.CreateSlider(category, setting, options, tooltip)
	end

	Slider("columns", "Items per row", "How many item buttons fit across a window.", 4, 24, 1)
	Slider("scale", "Window scale", "Scale of the bag and bank windows.", 0.5, 2, 0.05,
		function(v) return string.format("%.2f", v) end)
	Checkbox("compactEmpty", "Compact free slots",
		"Show a single button with a count for each kind of free slot, instead of every empty slot.")
	Checkbox("newFirst", "New items category",
		"Put newly looted items in a \"New Items\" category at the top until you mouse over them.")
	Checkbox("dimSearch", "Dim search misses",
		"While searching, dim items that do not match. When off, non-matching items are hidden.")
	Checkbox("tooltipCounts", "Character counts in tooltips",
		"Show how many of an item each of your characters has (bags, bank, equipped, mail).")
	Checkbox("locked", "Lock window positions", "Prevent the bag and bank windows from being dragged.")
	Checkbox("hideBlizzard", "Replace default bags and bank",
		"Hide Blizzard's bag and bank windows and use TBag instead. Requires /reload.",
		function() ns.Print("Type /reload for this change to take effect.") end)

	Settings.RegisterAddOnCategory(category)
end

function ns.SetupOptions()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
	local ok, err = pcall(Register)
	if not ok then
		category = nil
		ns.Print("Settings panel unavailable (" .. tostring(err) .. "). Use /tbag help for slash commands.")
	end
end

function ns.OpenOptions()
	if category and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
	else
		SlashCmdList.TBAGREMAKE("help")
	end
end
