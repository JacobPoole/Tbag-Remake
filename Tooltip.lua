-- TBag Remake: adds "how many do my characters have" lines to item tooltips.
local _, ns = ...

local function ShortName(key)
	if key == "account" then return "Warband Bank" end
	return key:match("^(.-) %- ") or key
end

local function NameColor(key)
	local c = ns.db.chars[key]
	local color = c and c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
	if color then return color.r, color.g, color.b end
	return 0.6, 0.8, 1
end

local function AddCounts(tooltip, data)
	if not ns.db or not ns.settings.tooltipCounts then return end
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
	local itemID = data and ns.Safe(data.id)
	if type(itemID) ~= "number" then return end

	local results = ns.CountItem(itemID)
	if #results == 0 then return end

	tooltip:AddLine(" ")
	local grand = 0
	for _, r in ipairs(results) do
		grand = grand + r.total
		local parts = {}
		if r.bags then table.insert(parts, "Bags " .. r.bags) end
		if r.bank then table.insert(parts, "Bank " .. r.bank) end
		if r.equip then table.insert(parts, "Equipped " .. r.equip) end
		if r.mail then table.insert(parts, "Mail " .. r.mail) end
		local red, green, blue = NameColor(r.key)
		tooltip:AddDoubleLine(ShortName(r.key), table.concat(parts, ", "), red, green, blue, 0.9, 0.9, 0.9)
	end
	if #results > 1 then
		tooltip:AddDoubleLine("Total", grand, 1, 0.82, 0, 1, 1, 1)
	end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		-- Never let a tooltip error (e.g. a secret value in combat) break the tooltip.
		pcall(AddCounts, tooltip, data)
	end)
end
