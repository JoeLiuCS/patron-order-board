local addonName, ns = ...

ns.addonName = addonName

function ns.Print(message)
	print("|cff5fd0ffPatron Order Board|r: " .. message)
end

ns.cachedPatronOrders = ns.cachedPatronOrders or {}

local function CopyOrders(source)
	local copy = {}
	for i, order in ipairs(source) do
		copy[i] = order
	end
	return copy
end

function ns.GetPatronOrders()
	local orders = {}
	local npcType = Enum.CraftingOrderType and Enum.CraftingOrderType.Npc
	local crafterOrders = C_CraftingOrders.GetCrafterOrders and C_CraftingOrders.GetCrafterOrders() or {}
	for _, order in ipairs(crafterOrders) do
		if npcType == nil or order.orderType == npcType then
			table.insert(orders, order)
		end
	end
	local claimed = C_CraftingOrders.GetClaimedOrder and C_CraftingOrders.GetClaimedOrder()
	if claimed and (npcType == nil or claimed.orderType == npcType or claimed.orderType == nil) then
		local found = false
		for i, order in ipairs(orders) do
			if order.orderID == claimed.orderID then
				orders[i] = claimed
				found = true
				break
			end
		end
		if not found then
			table.insert(orders, 1, claimed)
		end
	end
	if #orders > 0 then
		ns.cachedPatronOrders = CopyOrders(orders)
		return orders
	end
	orders = CopyOrders(ns.cachedPatronOrders)
	if claimed then
		local found = false
		for i, order in ipairs(orders) do
			if order.orderID == claimed.orderID then
				orders[i] = claimed
				found = true
				break
			end
		end
		if not found and (npcType == nil or claimed.orderType == npcType or claimed.orderType == nil) then
			table.insert(orders, 1, claimed)
		end
	end
	return orders
end

function ns.IsProfessionOpen()
	return ProfessionsFrame and ProfessionsFrame:IsShown()
end

function ns.IsPatronTabOpen()
	if not ns.IsProfessionOpen() then
		return false
	end
	local page = ProfessionsFrame.OrdersPage
	if not page or not page:IsShown() then
		return false
	end
	local npcType = Enum.CraftingOrderType and Enum.CraftingOrderType.Npc
	if npcType and page.orderType ~= nil then
		return page.orderType == npcType
	end
	return true
end

function ns.RequestPatronOrders()
	local professionInfo = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
	local profession = professionInfo and professionInfo.profession
	if not profession then
		ns.Print("Open a profession at your crafting table first.")
		return
	end
	if not C_CraftingOrders or not C_CraftingOrders.RequestCrafterOrders then
		ns.Print("Crafting order API is not available.")
		return
	end
	local request = {
		orderType = Enum.CraftingOrderType.Npc,
		searchFavorites = false,
		initialNonPublicSearch = false,
		primarySort = {
			sortType = Enum.CraftingOrderSortType.TimeRemaining,
			reversed = false,
		},
		secondarySort = {
			sortType = Enum.CraftingOrderSortType.ItemName,
			reversed = false,
		},
		forCrafter = true,
		offset = 0,
		profession = profession,
	}
	if C_FunctionContainers and C_FunctionContainers.CreateCallback then
		request.callback = C_FunctionContainers.CreateCallback(function()
			ns.RefreshUI()
		end)
	end
	C_CraftingOrders.RequestCrafterOrders(request)
	C_Timer.After(0.5, ns.RefreshUI)
end

local refreshQueued = false
local function QueueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	C_Timer.After(0.15, function()
		refreshQueued = false
		if ns.frame and ns.frame:IsShown() then
			ns.RefreshUI()
		end
	end)
end

function ns.InjectProfessionButton()
	if ns.openButton or not ProfessionsFrame then
		return
	end
	local parent = ProfessionsFrame.TitleContainer or ProfessionsFrame
	local button = CreateFrame("Button", "PatronOrderBoardOpenButton", parent, "UIPanelButtonTemplate")
	button:SetSize(130, 24)
	button:SetText("Patron Board")
	button:SetPoint("TOPRIGHT", ProfessionsFrame, "TOPRIGHT", -30, -4)
	button:SetFrameStrata("HIGH")
	button:SetScript("OnClick", function()
		ns.ToggleBoard()
	end)
	ns.openButton = button
end

local function HookProfessionsFrame()
	if ns.hooked or not ProfessionsFrame then
		return
	end
	ns.hooked = true
	ns.InjectProfessionButton()

	ProfessionsFrame:HookScript("OnShow", function()
		ns.InjectProfessionButton()
		if ns.openButton then
			ns.openButton:Show()
		end
		C_Timer.After(0.2, function()
			if ns.ShowBoard then
				ns.ShowBoard()
			end
		end)
	end)
	ProfessionsFrame:HookScript("OnHide", function()
		ns.HideBoard()
	end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name == addonName then
			PatronOrderBoardDB = PatronOrderBoardDB or {}
			if PatronOrderBoardDB.docked == nil then
				PatronOrderBoardDB.docked = true
			end
			if PatronOrderBoardDB.hideConcentration == nil then
				PatronOrderBoardDB.hideConcentration = false
			end
			if PatronOrderBoardDB.hideUnlearned == nil then
				PatronOrderBoardDB.hideUnlearned = false
			end
			PatronOrderBoardDB.readyOnly = nil
		elseif name == "Blizzard_Professions" then
			HookProfessionsFrame()
		end
	elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
		if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Professions") then
			HookProfessionsFrame()
		end
		if event == "PLAYER_LOGIN" then
			ns.Print("Loaded. Type |cffffffff/pob|r, or open your profession and click |cffffffffPatron Board|r.")
		end
	elseif event == "TRADE_SKILL_SHOW" then
		HookProfessionsFrame()
		C_Timer.After(0.25, function()
			if ns.ShowBoard then
				ns.ShowBoard()
			end
		end)
	elseif event == "TRADE_SKILL_CLOSE" then
		ns.HideBoard()
	elseif event == "CRAFTINGORDERS_CLAIM_ORDER_RESPONSE" then
		if ns.OnClaimResponse then
			ns.OnClaimResponse(...)
		end
	elseif event == "CRAFTINGORDERS_FULFILL_ORDER_RESPONSE" then
		if ns.OnFulfillResponse then
			ns.OnFulfillResponse(...)
		end
	elseif event == "CRAFTINGORDERS_RELEASE_ORDER_RESPONSE" then
		if ns.OnReleaseResponse then
			ns.OnReleaseResponse(...)
		end
	elseif event == "CRAFTINGORDERS_CLAIMED_ORDER_REMOVED" then
		if ns.OnClaimedOrderRemoved then
			ns.OnClaimedOrderRemoved()
		end
	elseif event == "CRAFTINGORDERS_CLAIMED_ORDER_UPDATED" or event == "CRAFTINGORDERS_CLAIMED_ORDER_ADDED" then
		if ns.RefreshUI then
			ns.RefreshUI()
		end
	elseif event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
		if ns.OnCrafted then
			ns.OnCrafted(...)
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if ns.OnSpellCastSucceeded then
			ns.OnSpellCastSucceeded(...)
		end
	elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
		if ns.OnSpellCastFailed then
			ns.OnSpellCastFailed(...)
		end
	else
		QueueRefresh()
	end
end)

local events = {
	"ADDON_LOADED",
	"PLAYER_LOGIN",
	"PLAYER_ENTERING_WORLD",
	"TRADE_SKILL_SHOW",
	"TRADE_SKILL_CLOSE",
	"TRADE_SKILL_LIST_UPDATE",
	"BAG_UPDATE_DELAYED",
	"CRAFTINGORDERS_UPDATE_ORDER_COUNT",
	"CRAFTINGORDERS_CRAFTER_ORDER_LIST_UPDATED",
	"CRAFTINGORDERS_CLAIM_ORDER_RESPONSE",
	"CRAFTINGORDERS_FULFILL_ORDER_RESPONSE",
	"CRAFTINGORDERS_RELEASE_ORDER_RESPONSE",
	"CRAFTINGORDERS_CLAIMED_ORDER_UPDATED",
	"CRAFTINGORDERS_CLAIMED_ORDER_ADDED",
	"CRAFTINGORDERS_CLAIMED_ORDER_REMOVED",
	"TRADE_SKILL_ITEM_CRAFTED_RESULT",
	"UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_SUCCEEDED",
}

for _, eventName in ipairs(events) do
	pcall(eventFrame.RegisterEvent, eventFrame, eventName)
end

SLASH_PATRONORDERBOARD1 = "/pob"
SLASH_PATRONORDERBOARD2 = "/patronorders"
SlashCmdList.PATRONORDERBOARD = function(msg)
	msg = string.lower(msg or "")
	if msg == "refresh" then
		ns.RequestPatronOrders()
	elseif msg == "dock" then
		PatronOrderBoardDB.docked = true
		ns.DockToProfessions()
		ns.ShowBoard()
		ns.Print("Docked to the profession window.")
	elseif msg == "undock" then
		PatronOrderBoardDB.docked = false
		ns.Print("Undocked. Drag the window wherever you want.")
	else
		ns.ToggleBoard()
	end
end
