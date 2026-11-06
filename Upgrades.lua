-- TBag Remake: finds gear in your bags that is better than what you are wearing.
--
-- Each item gets a score from its stats using class-based weights (Strength
-- matters to a Warrior, Intellect to a Mage, and so on). An item is an upgrade
-- if you can use it and it scores higher than the item in the matching
-- equipment slot (for rings, trinkets and dual-wield weapons, the weaker of
-- the two equipped items). An empty slot counts as score 0.
local _, ns = ...

-------------------------------------------------------------------------------
-- Stat weights
-------------------------------------------------------------------------------

-- Stat keys from C_Item.GetItemStats look like ITEM_MOD_STRENGTH_SHORT. They are
-- matched by pattern so slightly different key names still count.
local STAT_PATTERNS = {
	{ "STRENGTH", "str" },
	{ "AGILITY", "agi" },
	{ "INTELLECT", "int" },
	{ "SPIRIT", "spi" },
	{ "STAMINA", "sta" },
	{ "RESISTANCE0", "armor" },
	{ "DAMAGE_PER_SECOND", "dps" },
	{ "RANGED_ATTACK_POWER", "ap" },
	{ "ATTACK_POWER", "ap" },
	{ "SPELL_POWER", "sp" },
	{ "SPELL_DAMAGE", "sp" },
	{ "HEALING", "sp" },
	{ "DEFENSE", "tank" },
	{ "DODGE", "tank" },
	{ "PARRY", "tank" },
	{ "BLOCK", "tank" },
	{ "RESISTANCE", "resist" }, -- fire/frost/etc. (armor matched above first)
}

local CASTER = { MAGE = true, WARLOCK = true, PRIEST = true }

local function WeightsForClass(class)
	-- Armor is worth a little for everyone so low-level white gear (armor only) still compares.
	local w = { sta = 0.5, armor = 0.04, resist = 0.05, other = 0.4, tank = 0.1, spi = 0.1 }
	if class == "WARRIOR" or class == "DEATHKNIGHT" then
		w.str, w.agi, w.int, w.ap, w.sp, w.dps, w.tank = 1, 0.6, 0, 0.5, 0, 2.5, 0.4
	elseif class == "PALADIN" then
		w.str, w.agi, w.int, w.ap, w.sp, w.dps, w.tank = 1, 0.3, 0.6, 0.5, 0.6, 2, 0.4
	elseif class == "ROGUE" or class == "DEMONHUNTER" or class == "MONK" then
		w.str, w.agi, w.int, w.ap, w.sp, w.dps = 0.3, 1, 0, 0.5, 0, 2.5
	elseif class == "HUNTER" then
		w.str, w.agi, w.int, w.ap, w.sp, w.dps = 0.1, 1, 0.2, 0.5, 0, 2.5
	elseif class == "SHAMAN" then
		w.str, w.agi, w.int, w.ap, w.sp, w.dps, w.spi = 0.4, 0.6, 0.8, 0.4, 0.6, 1.5, 0.2
	elseif class == "DRUID" then
		w.str, w.agi, w.int, w.ap, w.sp, w.dps, w.spi = 0.4, 0.8, 0.8, 0.4, 0.6, 1, 0.3
	elseif CASTER[class] then
		w.str, w.agi, w.int, w.ap, w.sp, w.dps = 0, 0.1, 1, 0, 0.8, 0.1
		w.spi = (class == "PRIEST") and 0.6 or 0.4
	else
		w.str, w.agi, w.int, w.ap, w.sp, w.dps = 0.5, 0.5, 0.5, 0.4, 0.4, 1.5
	end
	return w
end

-- Highest armor type each class can wear (1 cloth, 2 leather, 3 mail, 4 plate).
local MAX_ARMOR = {
	WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
	HUNTER = 3, SHAMAN = 3, EVOKER = 3,
	ROGUE = 2, DRUID = 2, MONK = 2, DEMONHUNTER = 2,
	MAGE = 1, PRIEST = 1, WARLOCK = 1,
}

-------------------------------------------------------------------------------
-- Equipment slots for each item type
-------------------------------------------------------------------------------

local SLOT = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
	INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
	INVTYPE_RELIC = { 18 },
}

local CLASS_ARMOR = 4

-------------------------------------------------------------------------------
-- Scoring
-------------------------------------------------------------------------------

local weights
local scoreCache = {}   -- [link] = score (false while item data is not loaded)
local upgradeCache = {} -- [link] = { isUpgrade, delta, versusLink }

local function Weights()
	if not weights then
		weights = WeightsForClass(select(2, UnitClass("player")))
	end
	return weights
end

local function Classify(statKey)
	for _, p in ipairs(STAT_PATTERNS) do
		if statKey:find(p[1], 1, true) then return p[2] end
	end
	return "other"
end

-------------------------------------------------------------------------------
-- Reading an item's tooltip (usability + backup stat source)
-------------------------------------------------------------------------------

local function TooltipLines(link)
	if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil end
	local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
	return data.lines
end

-- Red tooltip text is how the game marks things you cannot use: too low level,
-- wrong armor/weapon type, wrong class, and so on.
local function IsRed(c)
	if type(c) ~= "table" then return false end
	local r, g, b = ns.Safe(c.r), ns.Safe(c.g), ns.Safe(c.b)
	return type(r) == "number" and type(g) == "number" and type(b) == "number"
		and r > 0.9 and g < 0.3 and b < 0.3
end

local function TooltipBlocker(lines)
	for _, line in ipairs(lines) do
		if IsRed(line.leftColor) or IsRed(line.rightColor) then
			local text = ns.Safe(line.leftText) or ""
			-- A broken item's durability line is red, but it can still be worn.
			if not text:find("Durability", 1, true) then
				local right = ns.Safe(line.rightText)
				return (text ~= "" and text) or right or "red tooltip line"
			end
		end
	end
end

-- English tooltip text -> stat bucket, used only if C_Item.GetItemStats gives nothing.
local TEXT_STATS = {
	Strength = "str", Agility = "agi", Intellect = "int", Spirit = "spi", Stamina = "sta",
}

local function StatsFromTooltip(lines)
	local stats = {}
	local function add(key, v)
		v = tonumber((tostring(v):gsub(",", "")))
		if v then stats[key] = (stats[key] or 0) + v end
	end
	for _, line in ipairs(lines) do
		local text = ns.Safe(line.leftText)
		if type(text) == "string" then
			local armor = text:match("^([%d,]+) Armor")
			if armor then add("armor", armor) end
			local dps = text:match("%(([%d%.,]+) damage per second%)")
			if dps then add("dps", dps) end
			local n, stat = text:match("^%+([%d,]+) (%a+)$")
			if n and TEXT_STATS[stat] then add(TEXT_STATS[stat], n) end
			local ap = text:match("[Aa]ttack [Pp]ower by ([%d,]+)")
			if ap then add("ap", ap) end
			local sp = text:match("magical spells and effects by up to ([%d,]+)")
			if sp then add("sp", sp) end
		end
	end
	return stats
end

-------------------------------------------------------------------------------
-- Scoring
-------------------------------------------------------------------------------

-- Returns score, or nil while the item's data is still loading.
function ns.ScoreItem(link)
	if not link then return 0 end
	local cached = scoreCache[link]
	if cached ~= nil then return cached or nil end

	if not C_Item.GetItemInfo(link) then
		scoreCache[link] = false -- not loaded yet; retried on GET_ITEM_INFO_RECEIVED
		return nil
	end

	local w = Weights()
	local score = 0
	local stats = C_Item.GetItemStats(link)
	if type(stats) == "table" and next(stats) then
		for key, value in pairs(stats) do
			value = ns.Safe(value)
			if type(value) == "number" then
				score = score + value * (w[Classify(key)] or w.other)
			end
		end
	else
		local lines = TooltipLines(link)
		if lines then
			for bucket, value in pairs(StatsFromTooltip(lines)) do
				score = score + value * (w[bucket] or w.other)
			end
		end
	end
	scoreCache[link] = score
	return score
end

-- Returns ok, equipLocOrReason
local function CanWear(link)
	local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
	if not equipLoc or not SLOT[equipLoc] then return false, "not gear" end

	local lines = TooltipLines(link)
	if lines then
		local blocker = TooltipBlocker(lines)
		if blocker then return false, "unusable: " .. blocker end
		return true, equipLoc
	end

	-- No tooltip data available: fall back to level and armor type rules.
	local minLevel = select(5, C_Item.GetItemInfo(link))
	if minLevel and minLevel > UnitLevel("player") then
		return false, "requires level " .. minLevel
	end
	if classID == CLASS_ARMOR and subClassID and subClassID >= 1 and subClassID <= 4 and equipLoc ~= "INVTYPE_CLOAK" then
		local max = MAX_ARMOR[select(2, UnitClass("player"))]
		if max and subClassID > max then return false, "armor type too heavy" end
	end
	return true, equipLoc
end

-- Score of what is currently in the slots this item would replace.
local function EquippedScore(equipLoc)
	local slots = SLOT[equipLoc]
	if equipLoc == "INVTYPE_2HWEAPON" then
		-- A two-hander replaces both hands.
		local mh = GetInventoryItemLink("player", 16)
		local oh = GetInventoryItemLink("player", 17)
		local s1, s2 = ns.ScoreItem(mh), ns.ScoreItem(oh)
		if s1 == nil or s2 == nil then return nil end
		return s1 + s2, mh
	end
	if equipLoc == "INVTYPE_WEAPON" then
		local oh = GetInventoryItemLink("player", 17)
		local ohLoc = oh and select(4, C_Item.GetItemInfoInstant(oh))
		if ohLoc == "INVTYPE_WEAPON" or ohLoc == "INVTYPE_WEAPONOFFHAND" then
			slots = { 16, 17 } -- dual wielding: compare against the weaker weapon
		end
	end
	local worst, worstLink
	for _, slot in ipairs(slots) do
		local link = GetInventoryItemLink("player", slot)
		local score = 0
		if link then
			score = ns.ScoreItem(link)
			if score == nil then return nil end -- equipped item data still loading
		end
		if not worst or score < worst then
			worst, worstLink = score, link
		end
	end
	return worst or 0, worstLink
end

-- Full evaluation with the reason, used by GetUpgradeInfo and /tbag upgrades.
-- result.status is "loading", "skip" or "done".
local function Evaluate(link)
	if not C_Item.GetItemInfo(link) then
		return { status = "loading", reason = "item data still loading" }
	end
	local ok, equipLocOrReason = CanWear(link)
	if not ok then
		return { status = "skip", reason = equipLocOrReason }
	end
	-- Something you are already wearing is never an upgrade (e.g. hovering
	-- your better ring would otherwise compare it against your weaker one).
	for slot = 1, 19 do
		if GetInventoryItemLink("player", slot) == link then
			return { status = "skip", reason = "already equipped" }
		end
	end
	local score = ns.ScoreItem(link)
	local equipped, versus = EquippedScore(equipLocOrReason)
	if not score or not equipped then
		return { status = "loading", reason = "item data still loading" }
	end
	local delta = score - equipped
	return {
		status = "done", isUpgrade = delta > 0.01, delta = delta,
		score = score, equipped = equipped, versus = versus,
	}
end

-- Returns isUpgrade, scoreDelta, linkOfItemItWouldReplace
function ns.GetUpgradeInfo(link)
	if not link then return false end
	local r = upgradeCache[link]
	if not r then
		r = Evaluate(link)
		if r.status == "loading" then
			scoreCache[link] = false -- makes GET_ITEM_INFO_RECEIVED trigger a re-check
			return false
		end
		upgradeCache[link] = r
	end
	return r.isUpgrade or false, r.delta, r.versus
end

-- /tbag upgrades: explain the decision for every piece of gear in your bags.
function ns.ExplainUpgrades()
	ns.Print("Upgrade check (" .. (select(2, UnitClass("player")) or "?") .. ", level " .. UnitLevel("player") .. "):")
	local n = 0
	for _, bag in ipairs(ns.InventoryBags()) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local link = info and info.hyperlink
			if link and SLOT[select(4, C_Item.GetItemInfoInstant(link)) or ""] then
				n = n + 1
				local r = Evaluate(link)
				if r.status == "done" then
					print(string.format("  %s: %s (score %.1f vs %.1f for %s)", link,
						r.isUpgrade and "|cff20ff20UPGRADE|r" or "not better", r.score, r.equipped, r.versus or "empty slot"))
				else
					print("  " .. link .. ": " .. r.reason)
				end
			end
		end
	end
	if n == 0 then
		print("  No wearable gear found in your bags.")
	end
end

local function ClearCaches()
	wipe(upgradeCache)
	weights = nil
end

local refresh = ns.Debounce(function()
	wipe(scoreCache)
	ClearCaches()
	ns.RefreshAll()
end, 0.3)

ns.On("PLAYER_EQUIPMENT_CHANGED", refresh)
ns.On("PLAYER_LEVEL_UP", refresh)
ns.On("GET_ITEM_INFO_RECEIVED", function()
	-- Only re-check if some item was still waiting on its data.
	for _, score in pairs(scoreCache) do
		if score == false then
			refresh()
			return
		end
	end
end)
