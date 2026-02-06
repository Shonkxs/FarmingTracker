local ADDON_NAME, FT = ...

local ROW_HEIGHT = 28
local ITEM_BUTTON_SIZE = 24
local ITEM_ID_WIDTH = 150
local TARGET_WIDTH = 60
local CURRENT_WIDTH = 90

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
                FT:SetSelectedPreset(name)
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

function FT:ShowTransferFrame(mode, payload)
    if not self.transferFrame then
        self:CreateTransferFrame()
    end
    local frame = self.transferFrame
    frame.mode = mode
    if mode == "import" then
        frame.title:SetText("Import Presets")
        frame.actionButton:SetText("Import")
        frame.actionButton:Show()
        frame.mergeCheck:Show()
        frame.mergeCheck:SetChecked(true)
        frame.editBox:SetText("")
    else
        frame.title:SetText("Export Presets")
        frame.actionButton:Hide()
        frame.mergeCheck:Hide()
        frame.editBox:SetText(payload or "")
    end

    if frame.updateTransferBoxSize then
        frame.updateTransferBoxSize()
    end
    frame.editBox:HighlightText()
    frame.editBox:SetFocus()
    frame:Show()
end

function FT:CreateTransferFrame()
    if self.transferFrame then
        return
    end

    local frame = CreateFrame("Frame", "FarmingTimerTransferFrame", UIParent, "BackdropTemplate")
    frame:SetSize(420, 230)
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
    title:SetText("Export Presets")
    frame.title = title

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -6, -6)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 16, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 56)

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

    local function updateTransferBoxSize()
        local width = scrollFrame:GetWidth()
        local height = scrollFrame:GetHeight()
        if width and width > 0 then
            scrollChild:SetWidth(width)
        end
        if height and height > 0 then
            scrollChild:SetHeight(height)
        end
    end

    scrollFrame:SetScript("OnSizeChanged", updateTransferBoxSize)
    frame:SetScript("OnShow", function()
        updateTransferBoxSize()
    end)

    local mergeCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    mergeCheck:SetPoint("BOTTOMLEFT", 16, 18)
    local mergeLabel = mergeCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mergeLabel:SetPoint("LEFT", mergeCheck, "RIGHT", 4, 0)
    mergeLabel:SetText("Merge (do not overwrite)")

    local actionButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    actionButton:SetSize(80, 22)
    actionButton:SetPoint("BOTTOMRIGHT", -16, 16)
    actionButton:SetText("Import")
    actionButton:SetScript("OnClick", function()
        FT:ImportPresets(editBox:GetText(), mergeCheck:GetChecked())
        frame:Hide()
    end)

    frame.editBox = editBox
    frame.updateTransferBoxSize = updateTransferBoxSize
    frame.mergeCheck = mergeCheck
    frame.actionButton = actionButton

    self.transferFrame = frame
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
    self:RefreshProgress()
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
    self:RefreshProgress()
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
    self:RefreshProgress()
end

function FT:HandleItemCursor(row)
    if self.running then
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
        if FT.running then
            return
        end
        table.remove(FT.db.items, row.index)
        FT:RefreshList()
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

function FT:UpdateRows()
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

function FT:UpdateSummary(completed, valid)
    if not self.frame or not self.frame.statusText then
        return
    end
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

function FT:UpdateControls()
    if not self.frame then
        return
    end

    local isRunning = self.running
    local isPaused = self.paused

    if isPaused then
        self.frame.startButton:SetText("Resume")
    else
        self.frame.startButton:SetText("Start")
    end

    self.frame.startButton:SetEnabled(not isRunning or isPaused)
    self.frame.pauseButton:SetEnabled(isRunning and not isPaused)
    self.frame.stopButton:SetEnabled(isRunning)
    self.frame.resetButton:SetEnabled(not isRunning)
    self.frame.addButton:SetEnabled(not isRunning)

    if self.frame.presetDropdown then
        if isRunning then
            UIDropDownMenu_DisableDropDown(self.frame.presetDropdown)
        else
            UIDropDownMenu_EnableDropDown(self.frame.presetDropdown)
        end
    end
    if self.frame.presetNameBox then
        setEditBoxEnabled(self.frame.presetNameBox, not isRunning)
    end
    if self.frame.presetSaveButton then
        self.frame.presetSaveButton:SetEnabled(not isRunning)
    end
    if self.frame.presetLoadButton then
        self.frame.presetLoadButton:SetEnabled(not isRunning)
    end
    if self.frame.presetDeleteButton then
        self.frame.presetDeleteButton:SetEnabled(not isRunning)
    end
    if self.frame.targetCheck then
        self.frame.targetCheck:SetEnabled(not isRunning)
        if self.frame.targetCheckLabel then
            if isRunning then
                self.frame.targetCheckLabel:SetTextColor(0.6, 0.6, 0.6)
            else
                self.frame.targetCheckLabel:SetTextColor(1, 1, 1)
            end
        end
    end
    if self.frame.exportAllButton then
        self.frame.exportAllButton:SetEnabled(not isRunning)
    end
    if self.frame.exportSelectedButton then
        self.frame.exportSelectedButton:SetEnabled(not isRunning)
    end
    if self.frame.importButton then
        self.frame.importButton:SetEnabled(not isRunning)
    end

    for _, row in ipairs(self.rows) do
        row.itemButton:SetEnabled(not isRunning)
        row.removeButton:SetEnabled(not isRunning)
        setEditBoxEnabled(row.itemIDBox, not isRunning)
        setEditBoxEnabled(row.targetBox, not isRunning)
    end
end

function FT:RefreshList()
    if not self.db then
        return
    end
    self.db.items = self.db.items or {}
    self:RefreshProgress()
end

function FT:InitUI()
    if self.frame then
        return
    end

    local frame = CreateFrame("Frame", "FarmingTimerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(460, 360)
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

    local point = self.db.frame.point or "CENTER"
    local x = self.db.frame.x or 0
    local y = self.db.frame.y or 0
    frame:SetPoint(point, UIParent, point, x, y)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("FarmingTimer")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -6, -6)

    frame.timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.timerText:SetPoint("TOP", title, "BOTTOM", 0, -8)
    frame.timerText:SetText("00:00")

    frame.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.statusText:SetPoint("TOP", frame.timerText, "BOTTOM", 0, -6)
    frame.statusText:SetText("No items configured")

    local targetCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    targetCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -72)
    targetCheck:SetChecked(self.db.considerTargets ~= false)
    local targetLabel = targetCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    targetLabel:SetPoint("LEFT", targetCheck, "RIGHT", 4, 0)
    targetLabel:SetText("Use target amounts")
    targetCheck:SetScript("OnClick", function(self)
        if not FT.db then
            return
        end
        FT.db.considerTargets = self:GetChecked()
        FT:RefreshProgress()
        FT:UpdateControls()
    end)

    local presetRow = CreateFrame("Frame", nil, frame)
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

    local transferRow = CreateFrame("Frame", nil, frame)
    transferRow:SetPoint("TOPLEFT", 18, -122)
    transferRow:SetPoint("TOPRIGHT", -18, -122)
    transferRow:SetHeight(22)

    local transferLabel = transferRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    transferLabel:SetPoint("LEFT", 2, 0)
    transferLabel:SetText("Transfer")

    local exportAllButton = CreateFrame("Button", nil, transferRow, "UIPanelButtonTemplate")
    exportAllButton:SetSize(78, 20)
    exportAllButton:SetPoint("RIGHT", transferRow, "RIGHT", -2, 0)
    exportAllButton:SetText("Export All")
    exportAllButton:SetScript("OnClick", function()
        FT:ShowExportDialog()
    end)

    local exportSelectedButton = CreateFrame("Button", nil, transferRow, "UIPanelButtonTemplate")
    exportSelectedButton:SetSize(96, 20)
    exportSelectedButton:SetPoint("RIGHT", exportAllButton, "LEFT", -6, 0)
    exportSelectedButton:SetText("Export Selected")
    exportSelectedButton:SetScript("OnClick", function()
        local name = FT:GetSelectedPresetName()
        if not name then
            FT:Print("Please select a preset.")
            return
        end
        FT:ShowExportDialog(name)
    end)

    local importButton = CreateFrame("Button", nil, transferRow, "UIPanelButtonTemplate")
    importButton:SetSize(60, 20)
    importButton:SetPoint("RIGHT", exportSelectedButton, "LEFT", -6, 0)
    importButton:SetText("Import")
    importButton:SetScript("OnClick", function()
        FT:ShowImportDialog()
    end)

    frame.exportAllButton = exportAllButton
    frame.exportSelectedButton = exportSelectedButton
    frame.importButton = importButton

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 18, -156)
    header:SetPoint("TOPRIGHT", -34, -156)
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

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 18, -174)
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

    frame.addButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.addButton:SetSize(90, 22)
    frame.addButton:SetPoint("BOTTOMLEFT", 18, 18)
    frame.addButton:SetText("Add Item")
    frame.addButton:SetScript("OnClick", function()
        if FT.running then
            return
        end
        table.insert(FT.db.items, { itemID = nil, target = 0 })
        FT:RefreshList()
    end)

    frame.startButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.startButton:SetSize(70, 22)
    frame.startButton:SetPoint("LEFT", frame.addButton, "RIGHT", 12, 0)
    frame.startButton:SetText("Start")
    frame.startButton:SetScript("OnClick", function()
        FT:StartRun()
    end)

    frame.pauseButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.pauseButton:SetSize(70, 22)
    frame.pauseButton:SetPoint("LEFT", frame.startButton, "RIGHT", 12, 0)
    frame.pauseButton:SetText("Pause")
    frame.pauseButton:SetScript("OnClick", function()
        FT:PauseRun()
    end)

    frame.stopButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.stopButton:SetSize(70, 22)
    frame.stopButton:SetPoint("LEFT", frame.pauseButton, "RIGHT", 12, 0)
    frame.stopButton:SetText("Stop")
    frame.stopButton:SetScript("OnClick", function()
        FT:StopRun()
    end)

    frame.resetButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.resetButton:SetSize(70, 22)
    frame.resetButton:SetPoint("LEFT", frame.stopButton, "RIGHT", 12, 0)
    frame.resetButton:SetText("Reset")
    frame.resetButton:SetScript("OnClick", function()
        FT:ResetRun()
    end)

    self:RefreshList()
    self:UpdateControls()
    self:UpdateTimer()
    self:RefreshPresetDropdown()

    if self.db.visible then
        frame:Show()
    else
        frame:Hide()
    end
end
