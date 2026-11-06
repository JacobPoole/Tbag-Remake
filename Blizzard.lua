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

local function HideBlizzardBank()
	-- Parenting BankFrame to a hidden frame before it is ever shown means its
	-- OnShow/OnHide never run, so the bank interaction stays open while our
	-- window is the one you see. Closing our bank window ends the interaction.
	if BankFrame then
		BankFrame:SetParent(hiddenParent)
	end
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
		if ns.settings.hideBlizzard then
			-- BankFrame's OnShow normally opens the bags; it never runs while hidden.
			OpenAllBags()
		end
		inv.frame:Show()
	end)

	ns.On("BANKFRAME_CLOSED", function()
		if not ns.atBank then return end
		ns.atBank = false
		ns.closingBank = true
		bank.frame:Hide()
		ns.closingBank = false
		if ns.settings.hideBlizzard then
			CloseAllBags()
		end
		ns.RefreshAll()
	end)
end
