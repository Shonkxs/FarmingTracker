local ADDON_NAME, FT = ...

function FT:InitOptions()
    if self.optionsPanel then
        return
    end

    local panel = CreateFrame("Frame")
    panel.name = "FarmingTracker"

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("FarmingTracker")

    local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Global settings")

    local openButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openButton:SetSize(160, 22)
    openButton:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
    openButton:SetText("Open FarmingTracker")
    openButton:SetScript("OnClick", function()
        FT:ShowFrame()
    end)

    local minimapCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    minimapCheck:SetPoint("TOPLEFT", openButton, "BOTTOMLEFT", 0, -16)
    local minimapLabel = minimapCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    minimapLabel:SetPoint("LEFT", minimapCheck, "RIGHT", 4, 0)
    minimapLabel:SetText("Show minimap button")

    minimapCheck:SetScript("OnClick", function(self)
        if not FT.db or not FT.db.minimap then
            return
        end
        FT.db.minimap.hide = not self:GetChecked()
        FT:UpdateMinimapVisibility()
    end)

    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetSize(160, 22)
    resetButton:SetPoint("TOPLEFT", minimapCheck, "BOTTOMLEFT", 0, -16)
    resetButton:SetText("Reset frame position")
    resetButton:SetScript("OnClick", function()
        FT:ResetFramePosition()
    end)

    panel:SetScript("OnShow", function()
        if FT.db and FT.db.minimap then
            minimapCheck:SetChecked(not FT.db.minimap.hide)
        end
    end)

    self.optionsPanel = panel

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    else
        InterfaceOptions_AddCategory(panel)
    end
end
