local ADDON_NAME, FT = ...

local ROW_HEIGHT = 28
local ITEM_BUTTON_SIZE = 24
local ITEM_ID_WIDTH = 150
local TARGET_WIDTH = 60
local CURRENT_WIDTH = 90
local ALL_NAME_WIDTH = 140
local ALL_COUNT_WIDTH = 50
local ALL_UNIT_WIDTH = 60
local ALL_TOTAL_WIDTH = 70
local FRAME_WIDTH = 460
local FRAME_HEIGHT = 360
local FRAME_MIN_HEIGHT = 300
local FRAME_MAX_HEIGHT = 700

local function positionRow(row, index)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", 0, -((index - 1) * ROW_HEIGHT))
end

local function setEditBoxEnabled(editBox, enabled)
    if enabled then
        editBox:EnableMouse(true)
        editBox:SetTextColor(1, 1, 1)
    else
        editBox:EnableMouse(false)
        editBox:SetTextColor(0.6, 0.6, 0.6)
        editBox:ClearFocus()
    end
end

function FT:RefreshPresetDropdown()
    if not self.frame or not self.frame.presetDropdown then
        return
    end

    UIDropDownMenu_Initialize(self.frame.presetDropdown, function(_, level)
        local names = FT:GetPresetNamesSorted()
        if #names == 0 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "No presets"
            info.disabled = true
            UIDropDownMenu_AddButton(info, level)
            return
        end

        for _, name in ipairs(names) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.value = name
            info.func = function()
                FT:LoadPreset(name)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local selected = self.selectedPreset or (self.db and self.db.lastPreset)
    if selected and self.accountDb and self.accountDb.presets and self.accountDb.presets[selected] then
        self:SetSelectedPreset(selected)
    else
        UIDropDownMenu_SetSelectedValue(self.frame.presetDropdown, nil)
        UIDropDownMenu_SetText(self.frame.presetDropdown, "Select")
        if self.frame.presetNameBox and not self.frame.presetNameBox:HasFocus() then
            self.frame.presetNameBox:SetText("")
        end
    end
end

function FT:ShowProfilesWindow(mode, payload)
    if not self.profilesFrame then
        self:CreateProfilesWindow()
    end
    local frame = self.profilesFrame
    if mode == "import" then
        frame.editBox:SetText("")
        frame.mergeCheck:SetChecked(true)
    elseif mode == "export" then
        frame.editBox:SetText(payload or "")
    end
    if frame.updateSize then
        frame.updateSize()
    end
    frame.editBox:HighlightText()
    frame.editBox:SetFocus()
    frame:Show()
end

function FT:CreateProfilesWindow()
    if self.profilesFrame then
        return
    end

    local frame = CreateFrame("Frame", "FarmingTimerProfilesFrame", UIParent, "BackdropTemplate")
    frame:SetSize(460, 280)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Profiles")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -6, -6)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 16, -34)
    hint:SetText("Paste or copy your preset string below.")

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 16, -52)
    scrollFrame:SetPoint("BOTTOMRIGHT", -34, 64)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)

    local editBox = CreateFrame("EditBox", nil, scrollChild, "BackdropTemplate")
    editBox:SetMultiLine(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetAutoFocus(false)
    editBox:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
    editBox:SetPoint("BOTTOMRIGHT", scrollChild, "BOTTOMRIGHT", 0, 0)
    editBox:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    })
    editBox:SetBackdropColor(0, 0, 0, 0.5)
    editBox:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.8)
    editBox:SetTextInsets(6, 6, 6, 6)
    editBox:SetScript("OnCursorChanged", function(self, x, y, w, h)
        scrollFrame:UpdateScrollChildRect()
        local height = scrollFrame:GetHeight()
        if h and h > height then
            scrollFrame:SetVerticalScroll(-y - height)
        end
    end)
    editBox:SetScript("OnTextChanged", function()
        scrollFrame:UpdateScrollChildRect()
    end)

    local function updateSize()
        local width = scrollFrame:GetWidth()
        local height = scrollFrame:GetHeight()
        if width and width > 0 then
            scrollChild:SetWidth(width)
        end
        if height and height > 0 then
            scrollChild:SetHeight(height)
        end
    end
    scrollFrame:SetScript("OnSizeChanged", updateSize)
    frame:SetScript("OnShow", updateSize)

    local mergeCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    mergeCheck:SetPoint("BOTTOMLEFT", 16, 44)
    local mergeLabel = mergeCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mergeLabel:SetPoint("LEFT", mergeCheck, "RIGHT", 4, 0)
    mergeLabel:SetText("Merge (do not overwrite)")
    mergeCheck:SetChecked(true)

    local importButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importButton:SetSize(70, 22)
    importButton:SetPoint("BOTTOMRIGHT", -16, 16)
    importButton:SetText("Import")
    importButton:SetScript("OnClick", function()
        FT:ImportPresets(editBox:GetText(), mergeCheck:GetChecked())
    end)

    local exportSelectedButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportSelectedButton:SetSize(110, 22)
    exportSelectedButton:SetPoint("RIGHT", importButton, "LEFT", -8, 0)
    exportSelectedButton:SetText("Export Selected")
    exportSelectedButton:SetScript("OnClick", function()
        local name = FT:GetSelectedPresetName()
        if not name then
            FT:Print("Please select a preset.")
            return
        end
        local exportString, err = FT:BuildExportString(name)
        if not exportString then
            FT:Print(err or "No presets available.")
            return
        end
        editBox:SetText(exportString)
        editBox:HighlightText()
        editBox:SetFocus()
    end)

    local exportAllButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportAllButton:SetSize(88, 22)
    exportAllButton:SetPoint("RIGHT", exportSelectedButton, "LEFT", -8, 0)
    exportAllButton:SetText("Export All")
    exportAllButton:SetScript("OnClick", function()
        local exportString, err = FT:BuildExportString()
        if not exportString then
            FT:Print(err or "No presets available.")
            return
        end
        editBox:SetText(exportString)
        editBox:HighlightText()
        editBox:SetFocus()
    end)

    frame.editBox = editBox
    frame.mergeCheck = mergeCheck
    frame.exportAllButton = exportAllButton
    frame.exportSelectedButton = exportSelectedButton
    frame.importButton = importButton
    frame.updateSize = updateSize

    self.profilesFrame = frame
end

function FT:SetTimerText(text)
    if self.frame and self.frame.timerText then
        self.frame.timerText:SetText(text or "00:00")
    end
end

function FT:SaveFramePosition()
    if not self.frame or not self.db then
        return
    end
    local point, _, _, x, y = self.frame:GetPoint(1)
    if point then
        self.db.frame.point = point
        self.db.frame.x = math.floor(x + 0.5)
        self.db.frame.y = math.floor(y + 0.5)
    end
end

function FT:SaveFrameSize()
    if not self.frame or not self.db then
        return
    end
    local height = self.frame:GetHeight()
    if height then
        height = math.max(FRAME_MIN_HEIGHT, math.min(height, FRAME_MAX_HEIGHT))
        self.db.frame.height = math.floor(height + 0.5)
    end
end

function FT:ResetFramePosition()
    if not self.frame or not self.db then
        return
    end
    self.db.frame.point = "CENTER"
    self.db.frame.x = 0
    self.db.frame.y = 0
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

function FT:RequestItemData(itemID)
    if not itemID then
        return
    end
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

function FT:SetRowItem(row, itemID)
    row.data.itemID = itemID
    row.itemIDBox:SetText(itemID and tostring(itemID) or "")
    self:RequestItemData(itemID)
    self:UpdateRow(row)
    self:RefreshProgress(self.MODES.TARGETS)
end

function FT:CommitItemID(row)
    local text = row.itemIDBox:GetText()
    local itemID = self:ResolveItemID(text)
    if itemID then
        row.data.itemID = itemID
        row.itemIDBox:SetText(tostring(itemID))
        self:RequestItemData(itemID)
    else
        row.data.itemID = nil
        row.itemIDBox:SetText("")
    end
    self:UpdateRow(row)
    self:RefreshProgress(self.MODES.TARGETS)
end

function FT:CommitTarget(row)
    local text = row.targetBox:GetText()
    local target = tonumber(text)
    if target and target > 0 then
        row.data.target = math.floor(target)
        row.targetBox:SetText(tostring(row.data.target))
    else
        row.data.target = 0
        row.targetBox:SetText("")
    end
    self:UpdateRow(row)
    self:RefreshProgress(self.MODES.TARGETS)
end

function FT:HandleItemCursor(row)
    if self:IsAnyRunning() then
        return
    end
    local infoType, itemID, itemLink = GetCursorInfo()
    if infoType == "item" then
        local resolved = itemID
        if not resolved and itemLink then
            resolved = self:ResolveItemID(itemLink)
        end
        if resolved then
            ClearCursor()
            self:SetRowItem(row, resolved)
        end
    end
end

function FT:CreateRow(index)
    local row = CreateFrame("Frame", nil, self.listContent)
    row:SetHeight(ROW_HEIGHT)
    positionRow(row, index)

    row.itemButton = CreateFrame("Button", nil, row, "BackdropTemplate")
    row.itemButton:SetSize(ITEM_BUTTON_SIZE, ITEM_BUTTON_SIZE)
    row.itemButton:SetPoint("LEFT", 2, 0)
    row.itemButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-Quickslot2",
        edgeFile = "Interface\\Buttons\\UI-Quickslot2",
        tile = false,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })

    row.itemButton.icon = row.itemButton:CreateTexture(nil, "ARTWORK")
    row.itemButton.icon:SetAllPoints()
    row.itemButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.itemButton.qualityText = row.itemButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.itemButton.qualityText:SetPoint("BOTTOMRIGHT", -2, 2)
    row.itemButton.qualityText:SetJustifyH("RIGHT")
    row.itemButton.qualityText:Hide()

    row.itemButton:RegisterForClicks("LeftButtonUp")
    row.itemButton:RegisterForDrag("LeftButton")
    row.itemButton:SetScript("OnReceiveDrag", function()
        FT:HandleItemCursor(row)
    end)
    row.itemButton:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            FT:HandleItemCursor(row)
        end
    end)
    row.itemButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if row.data and row.data.itemID then
            if GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(row.data.itemID)
            else
                GameTooltip:SetHyperlink("item:" .. row.data.itemID)
            end
        else
            GameTooltip:AddLine("Drag an item here")
        end
        GameTooltip:Show()
    end)
    row.itemButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    row.itemIDBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.itemIDBox:SetSize(ITEM_ID_WIDTH, 20)
    row.itemIDBox:SetPoint("LEFT", row.itemButton, "RIGHT", 8, 0)
    row.itemIDBox:SetAutoFocus(false)
    row.itemIDBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        FT:CommitItemID(row)
    end)
    row.itemIDBox:SetScript("OnEditFocusLost", function()
        FT:CommitItemID(row)
    end)

    row.targetBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.targetBox:SetSize(TARGET_WIDTH, 20)
    row.targetBox:SetPoint("LEFT", row.itemIDBox, "RIGHT", 8, 0)
    row.targetBox:SetAutoFocus(false)
    row.targetBox:SetNumeric(true)
    row.targetBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        FT:CommitTarget(row)
    end)
    row.targetBox:SetScript("OnEditFocusLost", function()
        FT:CommitTarget(row)
    end)

    row.currentText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.currentText:SetWidth(CURRENT_WIDTH)
    row.currentText:SetJustifyH("LEFT")
    row.currentText:SetPoint("LEFT", row.targetBox, "RIGHT", 12, 0)

    row.removeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.removeButton:SetSize(22, 20)
    row.removeButton:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.removeButton:SetText("X")
    row.removeButton:SetScript("OnClick", function()
        if FT:IsAnyRunning() then
            return
        end
        table.remove(FT.db.items, row.index)
        FT:RefreshList(FT.MODES.TARGETS)
    end)

    self.rows[index] = row
    return row
end

function FT:UpdateRow(row)
    if not row or not row.data then
        return
    end

    local itemID = row.data.itemID
    if not row.itemIDBox:HasFocus() then
        row.itemIDBox:SetText(itemID and tostring(itemID) or "")
    end
    if not row.targetBox:HasFocus() then
        local target = tonumber(row.data.target)
        row.targetBox:SetText(target and target > 0 and tostring(target) or "")
    end

    if itemID then
        local name, link, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
        if icon then
            row.itemButton.icon:SetTexture(icon)
            row.itemButton.icon:SetDesaturated(false)
        else
            row.itemButton.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            row.itemButton.icon:SetDesaturated(false)
            self:RequestItemData(itemID)
        end
    else
        row.itemButton.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        row.itemButton.icon:SetDesaturated(true)
    end

    if row.itemButton.qualityText then
        if itemID then
            local tier = FT.GetQualityTier and FT:GetQualityTier(itemID) or nil
            if tier and tier > 0 then
                row.itemButton.qualityText:SetText(FT:GetQualityTierLabel(tier))
                local r, g, b = FT:GetQualityTierColor(tier)
                row.itemButton.qualityText:SetTextColor(r, g, b)
                row.itemButton.qualityText:Show()
            else
                row.itemButton.qualityText:SetText("")
                row.itemButton.qualityText:Hide()
            end
        else
            row.itemButton.qualityText:SetText("")
            row.itemButton.qualityText:Hide()
        end
    end

    local current = tonumber(row.data.current) or 0
    local target = tonumber(row.data.target) or 0
    local considerTargets = FT.db and FT.db.considerTargets ~= false
    if considerTargets and target > 0 then
        row.currentText:SetText(string.format("%d / %d", current, target))
        if current >= target then
            row.currentText:SetTextColor(0.2, 1.0, 0.2)
        else
            row.currentText:SetTextColor(1, 1, 1)
        end
    elseif itemID then
        row.currentText:SetText(string.format("%d", current))
        row.currentText:SetTextColor(1, 1, 1)
    else
        row.currentText:SetText("-")
        row.currentText:SetTextColor(0.7, 0.7, 0.7)
    end
end

function FT:CreateAllRow(index)
    local row = CreateFrame("Frame", nil, self.allListContent)
    row:SetHeight(ROW_HEIGHT)
    positionRow(row, index)

    row.itemButton = CreateFrame("Button", nil, row, "BackdropTemplate")
    row.itemButton:SetSize(ITEM_BUTTON_SIZE, ITEM_BUTTON_SIZE)
    row.itemButton:SetPoint("LEFT", 2, 0)
    row.itemButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-Quickslot2",
        edgeFile = "Interface\\Buttons\\UI-Quickslot2",
        tile = false,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })

    row.itemButton.icon = row.itemButton:CreateTexture(nil, "ARTWORK")
    row.itemButton.icon:SetAllPoints()
    row.itemButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.itemButton.qualityText = row.itemButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.itemButton.qualityText:SetPoint("BOTTOMRIGHT", -2, 2)
    row.itemButton.qualityText:SetJustifyH("RIGHT")
    row.itemButton.qualityText:Hide()

    row.itemButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if row.data and row.data.itemID then
            if GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(row.data.itemID)
            else
                GameTooltip:SetHyperlink("item:" .. row.data.itemID)
            end
        else
            GameTooltip:AddLine("Item data not available")
        end
        GameTooltip:Show()
    end)
    row.itemButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.nameText:SetWidth(ALL_NAME_WIDTH)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetPoint("LEFT", row.itemButton, "RIGHT", 8, 0)

    row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.countText:SetWidth(ALL_COUNT_WIDTH)
    row.countText:SetJustifyH("RIGHT")
    row.countText:SetPoint("LEFT", row.nameText, "RIGHT", 12, 0)

    row.unitText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.unitText:SetWidth(ALL_UNIT_WIDTH)
    row.unitText:SetJustifyH("RIGHT")
    row.unitText:SetPoint("LEFT", row.countText, "RIGHT", 12, 0)

    row.totalText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.totalText:SetWidth(ALL_TOTAL_WIDTH)
    row.totalText:SetJustifyH("RIGHT")
    row.totalText:SetPoint("LEFT", row.unitText, "RIGHT", 12, 0)

    self.allRows[index] = row
    return row
end

function FT:UpdateAllRow(row)
    if not row or not row.data then
        return
    end

    local itemID = row.data.itemID
    if itemID then
        local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
        if icon then
            row.itemButton.icon:SetTexture(icon)
            row.itemButton.icon:SetDesaturated(false)
        else
            row.itemButton.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            row.itemButton.icon:SetDesaturated(false)
            self:RequestItemData(itemID)
        end

        if row.itemButton.qualityText then
            local tier = FT.GetQualityTier and FT:GetQualityTier(itemID) or nil
            if tier and tier > 0 then
                row.itemButton.qualityText:SetText(FT:GetQualityTierLabel(tier))
                local r, g, b = FT:GetQualityTierColor(tier)
                row.itemButton.qualityText:SetTextColor(r, g, b)
                row.itemButton.qualityText:Show()
            else
                row.itemButton.qualityText:SetText("")
                row.itemButton.qualityText:Hide()
            end
        end

        row.nameText:SetText(name or ("Item " .. itemID))
    else
        row.itemButton.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        row.itemButton.icon:SetDesaturated(true)
        row.itemButton.qualityText:SetText("")
        row.itemButton.qualityText:Hide()
        row.nameText:SetText("-")
        row.unitText:SetText("-")
        row.totalText:SetText("-")
        row.unitText:SetTextColor(0.7, 0.7, 0.7)
        row.totalText:SetTextColor(0.7, 0.7, 0.7)
    end

    local current = tonumber(row.data.current) or 0
    row.countText:SetText(string.format("%d", current))
    if current > 0 then
        row.countText:SetTextColor(0.2, 1.0, 0.2)
    elseif current < 0 then
        row.countText:SetTextColor(1.0, 0.2, 0.2)
    else
        row.countText:SetTextColor(1, 1, 1)
    end

    local unitPrice, auctionable = FT:GetCachedPrice(itemID)
    if unitPrice then
        row.unitText:SetText(FT:FormatMoney(unitPrice))
        local total = unitPrice * current
        row.totalText:SetText(FT:FormatMoney(total))
        local color = current < 0 and { 1.0, 0.2, 0.2 } or { 0.2, 1.0, 0.2 }
        row.totalText:SetTextColor(color[1], color[2], color[3])
        row.unitText:SetTextColor(1, 1, 1)
    else
        if auctionable == false then
            row.unitText:SetText("N/A")
            row.totalText:SetText("N/A")
        else
            row.unitText:SetText("—")
            row.totalText:SetText("—")
        end
        row.unitText:SetTextColor(0.7, 0.7, 0.7)
        row.totalText:SetTextColor(0.7, 0.7, 0.7)
    end
end

function FT:UpdateAllRows()
    if not self.db or not self.allListContent then
        return
    end

    local items = self.db.allItems or {}
    for i, item in ipairs(items) do
        local row = self.allRows[i] or self:CreateAllRow(i)
        row.index = i
        row.data = item
        positionRow(row, i)
        row:Show()
        self:UpdateAllRow(row)
    end

    for i = #items + 1, #self.allRows do
        self.allRows[i]:Hide()
    end

    local height = math.max(1, #items * ROW_HEIGHT)
    self.allListContent:SetHeight(height)
end

function FT:UpdateRows(mode)
    mode = mode or self:GetActiveMode()
    if mode == self.MODES.ALL then
        self:UpdateAllRows()
        return
    end

    if not self.db or not self.listContent then
        return
    end

    local items = self.db.items
    for i, item in ipairs(items) do
        local row = self.rows[i] or self:CreateRow(i)
        row.index = i
        row.data = item
        positionRow(row, i)
        row:Show()
        self:UpdateRow(row)
    end

    for i = #items + 1, #self.rows do
        self.rows[i]:Hide()
    end

    local height = math.max(1, #items * ROW_HEIGHT)
    self.listContent:SetHeight(height)
end

function FT:UpdateSummary(mode, completed, valid)
    if not self.frame or not self.frame.statusText then
        return
    end
    mode = mode or self:GetActiveMode()
    if mode == self.MODES.ALL then
        local items = (self.db and self.db.allItems) or {}
        if #items == 0 then
            self.frame.statusText:SetText("No items collected")
        else
            local total, pricedCount, totalCount = FT:GetAllItemsTotalValue()
            local status = string.format("Tracking %d items", #items)
            if total then
                status = string.format("%s | AH Total: %s", status, FT:FormatMoney(total))
            else
                status = string.format("%s | AH Total: —", status)
            end
            if totalCount > 0 and pricedCount < totalCount then
                status = status .. " (partial)"
            end
            if not FT.ahScanReady then
                status = status .. " | Open Auction House to scan reagents"
            end
            self.frame.statusText:SetText(status)
        end
        return
    end

    completed = tonumber(completed) or 0
    valid = tonumber(valid) or 0
    local considerTargets = self.db and self.db.considerTargets ~= false
    if valid == 0 then
        if considerTargets then
            self.frame.statusText:SetText("No target amounts set")
        else
            self.frame.statusText:SetText("No items configured")
        end
        return
    end
    if considerTargets then
        self.frame.statusText:SetText(string.format("%d / %d items completed", completed, valid))
    else
        self.frame.statusText:SetText(string.format("Tracking %d items", valid))
    end
end

function FT:UpdateControls(mode)
    if not self.frame then
        return
    end

    if not mode then
        self:UpdateControls(self.MODES.TARGETS)
        self:UpdateControls(self.MODES.ALL)
        if self.UpdateTabs then
            self:UpdateTabs()
        end
        return
    end

    local runningMode = self:GetRunningMode()
    local state = self:GetModeState(mode)
    local isRunning = state.running
    local isPaused = state.paused
    local isLocked = runningMode and runningMode ~= mode

    local content = (mode == self.MODES.ALL) and self.frame.allItemsContent or self.frame.targetsContent
    if not content then
        return
    end

    if content.startButton then
        content.startButton:SetText(isPaused and "Resume" or "Start")
        content.startButton:SetEnabled(not isLocked and (not isRunning or isPaused))
    end
    if content.pauseButton then
        content.pauseButton:SetEnabled(not isLocked and isRunning and not isPaused)
    end
    if content.stopButton then
        content.stopButton:SetEnabled(not isLocked and isRunning)
    end
    if content.resetButton then
        content.resetButton:SetEnabled(not isLocked and not isRunning)
    end

    if mode == self.MODES.TARGETS then
        if content.addButton then
            content.addButton:SetEnabled(not isLocked and not isRunning)
        end

        if content.presetDropdown then
            if isLocked or isRunning then
                UIDropDownMenu_DisableDropDown(content.presetDropdown)
            else
                UIDropDownMenu_EnableDropDown(content.presetDropdown)
            end
        end
        if content.presetNameBox then
            setEditBoxEnabled(content.presetNameBox, not isLocked and not isRunning)
        end
        if content.presetSaveButton then
            content.presetSaveButton:SetEnabled(not isLocked and not isRunning)
        end
        if content.presetLoadButton then
            content.presetLoadButton:SetEnabled(not isLocked and not isRunning)
        end
        if content.presetDeleteButton then
            content.presetDeleteButton:SetEnabled(not isLocked and not isRunning)
        end
        if content.targetCheck then
            content.targetCheck:SetEnabled(not isLocked and not isRunning)
            if content.targetCheckLabel then
                if isLocked or isRunning then
                    content.targetCheckLabel:SetTextColor(0.6, 0.6, 0.6)
                else
                    content.targetCheckLabel:SetTextColor(1, 1, 1)
                end
            end
        end
        if content.profilesButton then
            content.profilesButton:SetEnabled(not isLocked and not isRunning)
        end
        if self.profilesFrame then
            if self.profilesFrame.exportAllButton then
                self.profilesFrame.exportAllButton:SetEnabled(not isLocked and not isRunning)
            end
            if self.profilesFrame.exportSelectedButton then
                self.profilesFrame.exportSelectedButton:SetEnabled(not isLocked and not isRunning)
            end
            if self.profilesFrame.importButton then
                self.profilesFrame.importButton:SetEnabled(not isLocked and not isRunning)
            end
            if self.profilesFrame.mergeCheck then
                self.profilesFrame.mergeCheck:SetEnabled(not isLocked and not isRunning)
            end
        end

        for _, row in ipairs(self.rows) do
            row.itemButton:SetEnabled(not isLocked and not isRunning)
            row.removeButton:SetEnabled(not isLocked and not isRunning)
            setEditBoxEnabled(row.itemIDBox, not isLocked and not isRunning)
            setEditBoxEnabled(row.targetBox, not isLocked and not isRunning)
        end
    end
end

function FT:ShowScanProgress(progress, text)
    if not self.frame or not self.frame.scanBar then
        return
    end
    if progress == nil then
        self.frame.scanBar:Hide()
        self.frame.scanText:SetText("")
        return
    end
    self.frame.scanBar:Show()
    self.frame.scanBar:SetValue(math.max(0, math.min(1, progress)))
    if text then
        self.frame.scanText:SetText(text)
    end
end

function FT:UpdateTabs()
    if not self.frame or not self.frame.tabs then
        return
    end
    local runningMode = self:GetRunningMode()
    for _, tab in ipairs(self.frame.tabs) do
        if runningMode and runningMode ~= tab.mode then
            tab:SetEnabled(false)
        else
            tab:SetEnabled(true)
        end
    end
    local active = self:GetActiveMode()
    local activeId = active == self.MODES.ALL and 2 or 1
    PanelTemplates_SetTab(self.frame, activeId)
end

function FT:ActivateMode(mode)
    local runningMode = self:GetRunningMode()
    if runningMode and runningMode ~= mode then
        self:Print("Stop the other mode before switching tabs.")
        return
    end
    self:SetActiveMode(mode)
    mode = self:GetActiveMode()
    if self.frame and self.frame.targetsContent then
        self.frame.targetsContent:SetShown(mode == self.MODES.TARGETS)
    end
    if self.frame and self.frame.allItemsContent then
        self.frame.allItemsContent:SetShown(mode == self.MODES.ALL)
    end
    self:UpdateTabs()
    self:RefreshProgress(mode)
    self:UpdateTimer(mode)
    self:UpdateControls()
end

function FT:RefreshList(mode)
    if not self.db then
        return
    end
    mode = mode or self:GetActiveMode()
    if mode == self.MODES.ALL then
        self.db.allItems = self.db.allItems or {}
    else
        self.db.items = self.db.items or {}
    end
    self:RefreshProgress(mode)
end

function FT:InitUI()
    if self.frame then
        return
    end

    local frame = CreateFrame("Frame", "FarmingTimerFrame", UIParent, "BackdropTemplate")
    local height = self.db.frame.height or FRAME_HEIGHT
    height = math.max(FRAME_MIN_HEIGHT, math.min(height, FRAME_MAX_HEIGHT))
    frame:SetSize(FRAME_WIDTH, height)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        FT:SaveFramePosition()
    end)
    frame:SetClampedToScreen(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(FRAME_WIDTH, FRAME_MIN_HEIGHT, FRAME_WIDTH, FRAME_MAX_HEIGHT)
    else
        frame:SetMinResize(FRAME_WIDTH, FRAME_MIN_HEIGHT)
        frame:SetMaxResize(FRAME_WIDTH, FRAME_MAX_HEIGHT)
    end
    frame:SetScript("OnSizeChanged", function(self, width, height)
        if width and math.abs(width - FRAME_WIDTH) > 0.5 then
            self:SetWidth(FRAME_WIDTH)
        end
        FT:SaveFrameSize()
    end)

    frame:SetScript("OnShow", function()
        if FT.db then
            FT.db.visible = true
        end
    end)
    frame:SetScript("OnHide", function()
        if FT.db then
            FT.db.visible = false
        end
    end)

    self.frame = frame
    self.rows = {}
    self.allRows = {}

    local point = self.db.frame.point or "CENTER"
    local x = self.db.frame.x or 0
    local y = self.db.frame.y or 0
    frame:SetPoint(point, UIParent, point, x, y)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("FarmingTimer")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -6, -6)

    local resizeHandle = CreateFrame("Button", nil, frame)
    resizeHandle:SetSize(16, 16)
    resizeHandle:SetPoint("BOTTOMRIGHT", -6, 6)
    resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeHandle:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then
            return
        end
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeHandle:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then
            return
        end
        frame:StopMovingOrSizing()
        FT:SaveFrameSize()
    end)

    frame.timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.timerText:SetPoint("TOP", title, "BOTTOM", 0, -8)
    frame.timerText:SetText("00:00")

    frame.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.statusText:SetPoint("TOP", frame.timerText, "BOTTOM", 0, -6)
    frame.statusText:SetText("No items configured")

    local scanBar = CreateFrame("StatusBar", nil, frame)
    scanBar:SetSize(240, 12)
    scanBar:SetPoint("TOP", frame.statusText, "BOTTOM", 0, -6)
    scanBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    scanBar:GetStatusBarTexture():SetHorizTile(false)
    scanBar:GetStatusBarTexture():SetVertTile(false)
    scanBar:SetMinMaxValues(0, 1)
    scanBar:SetValue(0)
    scanBar:Hide()

    local scanBg = scanBar:CreateTexture(nil, "BACKGROUND")
    scanBg:SetAllPoints(true)
    scanBg:SetColorTexture(0, 0, 0, 0.5)

    local scanText = scanBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scanText:SetPoint("CENTER", scanBar, "CENTER", 0, 0)
    scanText:SetText("")

    frame.scanBar = scanBar
    frame.scanText = scanText

    local farmingContent = CreateFrame("Frame", nil, frame)
    farmingContent:SetAllPoints(frame)
    frame.farmingContent = farmingContent
    frame.targetsContent = farmingContent

    local targetCheck = CreateFrame("CheckButton", nil, farmingContent, "UICheckButtonTemplate")
    targetCheck:SetPoint("TOPLEFT", farmingContent, "TOPLEFT", 18, -72)
    targetCheck:SetChecked(self.db.considerTargets ~= false)
    local targetLabel = targetCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    targetLabel:SetPoint("LEFT", targetCheck, "RIGHT", 4, 0)
    targetLabel:SetText("Use target amounts")
    targetCheck:SetScript("OnClick", function(self)
        if not FT.db then
            return
        end
        FT.db.considerTargets = self:GetChecked()
        FT:RefreshProgress(FT.MODES.TARGETS)
        FT:UpdateControls()
    end)

    local presetRow = CreateFrame("Frame", nil, farmingContent)
    presetRow:SetPoint("TOPLEFT", 18, -96)
    presetRow:SetPoint("TOPRIGHT", -18, -96)
    presetRow:SetHeight(26)

    local presetLabel = presetRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    presetLabel:SetPoint("LEFT", 2, 0)
    presetLabel:SetText("Preset")

    local presetDropdown = CreateFrame("Frame", "FarmingTimerPresetDropDown", presetRow, "UIDropDownMenuTemplate")
    presetDropdown:SetPoint("LEFT", presetLabel, "RIGHT", -6, -2)
    UIDropDownMenu_SetWidth(presetDropdown, 90)
    UIDropDownMenu_SetText(presetDropdown, "Select")

    local presetNameBox

    local deleteButton = CreateFrame("Button", nil, presetRow, "UIPanelButtonTemplate")
    deleteButton:SetSize(46, 20)
    deleteButton:SetPoint("RIGHT", presetRow, "RIGHT", -2, 0)
    deleteButton:SetText("Delete")
    deleteButton:SetScript("OnClick", function()
        FT:DeletePreset(presetNameBox:GetText())
    end)

    local loadButton = CreateFrame("Button", nil, presetRow, "UIPanelButtonTemplate")
    loadButton:SetSize(46, 20)
    loadButton:SetPoint("RIGHT", deleteButton, "LEFT", -6, 0)
    loadButton:SetText("Load")
    loadButton:SetScript("OnClick", function()
        FT:LoadPreset(presetNameBox:GetText())
    end)

    local saveButton = CreateFrame("Button", nil, presetRow, "UIPanelButtonTemplate")
    saveButton:SetSize(46, 20)
    saveButton:SetPoint("RIGHT", loadButton, "LEFT", -6, 0)
    saveButton:SetText("Save")
    saveButton:SetScript("OnClick", function()
        FT:SavePreset(presetNameBox:GetText())
    end)

    presetNameBox = CreateFrame("EditBox", nil, presetRow, "InputBoxTemplate")
    presetNameBox:SetSize(90, 20)
    presetNameBox:SetPoint("RIGHT", saveButton, "LEFT", -8, 0)
    presetNameBox:SetAutoFocus(false)

    frame.presetDropdown = presetDropdown
    frame.presetNameBox = presetNameBox
    frame.presetSaveButton = saveButton
    frame.presetLoadButton = loadButton
    frame.presetDeleteButton = deleteButton
    frame.targetCheck = targetCheck
    frame.targetCheckLabel = targetLabel

    local profilesButton = CreateFrame("Button", nil, farmingContent, "UIPanelButtonTemplate")
    profilesButton:SetSize(80, 22)
    profilesButton:SetPoint("TOPRIGHT", farmingContent, "TOPRIGHT", -18, -68)
    profilesButton:SetText("Profiles")
    profilesButton:SetScript("OnClick", function()
        FT:ShowProfilesWindow()
    end)
    frame.profilesButton = profilesButton

    local header = CreateFrame("Frame", nil, farmingContent)
    header:SetPoint("TOPLEFT", 18, -132)
    header:SetPoint("TOPRIGHT", -34, -132)
    header:SetHeight(16)

    local headerItem = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerItem:SetPoint("LEFT", 2, 0)
    headerItem:SetText("Item")

    local headerID = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerID:SetPoint("LEFT", header, "LEFT", 2 + ITEM_BUTTON_SIZE + 8, 0)
    headerID:SetText("ItemID / Link")

    local headerTarget = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerTarget:SetPoint("LEFT", header, "LEFT", 2 + ITEM_BUTTON_SIZE + 8 + ITEM_ID_WIDTH + 8, 0)
    headerTarget:SetText("Target")

    local headerCurrent = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerCurrent:SetPoint("LEFT", header, "LEFT", 2 + ITEM_BUTTON_SIZE + 8 + ITEM_ID_WIDTH + 8 + TARGET_WIDTH + 12, 0)
    headerCurrent:SetText("Progress")

    local scrollFrame = CreateFrame("ScrollFrame", nil, farmingContent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 18, -150)
    scrollFrame:SetPoint("BOTTOMRIGHT", -34, 54)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    scrollFrame:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(width)
    end)
    content:SetWidth(scrollFrame:GetWidth())

    self.listScrollFrame = scrollFrame
    self.listContent = content

    frame.addButton = CreateFrame("Button", nil, farmingContent, "UIPanelButtonTemplate")
    frame.addButton:SetSize(90, 22)
    frame.addButton:SetPoint("BOTTOMLEFT", 18, 18)
    frame.addButton:SetText("Add Item")
    frame.addButton:SetScript("OnClick", function()
        if FT:IsAnyRunning() then
            return
        end
        table.insert(FT.db.items, { itemID = nil, target = 0 })
        FT:RefreshList(FT.MODES.TARGETS)
    end)

    frame.startButton = CreateFrame("Button", nil, farmingContent, "UIPanelButtonTemplate")
    frame.startButton:SetSize(70, 22)
    frame.startButton:SetPoint("LEFT", frame.addButton, "RIGHT", 12, 0)
    frame.startButton:SetText("Start")
    frame.startButton:SetScript("OnClick", function()
        FT:StartRun(FT.MODES.TARGETS)
    end)

    frame.pauseButton = CreateFrame("Button", nil, farmingContent, "UIPanelButtonTemplate")
    frame.pauseButton:SetSize(70, 22)
    frame.pauseButton:SetPoint("LEFT", frame.startButton, "RIGHT", 12, 0)
    frame.pauseButton:SetText("Pause")
    frame.pauseButton:SetScript("OnClick", function()
        FT:PauseRun(FT.MODES.TARGETS)
    end)

    frame.stopButton = CreateFrame("Button", nil, farmingContent, "UIPanelButtonTemplate")
    frame.stopButton:SetSize(70, 22)
    frame.stopButton:SetPoint("LEFT", frame.pauseButton, "RIGHT", 12, 0)
    frame.stopButton:SetText("Stop")
    frame.stopButton:SetScript("OnClick", function()
        FT:StopRun(FT.MODES.TARGETS)
    end)

    frame.resetButton = CreateFrame("Button", nil, farmingContent, "UIPanelButtonTemplate")
    frame.resetButton:SetSize(70, 22)
    frame.resetButton:SetPoint("LEFT", frame.stopButton, "RIGHT", 12, 0)
    frame.resetButton:SetText("Reset")
    frame.resetButton:SetScript("OnClick", function()
        FT:ResetRun(FT.MODES.TARGETS)
    end)

    farmingContent.addButton = frame.addButton
    farmingContent.startButton = frame.startButton
    farmingContent.pauseButton = frame.pauseButton
    farmingContent.stopButton = frame.stopButton
    farmingContent.resetButton = frame.resetButton
    farmingContent.presetDropdown = presetDropdown
    farmingContent.presetNameBox = presetNameBox
    farmingContent.presetSaveButton = saveButton
    farmingContent.presetLoadButton = loadButton
    farmingContent.presetDeleteButton = deleteButton
    farmingContent.targetCheck = targetCheck
    farmingContent.targetCheckLabel = targetLabel
    farmingContent.profilesButton = profilesButton

    local allItemsContent = CreateFrame("Frame", nil, frame)
    allItemsContent:SetAllPoints(frame)
    allItemsContent:Hide()
    frame.allItemsContent = allItemsContent

    local allHeader = CreateFrame("Frame", nil, allItemsContent)
    allHeader:SetPoint("TOPLEFT", 18, -88)
    allHeader:SetPoint("TOPRIGHT", -34, -88)
    allHeader:SetHeight(16)

    local allHeaderItem = allHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    allHeaderItem:SetPoint("LEFT", 2, 0)
    allHeaderItem:SetText("Item")

    local allHeaderName = allHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    allHeaderName:SetPoint("LEFT", allHeader, "LEFT", 2 + ITEM_BUTTON_SIZE + 8, 0)
    allHeaderName:SetText("Name")

    local allHeaderCount = allHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    allHeaderCount:SetPoint("LEFT", allHeader, "LEFT", 2 + ITEM_BUTTON_SIZE + 8 + ALL_NAME_WIDTH + 12, 0)
    allHeaderCount:SetText("Count")

    local allHeaderUnit = allHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    allHeaderUnit:SetPoint("LEFT", allHeader, "LEFT", 2 + ITEM_BUTTON_SIZE + 8 + ALL_NAME_WIDTH + 12 + ALL_COUNT_WIDTH + 12, 0)
    allHeaderUnit:SetText("Unit")

    local allHeaderTotal = allHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    allHeaderTotal:SetPoint("LEFT", allHeader, "LEFT", 2 + ITEM_BUTTON_SIZE + 8 + ALL_NAME_WIDTH + 12 + ALL_COUNT_WIDTH + 12 + ALL_UNIT_WIDTH + 12, 0)
    allHeaderTotal:SetText("Total")

    local allScrollFrame = CreateFrame("ScrollFrame", nil, allItemsContent, "UIPanelScrollFrameTemplate")
    allScrollFrame:SetPoint("TOPLEFT", 18, -106)
    allScrollFrame:SetPoint("BOTTOMRIGHT", -34, 54)

    local allContent = CreateFrame("Frame", nil, allScrollFrame)
    allContent:SetSize(1, 1)
    allScrollFrame:SetScrollChild(allContent)
    allScrollFrame:SetScript("OnSizeChanged", function(_, width)
        allContent:SetWidth(width)
    end)
    allContent:SetWidth(allScrollFrame:GetWidth())

    self.allListScrollFrame = allScrollFrame
    self.allListContent = allContent

    local allStartButton = CreateFrame("Button", nil, allItemsContent, "UIPanelButtonTemplate")
    allStartButton:SetSize(70, 22)
    allStartButton:SetPoint("BOTTOMLEFT", 18, 18)
    allStartButton:SetText("Start")
    allStartButton:SetScript("OnClick", function()
        FT:StartRun(FT.MODES.ALL)
    end)

    local allPauseButton = CreateFrame("Button", nil, allItemsContent, "UIPanelButtonTemplate")
    allPauseButton:SetSize(70, 22)
    allPauseButton:SetPoint("LEFT", allStartButton, "RIGHT", 12, 0)
    allPauseButton:SetText("Pause")
    allPauseButton:SetScript("OnClick", function()
        FT:PauseRun(FT.MODES.ALL)
    end)

    local allStopButton = CreateFrame("Button", nil, allItemsContent, "UIPanelButtonTemplate")
    allStopButton:SetSize(70, 22)
    allStopButton:SetPoint("LEFT", allPauseButton, "RIGHT", 12, 0)
    allStopButton:SetText("Stop")
    allStopButton:SetScript("OnClick", function()
        FT:StopRun(FT.MODES.ALL)
    end)

    local allResetButton = CreateFrame("Button", nil, allItemsContent, "UIPanelButtonTemplate")
    allResetButton:SetSize(70, 22)
    allResetButton:SetPoint("LEFT", allStopButton, "RIGHT", 12, 0)
    allResetButton:SetText("Reset")
    allResetButton:SetScript("OnClick", function()
        FT:ResetRun(FT.MODES.ALL)
    end)

    allItemsContent.startButton = allStartButton
    allItemsContent.pauseButton = allPauseButton
    allItemsContent.stopButton = allStopButton
    allItemsContent.resetButton = allResetButton

    frame.tabs = {}

    local tabTargets = CreateFrame("Button", "FarmingTimerFrameTab1", frame, "PanelTabButtonTemplate")
    tabTargets:SetID(1)
    tabTargets:SetText("Targets")
    tabTargets.mode = FT.MODES.TARGETS
    tabTargets:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, -2)
    tabTargets:SetScript("OnClick", function(self)
        FT:ActivateMode(self.mode)
    end)
    tabTargets:SetFrameLevel(frame:GetFrameLevel() + 2)
    PanelTemplates_TabResize(tabTargets, 0)
    tabTargets:Show()
    frame.tabs[1] = tabTargets

    local tabAll = CreateFrame("Button", "FarmingTimerFrameTab2", frame, "PanelTabButtonTemplate")
    tabAll:SetID(2)
    tabAll:SetText("All Items")
    tabAll.mode = FT.MODES.ALL
    tabAll:SetPoint("LEFT", tabTargets, "RIGHT", -16, 0)
    tabAll:SetScript("OnClick", function(self)
        FT:ActivateMode(self.mode)
    end)
    tabAll:SetFrameLevel(frame:GetFrameLevel() + 2)
    PanelTemplates_TabResize(tabAll, 0)
    tabAll:Show()
    frame.tabs[2] = tabAll

    PanelTemplates_SetNumTabs(frame, 2)

    self:RefreshList(FT.MODES.TARGETS)
    self:UpdateControls()
    self:RefreshPresetDropdown()
    self:ActivateMode(self:GetActiveMode())

    if self.db.visible then
        frame:Show()
    else
        frame:Hide()
    end
end
