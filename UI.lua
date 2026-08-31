local addonName, ns = ...

local ROW_HEIGHT = 168
local ICON_SIZE = 28
local BOARD_WIDTH = 520
local BUTTON_WIDTH = 124
local CHIP_GAP = 20
local QUALITY_ICON_SIZE = 20

local function FormatHaveNeed(have, need)
	local haveText
	if have >= 10000 then
		haveText = string.format("%dk", math.floor(have / 1000 + 0.5))
	elseif have >= 1000 then
		haveText = string.format("%.1fk", have / 1000):gsub("%.0k", "k")
	else
		haveText = tostring(have)
	end
	return haveText .. "/" .. tostring(need)
end

local function ColorText(text, r, g, b)
	return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
end

local function TimeLeftText(expirationTime)
	if not expirationTime then
		return ""
	end
	local remaining = expirationTime - GetServerTime()
	if remaining <= 0 then
		return ColorText("Expired", 1, 0.2, 0.2)
	end
	if remaining >= 86400 then
		return string.format("%dd", math.floor(remaining / 86400))
	end
	if remaining >= 3600 then
		return string.format("%dh", math.floor(remaining / 3600))
	end
	return string.format("%dm", math.max(1, math.floor(remaining / 60)))
end

local function FormatCopper(copper)
	copper = tonumber(copper) or 0
	if copper <= 0 then
		return nil
	end
	if GetMoneyString then
		return GetMoneyString(copper)
	end
	if GetCoinTextureString then
		return GetCoinTextureString(copper)
	end
	return tostring(copper)
end

local function OrderPayoutText(order)
	local tip = tonumber(order.tipAmount) or 0
	local cut = tonumber(order.consortiumCut) or 0
	local payout = FormatCopper(tip - cut)
	if not payout then
		return nil
	end
	return ColorText("You get: ", 1, 0.82, 0) .. payout
end

local function SetReagentQuality(button, chip)
	if button.quality then
		button.quality:Hide()
	end
	if not chip or not chip.itemID then
		return nil
	end
	local atlas, info = ns.GetReagentQualityAtlas(chip.itemID)
	if atlas and button.quality then
		local ok = pcall(button.quality.SetAtlas, button.quality, atlas)
		if ok then
			button.quality:SetSize(QUALITY_ICON_SIZE, QUALITY_ICON_SIZE)
			button.quality:Show()
		else
			atlas = nil
		end
	end
	return info, atlas
end

local function QualityMarkup(info)
	if not info then
		return ""
	end
	if Professions and Professions.GetChatIconMarkupForQuality then
		local markup = Professions.GetChatIconMarkupForQuality(info, true)
		if markup and markup ~= "" then
			return " " .. markup
		end
	end
	if info.iconChat or info.iconSmall then
		return " " .. CreateAtlasMarkup(info.iconChat or info.iconSmall, 14, 14)
	end
	if info.quality and info.quality > 0 then
		return " Q" .. info.quality
	end
	return ""
end

local function SetIcon(button, chip, provided)
	button:Show()
	button.icon:SetTexture(chip.icon or 134400)
	local qInfo = SetReagentQuality(button, chip)
	if provided then
		button.count:SetText("x" .. tostring(chip.quantity or 0))
		button.count:SetTextColor(0.35, 0.95, 0.5)
	else
		local have = chip.have or 0
		local need = chip.quantity or 0
		button.count:SetText(FormatHaveNeed(have, need))
		if chip.enough then
			button.count:SetTextColor(1, 0.82, 0)
		else
			button.count:SetTextColor(1, 0.28, 0.28)
		end
	end
	button.chip = chip
	button.qualityInfo = qInfo
end

local function HideIcon(button)
	button:Hide()
	button.chip = nil
	button.qualityInfo = nil
	if button.quality then
		button.quality:Hide()
	end
end

local function CreateIconButton(parent)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(ICON_SIZE, ICON_SIZE)

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	button.quality = button:CreateTexture(nil, "OVERLAY")
	button.quality:SetSize(QUALITY_ICON_SIZE, QUALITY_ICON_SIZE)
	button.quality:SetPoint("BOTTOMRIGHT", 4, -4)
	button.quality:Hide()

	button.countClip = CreateFrame("Frame", nil, button)
	button.countClip:SetPoint("TOP", button, "BOTTOM", 0, -1)
	button.countClip:SetSize(ICON_SIZE + 8, 14)
	if button.countClip.SetClipsChildren then
		button.countClip:SetClipsChildren(true)
	end

	button.count = button.countClip:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	button.count:SetAllPoints()
	button.count:SetJustifyH("CENTER")
	button.count:SetWordWrap(false)

	button:SetScript("OnEnter", function(self)
		if not self.chip then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.chip.itemID then
			GameTooltip:SetItemByID(self.chip.itemID)
			if self.qualityInfo then
				GameTooltip:AddLine(" ")
				local markup = QualityMarkup(self.qualityInfo)
				if markup ~= "" then
					GameTooltip:AddLine("Reagent quality:" .. markup, 1, 0.82, 0)
				elseif self.qualityInfo.quality then
					GameTooltip:AddLine("Reagent quality: " .. self.qualityInfo.quality, 1, 0.82, 0)
				end
			end
			if self.chip.have and self.chip.quantity then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine(string.format("You have %d / need %d", self.chip.have, self.chip.quantity), 1, 0.82, 0)
			elseif self.chip.quantity then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine("Provided: " .. self.chip.quantity, 0.3, 1, 0.45)
			end
			GameTooltip:Show()
		elseif self.chip.name then
			GameTooltip:AddLine(self.chip.name)
			GameTooltip:Show()
		end
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return button
end

local function CreateChipRow(parent, y, label, labelColor)
	local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", 12, y)
	title:SetText(label)
	title:SetWidth(78)
	title:SetJustifyH("LEFT")
	if labelColor then
		title:SetTextColor(labelColor[1], labelColor[2], labelColor[3])
	end
	local icons = {}
	for i = 1, 6 do
		local icon = CreateIconButton(parent)
		if i == 1 then
			icon:SetPoint("TOPLEFT", title, "TOPRIGHT", 8, 2)
		else
			icon:SetPoint("LEFT", icons[i - 1], "RIGHT", CHIP_GAP, 0)
		end
		icon:Hide()
		icons[i] = icon
	end
	local extra = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	extra:SetPoint("LEFT", icons[6], "RIGHT", 8, 0)
	extra:Hide()
	local empty = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	empty:SetPoint("LEFT", title, "RIGHT", 8, 0)
	empty:SetText("none")
	empty:Hide()
	return title, icons, extra, empty
end

local function CreateRewardIcon(parent)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(20, 20)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	button.count:SetPoint("BOTTOMRIGHT", 2, -1)
	button:SetScript("OnEnter", function(self)
		if not self.reward then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.reward.itemLink then
			GameTooltip:SetHyperlink(self.reward.itemLink)
		elseif self.reward.currencyType then
			local info = C_CurrencyInfo.GetCurrencyInfo(self.reward.currencyType)
			if info then
				GameTooltip:AddLine(info.name)
				if self.reward.count then
					GameTooltip:AddLine("Count: " .. self.reward.count, 1, 1, 1)
				end
				GameTooltip:Show()
			end
		end
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return button
end

local function FillIcons(icons, extra, chips, provided)
	local maxIcons = #icons
	for i, icon in ipairs(icons) do
		local chip = chips and chips[i]
		if chip then
			SetIcon(icon, chip, provided)
		else
			HideIcon(icon)
		end
	end
	if extra then
		if chips and #chips > maxIcons then
			extra:SetText("+" .. (#chips - maxIcons))
			extra:Show()
		else
			extra:Hide()
		end
	end
end

local function FillRewards(icons, rewards)
	for i, icon in ipairs(icons) do
		local reward = rewards and rewards[i]
		if reward then
			icon.reward = reward
			if reward.itemLink then
				local itemID = tonumber(reward.itemLink:match("item:(%d+)"))
				icon.icon:SetTexture(ns.GetItemIcon(itemID))
			elseif reward.currencyType then
				local info = C_CurrencyInfo.GetCurrencyInfo(reward.currencyType)
				icon.icon:SetTexture(info and info.iconFileID or 134400)
			else
				icon.icon:SetTexture(134400)
			end
			icon.count:SetText(reward.count and reward.count > 1 and reward.count or "")
			icon:Show()
		else
			icon.reward = nil
			icon:Hide()
		end
	end
end

local function CreateRow(parent, index)
	local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	row:SetSize(BOARD_WIDTH - 36, ROW_HEIGHT)
	row:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	row:SetBackdropColor(0.07, 0.07, 0.08, 0.92)
	row:SetBackdropBorderColor(0.35, 0.3, 0.2, 0.9)

	row.itemIcon = row:CreateTexture(nil, "ARTWORK")
	row.itemIcon:SetSize(40, 40)
	row.itemIcon:SetPoint("TOPLEFT", 10, -12)
	row.itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.qualityIcon = row:CreateTexture(nil, "OVERLAY")
	row.qualityIcon:SetSize(18, 18)
	row.qualityIcon:SetPoint("LEFT", row.itemIcon, "RIGHT", 6, 10)
	row.qualityIcon:Hide()

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.name:SetPoint("TOPLEFT", 58, -12)
	row.name:SetPoint("TOPRIGHT", -140, -12)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.name:SetMaxLines(1)

	row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
	row.meta:SetPoint("RIGHT", -200, 0)
	row.meta:SetJustifyH("LEFT")

	row.qualityLine = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.qualityLine:SetPoint("TOPLEFT", row.meta, "BOTTOMLEFT", 0, -3)
	row.qualityLine:SetPoint("RIGHT", -200, 0)
	row.qualityLine:SetJustifyH("LEFT")
	row.qualityLine:Hide()

	row.money = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.money:SetPoint("TOPRIGHT", -10, -34)
	row.money:SetWidth(BUTTON_WIDTH + 8)
	row.money:SetJustifyH("RIGHT")
	row.money:SetWordWrap(false)
	row.money:Hide()

	row.providedLabel, row.providedIcons, row.providedExtra, row.providedEmpty = CreateChipRow(row, -68, "Provided", { 0.35, 0.95, 0.5 })
	row.neededLabel, row.neededIcons, row.neededExtra, row.neededEmpty = CreateChipRow(row, -112, "You supply", { 1, 0.78, 0.25 })

	row.rewardIcons = {}
	for i = 1, 5 do
		local icon = CreateRewardIcon(row)
		if i == 1 then
			icon:SetPoint("TOPRIGHT", -10, -8)
		else
			icon:SetPoint("RIGHT", row.rewardIcons[i - 1], "LEFT", -3, 0)
		end
		icon:Hide()
		row.rewardIcons[i] = icon
	end

	row.startButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.startButton:SetSize(BUTTON_WIDTH, 22)
	row.startButton:SetPoint("TOPRIGHT", -10, -52)
	row.startButton:SetText("Start Order")
	row.startButton:SetScript("OnClick", function(self)
		if self.order and self.analysis then
			ns.StartOrder(self.order, self.analysis)
		end
	end)

	row.cancelButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.cancelButton:SetSize(BUTTON_WIDTH, 22)
	row.cancelButton:SetPoint("TOPRIGHT", -10, -52)
	row.cancelButton:SetText("Cancel")
	row.cancelButton:SetScript("OnClick", function(self)
		if self.order and self.analysis then
			ns.CancelOrder(self.order, self.analysis)
		end
	end)

	row.finishButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.finishButton:SetSize(BUTTON_WIDTH, 22)
	row.finishButton:SetPoint("TOPRIGHT", -10, -76)
	row.finishButton:SetText("Craft & Complete")
	row.finishButton:SetScript("OnClick", function(self)
		if self.order and self.analysis then
			ns.FinishOrder(self.order, self.analysis)
		end
	end)

	local function BindTooltip(button)
		button:SetScript("OnEnter", function(self)
			if self.reason then
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:AddLine(self.reason, 1, 0.2, 0.2, true)
				GameTooltip:Show()
			end
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
	end
	BindTooltip(row.startButton)
	BindTooltip(row.cancelButton)
	BindTooltip(row.finishButton)

	return row
end

local function UpdateRow(row, order, analysis)
	row.itemIcon:SetTexture(analysis.recipeIcon or ns.GetItemIcon(order.itemID))
	row.name:SetText(ns.GetRecipeDisplayName(order, analysis) .. ns.GetQualityMarkup(order))
	row.qualityIcon:Hide()
	if not analysis.learned then
		row.name:SetTextColor(1, 0.35, 0.35)
	else
		row.name:SetTextColor(1, 0.82, 0)
	end

	local patron = order.customerName or "Patron"
	local meta = string.format("%s  ·  %s", patron, TimeLeftText(order.expirationTime))
	if not analysis.learned then
		meta = meta .. "  ·  " .. ColorText("Unlearned", 1, 0.35, 0.35)
	end
	row.meta:SetText(meta)

	if analysis.needsConcentration then
		local cost = analysis.concentrationCost or 0
		local text = cost > 0 and ("Needs Concentration: " .. cost) or "Needs Concentration"
		row.qualityLine:SetText(ColorText(text, 1, 0.72, 0.2))
		row.qualityLine:Show()
	else
		row.qualityLine:SetText("")
		row.qualityLine:Hide()
	end

	FillRewards(row.rewardIcons, order.npcOrderRewards)
	local payout = OrderPayoutText(order)
	if payout then
		row.money:SetText(payout)
		row.money:Show()
	else
		row.money:SetText("")
		row.money:Hide()
	end

	row.providedLabel:SetText("Provided")
	row.neededLabel:SetText("You supply")
	if analysis.neededCount == 0 then
		row.neededLabel:SetTextColor(0.3, 1, 0.45)
	else
		row.neededLabel:SetTextColor(1, 0.75, 0.2)
	end

	FillIcons(row.providedIcons, row.providedExtra, analysis.provided, true)
	FillIcons(row.neededIcons, row.neededExtra, analysis.needed, false)
	row.providedEmpty:SetShown(analysis.providedCount == 0)
	row.neededEmpty:SetShown(analysis.neededCount == 0)
	if analysis.neededCount == 0 then
		row.neededEmpty:SetText("nothing")
		row.neededEmpty:SetTextColor(0.3, 1, 0.45)
	else
		row.neededEmpty:SetText("none")
	end

	local pendingThis = ns.pending and ns.pending.orderID == order.orderID
	local state = ns.GetOrderState(order)
	local startReason = ns.GetBusyReason(order, analysis, "start")
	local cancelReason = ns.GetBusyReason(order, analysis, "cancel")
	local finishReason = ns.GetBusyReason(order, analysis, "finish")

	local buttons = { row.startButton, row.cancelButton, row.finishButton }
	for _, button in ipairs(buttons) do
		button.order = order
		button.analysis = analysis
	end

	row.startButton:SetShown(state == "open")
	row.cancelButton:SetShown(state ~= "open")

	if pendingThis then
		for _, button in ipairs(buttons) do
			button:SetEnabled(false)
			button.reason = nil
		end
		if ns.pending.phase == "claim" then
			row.startButton:SetText("Starting...")
		elseif ns.pending.phase == "release" then
			row.cancelButton:SetText("Cancelling...")
		elseif ns.pending.phase == "craft" or ns.pending.phase == "await-fulfill" then
			row.finishButton:SetText("Crafting...")
		elseif ns.pending.phase == "fulfill" then
			row.finishButton:SetText("Completing...")
		end
	else
		row.startButton:SetText("Start Order")
		row.cancelButton:SetText("Cancel")
		row.finishButton:SetText(state == "fulfillable" and "Complete" or "Craft & Complete")
		row.startButton:SetEnabled(state == "open" and not startReason)
		row.startButton.reason = startReason
		row.cancelButton:SetEnabled(state ~= "open" and not cancelReason)
		row.cancelButton.reason = cancelReason
		row.finishButton:SetEnabled(state ~= "open" and not finishReason)
		row.finishButton.reason = finishReason
	end
end

function ns.CreateUI()
	if ns.frame then
		return ns.frame
	end

	local frame = CreateFrame("Frame", "PatronOrderBoardFrame", UIParent, "BackdropTemplate")
	frame:SetSize(BOARD_WIDTH, 640)
	frame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0.05, 0.05, 0.06, 0.96)
	frame:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relativePoint, x, y = self:GetPoint()
		PatronOrderBoardDB.point = point
		PatronOrderBoardDB.relativePoint = relativePoint
		PatronOrderBoardDB.x = x
		PatronOrderBoardDB.y = y
		PatronOrderBoardDB.docked = false
	end)
	frame:Hide()
	tinsert(UISpecialFrames, frame:GetName())

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.title:SetPoint("TOP", 0, -12)
	frame.title:SetText("Patron Order Board")

	frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.closeButton:SetPoint("TOPRIGHT", 2, 2)
	frame.closeButton:SetScript("OnClick", function()
		frame:Hide()
	end)

	frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.status:SetPoint("TOPLEFT", 16, -36)
	frame.status:SetPoint("TOPRIGHT", -16, -36)
	frame.status:SetJustifyH("LEFT")
	frame.status:SetText("Open your profession, then Crafting Orders > Patron.")

	frame.hideConcentration = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	frame.hideConcentration:SetSize(24, 24)
	frame.hideConcentration:SetPoint("TOPLEFT", 10, -54)
	frame.hideConcentration.text = frame.hideConcentration:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.hideConcentration.text:SetPoint("LEFT", frame.hideConcentration, "RIGHT", 0, 0)
	frame.hideConcentration.text:SetText("Hide concentration")
	frame.hideConcentration:SetScript("OnClick", function(self)
		PatronOrderBoardDB.hideConcentration = self:GetChecked()
		ns.RefreshUI(true)
	end)

	frame.hideUnlearned = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	frame.hideUnlearned:SetSize(24, 24)
	frame.hideUnlearned:SetPoint("LEFT", frame.hideConcentration.text, "RIGHT", 10, 0)
	frame.hideUnlearned.text = frame.hideUnlearned:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.hideUnlearned.text:SetPoint("LEFT", frame.hideUnlearned, "RIGHT", 0, 0)
	frame.hideUnlearned.text:SetText("Hide unlearned")
	frame.hideUnlearned:SetScript("OnClick", function(self)
		PatronOrderBoardDB.hideUnlearned = self:GetChecked()
		ns.RefreshUI(true)
	end)

	frame.refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.refreshButton:SetSize(80, 22)
	frame.refreshButton:SetPoint("TOPRIGHT", -12, -56)
	frame.refreshButton:SetText("Refresh")
	frame.refreshButton:SetScript("OnClick", function()
		ns.RequestPatronOrders()
	end)

	local scroll = CreateFrame("ScrollFrame", "PatronOrderBoardScroll", frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -86)
	scroll:SetPoint("BOTTOMRIGHT", -32, 12)
	frame.scroll = scroll

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(BOARD_WIDTH - 48, 1)
	scroll:SetScrollChild(content)
	frame.content = content
	frame.rows = {}

	ns.frame = frame
	return frame
end

function ns.DockToProfessions()
	local frame = ns.frame
	if not frame or not PatronOrderBoardDB.docked then
		return
	end
	if ProfessionsFrame and ProfessionsFrame:IsShown() then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 0, 0)
		frame:SetPoint("BOTTOMLEFT", ProfessionsFrame, "BOTTOMRIGHT", 0, 0)
		frame:SetWidth(BOARD_WIDTH)
	end
end

function ns.RestorePosition()
	local frame = ns.CreateUI()
	if PatronOrderBoardDB.docked ~= false then
		PatronOrderBoardDB.docked = true
		ns.DockToProfessions()
		return
	end
	if PatronOrderBoardDB.point then
		frame:ClearAllPoints()
		frame:SetPoint(
			PatronOrderBoardDB.point,
			UIParent,
			PatronOrderBoardDB.relativePoint or PatronOrderBoardDB.point,
			PatronOrderBoardDB.x or 0,
			PatronOrderBoardDB.y or 0
		)
	end
end

local function SortOrders(entries)
	table.sort(entries, function(a, b)
		local aReady = a.analysis.ready and 0 or 1
		local bReady = b.analysis.ready and 0 or 1
		if aReady ~= bReady then
			return aReady < bReady
		end
		if a.analysis.missingCount ~= b.analysis.missingCount then
			return a.analysis.missingCount < b.analysis.missingCount
		end
		local aName = ns.GetRecipeDisplayName(a.order, a.analysis)
		local bName = ns.GetRecipeDisplayName(b.order, b.analysis)
		if aName ~= bName then
			return aName < bName
		end
		return (a.order.orderID or 0) < (b.order.orderID or 0)
	end)
end

local displayOrderIDs = {}
local displayOrderProfession = nil

local function CurrentProfession()
	local info = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
	return info and info.profession
end

local function RememberDisplayOrder(entries)
	displayOrderIDs = {}
	displayOrderProfession = CurrentProfession()
	for i, entry in ipairs(entries) do
		displayOrderIDs[i] = entry.order.orderID
	end
end

local function StabilizeEntries(entries, forceResort)
	local profession = CurrentProfession()
	if forceResort or profession ~= displayOrderProfession or #displayOrderIDs == 0 then
		SortOrders(entries)
		RememberDisplayOrder(entries)
		return
	end
	local byID = {}
	for _, entry in ipairs(entries) do
		byID[entry.order.orderID] = entry
	end
	local stable = {}
	local seen = {}
	for _, orderID in ipairs(displayOrderIDs) do
		local entry = byID[orderID]
		if entry then
			table.insert(stable, entry)
			seen[orderID] = true
		end
	end
	local newcomers = {}
	for _, entry in ipairs(entries) do
		if not seen[entry.order.orderID] then
			table.insert(newcomers, entry)
		end
	end
	SortOrders(newcomers)
	for _, entry in ipairs(newcomers) do
		table.insert(stable, entry)
	end
	for i = 1, #entries do
		entries[i] = nil
	end
	for i, entry in ipairs(stable) do
		entries[i] = entry
	end
	RememberDisplayOrder(entries)
end

local function RestoreScroll(scroll, offset, contentHeight)
	if not scroll then
		return
	end
	local viewHeight = scroll:GetHeight() or 0
	local maxScroll = math.max(0, (contentHeight or 0) - viewHeight)
	scroll:SetVerticalScroll(math.min(math.max(offset or 0, 0), maxScroll))
end

function ns.RefreshUI(forceResort)
	if not ns.frame then
		return
	end
	local scroll = ns.frame.scroll
	local oldScroll = scroll and scroll:GetVerticalScroll() or 0
	local orders = ns.GetPatronOrders()
	local entries = {}
	local readyCount, missingCount, unlearnedCount = 0, 0, 0
	for _, order in ipairs(orders) do
		local analysis = ns.AnalyzeOrder(order)
		if not analysis.learned then
			unlearnedCount = unlearnedCount + 1
		elseif analysis.ready then
			readyCount = readyCount + 1
		else
			missingCount = missingCount + 1
		end
		local hideByConcentration = PatronOrderBoardDB.hideConcentration and analysis.needsConcentration
		local hideByUnlearned = PatronOrderBoardDB.hideUnlearned and not analysis.learned
		if not hideByConcentration and not hideByUnlearned then
			table.insert(entries, { order = order, analysis = analysis })
		end
	end
	StabilizeEntries(entries, forceResort)

	ns.frame.status:SetText(string.format(
		"%d ready   ·   %d missing mats   ·   %d unlearned",
		readyCount,
		missingCount,
		unlearnedCount
	))
	ns.frame.hideConcentration:SetChecked(PatronOrderBoardDB.hideConcentration)
	ns.frame.hideUnlearned:SetChecked(PatronOrderBoardDB.hideUnlearned)

	if #orders == 0 then
		ns.frame.status:SetText("No patron orders loaded. Click Refresh, or open Crafting Orders > Patron once.")
	end

	local content = ns.frame.content
	for i, entry in ipairs(entries) do
		local row = ns.frame.rows[i]
		if not row then
			row = CreateRow(content, i)
			ns.frame.rows[i] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -((i - 1) * (ROW_HEIGHT + 10)))
		row:Show()
		UpdateRow(row, entry.order, entry.analysis)
	end
	for i = #entries + 1, #ns.frame.rows do
		ns.frame.rows[i]:Hide()
	end
	local contentHeight = math.max(1, #entries * (ROW_HEIGHT + 10))
	content:SetHeight(contentHeight)
	RestoreScroll(scroll, oldScroll, contentHeight)
end

function ns.EnsureBoardShown()
	ns.CreateUI()
	ns.RestorePosition()
	ns.frame:Show()
end

function ns.ShowBoard()
	ns.CreateUI()
	ns.RestorePosition()
	if ns.SyncProfession then
		ns.SyncProfession()
	end
	ns.frame:Show()
	ns.RefreshUI(true)
	ns.RequestPatronOrders()
end

function ns.HideBoard()
	if ns.frame then
		ns.frame:Hide()
	end
end

function ns.ToggleBoard()
	ns.CreateUI()
	if ns.frame:IsShown() then
		ns.HideBoard()
	else
		ns.ShowBoard()
	end
end
