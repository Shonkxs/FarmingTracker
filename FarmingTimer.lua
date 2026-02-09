local ADDON_NAME, FT = ...
FT = FT or {}
_G.FarmingTimer = FT

FT.addonName = ADDON_NAME

FT.MODES = {
    TARGETS = "targets",
    ALL = "all",
}

local DEFAULTS = {
    version = 2,
    items = {},
    allItems = {},
    activeMode = "targets",
    frame = { point = "CENTER", x = 0, y = 0, height = 360 },
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
    self:GetActiveMode()
end

function FT:GetActiveMode()
    if not self.db then
        return self.MODES.TARGETS
    end
    local mode = self.db.activeMode
    if mode ~= self.MODES.ALL then
        mode = self.MODES.TARGETS
    end
    self.db.activeMode = mode
    return mode
end

function FT:SetActiveMode(mode)
    if not self.db then
        return
    end
    if mode ~= self.MODES.ALL then
        mode = self.MODES.TARGETS
    end
    self.db.activeMode = mode
end

function FT:GetModeState(mode)
    if not mode then
        mode = self:GetActiveMode()
    end
    self.modeStates = self.modeStates or {}
    local state = self.modeStates[mode]
    if not state then
        state = {
            running = false,
            paused = false,
            startTime = nil,
            elapsed = 0,
            baseline = {},
            baselineCounts = {},
        }
        self.modeStates[mode] = state
    end
    state.elapsed = state.elapsed or 0
    state.baseline = state.baseline or {}
    state.baselineCounts = state.baselineCounts or {}
    return state
end

function FT:GetRunningMode()
    for _, mode in pairs(self.MODES) do
        local state = self:GetModeState(mode)
        if state.running then
            return mode
        end
    end
    return nil
end

function FT:IsAnyRunning()
    return self:GetRunningMode() ~= nil
end

function FT:GetItemsForMode(mode)
    if not self.db then
        return {}
    end
    if mode == self.MODES.ALL then
        self.db.allItems = self.db.allItems or {}
        return self.db.allItems
    end
    self.db.items = self.db.items or {}
    return self.db.items
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

function FT:Base64Encode(data)
    local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    return ((data:gsub(".", function(x)
        local r = ""
        local byte = x:byte()
        for i = 8, 1, -1 do
            local bit = byte % 2 ^ i - byte % 2 ^ (i - 1)
            r = r .. (bit > 0 and "1" or "0")
        end
        return r
    end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
        if #x < 6 then
            return ""
        end
        local c = 0
        for i = 1, 6 do
            if x:sub(i, i) == "1" then
                c = c + 2 ^ (6 - i)
            end
        end
        return b:sub(c + 1, c + 1)
    end) .. ({ "", "==", "=" })[#data % 3 + 1])
end

function FT:Base64Decode(data)
    local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    data = data:gsub("[^" .. b .. "=]", "")
    return (data:gsub(".", function(x)
        if x == "=" then
            return ""
        end
        local r = ""
        local f = (b:find(x) or 1) - 1
        for i = 6, 1, -1 do
            local bit = f % 2 ^ i - f % 2 ^ (i - 1)
            r = r .. (bit > 0 and "1" or "0")
        end
        return r
    end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
        if #x ~= 8 then
            return ""
        end
        local c = 0
        for i = 1, 8 do
            if x:sub(i, i) == "1" then
                c = c + 2 ^ (8 - i)
            end
        end
        return string.char(c)
    end))
end

function FT:Base64EncodeUrl(data)
    local encoded = self:Base64Encode(data or "")
    encoded = encoded:gsub("%+", "-"):gsub("/", "_"):gsub("=", "")
    return encoded
end

function FT:Base64DecodeUrl(data)
    if not data then
        return nil
    end
    local decoded = data:gsub("-", "+"):gsub("_", "/")
    local pad = #decoded % 4
    if pad > 0 then
        decoded = decoded .. string.rep("=", 4 - pad)
    end
    return self:Base64Decode(decoded)
end

function FT:GetSelectedPresetName()
    if self.frame and self.frame.presetNameBox then
        local name = self:NormalizePresetName(self.frame.presetNameBox:GetText())
        if name then
            return name
        end
    end
    if self.selectedPreset then
        return self.selectedPreset
    end
    if self.db and self.db.lastPreset then
        return self.db.lastPreset
    end
    return nil
end

function FT:BuildExportString(names)
    if not self.accountDb or not self.accountDb.presets then
        return nil, "No presets available."
    end

    local exportNames = {}
    if type(names) == "string" then
        local normalized = self:NormalizePresetName(names)
        if normalized then
            exportNames = { normalized }
        end
    elseif type(names) == "table" then
        exportNames = names
    else
        exportNames = self:GetPresetNamesSorted()
    end

    if #exportNames == 0 then
        return nil, "No presets available."
    end

    local lines = { "v=1" }
    for _, name in ipairs(exportNames) do
        local items = self.accountDb.presets[name]
        if type(items) == "table" then
            local itemParts = {}
            for _, item in ipairs(items) do
                local itemID = self:ResolveItemID(item.itemID)
                local target = tonumber(item.target) or 0
                if itemID and itemID > 0 then
                    if target < 0 then
                        target = 0
                    end
                    table.insert(itemParts, string.format("%d,%d", itemID, target))
                end
            end
            if #itemParts > 0 then
                local line = string.format("%d:%s:%d:%s", #name, name, #itemParts, table.concat(itemParts, ";"))
                table.insert(lines, line)
            end
        end
    end

    if #lines == 1 then
        return nil, "No presets available."
    end

    local raw = table.concat(lines, "\n")
    return "FT1:" .. self:Base64EncodeUrl(raw)
end

function FT:ImportPresetsLegacy(data, merge)
    if type(data) ~= "string" then
        self:Print("Import failed: invalid data.")
        return
    end

    data = self:NormalizePresetName(data)
    if not data or data == "" then
        self:Print("Import failed: empty data.")
        return
    end

    if not data:match("^FT1;") then
        self:Print("Import failed: invalid format.")
        return
    end

    local imported = 0
    local totalItems = 0
    local skipped = 0

    for entry in data:gmatch("([^;]+)") do
        if entry ~= "FT1" then
            local nameEncoded, itemList = entry:match("^([^=]+)=(.*)$")
            if nameEncoded and itemList then
                local name = self:NormalizePresetName(nameEncoded)
                if name then
                    local items = {}
                    for pair in itemList:gmatch("([^,]+)") do
                        local itemID, target = pair:match("^(%d+):(%d+)$")
                        if itemID then
                            table.insert(items, {
                                itemID = tonumber(itemID),
                                target = tonumber(target) or 0,
                            })
                        end
                    end
                    if #items > 0 then
                        if merge and self.accountDb.presets[name] then
                            skipped = skipped + 1
                        else
                            self.accountDb.presets[name] = items
                            imported = imported + 1
                            totalItems = totalItems + #items
                        end
                    end
                end
            end
        end
    end

    if imported == 0 then
        self:Print("Import completed: no presets found.")
        return
    end

    if self.RefreshPresetDropdown then
        self:RefreshPresetDropdown()
    end
    if skipped > 0 then
        self:Print(string.format("Imported %d presets (%d items), skipped %d.", imported, totalItems, skipped))
    else
        self:Print(string.format("Imported %d presets (%d items).", imported, totalItems))
    end
end

function FT:ImportPresets(data, merge)
    if type(data) ~= "string" then
        self:Print("Import failed: invalid data.")
        return
    end

    data = self:NormalizePresetName(data)
    if not data or data == "" then
        self:Print("Import failed: empty data.")
        return
    end

    if data:match("^FT1;") then
        self:ImportPresetsLegacy(data, merge)
        return
    end

    if not data:match("^FT1:") then
        self:Print("Import failed: invalid format.")
        return
    end

    local payload = data:sub(5)
    local raw = self:Base64DecodeUrl(payload)
    if not raw or raw == "" then
        self:Print("Import failed: invalid data.")
        return
    end

    local lines = {}
    for line in raw:gmatch("[^\n]+") do
        table.insert(lines, line)
    end

    if #lines == 0 or lines[1] ~= "v=1" then
        self:Print("Import failed: unsupported version.")
        return
    end

    local imported = 0
    local totalItems = 0
    local skipped = 0

    for i = 2, #lines do
        local line = lines[i]
        local lenStr, rest = line:match("^(%d+):(.*)$")
        local nameLen = tonumber(lenStr)
        if nameLen and rest and #rest >= nameLen + 2 then
            local name = rest:sub(1, nameLen)
            local after = rest:sub(nameLen + 1)
            if after:sub(1, 1) == ":" then
                after = after:sub(2)
                local countStr, itemList = after:match("^(%d+):(.*)$")
                if countStr and itemList then
                    local items = {}
                    for pair in itemList:gmatch("([^;]+)") do
                        local itemID, target = pair:match("^(%d+),(%-?%d+)$")
                        if itemID then
                            local t = tonumber(target) or 0
                            if t < 0 then
                                t = 0
                            end
                            table.insert(items, { itemID = tonumber(itemID), target = t })
                        end
                    end
                    if #items > 0 then
                        if merge and self.accountDb.presets[name] then
                            skipped = skipped + 1
                        else
                            self.accountDb.presets[name] = items
                            imported = imported + 1
                            totalItems = totalItems + #items
                        end
                    end
                end
            end
        end
    end

    if imported == 0 then
        self:Print("Import completed: no presets found.")
        return
    end

    if self.RefreshPresetDropdown then
        self:RefreshPresetDropdown()
    end
    if skipped > 0 then
        self:Print(string.format("Imported %d presets (%d items), skipped %d.", imported, totalItems, skipped))
    else
        self:Print(string.format("Imported %d presets (%d items).", imported, totalItems))
    end
end

function FT:EnsurePopupDialogs()
    if self.popupsReady then
        return
    end
    self.popupsReady = true

    StaticPopupDialogs["FARMINGTIMER_EXPORT"] = {
        text = "Export preset data",
        button1 = "Close",
        hasEditBox = true,
        editBoxWidth = 320,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnShow = function(self, data)
            local payload = self.data or data or ""
            self.editBox:SetText(payload)
            self.editBox:HighlightText()
            self.editBox:SetFocus()
        end,
        EditBoxOnEnterPressed = function(self)
            self:GetParent():Hide()
        end,
        EditBoxOnEscapePressed = function(self)
            self:GetParent():Hide()
        end,
    }

    StaticPopupDialogs["FARMINGTIMER_IMPORT"] = {
        text = "Import preset data",
        button1 = "Import",
        button2 = "Cancel",
        hasEditBox = true,
        editBoxWidth = 320,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnShow = function(self)
            self.editBox:SetText("")
            self.editBox:SetFocus()
        end,
        OnAccept = function(self)
            FT:ImportPresets(self.editBox:GetText())
        end,
        EditBoxOnEnterPressed = function(self)
            FT:ImportPresets(self:GetText())
            self:GetParent():Hide()
        end,
    }
end

function FT:ShowExportDialog(presetName)
    local exportString, err = self:BuildExportString(presetName)
    if not exportString then
        self:Print(err or "No presets available.")
        return
    end
    if self.ShowProfilesWindow then
        self:ShowProfilesWindow("export", exportString)
        return
    end
    self:EnsurePopupDialogs()
    local dialog = StaticPopup_Show("FARMINGTIMER_EXPORT")
    if dialog and dialog.editBox then
        dialog.data = exportString
        dialog.editBox:SetText(exportString)
        dialog.editBox:HighlightText()
        dialog.editBox:SetFocus()
    end
end

function FT:ShowImportDialog()
    if self.ShowProfilesWindow then
        self:ShowProfilesWindow("import", "")
        return
    end
    self:EnsurePopupDialogs()
    StaticPopup_Show("FARMINGTIMER_IMPORT")
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
        if name then
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
    if self:IsAnyRunning() then
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
        local itemID = self:GetItemIDFromItem(item)
        if itemID and itemID > 0 then
            table.insert(items, { itemID = itemID, target = tonumber(item.target) or 0 })
        end
    end

    if #items == 0 then
        self:Print("No items to save.")
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
    if self:IsAnyRunning() then
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
        local itemID = self:ResolveItemID(entry.itemID)
        local target = tonumber(entry.target) or 0
        if itemID and itemID > 0 then
            table.insert(items, { itemID = itemID, target = target })
        end
    end

    self.db.items = items
    self.db.lastPreset = name
    local state = self:GetModeState(self.MODES.TARGETS)
    state.running = false
    state.paused = false
    state.startTime = nil
    state.elapsed = 0
    state.baseline = {}
    for _, item in ipairs(self.db.items) do
        item.current = 0
        item._baseline = 0
    end

    self:RefreshList(self.MODES.TARGETS)
    if self.UpdateControls then
        self:UpdateControls()
    end
    self:UpdateTimer(self.MODES.TARGETS)
    self:SetSelectedPreset(name)
    self:Print("Preset loaded: " .. name)
end

function FT:DeletePreset(name)
    if self:IsAnyRunning() then
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

function FT:GetQualityTier(itemID)
    if not itemID then
        return nil
    end
    if C_TradeSkillUI then
        if C_TradeSkillUI.GetItemReagentQualityByItemInfo then
            local tier = C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID)
            if tier and tier > 0 then
                return tier
            end
        end
        if C_TradeSkillUI.GetItemCraftedQualityByItemInfo then
            local tier = C_TradeSkillUI.GetItemCraftedQualityByItemInfo(itemID)
            if tier and tier > 0 then
                return tier
            end
        end
    end
    return nil
end

function FT:GetQualityTierLabel(tier)
    if tier == 1 then
        return "I"
    elseif tier == 2 then
        return "II"
    elseif tier == 3 then
        return "III"
    end
    return tostring(tier or "")
end

function FT:GetQualityTierColor(tier)
    if tier == 1 then
        return 0.80, 0.55, 0.20
    elseif tier == 2 then
        return 0.75, 0.75, 0.75
    elseif tier == 3 then
        return 0.98, 0.82, 0.20
    end
    return 1, 1, 1
end

function FT:GetItemIDFromItem(item)
    if not item then
        return nil
    end
    local itemID = self:ResolveItemID(item.itemID)
    if itemID and item.itemID ~= itemID then
        item.itemID = itemID
    end
    return itemID
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

function FT:ScanBagCounts()
    local counts = {}
    if not C_Container or not C_Container.GetContainerNumSlots then
        return counts
    end
    local maxBag = NUM_BAG_SLOTS or 0
    for bag = 0, maxBag do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local itemID = C_Container.GetContainerItemID(bag, slot)
                if itemID then
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    local stack = (info and info.stackCount) or 1
                    counts[itemID] = (counts[itemID] or 0) + stack
                end
            end
        end
    end

    local reagentBag = _G and _G.REAGENTBAG_CONTAINER
    if reagentBag and reagentBag > maxBag then
        local numSlots = C_Container.GetContainerNumSlots(reagentBag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local itemID = C_Container.GetContainerItemID(reagentBag, slot)
                if itemID then
                    local info = C_Container.GetContainerItemInfo(reagentBag, slot)
                    local stack = (info and info.stackCount) or 1
                    counts[itemID] = (counts[itemID] or 0) + stack
                end
            end
        end
    end
    return counts
end

function FT:IsValidItem(item)
    if not item then
        return false
    end
    local itemID = self:GetItemIDFromItem(item)
    local target = tonumber(item.target)
    return itemID and itemID > 0 and target and target > 0
end

function FT:IsTrackableItem(item)
    if not item then
        return false
    end
    local itemID = self:GetItemIDFromItem(item)
    return itemID and itemID > 0
end

function FT:EnsureSortIndex()
    if not self.db or not self.db.items then
        return
    end
    for i, item in ipairs(self.db.items) do
        if item._sortIndex == nil then
            item._sortIndex = i
        end
    end
end

function FT:SortItemsByProgress()
    if not self.db or not self.db.items then
        return
    end
    self:EnsureSortIndex()
    table.sort(self.db.items, function(a, b)
        local aTrack = self:IsTrackableItem(a)
        local bTrack = self:IsTrackableItem(b)
        if aTrack ~= bTrack then
            return aTrack
        end
        local aCur = tonumber(a.current) or 0
        local bCur = tonumber(b.current) or 0
        if aCur ~= bCur then
            return aCur > bCur
        end
        local aIdx = a._sortIndex or 0
        local bIdx = b._sortIndex or 0
        return aIdx < bIdx
    end)
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

function FT:StartRun(mode)
    mode = mode or self:GetActiveMode()
    local runningMode = self:GetRunningMode()
    if runningMode and runningMode ~= mode then
        self:Print("Stop the other mode before starting this one.")
        return
    end

    local state = self:GetModeState(mode)
    if state.running and not state.paused then
        return
    end
    if state.running and state.paused then
        self:ResumeRun(mode)
        return
    end

    if mode == self.MODES.TARGETS then
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

        state.baseline = {}
        for i, item in ipairs(self.db.items) do
            item._sortIndex = i
            item._baseline = 0
            if self:IsTrackableItem(item) then
                local itemID = self:GetItemIDFromItem(item)
                local count = GetItemCount(itemID, false)
                item._baseline = count
                state.baseline[i] = count
            else
                state.baseline[i] = 0
            end
        end
    else
        state.baselineCounts = self:ScanBagCounts()
        self.db.allItems = {}
    end

    self:SetActiveMode(mode)
    state.running = true
    state.paused = false
    state.startTime = GetTime()
    state.elapsed = 0

    self:StartTicker()
    self:RefreshProgress(mode)
    if self.UpdateControls then
        self:UpdateControls()
    end
end

function FT:PauseRun(mode)
    mode = mode or self:GetActiveMode()
    local state = self:GetModeState(mode)
    if not state.running or state.paused then
        return
    end
    if state.startTime then
        state.elapsed = (state.elapsed or 0) + (GetTime() - state.startTime)
    end
    state.startTime = nil
    state.paused = true
    self:StopTicker()
    self:UpdateTimer(mode)
    if self.UpdateControls then
        self:UpdateControls()
    end
end

function FT:ResumeRun(mode)
    mode = mode or self:GetActiveMode()
    local state = self:GetModeState(mode)
    if not state.running or not state.paused then
        return
    end
    state.paused = false
    state.startTime = GetTime()
    self:StartTicker()
    self:UpdateTimer(mode)
    if self.UpdateControls then
        self:UpdateControls()
    end
end

function FT:StopRun(mode)
    mode = mode or self:GetActiveMode()
    local state = self:GetModeState(mode)
    if not state.running then
        return
    end

    if state.startTime then
        state.elapsed = (state.elapsed or 0) + (GetTime() - state.startTime)
    end

    state.running = false
    state.paused = false
    state.startTime = nil
    self:StopTicker()
    self:UpdateTimer(mode)

    if self.UpdateControls then
        self:UpdateControls()
    end
end

function FT:ResetRun(mode)
    mode = mode or self:GetActiveMode()
    local state = self:GetModeState(mode)
    self:StopRun(mode)
    state.elapsed = 0
    state.paused = false
    state.baseline = {}
    state.baselineCounts = {}
    if mode == self.MODES.TARGETS then
        for _, item in ipairs(self.db.items) do
            item.current = 0
            item._baseline = 0
        end
    else
        self.db.allItems = {}
    end
    self:RefreshProgress(mode)
    self:UpdateTimer(mode)
end

function FT:CompleteRun(mode)
    if SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE then
        PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE)
    else
        PlaySound(12867)
    end
    self:StopRun(mode)
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

function FT:UpdateTimer(mode)
    mode = mode or self:GetActiveMode()
    local state = self:GetModeState(mode)
    local elapsed = state.elapsed or 0
    if state.running and state.startTime then
        elapsed = elapsed + (GetTime() - state.startTime)
    end
    if self.SetTimerText then
        self:SetTimerText(self:FormatElapsed(elapsed))
    end
end

function FT:RefreshProgress(mode)
    mode = mode or self:GetActiveMode()

    if mode == self.MODES.ALL then
        local state = self:GetModeState(mode)
        if state.running then
            local currentCounts = self:ScanBagCounts()
            local baseline = state.baselineCounts or {}
            local union = {}
            for itemID in pairs(baseline) do
                union[itemID] = true
            end
            for itemID in pairs(currentCounts) do
                union[itemID] = true
            end

            local newItems = {}
            for itemID in pairs(union) do
                local current = (currentCounts[itemID] or 0) - (baseline[itemID] or 0)
                if current ~= 0 then
                    table.insert(newItems, { itemID = itemID, current = current })
                end
            end

            table.sort(newItems, function(a, b)
                if a.current ~= b.current then
                    return a.current > b.current
                end
                return (a.itemID or 0) < (b.itemID or 0)
            end)

            self.db.allItems = newItems
        end

        if self.UpdateRows then
            self:UpdateRows(mode)
        end
        if self.UpdateSummary then
            self:UpdateSummary(mode)
        end
        return
    end

    local state = self:GetModeState(mode)
    local completed = 0
    local targetable = 0
    local trackable = 0
    local considerTargets = self.db.considerTargets ~= false

    for i, item in ipairs(self.db.items) do
        local current = 0
        if self:IsTrackableItem(item) then
            trackable = trackable + 1
            local itemID = self:GetItemIDFromItem(item)
            local base = item._baseline or (state.baseline and state.baseline[i]) or 0
            if state.running then
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

    if state.running and not state.paused then
        self:SortItemsByProgress()
    end

    if self.UpdateRows then
        self:UpdateRows(mode)
    end
    if self.UpdateSummary then
        if considerTargets then
            self:UpdateSummary(mode, completed, targetable)
        else
            self:UpdateSummary(mode, 0, trackable)
        end
    end

    if state.running and not state.paused and considerTargets and targetable > 0 and completed == targetable then
        self:CompleteRun(mode)
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
    local runningMode = self:GetRunningMode()
    if runningMode then
        self:RefreshProgress(runningMode)
    end
end

function FT:ITEM_DATA_LOAD_RESULT()
    if self.UpdateRows then
        self:UpdateRows(self.MODES.TARGETS)
        self:UpdateRows(self.MODES.ALL)
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
