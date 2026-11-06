-- TBag Remake: reads live container contents and keeps a per-character cache
-- so bags, bank, gear and mail can be viewed and searched from any character.
local _, ns = ...

ns.BANK_CHARACTER = (Enum.BankType and Enum.BankType.Character) or 0
ns.BANK_ACCOUNT = (Enum.BankType and Enum.BankType.Account) or 2

ns.atBank = false

local REAGENT_BAG = (Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5

-------------------------------------------------------------------------------
-- Which containers make up the inventory / bank
-------------------------------------------------------------------------------

-- Number of usable slots in a container. The bag API reports the keyring at its
-- maximum possible size, so use GetKeyRingSize() like Blizzard's own bags do.
local function ContainerSize(bag)
	if KEYRING_CONTAINER and bag == KEYRING_CONTAINER then
		return GetKeyRingSize and GetKeyRingSize() or 0
	end
	return C_Container.GetContainerNumSlots(bag) or 0
end

function ns.InventoryBags()
	local bags = {}
	local last = NUM_TOTAL_BAG_FRAMES or 5
	for bag = 0, last do
		table.insert(bags, bag)
	end
	if KEYRING_CONTAINER and ContainerSize(KEYRING_CONTAINER) > 0 then
		table.insert(bags, KEYRING_CONTAINER)
	end
	return bags
end

function ns.BankBags(bankType)
	if not (C_Bank and C_Bank.FetchPurchasedBankTabIDs) then return {} end
	local ok, ids = pcall(C_Bank.FetchPurchasedBankTabIDs, bankType)
	if not ok or type(ids) ~= "table" then return {} end
	local bags = {}
	for _, id in ipairs(ids) do table.insert(bags, id) end
	table.sort(bags)
	return bags
end

function ns.CanViewBankType(bankType)
	if not (C_Bank and C_Bank.CanViewBank) then return bankType == ns.BANK_CHARACTER end
	local ok, can = pcall(C_Bank.CanViewBank, bankType)
	return ok and ns.Safe(can) and true or false
end

-- Empty slots are grouped by what can go in them (normal bags, reagent bag, keyring...).
local function FamilyKey(bag, family)
	if bag == REAGENT_BAG then return "reagent" end
	if KEYRING_CONTAINER and bag == KEYRING_CONTAINER then return "keyring" end
	if family and family ~= 0 then return "family" .. family end
	return "general"
end

-- The keyring and reagent bag only hold special items, so (like Blizzard's
-- free-slot count) they are left out of the "x/y free" numbers. Free keyring
-- slots are not shown at all, since keys go there automatically.
local function CountsAsBagSpace(famKey)
	return famKey ~= "keyring" and famKey ~= "reagent"
end

local function AddEmpty(empties, bag, slot, famKey, live)
	if famKey ~= "keyring" then
		empties[#empties + 1] = { bag = bag, slot = slot, family = famKey, live = live }
	end
end

-------------------------------------------------------------------------------
-- Reading containers
-------------------------------------------------------------------------------

-- Reads the given live containers. If `store` is given it is refilled with a
-- compact copy for the cache. Returns entries, empties, totalSlots, freeSlots.
function ns.ReadLive(bags, store)
	local entries, empties = {}, {}
	local total, free = 0, 0
	if store then wipe(store) end

	for _, bag in ipairs(bags) do
		local size = ContainerSize(bag)
		local _, family = C_Container.GetContainerNumFreeSlots(bag)
		local famKey = FamilyKey(bag, family)
		local counts = CountsAsBagSpace(famKey)
		local bagStore
		if store then
			bagStore = { size = size, fam = famKey }
			store[bag] = bagStore
		end

		for slot = 1, size do
			if counts then total = total + 1 end
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
				local e = {
					bag = bag, slot = slot, live = true,
					link = info.hyperlink, itemID = info.itemID, name = info.itemName,
					count = info.stackCount or 1, quality = info.quality, icon = info.iconFileID,
					isQuest = quest and (quest.isQuestItem or quest.questID) and true or false,
					isNew = C_NewItems and C_NewItems.IsNewItem(bag, slot) or false,
					locked = info.isLocked, noValue = info.hasNoValue, readable = info.isReadable,
					isQuestItem = quest and quest.isQuestItem, questID = quest and quest.questID,
					questActive = quest and quest.isActive,
				}
				if ns.settings.showUpgrades and ns.GetUpgradeInfo then
					e.isUpgrade = ns.GetUpgradeInfo(e.link, e.itemID)
				end
				entries[#entries + 1] = e
				if bagStore then
					bagStore[slot] = { l = e.link, id = e.itemID, n = e.name, c = e.count, q = e.quality, i = e.icon, qi = e.isQuest or nil }
				end
			else
				if counts then free = free + 1 end
				AddEmpty(empties, bag, slot, famKey, true)
			end
		end
	end
	return entries, empties, total, free
end

-- Same output as ReadLive, but from a cached store (read-only view).
function ns.ReadCached(store)
	local entries, empties = {}, {}
	local total, free = 0, 0
	if not store then return entries, empties, 0, 0 end

	local bags = {}
	for bag in pairs(store) do table.insert(bags, bag) end
	table.sort(bags)

	for _, bag in ipairs(bags) do
		local b = store[bag]
		local famKey = b.fam or "general"
		local counts = CountsAsBagSpace(famKey)
		for slot = 1, (b.size or 0) do
			if counts then total = total + 1 end
			local s = b[slot]
			if s then
				entries[#entries + 1] = {
					bag = bag, slot = slot, live = false,
					link = s.l, itemID = s.id, name = s.n, count = s.c or 1, quality = s.q,
					icon = s.i or (s.id and C_Item.GetItemIconByID(s.id)), isQuest = s.qi,
				}
			else
				if counts then free = free + 1 end
				AddEmpty(empties, bag, slot, famKey, false)
			end
		end
	end
	return entries, empties, total, free
end

-------------------------------------------------------------------------------
-- Scanning into the cache
-------------------------------------------------------------------------------

local function Me()
	return ns.db.chars[ns.me]
end

function ns.ScanInventory()
	if not ns.me then return end
	local c = Me()
	c.bags = c.bags or {}
	ns.ReadLive(ns.InventoryBags(), c.bags)
	c.money = GetMoney()
	ns.InvalidateCounts(ns.me)
end

function ns.ScanBank()
	if not ns.me or not ns.atBank then return end
	local c = Me()
	if ns.CanViewBankType(ns.BANK_CHARACTER) then
		c.bank = c.bank or {}
		ns.ReadLive(ns.BankBags(ns.BANK_CHARACTER), c.bank)
	end
	if ns.CanViewBankType(ns.BANK_ACCOUNT) then
		ns.db.account.bank = ns.db.account.bank or {}
		ns.ReadLive(ns.BankBags(ns.BANK_ACCOUNT), ns.db.account.bank)
	end
	ns.InvalidateCounts(ns.me)
	ns.InvalidateCounts("account")
end

function ns.ScanEquipment()
	if not ns.me then return end
	local c = Me()
	c.equip = {}
	for slot = 1, 19 do
		local link = GetInventoryItemLink("player", slot)
		if link then
			c.equip[slot] = { l = link, id = GetInventoryItemID("player", slot) }
		end
	end
	ns.InvalidateCounts(ns.me)
end

function ns.ScanMail()
	if not ns.me then return end
	local c = Me()
	c.mail = {}
	local maxAttach = ATTACHMENTS_MAX_RECEIVE or 16
	for i = 1, (GetInboxNumItems() or 0) do
		for a = 1, maxAttach do
			local name, itemID, texture, count, quality = GetInboxItem(i, a)
			if itemID then
				table.insert(c.mail, { l = GetInboxItemLink(i, a), id = itemID, n = name, c = count or 1, q = quality, i = texture })
			end
		end
	end
	ns.InvalidateCounts(ns.me)
end

-------------------------------------------------------------------------------
-- Item counts across characters (used by tooltips)
-------------------------------------------------------------------------------

local countIndex = {}

function ns.InvalidateCounts(key)
	countIndex[key] = nil
end

local function AddStore(index, store, field)
	if not store then return end
	for _, b in pairs(store) do
		for slot = 1, (b.size or 0) do
			local s = b[slot]
			if s and s.id then
				local t = index[s.id] or {}
				index[s.id] = t
				t[field] = (t[field] or 0) + (s.c or 1)
			end
		end
	end
end

local function AddList(index, list, field)
	if not list then return end
	for _, s in pairs(list) do
		if s.id then
			local t = index[s.id] or {}
			index[s.id] = t
			t[field] = (t[field] or 0) + (s.c or 1)
		end
	end
end

local function GetIndex(key)
	if countIndex[key] then return countIndex[key] end
	local index = {}
	if key == "account" then
		AddStore(index, ns.db.account.bank, "bank")
	else
		local c = ns.db.chars[key]
		if c then
			AddStore(index, c.bags, "bags")
			AddStore(index, c.bank, "bank")
			AddList(index, c.equip, "equip")
			AddList(index, c.mail, "mail")
		end
	end
	countIndex[key] = index
	return index
end

-- Returns a sorted list of { key, bags, bank, equip, mail, total } for an itemID.
function ns.CountItem(itemID)
	local results = {}
	local keys = { "account" }
	for key in pairs(ns.db.chars) do table.insert(keys, key) end
	for _, key in ipairs(keys) do
		local t = GetIndex(key)[itemID]
		if t then
			local total = (t.bags or 0) + (t.bank or 0) + (t.equip or 0) + (t.mail or 0)
			if total > 0 then
				table.insert(results, { key = key, bags = t.bags, bank = t.bank, equip = t.equip, mail = t.mail, total = total })
			end
		end
	end
	table.sort(results, function(a, b)
		if a.key == ns.me then return true end
		if b.key == ns.me then return false end
		return a.key < b.key
	end)
	return results
end

-------------------------------------------------------------------------------
-- Search every character (/tbag find)
-------------------------------------------------------------------------------

function ns.FindEverywhere(text)
	text = text and strtrim(text):lower() or ""
	if text == "" then
		ns.Print("Usage: /tbag find <item name>")
		return
	end

	local found = {} -- [itemID] = { link, places = { [charKey] = { bags=, bank=, ... } } }
	local function consider(key, field, s)
		local name = (s.n or (s.l and s.l:match("%[(.-)%]")) or ""):lower()
		if s.id and name:find(text, 1, true) then
			local f = found[s.id] or { link = s.l, places = {} }
			found[s.id] = f
			local p = f.places[key] or {}
			f.places[key] = p
			p[field] = (p[field] or 0) + (s.c or 1)
		end
	end
	local function scanStore(key, store, field)
		if not store then return end
		for _, b in pairs(store) do
			for slot = 1, (b.size or 0) do
				if b[slot] then consider(key, field, b[slot]) end
			end
		end
	end

	for key, c in pairs(ns.db.chars) do
		scanStore(key, c.bags, "bags")
		scanStore(key, c.bank, "bank")
		for _, s in pairs(c.equip or {}) do consider(key, "equip", s) end
		for _, s in pairs(c.mail or {}) do consider(key, "mail", s) end
	end
	scanStore("Warband Bank", ns.db.account.bank, "bank")

	local n = 0
	for _, f in pairs(found) do
		n = n + 1
		if n > 40 then
			ns.Print("...more results not shown. Try a longer search.")
			break
		end
		local parts = {}
		for key, p in pairs(f.places) do
			local where = {}
			for _, field in ipairs({ "bags", "bank", "equip", "mail" }) do
				if p[field] then table.insert(where, field .. " " .. p[field]) end
			end
			table.insert(parts, key .. " (" .. table.concat(where, ", ") .. ")")
		end
		print("  " .. (f.link or "?") .. ": " .. table.concat(parts, "; "))
	end
	if n == 0 then
		ns.Print("No items matching \"" .. text .. "\" found on any character.")
	end
end

-------------------------------------------------------------------------------
-- Events that keep the cache fresh
-------------------------------------------------------------------------------

local scanInventory = ns.Debounce(function()
	ns.ScanInventory()
	if ns.atBank then ns.ScanBank() end
	ns.RefreshAll()
end, 0.05)

function ns.OnLogin()
	ns.ScanInventory()
	ns.ScanEquipment()
end

ns.On("BAG_UPDATE_DELAYED", scanInventory)
ns.On("PLAYERBANKSLOTS_CHANGED", scanInventory)
ns.On("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", scanInventory)
ns.On("BANK_TABS_CHANGED", scanInventory)
ns.On("BAG_NEW_ITEMS_UPDATED", scanInventory)
ns.On("QUEST_ACCEPTED", scanInventory)
ns.On("QUEST_REMOVED", scanInventory)
ns.On("PLAYER_EQUIPMENT_CHANGED", function() ns.ScanEquipment() end)
ns.On("MAIL_INBOX_UPDATE", function() ns.ScanMail() end)
ns.On("PLAYER_MONEY", function()
	if ns.me then Me().money = GetMoney() end
	ns.RefreshAll()
end)
ns.On("PLAYER_LOGOUT", function()
	if ns.me then
		Me().money = GetMoney()
		Me().lastSeen = time()
	end
end)
