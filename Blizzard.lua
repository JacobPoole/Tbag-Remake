-- TBag Remake: replaces the default bag and bank windows.
--
-- Approach: Blizzard's own bag frames still open and close normally (so every
-- keybind, merchant, mailbox and bank that opens bags keeps working), but they
-- are parented to a hidden frame so they are never visible. After any of the
-- open/close functions run, our inventory window mirrors IsAnyBagOpen().
local _, ns = ...

local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

local syncing = false
local function SyncInventory()
	if syncing or not ns.inventory then return end
	syncing = true
	if IsAnyBagOpen() then
		ns.inventory.frame:Show()
	else
		ns.inventory.frame:Hide()
	end
	syncing = false
end

local function HideBlizzardBags()
	if ContainerFrameCombinedBags then
		ContainerFrameCombinedBags:SetParent(hiddenParent)
	end
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		local frame = _G["ContainerFrame" .. i]
		if frame then frame:SetParent(hiddenParent) end
	end
end

-- The default bank is NOT reparented (unlike the bags). It has to open and run
-- its own setup normally, untainted: that claims the free first bank tab, picks
-- the bank right-click deposits go to, and its purchase button calls the
-- restricted C_Bank.PurchaseBankTab, which addon code is not allowed to call.
-- So it opens as usual and is then shrunk to nothing and made invisible. The
-- "Blizzard Bank" button in our bank window brings it back for buying tabs.
local function ApplyBankVisibility()
	if not BankFrame or not ns.settings.hideBlizzard then return end
	if ns.showBlizzardBank then
		BankFrame:SetScale(1)
		BankFrame:SetAlpha(1)
	else
		BankFrame:SetScale(0.001) -- tiny, so it can't catch mouse clicks
		BankFrame:SetAlpha(0)
	end
end

function ns.ToggleBlizzardBank()
	ns.showBlizzardBank = not ns.showBlizzardBank
	ApplyBankVisibility()
	if ns.bank then ns.bank:Refresh() end
end

local function HideBlizzardBank()
	if not BankFrame then return end
	BankFrame:HookScript("OnShow", function()
		ns.showBlizzardBank = false
		ApplyBankVisibility()
	end)
	BankFrame:HookScript("OnHide", function()
		ns.showBlizzardBank = false
	end)
end

function ns.SetupBlizzardHooks()
	local inv, bank = ns.inventory, ns.bank

	if ns.settings.hideBlizzard then
		HideBlizzardBags()
		HideBlizzardBank()
	end

	for _, fn in ipairs({
		"OpenAllBags", "CloseAllBags", "ToggleAllBags",
		"OpenBackpack", "CloseBackpack", "ToggleBackpack",
		"OpenBag", "CloseBag", "ToggleBag",
	}) do
		if _G[fn] then hooksecurefunc(fn, SyncInventory) end
	end

	-- Closing our window (X button or Escape) closes Blizzard's hidden bags too,
	-- so the next keypress opens them again instead of needing two presses.
	function inv:OnClosed()
		-- Like Blizzard's bags: items stop being "new" once you've seen them.
		if ns.settings.clearNewOnClose and C_NewItems then
			for _, bag in ipairs(ns.InventoryBags()) do
				for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
					if C_NewItems.IsNewItem(bag, slot) then
						C_NewItems.RemoveNewItem(bag, slot)
					end
				end
			end
		end
		if not syncing and IsAnyBagOpen() then
			CloseAllBags()
		end
	end

	-- Closing our bank window while at a banker ends the bank interaction.
	function bank:OnClosed()
		if ns.atBank and not ns.closingBank and C_Bank and C_Bank.CloseBankFrame then
			C_Bank.CloseBankFrame()
		end
	end

	ns.On("BANKFRAME_OPENED", function()
		ns.atBank = true
		ns.ScanBank()
		bank.viewChar = nil
		if not ns.CanViewBankType(bank.bankType) then
			bank.bankType = ns.CanViewBankType(ns.BANK_CHARACTER) and ns.BANK_CHARACTER or ns.BANK_ACCOUNT
		end
		bank.frame:Show()
		bank:Refresh()
		-- Blizzard's BankFrame OnShow opens the bags itself (OpenAllBags), which
		-- our hooks mirror; this just makes sure the inventory is visible.
		inv.frame:Show()
	end)

	ns.On("BANKFRAME_CLOSED", function()
		if not ns.atBank then return end
		ns.atBank = false
		ns.closingBank = true
		bank.frame:Hide()
		ns.closingBank = false
		-- Blizzard's BankFrame OnHide closes the bags it opened (CloseAllBags).
		ns.RefreshAll()
	end)
end
