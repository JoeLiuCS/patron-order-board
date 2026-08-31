local addonName, ns = ...

ns.addonName = addonName

function ns.Print(message)
	print("|cff5fd0ffPatron Order Board|r: " .. message)
end

ns.orderCache = ns.orderCache or {}
ns.liveOrdersProfession = ns.liveOrdersProfession
ns.pendingListProfession = ns.pendingListProfession
ns.activeProfession = ns.activeProfession

local function CurrentProfession()
	local info = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
	return info and info.profession
end

local function CopyOrders(source)
	local copy = {}
	for i, order in ipairs(source or {}) do
		copy[i] = order
	end
	return copy
end

local function CollectLiveOrders()
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
	return orders
end

function ns.GetPatronOrders()
	local profession = CurrentProfession()
	if not profession then
		return {}
	end
	if ns.liveOrdersProfession == profession then
		local live = CollectLiveOrders()
		if #live > 0 then
			return live
		end
		return CopyOrders(ns.orderCache[profession])
	end
	return CopyOrders(ns.orderCache[profession])
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
	local profession = CurrentProfession()
	if not profession then
		ns.Print("Open a profession at your crafting table first.")
		return
	end
	if not C_CraftingOrders or not C_CraftingOrders.RequestCrafterOrders then
		ns.Print("Crafting order API is not available.")
		return
	end
	ns.pendingListProfession = profession
	ns.listRequestId = (ns.listRequestId or 0) + 1
	local requestId = ns.listRequestId
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
			if requestId ~= ns.listRequestId then
				return
			end
			ns.AcceptLiveOrderList()
			ns.RefreshUI()
		end)
	end
	C_CraftingOrders.RequestCrafterOrders(request)
	C_Timer.After(0.5, ns.RefreshUI)
end

function ns.AcceptLiveOrderList()
	local profession = ns.pendingListProfession
	if profession and profession == CurrentProfession() then
		ns.liveOrdersProfession = profession
		ns.orderCache[profession] = CopyOrders(CollectLiveOrders())
	end
end

function ns.SyncProfession()
	local profession = CurrentProfession()
	if profession == ns.activeProfession then
		return false
	end
	ns.activeProfession = profession
	ns.liveOrdersProfession = nil
	return true
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
	local close = ProfessionsFrame.CloseButton
	if close then
		button:SetPoint("RIGHT", close, "LEFT", -140, 0)
	else
		button:SetPoint("TOPRIGHT", ProfessionsFrame, "TOPRIGHT", -175, -4)
	end
	button:SetFrameStrata(parent:GetFrameStrata() or "MEDIUM")
	button:SetFrameLevel((parent:GetFrameLevel() or 1) + 2)
	button:SetScript("OnClick", function()
		ns.ToggleBoard()
	end)
	ns.openButton = button
end

function ns.TryAutoShowBoard()
	if ns.IsNearCraftingTable and ns.IsNearCraftingTable() then
		ns.ShowBoard()
		return
	end
	ns.HideBoard()
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
			if ns.TryAutoShowBoard then
				ns.TryAutoShowBoard()
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
			ns.SyncProfession()
			if ns.TryAutoShowBoard then
				ns.TryAutoShowBoard()
			end
		end)
	elseif event == "TRADE_SKILL_CLOSE" then
		ns.HideBoard()
		ns.activeProfession = nil
		ns.liveOrdersProfession = nil
		ns.pendingListProfession = nil
	elseif event == "TRADE_SKILL_LIST_UPDATE" then
		if ns.SyncProfession() and ns.frame and ns.frame:IsShown() then
			ns.RefreshUI()
			ns.RequestPatronOrders()
		else
			QueueRefresh()
		end
	elseif event == "CRAFTINGORDERS_CRAFTER_ORDER_LIST_UPDATED" then
		QueueRefresh()
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
	elseif event == "CRAFTINGORDERS_CLAIMED_ORDER_ADDED" then
		if ns.OnClaimedOrderAdded then
			ns.OnClaimedOrderAdded()
		elseif ns.RefreshUI then
			ns.RefreshUI()
		end
	elseif event == "CRAFTINGORDERS_CLAIMED_ORDER_UPDATED" then
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
