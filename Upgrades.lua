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

local PHYSICAL = { WARRIOR = true, ROGUE = true, HUNTER = true, DEATHKNIGHT = true, DEMONHUNTER = true, MONK = true }
local CASTER = { MAGE = true, WARLOCK = true, PRIEST = true }

local function WeightsForClass(class)
	local w = { sta = 0.5, armor = 0.01, resist = 0.05, other = 0.4, tank = 0.1, spi = 0.1 }
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

function ns.ScoreItem(link)
	if not link then return 0 end
	local cached = scoreCache[link]
	if cached ~= nil then return cached or nil end

	local stats = C_Item.GetItemStats(link)
	if not stats then
		scoreCache[link] = false -- try again once item data arrives
		return nil
	end
	local w = Weights()
	local score = 0
	for key, value in pairs(stats) do
		value = ns.Safe(value)
		if type(value) == "number" then
			score = score + value * (w[Classify(key)] or w.other)
		end
	end
	scoreCache[link] = score
	return score
end

local function CanWear(link, itemID)
	local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
	if not equipLoc or not SLOT[equipLoc] then return false end

	local minLevel = select(5, C_Item.GetItemInfo(link))
	if minLevel and minLevel > UnitLevel("player") then return false end

	if classID == CLASS_ARMOR and subClassID and subClassID >= 1 and subClassID <= 4 and equipLoc ~= "INVTYPE_CLOAK" then
		local max = MAX_ARMOR[select(2, UnitClass("player"))]
		if max and subClassID > max then return false end
	end

	if C_PlayerInfo and C_PlayerInfo.CanUseItem and itemID then
		local ok, usable = pcall(C_PlayerInfo.CanUseItem, itemID)
		if ok and ns.Safe(usable) == false then return false end
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
		if (mh and not s1) or (oh and not s2) then return nil end
		return (s1 or 0) + (s2 or 0), mh
	end
	if equipLoc == "INVTYPE_WEAPON" then
		slots = { 16 }
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

-- Returns isUpgrade, scoreDelta, linkOfItemItWouldReplace
function ns.GetUpgradeInfo(link, itemID)
	if not link then return false end
	local cached = upgradeCache[link]
	if cached then return cached[1], cached[2], cached[3] end

	local canWear, equipLoc = CanWear(link, itemID)
	if not canWear then
		upgradeCache[link] = { false }
		return false
	end
	-- Something you are already wearing is never an upgrade (e.g. hovering
	-- your better ring would otherwise compare it against your weaker one).
	for slot = 1, 19 do
		if GetInventoryItemLink("player", slot) == link then
			upgradeCache[link] = { false }
			return false
		end
	end

	local score = ns.ScoreItem(link)
	local equipped, versus = EquippedScore(equipLoc)
	if not score or not equipped then
		return false -- item data still loading; not cached so we retry later
	end
	local delta = score - equipped
	local isUpgrade = delta > 0.5
	upgradeCache[link] = { isUpgrade, delta, versus }
	return isUpgrade, delta, versus
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
