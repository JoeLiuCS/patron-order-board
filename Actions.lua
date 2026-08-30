local _, ns = ...

ns.pending = nil

local TIMEOUT_SECONDS = 20

local function ProfessionID()
	local info = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
	return info and info.profession
end

local function ResultOK(result)
	if result == nil then
		return true
	end
	if Enum.CraftingOrderResult and Enum.CraftingOrderResult.Ok ~= nil then
		return result == Enum.CraftingOrderResult.Ok
	end
	return result == 0
end

function ns.GetClaimedOrder()
	if C_CraftingOrders and C_CraftingOrders.GetClaimedOrder then
		return C_CraftingOrders.GetClaimedOrder()
	end
	return nil
end

function ns.IsClaimedByMe(order)
	if not order then
		return false
	end
	local claimed = ns.GetClaimedOrder()
	return claimed and claimed.orderID == order.orderID
end

function ns.GetLiveOrder(order)
	if not order then
		return nil, false
	end
	local claimed = ns.GetClaimedOrder()
	if claimed and claimed.orderID == order.orderID then
		return claimed, true
	end
	local list = C_CraftingOrders.GetCrafterOrders and C_CraftingOrders.GetCrafterOrders() or {}
	for _, entry in ipairs(list) do
		if entry.orderID == order.orderID then
			return entry, false
		end
	end
	return order, false
end

function ns.IsNearCraftingTable()
	local profession = ProfessionID()
	if not profession then
		return false
	end
	if C_TradeSkillUI.IsNearProfessionSpellFocus then
		return C_TradeSkillUI.IsNearProfessionSpellFocus(profession)
	end
	return true
end

function ns.GetOrderState(order)
	local live, claimed = ns.GetLiveOrder(order)
	live = live or order
	if claimed and live.isFulfillable then
		return "fulfillable"
	end
	if claimed then
		return "claimed"
	end
	return "open"
end

function ns.GetBusyReason(order, analysis, action)
	if ns.pending then
		return "Working on another order..."
	end
	if not ns.IsNearCraftingTable() then
		return "Stand at your crafting table."
	end
	local state = ns.GetOrderState(order)
	local claimed = ns.GetClaimedOrder()
	if claimed and claimed.orderID ~= order.orderID then
		return "Release your current claimed order first."
	end
	if action == "cancel" then
		if state == "open" then
			return "Start the order first."
		end
		return nil
	end
	if not analysis.learned then
		return "You have not learned this recipe."
	end
	if action == "start" then
		if state ~= "open" then
			return "Already started."
		end
		return nil
	end
	if action == "craft" then
		if state == "open" then
			return "Start the order first."
		end
		if state == "fulfillable" then
			return "Already crafted. Click Complete."
		end
		if analysis.missingCount > 0 then
			return "You are missing reagents you must provide."
		end
		if order.isRecraft and not order.outputItemGUID then
			return "Recraft orders must still be opened once to bind the item."
		end
		return nil
	end
	if action == "complete" then
		if state ~= "fulfillable" then
			return "Craft the order first."
		end
		return nil
	end
	return nil
end

local function ClearPending(message)
	if ns.pending and ns.pending.timeout then
		ns.pending.timeout:Cancel()
	end
	ns.pending = nil
	if message then
		ns.Print(message)
	end
	ns.RefreshUI()
end

local function ArmTimeout(orderID)
	if ns.pending and ns.pending.timeout then
		ns.pending.timeout:Cancel()
	end
	if not ns.pending then
		return
	end
	ns.pending.timeout = C_Timer.NewTimer(TIMEOUT_SECONDS, function()
		if ns.pending and ns.pending.orderID == orderID then
			ClearPending("Timed out. Try the button again.")
		end
	end)
end

local function GetOrderView()
	return ProfessionsFrame and ProfessionsFrame.OrdersPage and ProfessionsFrame.OrdersPage.OrderView
end

local function ReturnToPatronList()
	local page = ProfessionsFrame and ProfessionsFrame.OrdersPage
	if page then
		if page.BrowseFrame then
			page.BrowseFrame:Show()
		end
		if page.OrderView then
			page.OrderView:Hide()
		end
	end
	if ns.ShowBoard then
		ns.ShowBoard()
	end
	ns.RefreshUI()
end

local function OpenBlizzardOrder(order)
	local page = ProfessionsFrame and ProfessionsFrame.OrdersPage
	if page and page.ViewOrder then
		page:ViewOrder(order)
		return true
	end
	local view = GetOrderView()
	if view and view.SetOrder then
		view:SetOrder(order)
		return true
	end
	return false
end

function ns.StartOrder(order, analysis)
	local reason = ns.GetBusyReason(order, analysis, "start")
	if reason then
		ns.Print(reason)
		return
	end
	local profession = ProfessionID()
	if not profession then
		ns.Print("Could not detect your profession.")
		return
	end
	ns.pending = {
		orderID = order.orderID,
		order = order,
		analysis = analysis,
		phase = "claim",
	}
	ns.RefreshUI()
	ArmTimeout(order.orderID)
	C_CraftingOrders.ClaimOrder(order.orderID, profession)
end

function ns.CancelOrder(order, analysis)
	local reason = ns.GetBusyReason(order, analysis, "cancel")
	if reason then
		ns.Print(reason)
		return
	end
	local profession = ProfessionID()
	if not profession then
		ns.Print("Could not detect your profession.")
		return
	end
	ns.pending = {
		orderID = order.orderID,
		order = order,
		analysis = analysis,
		phase = "release",
	}
	ns.RefreshUI()
	ArmTimeout(order.orderID)
	C_CraftingOrders.ReleaseOrder(order.orderID, profession)
end

function ns.CraftOrder(order, analysis)
	local reason = ns.GetBusyReason(order, analysis, "craft")
	if reason then
		ns.Print(reason)
		return
	end
	local live = ns.GetLiveOrder(order) or order
	ns.pending = {
		orderID = live.orderID,
		order = live,
		analysis = analysis,
		phase = "craft",
		spellID = live.spellID,
		craftStarted = false,
	}
	ns.RefreshUI()
	ArmTimeout(live.orderID)

	OpenBlizzardOrder(live)
	local view = GetOrderView()
	local applyConcentration = analysis and analysis.needsConcentration or false
	if applyConcentration then
		ns.Print("This order needs Concentration to hit the required quality.")
		local form = view and view.OrderDetails and view.OrderDetails.SchematicForm
		local tx = form and form.transaction
		if tx and tx.SetApplyConcentration then
			pcall(function()
				tx:SetApplyConcentration(true)
			end)
		end
	end
	ns.pending.craftStarted = true
	local crafted = false
	if view then
		if live.isRecraft and view.RecraftOrder then
			view:RecraftOrder()
			crafted = true
		elseif view.CraftOrder then
			view:CraftOrder()
			crafted = true
		elseif view.CreateButton then
			view.CreateButton:Click()
			crafted = true
		end
	end

	if not crafted then
		if C_TradeSkillUI.OpenRecipe then
			C_TradeSkillUI.OpenRecipe(live.spellID)
		end
		local reagents = analysis.craftingReagents
		if reagents and #reagents == 0 then
			reagents = nil
		end
		if live.isRecraft then
			C_TradeSkillUI.RecraftRecipeForOrder(live.orderID, live.outputItemGUID, reagents, nil, applyConcentration)
		else
			C_TradeSkillUI.CraftRecipe(live.spellID, 1, reagents, nil, live.orderID, applyConcentration)
		end
	end
	C_Timer.After(0.15, ReturnToPatronList)
end

function ns.CompleteOrder(order, analysis)
	local reason = ns.GetBusyReason(order, analysis, "complete")
	if reason then
		ns.Print(reason)
		return
	end
	local live = ns.GetLiveOrder(order) or order
	local profession = ProfessionID()
	if not profession then
		ns.Print("Could not detect your profession.")
		return
	end
	ns.pending = {
		orderID = live.orderID,
		order = live,
		analysis = analysis,
		phase = "fulfill",
	}
	ns.RefreshUI()
	ArmTimeout(live.orderID)
	C_CraftingOrders.FulfillOrder(live.orderID, "", profession)
end

function ns.OnClaimResponse(result, orderID)
	if not ns.pending or ns.pending.orderID ~= orderID then
		ns.RefreshUI()
		return
	end
	if not ResultOK(result) then
		ClearPending("Could not start the order.")
		return
	end
	ClearPending("Order started.")
end

function ns.OnReleaseResponse(result, orderID)
	if ns.pending and orderID and ns.pending.orderID ~= orderID then
		ns.RefreshUI()
		return
	end
	if result ~= nil and not ResultOK(result) then
		ClearPending("Could not cancel the order.")
		return
	end
	ClearPending("Order cancelled.")
end

function ns.OnClaimedOrderRemoved()
	if ns.pending and ns.pending.phase ~= "fulfill" then
		ns.pending = nil
	end
	ns.RefreshUI()
end

function ns.OnCrafted(payload)
	if not ns.pending or ns.pending.phase ~= "craft" then
		ns.RefreshUI()
		return
	end
	local orderID = payload and payload.orderID
	local recipeID = payload and (payload.recipeID or payload.spellID)
	local matchesOrder = orderID and orderID == ns.pending.orderID
	local matchesSpell = recipeID and recipeID == ns.pending.spellID
	if not matchesOrder and not matchesSpell then
		return
	end
	ClearPending("Craft finished. Click Complete.")
end

function ns.OnSpellCastSucceeded(unit, _, spellID)
	if unit ~= "player" or not ns.pending then
		return
	end
	if ns.pending.phase ~= "craft" or spellID ~= ns.pending.spellID then
		return
	end
	C_Timer.After(0.8, function()
		if ns.pending and ns.pending.phase == "craft" then
			ClearPending("Craft finished. Click Complete.")
		end
	end)
end

function ns.OnSpellCastFailed(unit, _, spellID)
	if unit ~= "player" or not ns.pending then
		return
	end
	if ns.pending.phase ~= "craft" or not ns.pending.craftStarted then
		return
	end
	if spellID and ns.pending.spellID and spellID ~= ns.pending.spellID then
		return
	end
	ClearPending("Craft was interrupted. Click Craft again.")
end

function ns.OnFulfillResponse(result, orderID)
	if not ns.pending or ns.pending.orderID ~= orderID then
		ns.RefreshUI()
		return
	end
	if not ResultOK(result) then
		ClearPending("Could not complete the order.")
		return
	end
	ClearPending("Order completed.")
end
