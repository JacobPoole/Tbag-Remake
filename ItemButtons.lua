-- TBag Remake: item buttons.
-- Live buttons use Blizzard's ContainerFrameItemButtonTemplate so clicking,
-- dragging, using, selling, banking and tooltips all behave exactly like the
-- default bags. Cached buttons are lightweight, read-only buttons used when
-- viewing another character or a bank you are not standing at.
local _, ns = ...

local EMPTY_SLOT_TEXTURE = [[Interface\PaperDoll\UI-Backpack-EmptySlot]]

-------------------------------------------------------------------------------
-- Category assignment menu (Alt+Right-click an item)
-------------------------------------------------------------------------------

StaticPopupDialogs["TBAGREMAKE_NEWCAT"] = {
	text = "Name for the new category:",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = 32,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function(dialog, data)
		local editBox = (dialog.GetEditBox and dialog:GetEditBox()) or dialog.editBox or dialog.EditBox
		local key = ns.CreateCustomCategory(editBox and editBox:GetText())
		if key and data and data.itemID then
			ns.AssignItem(data.itemID, key)
		end
	end,
	EditBoxOnEnterPressed = function(editBox)
		local dialog = editBox:GetParent()
		StaticPopupDialogs["TBAGREMAKE_NEWCAT"].OnAccept(dialog, dialog.data)
		dialog:Hide()
	end,
	EditBoxOnEscapePressed = function(editBox)
		editBox:GetParent():Hide()
	end,
}

function ns.ShowAssignMenu(owner, itemID, link)
	if not itemID or not MenuUtil then return end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(link or ("Item " .. itemID))
		root:CreateCheckbox("Pin to top", function() return ns.IsPinned(itemID) end,
			function() ns.TogglePin(itemID) end)
		root:CreateDivider()
		root:CreateRadio("Automatic", function() return ns.db.assign[itemID] == nil end,
			function() ns.AssignItem(itemID, nil) end)
		for _, key in ipairs(ns.GetCategoryOrder()) do
			if key ~= "empty" and key ~= "new" and key ~= "pinned" and key ~= "upgrades" then
				root:CreateRadio(ns.CategoryName(key),
					function() return ns.db.assign[itemID] == key end,
					function() ns.AssignItem(itemID, key) end)
			end
		end
		root:CreateDivider()
		root:CreateButton("New category...", function()
			StaticPopup_Show("TBAGREMAKE_NEWCAT", nil, nil, { itemID = itemID })
		end)
	end)
end

local function AddDecorations(b)
	if b.tbagBG then return end
	b.tbagBG = b:CreateTexture(nil, "BACKGROUND", nil, -8)
	b.tbagBG:SetTexture(EMPTY_SLOT_TEXTURE)
	b.tbagBG:SetAllPoints()

	-- Number of free slots, shown on the compact "Free Slots" button.
	b.tbagFree = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
	b.tbagFree:SetPoint("CENTER")
	b.tbagFree:SetTextColor(0.8, 0.8, 0.8)

	-- Star in the top-right corner of pinned items.
	b.tbagPin = b:CreateTexture(nil, "OVERLAY", nil, 5)
	b.tbagPin:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcon_1]])
	b.tbagPin:SetSize(13, 13)
	b.tbagPin:SetPoint("TOPRIGHT", -1, -1)
	b.tbagPin:Hide()

	-- Green arrow in the top-left corner of gear upgrades.
	b.tbagUp = b:CreateTexture(nil, "OVERLAY", nil, 5)
	b.tbagUp:SetAtlas("bags-greenarrow", true)
	b.tbagUp:SetPoint("TOPLEFT", 1, -1)
	b.tbagUp:Hide()
end

local function UpdateMarkers(b, e)
	b.tbagPin:SetShown(e.link and ns.IsPinned(e.itemID) and true or false)
	b.tbagUp:SetShown(e.link and e.isUpgrade and ns.settings.showUpgrades and true or false)
end

-------------------------------------------------------------------------------
-- Live buttons (one per bag/slot, reused for the whole session)
-------------------------------------------------------------------------------

local liveButtons = {}
local liveCount = 0

local function LiveOnClick(self, button)
	if not IsAltKeyDown() or CursorHasItem() then return end
	local info = C_Container.GetContainerItemInfo(self:GetBagID(), self:GetID())
	if not info then return end
	if button == "RightButton" then
		ns.ShowAssignMenu(self, info.itemID, info.hyperlink)
	elseif button == "LeftButton" then
		ns.TogglePin(info.itemID)
	end
end

-- One invisible holder frame per bag, whose frame ID is the bag ID.
-- IMPORTANT: never call button:SetBagID(). That stores bagID in a Lua field
-- written by addon code, which taints it, and Blizzard's click handler reads
-- it right before the protected C_Container.UseContainerItem call, so using
-- items gets blocked. With no bagID field, GetBagID() falls back to
-- self:GetParent():GetID(), which the game stores itself and stays untainted.
local holders = {}

local function GetHolder(parent, bag)
	local h = holders[bag]
	if not h then
		h = CreateFrame("Frame", nil, parent)
		h:SetID(bag)
		h:SetAllPoints(parent)
		holders[bag] = h
	elseif h:GetParent() ~= parent then
		h:SetParent(parent)
		h:ClearAllPoints()
		h:SetAllPoints(parent)
	end
	return h
end

function ns.GetLiveButton(parent, bag, slot)
	local holder = GetHolder(parent, bag)
	local key = bag .. ":" .. slot
	local b = liveButtons[key]
	if not b then
		liveCount = liveCount + 1
		b = CreateFrame("ItemButton", "TBagRemakeItem" .. liveCount, holder, "ContainerFrameItemButtonTemplate")
		b:SetID(slot)
		b:HookScript("OnClick", LiveOnClick)
		AddDecorations(b)
		liveButtons[key] = b
	end
	return b
end

function ns.FindLiveButton(bag, slot)
	return liveButtons[bag .. ":" .. slot]
end

function ns.UpdateLiveButton(b, e, freeCount)
	local hasItem = e.link ~= nil
	SetItemButtonTexture(b, hasItem and e.icon or nil)
	SetItemButtonCount(b, hasItem and e.count or 0)
	SetItemButtonDesaturated(b, e.locked)
	SetItemButtonQuality(b, e.quality, e.link)
	b:UpdateCooldown(hasItem)
	b:UpdateQuestItem(e.isQuestItem, e.questID, e.questActive)
	b:UpdateNewItem(e.quality)
	b:UpdateJunkItem(e.quality, e.noValue)
	b.readable = e.readable
	b.tbagFree:SetText(freeCount and freeCount > 1 and freeCount or "")
	UpdateMarkers(b, e)
end

function ns.ForEachLiveButton(fn)
	for _, b in pairs(liveButtons) do fn(b) end
end

ns.On("ITEM_LOCK_CHANGED", function(_, bag, slot)
	if not bag or not slot then return end
	local b = liveButtons[bag .. ":" .. slot]
	if b and b:IsShown() then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		SetItemButtonDesaturated(b, info and info.isLocked)
	end
end)

ns.On("BAG_UPDATE_COOLDOWN", function()
	for _, b in pairs(liveButtons) do
		if b:IsVisible() then
			b:UpdateCooldown(C_Container.HasContainerItem(b:GetBagID(), b:GetID()))
		end
	end
end)

local function RefreshJunk()
	for _, b in pairs(liveButtons) do
		if b:IsVisible() then
			local info = C_Container.GetContainerItemInfo(b:GetBagID(), b:GetID())
			b:UpdateJunkItem(info and info.quality, info and info.hasNoValue)
		end
	end
end
ns.On("MERCHANT_SHOW", RefreshJunk)
ns.On("MERCHANT_CLOSED", RefreshJunk)

-------------------------------------------------------------------------------
-- Cached (read-only) buttons
-------------------------------------------------------------------------------

local function CachedOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self.link then
		GameTooltip:SetHyperlink(self.link)
		if self.count and self.count > 1 then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Stack: " .. self.count, 1, 1, 1)
		end
	else
		GameTooltip:SetText(EMPTY or "Empty")
		if self.freeCount and self.freeCount > 0 then
			GameTooltip:AddLine(self.freeCount .. " free slots", 1, 1, 1)
		end
	end
	GameTooltip:AddLine("Cached view (read-only)", 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

local function CachedOnClick(self, button)
	if not self.link then return end
	if button == "RightButton" and IsAltKeyDown() then
		ns.ShowAssignMenu(self, self.itemID, self.link)
	elseif button == "LeftButton" and IsAltKeyDown() then
		ns.TogglePin(self.itemID)
	elseif IsModifiedClick() then
		HandleModifiedItemClick(self.link)
	end
end

function ns.CreateCachedButton(parent)
	local b = CreateFrame("ItemButton", nil, parent)
	b:SetSize(37, 37)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnEnter", CachedOnEnter)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetScript("OnClick", CachedOnClick)
	AddDecorations(b)
	return b
end

function ns.UpdateCachedButton(b, e, freeCount)
	b.link = e.link
	b.itemID = e.itemID
	b.count = e.count
	b.freeCount = freeCount
	SetItemButtonTexture(b, e.link and e.icon or nil)
	SetItemButtonCount(b, e.link and e.count or 0)
	SetItemButtonQuality(b, e.quality, e.link)
	b.tbagFree:SetText(freeCount and freeCount > 1 and freeCount or "")
	UpdateMarkers(b, e)
end
