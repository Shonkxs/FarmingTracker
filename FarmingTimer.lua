local ADDON_NAME, FT = ...
FT = FT or {}
_G.FarmingTimer = FT

FT.addonName = ADDON_NAME

local DEFAULTS = {
    version = 1,
    items = {},
    frame = { point = "CENTER", x = 0, y = 0 },
    visible = true,
    minimap = { hide = false, minimapPos = 220 },
    lastPreset = nil,
    considerTargets = true,
}

local function copyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = dst[k] or {}
            copyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function FT:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff4ade80FarmingTimer:|r " .. tostring(msg))
end

function FT:InitDB()
    FarmingTimerDB = FarmingTimerDB or {}
    FarmingTimerAccountDB = FarmingTimerAccountDB or {}
    copyDefaults(FarmingTimerDB, DEFAULTS)
    self.db = FarmingTimerDB
    self.accountDb = FarmingTimerAccountDB
    self.accountDb.presets = self.accountDb.presets or {}
end

function FT:NormalizePresetName(name)
    if not name then
        return nil
    end
    if strtrim then
        name = strtrim(name)
    else
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
    end
    if name == "" then
        return nil
    end
    return name
end

function FT:GetPresetNamesSorted()
    local names = {}
    if not self.accountDb or not self.accountDb.presets then
        return names
    end
    for name in pairs(self.accountDb.presets) do
        table.insert(names, name)
    end
    table.sort(names, function(a, b)
        return string.lower(a) < string.lower(b)
    end)
    return names
end

function FT:SetSelectedPreset(name)
    self.selectedPreset = name
    if self.frame and self.frame.presetDropdown then
        if name and self.accountDb.presets[name] then
            UIDropDownMenu_SetSelectedValue(self.frame.presetDropdown, name)
            UIDropDownMenu_SetText(self.frame.presetDropdown, name)
        else
            UIDropDownMenu_SetSelectedValue(self.frame.presetDropdown, nil)
            UIDropDownMenu_SetText(self.frame.presetDropdown, "Select")
        end
    end
    if self.frame and self.frame.presetNameBox and name and not self.frame.presetNameBox:HasFocus() then
        self.frame.presetNameBox:SetText(name)
    end
end

function FT:SavePreset(name)
    if self.running then
        self:Print("Stop the timer before saving a preset.")
        return
    end

    name = self:NormalizePresetName(name)
    if not name then
        self:Print("Please enter a preset name.")
        return
    end

    local items = {}
    for _, item in ipairs(self.db.items) do
        if self:IsValidItem(item) then
            table.insert(items, { itemID = tonumber(item.itemID), target = tonumber(item.target) })
        end
    end

    if #items == 0 then
        self:Print("No valid items to save.")
        return
    end

    self.accountDb.presets[name] = items
    self.db.lastPreset = name
    self:SetSelectedPreset(name)
    if self.RefreshPresetDropdown then
        self:RefreshPresetDropdown()
    end
    self:Print("Preset saved: " .. name)
end

function FT:LoadPreset(name)
    if self.running then
        self:Print("Stop the timer before loading a preset.")
        return
    end

    name = self:NormalizePresetName(name)
    if not name then
        name = self:NormalizePresetName(self.selectedPreset)
    end
    if not name then
        self:Print("Please select a preset.")
        return
    end

    local preset = self.accountDb.presets[name]
    if not preset then
        self:Print("Preset not found: " .. name)
        return
    end

    local items = {}
    for _, entry in ipairs(preset) do
        local itemID = tonumber(entry.itemID)
        local target = tonumber(entry.target)
        if itemID and itemID > 0 and target and target > 0 then
            table.insert(items, { itemID = itemID, target = target })
        end
    end

    self.db.items = items
    self.db.lastPreset = name
    self.baseline = {}
    for _, item in ipairs(self.db.items) do
        item.current = 0
    end
    self.elapsed = 0

    self:RefreshList()
    if self.UpdateControls then
        self:UpdateControls()
    end
    self:UpdateTimer()
    self:SetSelectedPreset(name)
    self:Print("Preset loaded: " .. name)
end

function FT:DeletePreset(name)
    if self.running then
        self:Print("Stop the timer before deleting a preset.")
        return
    end

    name = self:NormalizePresetName(name)
    if not name then
        name = self:NormalizePresetName(self.selectedPreset)
    end
    if not name then
        self:Print("Please select a preset.")
        return
    end

    if not self.accountDb.presets[name] then
        self:Print("Preset not found: " .. name)
        return
    end

    self.accountDb.presets[name] = nil
    if self.db.lastPreset == name then
        self.db.lastPreset = nil
    end
    if self.selectedPreset == name then
        self.selectedPreset = nil
    end
    if self.RefreshPresetDropdown then
        self:RefreshPresetDropdown()
    end
    self:Print("Preset deleted: " .. name)
end

function FT:ResolveItemID(value)
    if not value or value == "" then
        return nil
    end
    if type(value) == "number" then
        return value
    end
    if type(value) == "string" then
        local num = tonumber(value)
        if num then
            return num
        end
        if C_Item and C_Item.GetItemInfoInstant then
            return select(1, C_Item.GetItemInfoInstant(value))
        end
        if GetItemInfoInstant then
            return select(1, GetItemInfoInstant(value))
        end
    end
    return nil
end

function FT:FormatElapsed(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds >= 3600 then
        local h = math.floor(seconds / 3600)
        local m = math.floor((seconds % 3600) / 60)
        local s = seconds % 60
        return string.format("%02d:%02d:%02d", h, m, s)
    end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%02d:%02d", m, s)
end

function FT:IsValidItem(item)
    if not item then
        return false
    end
    local itemID = tonumber(item.itemID)
    local target = tonumber(item.target)
    return itemID and itemID > 0 and target and target > 0
end

function FT:IsTrackableItem(item)
    if not item then
        return false
    end
    local itemID = tonumber(item.itemID)
    return itemID and itemID > 0
end

function FT:GetValidCount()
    local count = 0
    for _, item in ipairs(self.db.items) do
        if self:IsValidItem(item) then
            count = count + 1
        end
    end
    return count
end

function FT:GetTrackableCount()
    local count = 0
    for _, item in ipairs(self.db.items) do
        if self:IsTrackableItem(item) then
            count = count + 1
        end
    end
    return count
end

function FT:StartRun()
    if self.running and not self.paused then
        return
    end
    if self.running and self.paused then
        self:ResumeRun()
        return
    end

    local considerTargets = self.db.considerTargets ~= false
    if considerTargets then
        if self:GetValidCount() == 0 then
            self:Print("Please add at least one item with a target amount.")
            return
        end
    else
        if self:GetTrackableCount() == 0 then
            self:Print("Please add at least one item to track.")
            return
        end
    end

    self.baseline = {}
    for i, item in ipairs(self.db.items) do
        if self:IsTrackableItem(item) then
            local itemID = tonumber(item.itemID)
            self.baseline[i] = GetItemCount(itemID, false)
        else
            self.baseline[i] = 0
        end
    end

    self.running = true
    self.paused = false
    self.startTime = GetTime()
    self.elapsed = 0

    self:StartTicker()
    self:RefreshProgress()
    if self.UpdateControls then
        self:UpdateControls()
    end
end

function FT:PauseRun()
    if not self.running or self.paused then
        return
    end
    if self.startTime then
        self.elapsed = (self.elapsed or 0) + (GetTime() - self.startTime)
    end
    self.startTime = nil
    self.paused = true
    self:StopTicker()
    self:UpdateTimer()
    if self.UpdateControls then
        self:UpdateControls()
    end
end

function FT:ResumeRun()
    if not self.running or not self.paused then
        return
    end
    self.paused = false
    self.startTime = GetTime()
    self:StartTicker()
    self:UpdateTimer()
    if self.UpdateControls then
        self:UpdateControls()
    end
end

function FT:StopRun()
    if not self.running then
        return
    end

    if self.startTime then
        self.elapsed = (self.elapsed or 0) + (GetTime() - self.startTime)
    end

    self.running = false
    self.paused = false
    self.startTime = nil
    self:StopTicker()
    self:UpdateTimer()

    if self.UpdateControls then
        self:UpdateControls()
    end
end

function FT:ResetRun()
    self:StopRun()
    self.elapsed = 0
    self.paused = false
    self.baseline = {}
    for _, item in ipairs(self.db.items) do
        item.current = 0
    end
    self:RefreshProgress()
end

function FT:CompleteRun()
    if SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE then
        PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE)
    else
        PlaySound(12867)
    end
    self:StopRun()
end

function FT:StartTicker()
    self:StopTicker()
    self.timerTicker = C_Timer.NewTicker(0.2, function()
        self:UpdateTimer()
    end)
end

function FT:StopTicker()
    if self.timerTicker then
        self.timerTicker:Cancel()
        self.timerTicker = nil
    end
end

function FT:UpdateTimer()
    local elapsed = self.elapsed or 0
    if self.running and self.startTime then
        elapsed = elapsed + (GetTime() - self.startTime)
    end
    if self.SetTimerText then
        self:SetTimerText(self:FormatElapsed(elapsed))
    end
end

function FT:RefreshProgress()
    local completed = 0
    local targetable = 0
    local trackable = 0
    local considerTargets = self.db.considerTargets ~= false

    for i, item in ipairs(self.db.items) do
        local current = 0
        if self:IsTrackableItem(item) then
            trackable = trackable + 1
            local itemID = tonumber(item.itemID)
            local base = self.baseline and self.baseline[i] or 0
            if self.running then
                current = GetItemCount(itemID, false) - base
            else
                current = 0
            end
            local target = tonumber(item.target) or 0
            if considerTargets and target > 0 then
                targetable = targetable + 1
                if current >= target then
                    completed = completed + 1
                end
            end
        end
        item.current = current
    end

    if self.UpdateRows then
        self:UpdateRows()
    end
    if self.UpdateSummary then
        if considerTargets then
            self:UpdateSummary(completed, targetable)
        else
            self:UpdateSummary(0, trackable)
        end
    end

    if self.running and not self.paused and considerTargets and targetable > 0 and completed == targetable then
        self:CompleteRun()
    end
end

function FT:RegisterSlash()
    if self.slashRegistered then
        return
    end
    self.slashRegistered = true
    SLASH_FARMINGTIMER1 = "/ft"
    SLASH_FARMINGTIMER2 = "/farmingtimer"
    SlashCmdList["FARMINGTIMER"] = function()
        self:ToggleFrame()
    end
end

function FT:ToggleFrame()
    if not self.frame then
        return
    end
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
    end
end

function FT:ShowFrame()
    if self.frame then
        self.frame:Show()
    end
end

function FT:HideFrame()
    if self.frame then
        self.frame:Hide()
    end
end

function FT:InitLDB()
    if not LibStub then
        return
    end

    local LDB = LibStub("LibDataBroker-1.1", true)
    local DBIcon = LibStub("LibDBIcon-1.0", true)
    if not LDB or not DBIcon then
        return
    end

    self.ldb = LDB:NewDataObject("FarmingTimer", {
        type = "launcher",
        text = "FarmingTimer",
        icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    })

    self.ldb.OnClick = function(_, button)
        if button == "LeftButton" then
            self:ToggleFrame()
        end
    end

    self.ldb.OnTooltipShow = function(tooltip)
        tooltip:AddLine("FarmingTimer")
        tooltip:AddLine("Left-click to toggle")
        tooltip:AddLine("/ft")
    end

    self.db.minimap = self.db.minimap or { hide = false, minimapPos = 220 }
    DBIcon:Register("FarmingTimer", self.ldb, self.db.minimap)
    self.dbicon = DBIcon
end

function FT:UpdateMinimapVisibility()
    if not self.dbicon then
        return
    end
    if self.db.minimap.hide then
        self.dbicon:Hide("FarmingTimer")
    else
        self.dbicon:Show("FarmingTimer")
    end
end

function FT:ADDON_LOADED(addonName)
    if addonName ~= ADDON_NAME then
        return
    end
    self:InitDB()
    self:InitLDB()
end

function FT:PLAYER_LOGIN()
    if self.InitUI then
        self:InitUI()
    end
    if self.InitOptions then
        self:InitOptions()
    end
    self:RegisterSlash()
    self:UpdateMinimapVisibility()
    self:UpdateTimer()
end

function FT:BAG_UPDATE_DELAYED()
    if self.running then
        self:RefreshProgress()
    end
end

function FT:ITEM_DATA_LOAD_RESULT()
    if self.UpdateRows then
        self:UpdateRows()
    end
end

FT.eventFrame = CreateFrame("Frame")
FT.eventFrame:SetScript("OnEvent", function(_, event, ...)
    if FT[event] then
        FT[event](FT, ...)
    end
end)
FT.eventFrame:RegisterEvent("ADDON_LOADED")
FT.eventFrame:RegisterEvent("PLAYER_LOGIN")
FT.eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
FT.eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
