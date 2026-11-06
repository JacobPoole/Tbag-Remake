-- TBag Remake: item categories, classification and sorting.
local _, ns = ...

-- Item class IDs (Enum.ItemClass), kept numeric so we do not depend on enum names.
local CLASS_CONSUMABLE  = 0
local CLASS_CONTAINER   = 1
local CLASS_WEAPON      = 2
local CLASS_GEM         = 3
local CLASS_ARMOR       = 4
local CLASS_REAGENT     = 5
local CLASS_PROJECTILE  = 6
local CLASS_TRADEGOODS  = 7
local CLASS_ENHANCEMENT = 8
local CLASS_RECIPE      = 9
local CLASS_QUIVER      = 11
local CLASS_QUEST       = 12
local CLASS_KEY         = 13
local CLASS_MISC        = 15
local CLASS_GLYPH       = 16
local CLASS_BATTLEPET   = 17
local CLASS_PROFESSION  = 19

local MISC_SUB_PET   = 2
local MISC_SUB_MOUNT = 5

-- Built-in categories in their default display order.
ns.builtinCategories = {
	{ key = "pinned",     name = "Pinned" },
	{ key = "upgrades",   name = "Gear Upgrades" },
	{ key = "new",        name = "New Items" },
	{ key = "quest",      name = "Quest Items" },
	{ key = "weapon",     name = "Weapons" },
	{ key = "armor",      name = "Armor" },
	{ key = "consumable", name = "Consumables" },
	{ key = "tradegoods", name = "Trade Goods" },
	{ key = "gem",        name = "Gems & Enhancements" },
	{ key = "recipe",     name = "Recipes" },
	{ key = "profession", name = "Profession Tools" },
	{ key = "ammo",       name = "Ammo" },
	{ key = "container",  name = "Bags" },
	{ key = "key",        name = "Keys" },
	{ key = "collection", name = "Pets & Mounts" },
	{ key = "misc",       name = "Miscellaneous" },
	{ key = "junk",       name = "Junk" },
	{ key = "empty",      name = "Free Slots" },
}

local builtinNames = {}
for _, c in ipairs(ns.builtinCategories) do
	builtinNames[c.key] = c.name
end

function ns.CategoryName(key)
	return builtinNames[key] or (ns.db and ns.db.custom[key]) or key
end

function ns.CategoryExists(key)
	return builtinNames[key] ~= nil or (ns.db and ns.db.custom[key] ~= nil)
end

-- Ordered list of every category key: saved order first, then anything new.
function ns.GetCategoryOrder()
	local db = ns.db
	local seen, order = {}, {}
	for _, key in ipairs(db.catOrder) do
		if ns.CategoryExists(key) and not seen[key] then
			seen[key] = true
			table.insert(order, key)
		end
	end
	local function append(key)
		if not seen[key] then
			seen[key] = true
			-- New custom categories go just before Junk/Free Slots so they are visible.
			local insertAt = #order + 1
			for i, k in ipairs(order) do
				if k == "junk" or k == "empty" then
					insertAt = i
					break
				end
			end
			table.insert(order, insertAt, key)
		end
	end
	-- A built-in missing from a saved order (e.g. added in an update) goes right
	-- after the built-in that precedes it by default, or first if there is none.
	local prevBuiltin
	for _, c in ipairs(ns.builtinCategories) do
		if not seen[c.key] then
			seen[c.key] = true
			local insertAt = 1
			if prevBuiltin then
				for i, k in ipairs(order) do
					if k == prevBuiltin then insertAt = i + 1 break end
				end
			end
			table.insert(order, insertAt, c.key)
		end
		prevBuiltin = c.key
	end
	local customKeys = {}
	for key in pairs(db.custom) do table.insert(customKeys, key) end
	table.sort(customKeys)
	for _, key in ipairs(customKeys) do append(key) end

	wipe(db.catOrder)
	for i, key in ipairs(order) do db.catOrder[i] = key end
	return order
end

function ns.MoveCategory(key, delta)
	local order = ns.GetCategoryOrder()
	for i, k in ipairs(order) do
		if k == key then
			local j = i + delta
			if j >= 1 and j <= #order then
				order[i], order[j] = order[j], order[i]
				wipe(ns.db.catOrder)
				for n, v in ipairs(order) do ns.db.catOrder[n] = v end
				ns.RefreshAll()
			end
			return
		end
	end
end

function ns.CreateCustomCategory(name)
	name = name and strtrim(name) or ""
	if name == "" then
		ns.Print("Usage: /tbag newcat <name>")
		return
	end
	local key = "custom:" .. name:lower():gsub("%s+", "_")
	if ns.db.custom[key] then
		ns.Print("Category already exists:", name)
		return key
	end
	ns.db.custom[key] = name
	ns.GetCategoryOrder()
	ns.RefreshAll()
	ns.Print("Created category:", name, "- Alt+Right-click items to assign them.")
	return key
end

function ns.DeleteCustomCategory(key)
	if not ns.db.custom[key] then return end
	ns.db.custom[key] = nil
	for itemID, cat in pairs(ns.db.assign) do
		if cat == key then ns.db.assign[itemID] = nil end
	end
	ns.GetCategoryOrder()
	ns.RefreshAll()
end

function ns.AssignItem(itemID, key)
	if not itemID then return end
	ns.db.assign[itemID] = key
	ns.RefreshAll()
end

function ns.IsPinned(itemID)
	return itemID and ns.db.pinned[itemID] or false
end

function ns.TogglePin(itemID)
	if not itemID then return end
	ns.db.pinned[itemID] = not ns.db.pinned[itemID] or nil
	ns.RefreshAll()
end

-------------------------------------------------------------------------------
-- Classification
-------------------------------------------------------------------------------

-- entry fields: itemID, link, quality, isQuest, isNew
function ns.Classify(entry)
	if ns.IsPinned(entry.itemID) then
		return "pinned"
	end

	local assigned = entry.itemID and ns.db.assign[entry.itemID]
	if assigned and ns.CategoryExists(assigned) then
		return assigned
	end

	if entry.isUpgrade and ns.settings.showUpgrades then
		return "upgrades"
	end

	if entry.isNew and ns.settings.newFirst then
		return "new"
	end

	if entry.isQuest then
		return "quest"
	end

	if entry.quality == 0 then
		return "junk"
	end

	local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(entry.itemID or entry.link)
	if classID == CLASS_QUEST then return "quest" end
	if classID == CLASS_WEAPON then return "weapon" end
	if classID == CLASS_ARMOR then return "armor" end
	if classID == CLASS_CONSUMABLE then return "consumable" end
	if classID == CLASS_TRADEGOODS or classID == CLASS_REAGENT then return "tradegoods" end
	if classID == CLASS_GEM or classID == CLASS_ENHANCEMENT or classID == CLASS_GLYPH then return "gem" end
	if classID == CLASS_RECIPE then return "recipe" end
	if classID == CLASS_PROFESSION then return "profession" end
	if classID == CLASS_PROJECTILE then return "ammo" end
	if classID == CLASS_CONTAINER or classID == CLASS_QUIVER then return "container" end
	if classID == CLASS_KEY then return "key" end
	if classID == CLASS_BATTLEPET then return "collection" end
	if classID == CLASS_MISC and (subClassID == MISC_SUB_PET or subClassID == MISC_SUB_MOUNT) then
		return "collection"
	end
	return "misc"
end

-------------------------------------------------------------------------------
-- Sorting inside a category
-------------------------------------------------------------------------------

local function EntryName(e)
	if e.name and e.name ~= "" then return e.name end
	return e.link and e.link:match("%[(.-)%]") or ""
end
ns.EntryName = EntryName

function ns.SortEntries(list)
	table.sort(list, function(a, b)
		local qa, qb = a.quality or -1, b.quality or -1
		if qa ~= qb then return qa > qb end
		local na, nb = EntryName(a), EntryName(b)
		if na ~= nb then return na < nb end
		local ia, ib = a.itemID or 0, b.itemID or 0
		if ia ~= ib then return ia < ib end
		local ca, cb = a.count or 0, b.count or 0
		if ca ~= cb then return ca > cb end
		-- Stable tie-break so items never jump around between refreshes.
		if a.bag ~= b.bag then return (a.bag or 0) < (b.bag or 0) end
		return (a.slot or 0) < (b.slot or 0)
	end)
end
