-- TBag Remake: the inventory and bank windows.
-- Items are auto-sorted into category blocks. Small categories share a row;
-- larger ones wrap across the full width.
local _, ns = ...

local CELL = 37        -- item button size
local GAP = 4          -- space between buttons
local PAD = 10         -- window padding
local HEADER_H = 16    -- category header height
local BLOCK_GAP_X = 10 -- space between categories sharing a row
local BLOCK_GAP_Y = 6  -- space between rows of categories
local TOP_H = 62       -- title row + search row
local BOTTOM_H = 30    -- footer
local MIN_W = 330

local Window = {}
Window.__index = Window

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function ShortName(key)
	return key and key:match("^(.-) %- ") or key
end

local function ClassColored(key)
	local c = ns.db.chars[key]
	local name = ShortName(key)
	local color = c and c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
	return color and color:WrapTextInColorCode(name) or name
end

local function MoneyString(copper)
	copper = copper or 0
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
		return C_CurrencyInfo.GetCoinTextureString(copper)
	end
	return GetMoneyString(copper, true)
end

local function SmallButton(parent, text, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 60, 20)
	b:SetText(text)
	b:GetFontString():SetFontObject("GameFontNormalSmall")
	return b
end

local function AddTooltip(frame, title, line)
	frame:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(title)
		if line then GameTooltip:AddLine(line, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", GameTooltip_Hide)
end

-------------------------------------------------------------------------------
-- Construction
-------------------------------------------------------------------------------

function ns.CreateWindow(kind)
	local self = setmetatable({ kind = kind, cachedPool = {}, headerPool = {}, shown = {} }, Window)
	if kind == "bank" then self.bankType = ns.BANK_CHARACTER end

	local name = (kind == "bank") and "TBagRemakeBankFrame" or "TBagRemakeInventoryFrame"
	local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	self.frame = f
	f:Hide()
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetBackdrop({
		bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
		edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	table.insert(UISpecialFrames, name) -- close with Escape

	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function()
		if not ns.settings.locked then f:StartMoving() end
	end)
	f:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		self:SavePosition()
	end)
	f:SetScript("OnShow", function()
		self:Refresh()
		PlaySound(SOUNDKIT.IG_BACKPACK_OPEN)
	end)
	f:SetScript("OnHide", function()
		PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE)
		self.viewChar = nil
		if self.OnClosed then self:OnClosed() end
	end)

	-- Title row -------------------------------------------------------------
	f.Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.Title:SetPoint("TOPLEFT", PAD + 2, -PAD - 2)
	f.Title:SetJustifyH("LEFT")

	f.Close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.Close:SetPoint("TOPRIGHT", -2, -2)

	f.CharButton = SmallButton(f, "", 120)
	f.CharButton:SetPoint("RIGHT", f.Close, "LEFT", -2, 0)
	f.CharButton:SetScript("OnClick", function(b) self:ShowCharacterMenu(b) end)
	AddTooltip(f.CharButton, "Character", "View the cached bags and bank of your other characters.")
	f.Title:SetPoint("RIGHT", f.CharButton, "LEFT", -6, 0)

	-- Search row ------------------------------------------------------------
	f.Search = CreateFrame("EditBox", name .. "Search", f, "SearchBoxTemplate")
	f.Search:SetHeight(20)
	f.Search:SetPoint("TOPLEFT", PAD + 6, -34)
	f.Search:SetAutoFocus(false)
	f.Search:HookScript("OnTextChanged", function(eb)
		local text = strtrim(eb:GetText() or ""):lower()
		if text ~= (self.searchText or "") then
			self.searchText = text
			self:Refresh()
		end
	end)

	local rightmost
	local function AddRowButton(b)
		if rightmost then
			b:SetPoint("RIGHT", rightmost, "LEFT", -2, 0)
		else
			b:SetPoint("TOPRIGHT", -PAD, -34)
		end
		rightmost = b
	end

	f.Options = CreateFrame("Button", nil, f)
	f.Options:SetSize(20, 20)
	f.Options:SetNormalTexture([[Interface\Buttons\UI-OptionsButton]])
	f.Options:SetHighlightTexture([[Interface\Buttons\UI-Common-MouseHilight]], "ADD")
	f.Options:SetScript("OnClick", function() ns.OpenOptions() end)
	AddTooltip(f.Options, "TBag Settings")
	AddRowButton(f.Options)

	f.Restack = SmallButton(f, "Restack", 58)
	f.Restack:SetScript("OnClick", function() self:Restack() end)
	AddTooltip(f.Restack, "Restack", "Merge partial stacks and let the game physically re-sort these bags. The display is always sorted either way.")
	AddRowButton(f.Restack)

	if kind == "inventory" then
		f.BankButton = SmallButton(f, "Bank", 46)
		f.BankButton:SetScript("OnClick", function()
			ns.bank.viewChar = self.viewChar
			ns.bank:Toggle()
		end)
		AddTooltip(f.BankButton, "Bank", "View this character's bank from anywhere (cached until you next visit a banker).")
		AddRowButton(f.BankButton)
	else
		f.Deposit = SmallButton(f, "Deposit", 56)
		f.Deposit:SetScript("OnClick", function()
			if ns.atBank and C_Bank.AutoDepositItemsIntoBank then
				C_Bank.AutoDepositItemsIntoBank(self.bankType)
			end
		end)
		AddTooltip(f.Deposit, "Deposit Reagents", "Deposit all reagents from your bags into this bank.")
		AddRowButton(f.Deposit)

		f.WarbandTab = SmallButton(f, "Warband", 60)
		f.WarbandTab:SetScript("OnClick", function() self.bankType = ns.BANK_ACCOUNT; self:Refresh() end)
		AddRowButton(f.WarbandTab)

		f.CharTab = SmallButton(f, "Bank", 44)
		f.CharTab:SetScript("OnClick", function() self.bankType = ns.BANK_CHARACTER; self:Refresh() end)
		AddRowButton(f.CharTab)
	end
	f.Search:SetPoint("RIGHT", rightmost, "LEFT", -6, 0)

	-- Content ---------------------------------------------------------------
	self.content = CreateFrame("Frame", nil, f)
	self.content:SetPoint("TOPLEFT", PAD, -TOP_H)
	self.content:SetSize(1, 1)

	-- Footer ----------------------------------------------------------------
	f.Slots = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.Slots:SetPoint("BOTTOMLEFT", PAD + 2, PAD + 2)

	f.MoneyHolder = CreateFrame("Frame", nil, f)
	f.MoneyHolder:SetSize(160, 16)
	f.MoneyHolder:SetPoint("BOTTOMRIGHT", -PAD - 2, PAD)
	f.MoneyHolder:EnableMouse(true)
	f.Money = f.MoneyHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.Money:SetPoint("RIGHT")
	f.Money:SetJustifyH("RIGHT")
	f.MoneyHolder:SetScript("OnEnter", function(h) ns.ShowMoneyTooltip(h) end)
	f.MoneyHolder:SetScript("OnLeave", GameTooltip_Hide)

	self:RestorePosition()
	return self
end

-------------------------------------------------------------------------------
-- Show / hide / position
-------------------------------------------------------------------------------

function Window:Toggle()
	if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end

function Window:SavePosition()
	local point, _, relPoint, x, y = self.frame:GetPoint(1)
	ns.db.pos[self.kind] = { point, relPoint, x, y }
end

function Window:RestorePosition()
	local f = self.frame
	f:ClearAllPoints()
	local p = ns.db and ns.db.pos[self.kind]
	if p then
		f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	elseif self.kind == "bank" then
		f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -110)
	else
		f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -90, 110)
	end
end

-------------------------------------------------------------------------------
-- Data for the current view
-------------------------------------------------------------------------------

function Window:ViewKey()
	return self.viewChar or ns.me
end

function Window:IsLive()
	if self:ViewKey() ~= ns.me then
		return self.kind == "bank" and self.bankType == ns.BANK_ACCOUNT and ns.atBank
			and ns.CanViewBankType(ns.BANK_ACCOUNT)
	end
	if self.kind == "inventory" then return true end
	return ns.atBank and ns.CanViewBankType(self.bankType)
end

function Window:Collect()
	local c = ns.db.chars[self:ViewKey()]
	local live = self:IsLive()
	if self.kind == "inventory" then
		if live then return ns.ReadLive(ns.InventoryBags()) end
		return ns.ReadCached(c and c.bags)
	end
	if live then return ns.ReadLive(ns.BankBags(self.bankType)) end
	if self.bankType == ns.BANK_ACCOUNT then
		return ns.ReadCached(ns.db.account.bank)
	end
	return ns.ReadCached(c and c.bank)
end

-------------------------------------------------------------------------------
-- Pools
-------------------------------------------------------------------------------

function Window:ReleaseAll()
	for _, b in ipairs(self.shown) do
		b:Hide()
		b:SetAlpha(1)
	end
	wipe(self.shown)
	for _, h in ipairs(self.headerPool) do h:Hide() end
	self.headersUsed = 0
	self.cachedUsed = 0
end

function Window:AcquireCached()
	self.cachedUsed = self.cachedUsed + 1
	local b = self.cachedPool[self.cachedUsed]
	if not b then
		b = ns.CreateCachedButton(self.content)
		self.cachedPool[self.cachedUsed] = b
	end
	return b
end

function Window:AcquireHeader()
	self.headersUsed = self.headersUsed + 1
	local h = self.headerPool[self.headersUsed]
	if not h then
		h = CreateFrame("Button", nil, self.content)
		h:SetHeight(HEADER_H)
		h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		h.Text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h.Text:SetPoint("LEFT", 1, 0)
		h.Text:SetPoint("RIGHT")
		h.Text:SetJustifyH("LEFT")
		h.Text:SetWordWrap(false)
		h.Line = h:CreateTexture(nil, "ARTWORK")
		h.Line:SetColorTexture(1, 0.82, 0, 0.25)
		h.Line:SetHeight(1)
		h.Line:SetPoint("BOTTOMLEFT", 0, 1)
		h.Line:SetPoint("BOTTOMRIGHT", 0, 1)
		h:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
		h:SetScript("OnClick", function(btn, mouse)
			if mouse == "RightButton" then
				self:ShowCategoryMenu(btn, btn.catKey)
			else
				ns.db.collapsed[btn.catKey] = not ns.db.collapsed[btn.catKey] or nil
				ns.RefreshAll()
			end
		end)
		h:SetScript("OnEnter", function(btn)
			GameTooltip:SetOwner(btn, "ANCHOR_TOP")
			GameTooltip:SetText(ns.CategoryName(btn.catKey))
			GameTooltip:AddLine("Click to collapse/expand. Right-click to move or hide.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		h:SetScript("OnLeave", GameTooltip_Hide)
		self.headerPool[self.headersUsed] = h
	end
	return h
end

-------------------------------------------------------------------------------
-- Layout
-------------------------------------------------------------------------------

local function Matches(e, search, catName)
	if not search or search == "" then return true end
	if not e.link then return false end
	if ns.EntryName(e):lower():find(search, 1, true) then return true end
	return catName:lower():find(search, 1, true) ~= nil
end

function Window:Refresh()
	local f = self.frame
	if not f:IsShown() or not ns.db then return end
	f:SetScale(ns.settings.scale or 1)
	local alpha = ns.settings.bgAlpha or 0.55
	f:SetBackdropColor(0.04, 0.04, 0.06, alpha)
	f:SetBackdropBorderColor(0.55, 0.55, 0.6, math.min(1, alpha + 0.3))

	local live = self:IsLive()
	local entries, empties, total, free = self:Collect()

	-- Group into categories.
	local groups = {}
	for _, e in ipairs(entries) do
		local key = ns.Classify(e)
		local g = groups[key]
		if not g then g = {}; groups[key] = g end
		g[#g + 1] = e
	end
	for _, g in pairs(groups) do ns.SortEntries(g) end

	if #empties > 0 then
		if ns.settings.compactEmpty then
			local byFamily, order = {}, {}
			for _, e in ipairs(empties) do
				local x = byFamily[e.family]
				if not x then
					x = { e = e, n = 0 }
					byFamily[e.family] = x
					table.insert(order, e.family)
				end
				x.n = x.n + 1
			end
			groups.empty = {}
			for _, fam in ipairs(order) do
				local x = byFamily[fam]
				x.e.freeCount = x.n
				table.insert(groups.empty, x.e)
			end
		else
			groups.empty = empties
		end
	end

	self:ReleaseAll()

	local columns = ns.settings.columns or 10
	local step = CELL + GAP
	local maxW = columns * step - GAP
	local search = self.searchText
	local hideNonMatches = search and search ~= "" and not ns.settings.dimSearch

	local x, lineTop, lineH = 0, 0, 0
	for _, key in ipairs(ns.GetCategoryOrder()) do
		local items = groups[key]
		if items and #items > 0 and not ns.db.hiddenCats[key] then
			local catName = ns.CategoryName(key)

			-- When hiding search misses, drop them before measuring the block.
			local visible = items
			if hideNonMatches and key ~= "empty" then
				visible = {}
				for _, e in ipairs(items) do
					if Matches(e, search, catName) then visible[#visible + 1] = e end
				end
			end

			if #visible > 0 or not hideNonMatches then
				local collapsed = ns.db.collapsed[key]
				local n = collapsed and 0 or #visible
				local cols = math.max(math.min(n, columns), 3)
				local rows = math.ceil(n / columns)
				local blockW = cols * step - GAP
				local blockH = HEADER_H + rows * step

				-- Start a new line if this block does not fit beside the previous one.
				if x > 0 and (rows > 1 or x + blockW > maxW) then
					lineTop = lineTop + lineH + BLOCK_GAP_Y
					x, lineH = 0, 0
				end

				local h = self:AcquireHeader()
				h.catKey = key
				local count = 0
				if key == "empty" then
					count = free -- same number as the footer (excludes reagent bag)
				else
					count = #items
				end
				h.Text:SetText((collapsed and "+ " or "") .. catName .. " |cff999999(" .. count .. ")|r")
				h:ClearAllPoints()
				h:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -lineTop)
				h:SetWidth(blockW)
				h:Show()

				if not collapsed then
					for i, e in ipairs(visible) do
						local b
						if e.live then
							b = ns.GetLiveButton(self.content, e.bag, e.slot)
							ns.UpdateLiveButton(b, e, e.freeCount)
						else
							b = self:AcquireCached()
							ns.UpdateCachedButton(b, e, e.freeCount)
						end
						-- The Blizzard template pins frameLevel to 10; keep buttons above our backdrop.
						b:SetFrameLevel(self.content:GetFrameLevel() + 2)
						local col = (i - 1) % columns
						local row = math.floor((i - 1) / columns)
						b:ClearAllPoints()
						b:SetPoint("TOPLEFT", self.content, "TOPLEFT", x + col * step, -(lineTop + HEADER_H + row * step))
						if search and search ~= "" and not Matches(e, search, catName) then
							b:SetAlpha(0.2)
						else
							b:SetAlpha(1)
						end
						b:Show()
						self.shown[#self.shown + 1] = b
					end
				end

				lineH = math.max(lineH, blockH)
				if rows > 1 then
					x = maxW -- force the next block onto a new line
				else
					x = x + blockW + BLOCK_GAP_X
				end
			end
		end
	end

	local contentH = lineTop + lineH
	local contentW = math.max(maxW, MIN_W - 2 * PAD)
	self.content:SetSize(contentW, math.max(contentH, 1))
	f:SetSize(contentW + 2 * PAD, TOP_H + contentH + BOTTOM_H)

	-- Title, footer, buttons --------------------------------------------------
	local key = self:ViewKey()
	local c = ns.db.chars[key]
	local who = ClassColored(key or "?")
	local title
	if self.kind == "inventory" then
		title = who .. "'s Bags"
	elseif self.bankType == ns.BANK_ACCOUNT then
		title = "Warband Bank"
	else
		title = who .. "'s Bank"
	end
	if not live then title = title .. " |cff888888(cached)|r" end
	if total == 0 and not live then title = title .. " |cffff6666- not seen yet|r" end
	f.Title:SetText(title)
	f.CharButton:SetText(ClassColored(key or "?"))

	f.Slots:SetText(string.format("%d/%d free", free, total))
	if self.kind == "inventory" then
		f.Money:SetText(MoneyString(key == ns.me and GetMoney() or (c and c.money)))
		f.Restack:SetEnabled(live)
	else
		local deposited = 0
		if self.bankType == ns.BANK_ACCOUNT and ns.atBank and C_Bank.FetchDepositedMoney then
			deposited = C_Bank.FetchDepositedMoney(ns.BANK_ACCOUNT) or 0
			f.Money:SetText(MoneyString(deposited))
		else
			f.Money:SetText("")
		end
		f.Restack:SetEnabled(live)
		f.Deposit:SetEnabled(live)
		f.CharTab:SetEnabled(self.bankType ~= ns.BANK_CHARACTER)
		f.WarbandTab:SetEnabled(self.bankType ~= ns.BANK_ACCOUNT)
	end
end

function Window:Restack()
	if not self:IsLive() then return end
	if self.kind == "inventory" then
		C_Container.SortBags()
	elseif C_Container.SortBank then
		C_Container.SortBank(self.bankType)
	end
end

-------------------------------------------------------------------------------
-- Menus
-------------------------------------------------------------------------------

function Window:ShowCharacterMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("View character")
		local keys = {}
		for key in pairs(ns.db.chars) do table.insert(keys, key) end
		table.sort(keys)
		for _, key in ipairs(keys) do
			root:CreateRadio(ClassColored(key) .. " |cff888888" .. (key:match(" %- (.*)$") or "") .. "|r",
				function() return self:ViewKey() == key end,
				function()
					self.viewChar = (key ~= ns.me) and key or nil
					self:Refresh()
				end)
		end
		root:CreateDivider()
		local forget = root:CreateButton("Forget character")
		for _, key in ipairs(keys) do
			if key ~= ns.me then
				forget:CreateButton(key, function()
					ns.db.chars[key] = nil
					ns.InvalidateCounts(key)
					if self.viewChar == key then self.viewChar = nil end
					ns.Print("Forgot cached data for", key)
					ns.RefreshAll()
				end)
			end
		end
	end)
end

function Window:ShowCategoryMenu(owner, key)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(ns.CategoryName(key))
		root:CreateButton("Move earlier", function() ns.MoveCategory(key, -1) end)
		root:CreateButton("Move later", function() ns.MoveCategory(key, 1) end)
		root:CreateButton(ns.db.collapsed[key] and "Expand" or "Collapse", function()
			ns.db.collapsed[key] = not ns.db.collapsed[key] or nil
			ns.RefreshAll()
		end)
		root:CreateButton("Hide category", function()
			ns.db.hiddenCats[key] = true
			ns.Print("Hid", ns.CategoryName(key) .. ". Right-click any header to show hidden categories again.")
			ns.RefreshAll()
		end)
		if next(ns.db.hiddenCats) then
			root:CreateButton("Show hidden categories", function()
				wipe(ns.db.hiddenCats)
				ns.RefreshAll()
			end)
		end
		if key == "upgrades" then
			root:CreateButton("Turn off gear upgrades", function() ns.SetUpgradesEnabled(false) end)
		end
		root:CreateDivider()
		root:CreateButton("New category...", function() StaticPopup_Show("TBAGREMAKE_NEWCAT") end)
		if ns.db.custom[key] then
			root:CreateButton("|cffff6666Delete this category|r", function() ns.DeleteCustomCategory(key) end)
		end
	end)
end

function ns.ShowMoneyTooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_TOPRIGHT")
	GameTooltip:SetText("Gold on all characters")
	local keys, total = {}, 0
	for key in pairs(ns.db.chars) do table.insert(keys, key) end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local money = (key == ns.me) and GetMoney() or (ns.db.chars[key].money or 0)
		total = total + money
		GameTooltip:AddDoubleLine(ClassColored(key), MoneyString(money), 1, 1, 1, 1, 1, 1)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Total", MoneyString(total), 1, 0.82, 0, 1, 1, 1)
	GameTooltip:Show()
end

-------------------------------------------------------------------------------
-- Instances
-------------------------------------------------------------------------------

function ns.RefreshAll()
	if ns.inventory then ns.inventory:Refresh() end
	if ns.bank then ns.bank:Refresh() end
end

function ns.OnDatabaseReady()
	ns.inventory = ns.CreateWindow("inventory")
	ns.bank = ns.CreateWindow("bank")
	if ns.SetupBlizzardHooks then ns.SetupBlizzardHooks() end
	if ns.SetupOptions then ns.SetupOptions() end
end
