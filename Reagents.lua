local _, ns = ...

local CustomerSource = (Enum.CraftingOrderReagentSource and Enum.CraftingOrderReagentSource.Customer) or 1
local CrafterSource = (Enum.CraftingOrderReagentSource and Enum.CraftingOrderReagentSource.Crafter) or 2
local NoneSource = Enum.CraftingOrderReagentSource and Enum.CraftingOrderReagentSource.None
local BasicType = (Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 1
local ModifyingType = (Enum.CraftingReagentType and Enum.CraftingReagentType.Modifying) or 0
local FinishingType = (Enum.CraftingReagentType and Enum.CraftingReagentType.Finishing) or 2
local AutomaticType = (Enum.CraftingReagentType and Enum.CraftingReagentType.Automatic) or 3
local ModifiedSlot = (Enum.TradeskillSlotDataType and Enum.TradeskillSlotDataType.ModifiedReagent) or 2
local CurrencySlot = (Enum.TradeskillSlotDataType and Enum.TradeskillSlotDataType.Currency) or 3

local function ReagentItemID(reagent)
	if not reagent then
		return nil
	end
	if reagent.itemID then
		return reagent.itemID
	end
	if reagent.reagent then
		return reagent.reagent.itemID
	end
	if reagent.reagentInfo and reagent.reagentInfo.reagent then
		return reagent.reagentInfo.reagent.itemID
	end
	return nil
end

local function ReagentCurrencyID(reagent)
	if not reagent then
		return nil
	end
	if reagent.currencyID then
		return reagent.currencyID
	end
	if reagent.reagent then
		return reagent.reagent.currencyID
	end
	return nil
end

local function OrderReagentInfo(entry)
	if not entry then
		return nil
	end
	return entry.reagentInfo or entry.reagent
end

function ns.CountItem(itemID)
	if not itemID then
		return 0
	end
	return C_Item.GetItemCount(itemID, true, false, true, true) or 0
end

function ns.CountCurrency(currencyID)
	if not currencyID then
		return 0
	end
	local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
	return info and info.quantity or 0
end

function ns.GetItemName(itemID)
	if not itemID then
		return nil
	end
	return C_Item.GetItemNameByID(itemID)
end

function ns.GetItemIcon(itemID)
	if not itemID then
		return 134400
	end
	local instantIcon
	if C_Item.GetItemInfoInstant then
		instantIcon = select(5, C_Item.GetItemInfoInstant(itemID))
	end
	if instantIcon and instantIcon ~= 0 then
		return instantIcon
	end
	local icon = C_Item.GetItemIconByID(itemID)
	if icon and icon ~= 0 then
		return icon
	end
	return 134400
end

function ns.GetQualityInfo(order)
	if not order or not order.minQuality or order.minQuality <= 1 then
		return nil
	end
	if C_TradeSkillUI.GetRecipeItemQualityInfo then
		local info = C_TradeSkillUI.GetRecipeItemQualityInfo(order.spellID, order.minQuality)
		if info then
			return info
		end
	end
	return nil
end

function ns.GetQualityAtlas(order)
	local info = ns.GetQualityInfo(order)
	if not info then
		return nil
	end
	return info.iconSmall or info.iconChat or info.icon
end

function ns.GetReagentQualityInfo(itemID)
	if not itemID then
		return nil
	end
	if C_TradeSkillUI.GetItemReagentQualityInfo then
		local ok, info = pcall(C_TradeSkillUI.GetItemReagentQualityInfo, itemID)
		if ok and info then
			return info
		end
	end
	if C_TradeSkillUI.GetItemReagentQualityByItemInfo then
		local ok, quality = pcall(C_TradeSkillUI.GetItemReagentQualityByItemInfo, itemID)
		if ok and quality and quality > 0 and C_TradeSkillUI.GetRecipeItemQualityInfo then
			-- Fallback: some items only return the tier number.
			return { quality = quality }
		end
		if ok and type(quality) == "table" then
			return quality
		end
	end
	return nil
end

function ns.GetReagentQualityAtlas(itemID)
	local info = ns.GetReagentQualityInfo(itemID)
	if not info then
		return nil, nil
	end
	return info.icon or info.iconChat or info.iconSmall, info
end

function ns.GetQualityMarkup(order)
	local markup = ns.GetQualityMarkupFor(order and order.spellID, order and order.minQuality)
	if markup ~= "" then
		return " " .. markup
	end
	return ""
end

function ns.GetQualityMarkupFor(spellID, quality)
	if not spellID or not quality or quality <= 0 then
		return ""
	end
	if not C_TradeSkillUI.GetRecipeItemQualityInfo then
		return ""
	end
	local info = C_TradeSkillUI.GetRecipeItemQualityInfo(spellID, quality)
	if not info then
		return ""
	end
	if Professions and Professions.GetChatIconMarkupForQuality then
		return Professions.GetChatIconMarkupForQuality(info, true)
	end
	local atlas = info.iconChat or info.iconSmall or info.icon
	if atlas then
		return CreateAtlasMarkup(atlas, 16, 16)
	end
	return ""
end

local function SlotQuantityRequired(slot)
	if not slot then
		return 0
	end
	if slot.quantityRequired and slot.quantityRequired > 0 then
		return slot.quantityRequired
	end
	local maxQ = 0
	if slot.variableQuantities then
		for _, entry in ipairs(slot.variableQuantities) do
			local quantity = entry.quantity or 0
			if quantity > maxQ then
				maxQ = quantity
			end
		end
	end
	return maxQ
end

local function SlotHasIdentifiableReagent(slot)
	if not slot or not slot.reagents then
		return false
	end
	for _, reagent in ipairs(slot.reagents) do
		if ReagentItemID(reagent) or ReagentCurrencyID(reagent) then
			return true
		end
	end
	return false
end

local function SlotIsConcentration(slot)
	if not slot or not slot.reagents or not C_TradeSkillUI.GetConcentrationCurrencyID then
		return false
	end
	local info = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
	local skillLineID = info and (info.professionID or info.skillLineID or info.parentProfessionID)
	if not skillLineID then
		return false
	end
	local ok, concID = pcall(C_TradeSkillUI.GetConcentrationCurrencyID, skillLineID)
	if not ok or not concID then
		return false
	end
	for _, reagent in ipairs(slot.reagents) do
		if ReagentCurrencyID(reagent) == concID then
			return true
		end
	end
	return false
end

local function SlotIsRequired(slot)
	if not slot or slot.hiddenInCraftingForm then
		return false
	end
	local rtype = slot.reagentType
	if rtype == FinishingType or rtype == AutomaticType then
		return false
	end
	-- Optional reagents (Modifying was named Optional) never belong in You supply
	-- unless the recipe marks that slot required, e.g. a quality gem.
	if slot.required == false then
		return false
	end
	if rtype == ModifyingType and slot.required ~= true then
		return false
	end
	if NoneSource and slot.orderSource == NoneSource then
		return false
	end
	if SlotQuantityRequired(slot) <= 0 then
		return false
	end
	if not SlotHasIdentifiableReagent(slot) then
		return false
	end
	if SlotIsConcentration(slot) then
		return false
	end
	if slot.dataSlotType == CurrencySlot and rtype ~= BasicType then
		return false
	end
	return rtype == BasicType or slot.required == true
end

local function SlotAcceptsItem(slot, itemID)
	if not itemID or not slot or not slot.reagents then
		return false
	end
	for _, reagent in ipairs(slot.reagents) do
		if ReagentItemID(reagent) == itemID then
			return true
		end
	end
	return false
end

local function PickOwnedReagent(slot, quantityNeeded, excludeItems)
	local empty = {
		itemID = nil,
		currencyID = nil,
		have = 0,
		icon = 134400,
		name = nil,
	}
	if not slot.reagents then
		return empty
	end
	local first
	for _, reagent in ipairs(slot.reagents) do
		local itemID = ReagentItemID(reagent)
		local currencyID = ReagentCurrencyID(reagent)
		if not (itemID and excludeItems and excludeItems[itemID]) then
			local have = 0
			if itemID then
				have = ns.CountItem(itemID)
			elseif currencyID then
				have = ns.CountCurrency(currencyID)
			end
			local candidate = {
				itemID = itemID,
				currencyID = currencyID,
				have = have,
				icon = itemID and ns.GetItemIcon(itemID) or 134400,
				name = itemID and ns.GetItemName(itemID) or nil,
			}
			if not first then
				first = candidate
			end
			if have >= quantityNeeded then
				return candidate
			end
		end
	end
	return first or empty
end

local function GetEntryQuantity(entry, info)
	if info and type(info.quantity) == "number" then
		return info.quantity
	end
	if type(entry.quantity) == "number" then
		return entry.quantity
	end
	if info and info.reagent and type(info.reagent.quantity) == "number" then
		return info.reagent.quantity
	end
	return 0
end

local function GetEntrySlotIndex(entry, info)
	return entry.slotIndex or entry.reagentSlot
end

local function IsCustomerProvided(entry)
	local source = entry.source
	local crafter = Enum.CraftingOrderReagentSource and Enum.CraftingOrderReagentSource.Crafter
	if crafter ~= nil and source == crafter then
		return false
	end
	return true
end

function ns.BuildProvidedMap(order)
	local provided = {
		bySlot = {},
		byDataSlot = {},
		byItem = {},
		list = {},
	}
	if not order then
		return provided
	end
	local reagentList = order.reagents or order.reagentInfos
	if not reagentList then
		return provided
	end
	if not reagentList[1] then
		local packed = {}
		for _, entry in pairs(reagentList) do
			if type(entry) == "table" then
				table.insert(packed, entry)
			end
		end
		reagentList = packed
	end
	for _, entry in ipairs(reagentList) do
		if type(entry) == "table" and IsCustomerProvided(entry) then
			local info = OrderReagentInfo(entry)
			local quantity = GetEntryQuantity(entry, info)
			local itemID = ReagentItemID(info)
			local currencyID = ReagentCurrencyID(info)
			if quantity <= 0 and (itemID or currencyID) then
				quantity = 1
			end
			if quantity > 0 then
				local slotIndex = GetEntrySlotIndex(entry, info)
				local dataSlotIndex = info and info.dataSlotIndex
				table.insert(provided.list, {
					slotIndex = slotIndex,
					dataSlotIndex = dataSlotIndex,
					itemID = itemID,
					currencyID = currencyID,
					quantity = quantity,
					icon = ns.GetItemIcon(itemID),
					name = ns.GetItemName(itemID),
				})
				if slotIndex then
					provided.bySlot[slotIndex] = (provided.bySlot[slotIndex] or 0) + quantity
				end
				if dataSlotIndex then
					provided.byDataSlot[dataSlotIndex] = (provided.byDataSlot[dataSlotIndex] or 0) + quantity
				end
				if itemID then
					provided.byItem[itemID] = (provided.byItem[itemID] or 0) + quantity
				end
			end
		end
	end
	return provided
end

local function ProvidedFitsSlot(provided, slot)
	if provided.itemID then
		return SlotAcceptsItem(slot, provided.itemID)
	end
	if provided.currencyID and slot.reagents then
		for _, reagent in ipairs(slot.reagents) do
			if ReagentCurrencyID(reagent) == provided.currencyID then
				return true
			end
		end
		return false
	end
	return true
end

local function TakeProvidedForSlot(providedList, used, slot)
	if slot.orderSource == CrafterSource then
		return 0
	end
	local function Claim(i, provided)
		used[i] = true
		provided.slotIndex = slot.slotIndex
		provided.dataSlotIndex = slot.dataSlotIndex
		return provided.quantity or 0
	end
	for i, provided in ipairs(providedList) do
		if not used[i] and provided.itemID and SlotAcceptsItem(slot, provided.itemID) then
			return Claim(i, provided)
		end
	end
	for i, provided in ipairs(providedList) do
		if not used[i] and provided.slotIndex and provided.slotIndex == slot.slotIndex and ProvidedFitsSlot(provided, slot) then
			return Claim(i, provided)
		end
	end
	for i, provided in ipairs(providedList) do
		if not used[i] and provided.dataSlotIndex and provided.dataSlotIndex == slot.dataSlotIndex and ProvidedFitsSlot(provided, slot) then
			return Claim(i, provided)
		end
	end
	return 0
end

local function OperationReagents(analysis)
	local reagents = {}
	local function add(chip)
		if chip and chip.dataSlotIndex and (chip.itemID or chip.currencyID) then
			table.insert(reagents, {
				reagent = {
					itemID = chip.itemID,
					currencyID = chip.currencyID,
				},
				dataSlotIndex = chip.dataSlotIndex,
				quantity = chip.quantity or 0,
			})
		end
	end
	for _, chip in ipairs(analysis.provided or {}) do
		add(chip)
	end
	for _, chip in ipairs(analysis.needed or {}) do
		add(chip)
	end
	return reagents
end

local function ExpectedQuality(info)
	if not info then
		return 0
	end
	if type(info.craftingQuality) == "number" and info.craftingQuality > 0 then
		return info.craftingQuality
	end
	if type(info.quality) == "number" and info.quality > 0 then
		return math.floor(info.quality)
	end
	return 0
end

local function RecipeIDForOrder(order)
	if order.skillLineAbilityID and C_TradeSkillUI.GetRecipeInfoForSkillLineAbility then
		local info = C_TradeSkillUI.GetRecipeInfoForSkillLineAbility(order.skillLineAbilityID)
		if info and info.recipeID then
			return info.recipeID
		end
	end
	if order.spellID and C_TradeSkillUI.GetRecipeInfo then
		local info = C_TradeSkillUI.GetRecipeInfo(order.spellID)
		if info and info.recipeID then
			return info.recipeID
		end
	end
	return order.spellID
end

local function TryOperation(api, ...)
	if not api then
		return nil
	end
	local ok, info = pcall(api, ...)
	if ok and type(info) == "table" then
		return info
	end
	return nil
end

local function QueryOperation(recipeID, orderID, reagents, applyConcentration)
	reagents = reagents or {}
	applyConcentration = applyConcentration and true or false
	local info
	if orderID then
		info = TryOperation(C_TradeSkillUI.GetCraftingOperationInfoForOrder, recipeID, reagents, orderID, applyConcentration)
		if info then
			return info
		end
	end
	return TryOperation(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, reagents, nil, applyConcentration)
end

function ns.AnalyzeConcentration(order, analysis)
	analysis.needsConcentration = false
	analysis.concentrationCost = 0
	analysis.expectedQuality = 0
	analysis.requiredQuality = order and order.minQuality or 0
	analysis.skill = 0
	analysis.difficulty = 0
	if not order then
		return
	end

	local recipeID = RecipeIDForOrder(order)
	local allocated = OperationReagents(analysis)
	local function Query(apply)
		return QueryOperation(recipeID, order.orderID, allocated, apply)
			or QueryOperation(recipeID, order.orderID, {}, apply)
	end

	local noConc = Query(false)
	local withConc = Query(true)
	local expected = ExpectedQuality(noConc)
	local expectedWith = ExpectedQuality(withConc)
	local cost = (withConc and withConc.concentrationCost) or (noConc and noConc.concentrationCost) or 0
	local info = noConc or withConc
	if info then
		analysis.skill = (info.baseSkill or 0) + (info.bonusSkill or 0)
		analysis.difficulty = (info.baseDifficulty or 0) + (info.bonusDifficulty or 0)
	end
	analysis.expectedQuality = expected
	analysis.concentrationCost = cost

	local required = analysis.requiredQuality
	if expected > 0 and required > 1 and expected < required then
		analysis.needsConcentration = true
	elseif expected == 0 and expectedWith >= math.max(required, 1) and cost > 0 then
		analysis.needsConcentration = true
	elseif expected == 0 and required > 1 and analysis.skill > 0 and analysis.difficulty > analysis.skill then
		analysis.needsConcentration = true
	end
	if analysis.needsConcentration and analysis.concentrationCost == 0 and cost > 0 then
		analysis.concentrationCost = cost
	end
end

function ns.IsRecipeLearned(order)
	if not order then
		return false
	end
	if order.skillLineAbilityID and C_TradeSkillUI.GetRecipeInfoForSkillLineAbility then
		local info = C_TradeSkillUI.GetRecipeInfoForSkillLineAbility(order.skillLineAbilityID)
		if info and info.learned ~= nil then
			return info.learned
		end
	end
	if order.spellID then
		local info = C_TradeSkillUI.GetRecipeInfo(order.spellID)
		if info and info.learned ~= nil then
			return info.learned
		end
	end
	return false
end

function ns.AnalyzeOrder(order)
	local analysis = {
		order = order,
		provided = {},
		needed = {},
		ready = false,
		learned = false,
		missingCount = 0,
		providedCount = 0,
		neededCount = 0,
		craftingReagents = {},
		recipeName = nil,
		recipeIcon = 134400,
	}

	if not order then
		return analysis
	end

	analysis.minQuality = order.minQuality or 0
	analysis.learned = ns.IsRecipeLearned(order)
	analysis.recipeIcon = ns.GetItemIcon(order.itemID)
	if (not analysis.recipeIcon or analysis.recipeIcon == 134400) and order.outputItemHyperlink then
		local linkID = tonumber(order.outputItemHyperlink:match("item:(%d+)"))
		analysis.recipeIcon = ns.GetItemIcon(linkID)
	end
	local schematic = C_TradeSkillUI.GetRecipeSchematic(order.spellID, order.isRecraft and true or false, order.recipeLevel)
	if schematic then
		analysis.recipeName = schematic.name
		if schematic.icon and schematic.icon ~= 0 and analysis.recipeIcon == 134400 then
			analysis.recipeIcon = schematic.icon
		end
	else
		analysis.recipeName = ns.GetItemName(order.itemID)
	end

	local providedMap = ns.BuildProvidedMap(order)
	analysis.provided = providedMap.list
	analysis.providedCount = #providedMap.list

	local providedItems = {}
	for _, chip in ipairs(analysis.provided) do
		if chip.itemID then
			providedItems[chip.itemID] = true
		end
	end

	local allProvided = analysis.providedCount == 0
		and order.reagentState == (Enum.CraftingOrderReagentsType and Enum.CraftingOrderReagentsType.All)
	local usedProvided = {}

	if schematic and schematic.reagentSlotSchematics then
		for _, slot in ipairs(schematic.reagentSlotSchematics) do
			if SlotIsRequired(slot) then
				local required = SlotQuantityRequired(slot)
				local providedQty = TakeProvidedForSlot(providedMap.list, usedProvided, slot)
				if providedQty == 0 and allProvided then
					providedQty = required
				end
				local need = required - providedQty
				local owned = PickOwnedReagent(slot, math.max(need, 0), providedItems)
				if providedQty > 0 and analysis.providedCount == 0 then
					local displayItemID = owned.itemID
					table.insert(analysis.provided, {
						slotIndex = slot.slotIndex,
						dataSlotIndex = slot.dataSlotIndex,
						itemID = displayItemID,
						quantity = providedQty,
						icon = ns.GetItemIcon(displayItemID),
						name = ns.GetItemName(displayItemID),
					})
					analysis.providedCount = analysis.providedCount + 1
				end
				if need > 0 then
					local have = owned.have
					local chip = {
						slotIndex = slot.slotIndex,
						dataSlotIndex = slot.dataSlotIndex,
						itemID = owned.itemID,
						currencyID = owned.currencyID,
						quantity = need,
						have = have,
						enough = have >= need,
						icon = owned.icon,
						name = owned.name or ns.GetItemName(owned.itemID),
						isModified = slot.dataSlotType == ModifiedSlot or slot.reagentType == ModifyingType,
					}
					table.insert(analysis.needed, chip)
					analysis.neededCount = analysis.neededCount + 1
					if not chip.enough then
						analysis.missingCount = analysis.missingCount + 1
					end
					if chip.isModified and chip.enough and (chip.itemID or chip.currencyID) then
						table.insert(analysis.craftingReagents, {
							reagent = {
								itemID = chip.itemID,
								currencyID = chip.currencyID,
							},
							dataSlotIndex = chip.dataSlotIndex,
							quantity = chip.quantity,
						})
					end
				end
			end
		end
	elseif analysis.providedCount == 0 and order.reagents then
		for _, entry in ipairs(order.reagents) do
			local info = OrderReagentInfo(entry)
			local quantity = GetEntryQuantity(entry, info)
			local itemID = ReagentItemID(info)
			local currencyID = ReagentCurrencyID(info)
			local chip = {
				slotIndex = GetEntrySlotIndex(entry, info),
				itemID = itemID,
				currencyID = currencyID,
				quantity = quantity,
				icon = ns.GetItemIcon(itemID),
				name = ns.GetItemName(itemID),
			}
			if IsCustomerProvided(entry) then
				table.insert(analysis.provided, chip)
				analysis.providedCount = analysis.providedCount + 1
			elseif entry.isBasicReagent ~= false then
				chip.have = itemID and ns.CountItem(itemID) or ns.CountCurrency(currencyID)
				chip.enough = chip.have >= quantity
				chip.isModified = not entry.isBasicReagent
				table.insert(analysis.needed, chip)
				analysis.neededCount = analysis.neededCount + 1
				if not chip.enough then
					analysis.missingCount = analysis.missingCount + 1
				end
			end
		end
	end

	analysis.ready = analysis.learned and analysis.missingCount == 0
	ns.AnalyzeConcentration(order, analysis)
	return analysis
end

function ns.GetRecipeDisplayName(order, analysis)
	if analysis and analysis.recipeName and analysis.recipeName ~= "" then
		return analysis.recipeName
	end
	if order.outputItemHyperlink then
		local name = order.outputItemHyperlink:match("%[(.-)%]")
		if name then
			return name
		end
	end
	return ns.GetItemName(order.itemID) or ("Order " .. tostring(order.orderID))
end
