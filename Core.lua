-- TBag Remake: core namespace, saved variables, event dispatch, slash commands.
local ADDON, ns = ...

ns.name = ADDON
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

ns.defaults = {
	columns = 10,          -- item columns per window
	scale = 1,             -- window scale
	bgAlpha = 0.3,         -- window background opacity (0 = fully see-through)
	showUpgrades = true,   -- show gear upgrades in their own category at the top
	compactEmpty = true,   -- show one "free slot" button per bag type instead of every empty slot
	newFirst = false,      -- put new items in their own "New Items" category at the top
	dimSearch = true,      -- dim non-matching items while searching (false = hide them)
	hideBlizzard = true,   -- hide the default bag and bank frames (requires /reload)
	tooltipCounts = true,  -- show counts across characters in item tooltips
	locked = false,        -- lock window positions
}

-------------------------------------------------------------------------------
-- Utilities
-------------------------------------------------------------------------------

function ns.Print(...)
	print("|cff33ff99TBag|r:", ...)
end

-- Returns nil for "secret" values on Midnight-era clients so we never branch on them.
function ns.Safe(v)
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	return v
end

function ns.IsEventValid(event)
	if C_EventUtils and C_EventUtils.IsEventValid then
		return C_EventUtils.IsEventValid(event)
	end
	return true
end

-- "Name - Realm" key used for the character cache.
function ns.CharKey(name, realm)
	return (name or UnitName("player")) .. " - " .. (realm or GetRealmName())
end

function ns.CopyDefaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			ns.CopyDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
	if not ns.IsEventValid(event) then return end
	if not handlers[event] then
		handlers[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		list[i](event, ...)
	end
end)

-- Coalesce many calls in the same frame into one (bag updates fire in bursts).
function ns.Debounce(fn, delay)
	local pending = false
	return function()
		if pending then return end
		pending = true
		C_Timer.After(delay or 0.05, function()
			pending = false
			fn()
		end)
	end
end

-------------------------------------------------------------------------------
-- Saved variables
-------------------------------------------------------------------------------

ns.On("ADDON_LOADED", function(_, name)
	if name ~= ADDON then return end

	TBagRemakeDB = TBagRemakeDB or {}
	local db = TBagRemakeDB
	-- Move anyone still on an old default (55% or 20%) to the new 30% default.
	if db.settings and (db.settings.bgAlpha == 0.55 or db.settings.bgAlpha == 0.2) then
		db.settings.bgAlpha = nil
	end
	db.settings = ns.CopyDefaults(db.settings or {}, ns.defaults)
	db.chars = db.chars or {}
	db.account = db.account or {}
	db.assign = db.assign or {}       -- [itemID] = categoryKey (manual overrides)
	db.pinned = db.pinned or {}       -- [itemID] = true (always shown at the top)
	db.custom = db.custom or {}       -- [categoryKey] = display name (user-made categories)
	db.catOrder = db.catOrder or {}   -- ordered category keys
	db.collapsed = db.collapsed or {} -- [categoryKey] = true
	db.hiddenCats = db.hiddenCats or {}
	db.pos = db.pos or {}

	ns.db = db
	ns.settings = db.settings

	if ns.OnDatabaseReady then ns.OnDatabaseReady() end
end)

ns.On("PLAYER_LOGIN", function()
	ns.me = ns.CharKey()
	local db = ns.db
	db.chars[ns.me] = db.chars[ns.me] or {}
	local c = db.chars[ns.me]
	c.class = select(2, UnitClass("player"))
	c.faction = UnitFactionGroup("player")
	c.level = UnitLevel("player")
	c.lastSeen = time()

	if ns.OnLogin then ns.OnLogin() end
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

local function Help()
	ns.Print("v" .. ns.version .. " commands:")
	print("  /tbag - toggle your bags")
	print("  /tbag bank - toggle the bank window (cached view when away from a banker)")
	print("  /tbag find <text> - search every character's bags, bank, gear and mail")
	print("  /tbag upgrades - explain which gear in your bags is (or isn't) an upgrade")
	print("  /tbag cols <n> - items per row (4-24)")
	print("  /tbag scale <n> - window scale (0.5-2)")
	print("  /tbag alpha <n> - background opacity (0-1)")
	print("  /tbag newcat <name> - create a custom category")
	print("  /tbag lock - lock/unlock window positions")
	print("  /tbag reset - reset window positions")
	print("  /tbag config - open settings")
	print("  Tip: Alt+Left-click an item to pin it to the top of your bags.")
	print("  Tip: Alt+Right-click an item to assign it to a category.")
	print("  Tip: Click a category header to collapse it, right-click to reorder.")
end

SLASH_TBAGREMAKE1 = "/tbag"
SLASH_TBAGREMAKE2 = "/tb"
SlashCmdList.TBAGREMAKE = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "" then
		ns.inventory:Toggle()
	elseif cmd == "bank" then
		ns.bank:Toggle()
	elseif cmd == "find" or cmd == "search" then
		ns.FindEverywhere(rest)
	elseif cmd == "cols" or cmd == "columns" then
		local n = tonumber(rest)
		if n then
			ns.settings.columns = math.max(4, math.min(24, math.floor(n)))
			ns.RefreshAll()
		end
		ns.Print("Columns:", ns.settings.columns)
	elseif cmd == "scale" then
		local n = tonumber(rest)
		if n then
			ns.settings.scale = math.max(0.5, math.min(2, n))
			ns.RefreshAll()
		end
		ns.Print("Scale:", ns.settings.scale)
	elseif cmd == "upgrades" or cmd == "upgrade" then
		ns.ExplainUpgrades()
	elseif cmd == "alpha" or cmd == "opacity" then
		local n = tonumber(rest)
		if n then
			ns.settings.bgAlpha = math.max(0, math.min(1, n))
			ns.RefreshAll()
		end
		ns.Print("Background opacity:", ns.settings.bgAlpha)
	elseif cmd == "newcat" then
		ns.CreateCustomCategory(rest)
	elseif cmd == "lock" then
		ns.settings.locked = not ns.settings.locked
		ns.Print(ns.settings.locked and "Windows locked." or "Windows unlocked.")
	elseif cmd == "reset" then
		wipe(ns.db.pos)
		ns.inventory:RestorePosition()
		ns.bank:RestorePosition()
		ns.Print("Window positions reset.")
	elseif cmd == "config" or cmd == "options" then
		ns.OpenOptions()
	else
		Help()
	end
end

function TBagRemake_OnAddonCompartmentClick()
	ns.inventory:Toggle()
end
