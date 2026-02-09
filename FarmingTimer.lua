local ADDON_NAME, FT = ...
FT = FT or {}
_G.FarmingTimer = FT

FT.addonName = ADDON_NAME

FT.MODES = {
    TARGETS = "targets",
    ALL = "all",
}

FT.useBrowseScan = true

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
    self.accountDb.ahPrices = self.accountDb.ahPrices or {}
    self:GetActiveMode()
end

function FT:GetRealmKey()
    local realm = GetRealmName and GetRealmName() or "Unknown"
    return realm or "Unknown"
end

function FT:GetAHPriceBucket()
    if not self.accountDb then
        return nil
    end
    self.accountDb.ahPrices = self.accountDb.ahPrices or {}
    local key = self:GetRealmKey()
    self.accountDb.ahPrices[key] = self.accountDb.ahPrices[key] or {}
    return self.accountDb.ahPrices[key]
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
            lastScan = 0,
        }
        self.modeStates[mode] = state
    end
    state.elapsed = state.elapsed or 0
    state.baseline = state.baseline or {}
    state.baselineCounts = state.baselineCounts or {}
    state.lastScan = state.lastScan or 0
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

function FT:GetBagIds()
    local bagIds = {}
    local seen = {}
    local function add(id)
        if id == nil or seen[id] then
            return
        end
        seen[id] = true
        table.insert(bagIds, id)
    end

    if Enum and Enum.BagIndex then
        add(Enum.BagIndex.Backpack)
        add(Enum.BagIndex.Bag1)
        add(Enum.BagIndex.Bag2)
        add(Enum.BagIndex.Bag3)
        add(Enum.BagIndex.Bag4)
        add(Enum.BagIndex.ReagentBag)
    else
        local maxBag = NUM_BAG_SLOTS or 0
        for bag = 0, maxBag do
            add(bag)
        end
        add(_G and _G.REAGENTBAG_CONTAINER)
    end

    return bagIds
end

function FT:ScanBagCounts()
    local counts = {}
    if not C_Container or not C_Container.GetContainerNumSlots then
        return counts
    end
    for _, bag in ipairs(self:GetBagIds()) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local itemID = info and info.itemID or (C_Container.GetContainerItemID and C_Container.GetContainerItemID(bag, slot))
                if itemID then
                    local stack = (info and info.stackCount) or 1
                    counts[itemID] = (counts[itemID] or 0) + stack
                end
            end
        end
    end
    return counts
end

function FT:FindItemLocation(itemID)
    if not itemID or not ItemLocation or not C_Container or not C_Container.GetContainerNumSlots then
        return nil
    end
    for _, bag in ipairs(self:GetBagIds()) do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID == itemID then
                    return ItemLocation:CreateFromBagAndSlot(bag, slot)
                end
            end
        end
    end
    return nil
end

function FT:FindCategoryByName(categories, name)
    if type(categories) ~= "table" then
        return nil
    end
    for _, c in ipairs(categories) do
        if c and c.name == name then
            return c
        end
        local found = self:FindCategoryByName(c.subCategories, name)
        if found then
            return found
        end
    end
    return nil
end

function FT:CollectLeafCategories(node, out)
    if not node then
        return
    end
    if node.subCategories and #node.subCategories > 0 then
        for _, sub in ipairs(node.subCategories) do
            self:CollectLeafCategories(sub, out)
        end
        return
    end
    if node.filters then
        table.insert(out, { name = node.name or "Reagents", filters = node.filters })
    end
end

function FT:GetTradegoodsSubclassFilters()
    local filterSets = {}
    if not (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods and Enum.ItemTradeGoodsSubclass) then
        return filterSets
    end
    local classID = Enum.ItemClass.Tradegoods
    for _, subClassID in pairs(Enum.ItemTradeGoodsSubclass) do
        if type(subClassID) == "number" then
            local name = nil
            if GetItemSubClassInfo then
                name = GetItemSubClassInfo(classID, subClassID)
            end
            table.insert(filterSets, {
                name = name or ("Trade Goods " .. tostring(subClassID)),
                filters = { { classID = classID, subClassID = subClassID } },
            })
        end
    end
    table.sort(filterSets, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    return filterSets
end

function FT:FilterHasTradegoods(filters)
    if type(filters) ~= "table" or not (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) then
        return false
    end
    for _, f in ipairs(filters) do
        if f and f.classID == Enum.ItemClass.Tradegoods then
            return true
        end
    end
    return false
end

function FT:CollectTradegoodsCategories(categories, out)
    if type(categories) ~= "table" then
        return
    end
    for _, c in ipairs(categories) do
        if c then
            if self:FilterHasTradegoods(c.filters) then
                table.insert(out, { name = c.name or "Reagents", filters = c.filters })
            end
            if c.subCategories then
                self:CollectTradegoodsCategories(c.subCategories, out)
            end
        end
    end
end

function FT:GetReagentFilterSets()
    local filterSets = {}
    if type(_G.AuctionCategories) == "table" then
        self:CollectTradegoodsCategories(_G.AuctionCategories, filterSets)
    end
    if #filterSets == 0 then
        local subclassFilters = self:GetTradegoodsSubclassFilters()
        if #subclassFilters > 0 then
            return subclassFilters
        end
    end
    if #filterSets == 0 then
        if Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods then
            table.insert(filterSets, { name = "Trade Goods", filters = { { classID = Enum.ItemClass.Tradegoods } } })
        else
            table.insert(filterSets, { name = "Reagents", filters = {} })
        end
    end
    return filterSets
end

function FT:IsItemAuctionable(itemID)
    if not C_AuctionHouse or not C_AuctionHouse.IsSellItem then
        return nil, false
    end
    local loc = self:FindItemLocation(itemID)
    if not loc then
        return nil, false
    end
    return C_AuctionHouse.IsSellItem(loc), true
end

function FT:GetServerTimestamp()
    if GetServerTime then
        return GetServerTime()
    end
    return time()
end

function FT:GetCachedPrice(itemID)
    local bucket = self:GetAHPriceBucket()
    if not bucket then
        return nil, nil, nil
    end
    local entry = bucket[itemID]
    if not entry then
        return nil, nil, nil
    end
    return entry.unitPrice, entry.auctionable, entry.lastUpdated
end

function FT:SetCachedPrice(itemID, unitPrice, auctionable)
    local bucket = self:GetAHPriceBucket()
    if not bucket or not itemID then
        return
    end
    bucket[itemID] = {
        unitPrice = unitPrice,
        auctionable = auctionable and true or false,
        lastUpdated = self:GetServerTimestamp(),
    }
end

function FT:SetCachedPriceMin(itemID, unitPrice, scanStamp)
    if not itemID or not unitPrice then
        return
    end
    local existing, _, lastUpdated = self:GetCachedPrice(itemID)
    if scanStamp and lastUpdated and lastUpdated < scanStamp then
        existing = nil
    end
    if existing and existing > 0 and existing <= unitPrice then
        return
    end
    self:SetCachedPrice(itemID, unitPrice, true)
end

function FT:IsPriceFresh(itemID)
    local unitPrice, auctionable, lastUpdated = self:GetCachedPrice(itemID)
    if not lastUpdated then
        return false
    end
    local now = self:GetServerTimestamp()
    local ttl
    if auctionable == false and not unitPrice then
        ttl = 2 * 60 * 60
    else
        ttl = 15 * 60
    end
    return (now - lastUpdated) <= ttl
end

function FT:EnsurePrice(itemID)
    if self.useBrowseScan then
        return
    end
    if not itemID then
        return
    end
    if self:IsPriceFresh(itemID) then
        return
    end
    local auctionable, hasLocation = self:IsItemAuctionable(itemID)
    if auctionable == false then
        self:SetCachedPrice(itemID, nil, false)
        return
    end
    if not self.ahAvailable then
        self:EnqueuePendingPrice(itemID)
        return
    end
    self:EnqueuePrice(itemID, auctionable, hasLocation)
end

function FT:EnqueuePendingPrice(itemID)
    if not itemID then
        return
    end
    self.ahPending = self.ahPending or {}
    self.ahPendingSet = self.ahPendingSet or {}
    if self.ahPendingSet[itemID] then
        return
    end
    table.insert(self.ahPending, itemID)
    self.ahPendingSet[itemID] = true
end

function FT:EnqueuePrice(itemID, auctionable, hasLocation)
    self.ahQueue = self.ahQueue or {}
    self.ahQueueSet = self.ahQueueSet or {}
    if self.ahQueueSet[itemID] or (self.ahInFlight and self.ahInFlight.itemID == itemID) then
        return
    end
    table.insert(self.ahQueue, { itemID = itemID, auctionable = auctionable, hasLocation = hasLocation })
    self.ahQueueSet[itemID] = true
end

function FT:GetItemKey(itemID)
    if C_AuctionHouse and C_AuctionHouse.MakeItemKey then
        return C_AuctionHouse.MakeItemKey(itemID)
    end
    return nil
end

function FT:IsCommodity(itemID)
    if C_AuctionHouse and C_AuctionHouse.GetItemCommodityStatus and Enum and Enum.ItemCommodityStatus then
        local status = C_AuctionHouse.GetItemCommodityStatus(itemID)
        if status == Enum.ItemCommodityStatus.Commodity then
            return true
        end
        if status == Enum.ItemCommodityStatus.Item then
            return false
        end
    end
    if C_AuctionHouse and C_AuctionHouse.IsCommodity then
        return C_AuctionHouse.IsCommodity(itemID)
    end
    return false
end

function FT:StartAHTicker()
    if self.ahTicker then
        return
    end
    self.ahTicker = C_Timer.NewTicker(0.4, function()
        self:ProcessPriceQueue()
    end)
end

function FT:StopAHTicker()
    if self.ahTicker then
        self.ahTicker:Cancel()
        self.ahTicker = nil
    end
end

function FT:ProcessPriceQueue()
    if not self.ahAvailable or not C_AuctionHouse or not C_AuctionHouse.SendSearchQuery then
        return
    end
    if self.ahInFlight then
        return
    end
    self.ahQueue = self.ahQueue or {}
    self.ahQueueSet = self.ahQueueSet or {}
    if #self.ahQueue == 0 then
        return
    end
    local now = GetTime()
    self.ahNextQueryAt = self.ahNextQueryAt or 0
    if now < self.ahNextQueryAt then
        return
    end

    local payload = table.remove(self.ahQueue, 1)
    if not payload or not payload.itemID then
        return
    end
    self.ahQueueSet[payload.itemID] = nil

    if self:IsPriceFresh(payload.itemID) then
        return
    end

    local itemKey = self:GetItemKey(payload.itemID)
    if not itemKey then
        self:SetCachedPrice(payload.itemID, nil, false)
        return
    end

    local isCommodity = self:IsCommodity(payload.itemID)
    if C_AuctionHouse.CanSendSearchQuery and not C_AuctionHouse.CanSendSearchQuery() then
        self.ahNextQueryAt = now + 0.4
        table.insert(self.ahQueue, 1, payload)
        self.ahQueueSet[payload.itemID] = true
        return
    end

    self.ahInFlight = {
        itemID = payload.itemID,
        itemKey = itemKey,
        isCommodity = isCommodity,
        auctionable = payload.auctionable,
        hasLocation = payload.hasLocation,
    }

    C_AuctionHouse.SendSearchQuery(itemKey, {}, false)
    self.ahNextQueryAt = now + 0.4
end

function FT:HandlePriceResult(itemID, unitPrice)
    local inflight = self.ahInFlight
    if not inflight or inflight.itemID ~= itemID then
        return
    end

    local auctionable = inflight.auctionable
    if unitPrice and unitPrice > 0 then
        self:SetCachedPrice(itemID, unitPrice, true)
    else
        if auctionable == nil and not inflight.hasLocation then
            self:SetCachedPrice(itemID, nil, false)
        else
            self:SetCachedPrice(itemID, nil, auctionable ~= false)
        end
    end

    self.ahInFlight = nil
    if self.UpdateRows then
        self:UpdateRows(self.MODES.ALL)
    end
    if self.UpdateSummary then
        self:UpdateSummary(self.MODES.ALL)
    end
end

function FT:StartReagentScan(force)
    if not self.ahAvailable or not C_AuctionHouse or not C_AuctionHouse.SendBrowseQuery then
        return
    end
    if self.ahScan and self.ahScan.inProgress then
        return
    end
    if self.ahScanReady and not force then
        return
    end
    if force then
        self.ahScanReady = false
    end
    local filters = self:GetReagentFilterSets()
    if #filters == 0 then
        return
    end
    self.ahScan = {
        inProgress = true,
        filters = filters,
        index = 1,
        total = #filters,
        lastResultAt = GetTime(),
        querySentAt = 0,
        maxCategorySeconds = 8,
        startStamp = self:GetServerTimestamp(),
    }
    self.ahScanReady = false
    if self.ShowScanProgress then
        self:ShowScanProgress(0, "Scanning AH...")
    end
    self:StartScanTicker()
    self:SendReagentBrowseQuery()
end

function FT:StartScanTicker()
    if self.ahScanTicker then
        return
    end
    self.ahScanTicker = C_Timer.NewTicker(0.5, function()
        self:PollReagentScan()
    end)
end

function FT:StopScanTicker()
    if self.ahScanTicker then
        self.ahScanTicker:Cancel()
        self.ahScanTicker = nil
    end
end

function FT:SendReagentBrowseQuery()
    if not self.ahScan or not self.ahScan.inProgress then
        return
    end
    local entry = self.ahScan.filters[self.ahScan.index]
    if not entry then
        return
    end
    local filterSet = entry.filters
    local query = {
        searchString = "",
        sorts = {},
        filters = {},
        itemClassFilters = filterSet,
    }
    if C_AuctionHouse.SendBrowseQuery then
        C_AuctionHouse.SendBrowseQuery(query)
    end
    local progress = (self.ahScan.index - 1) / self.ahScan.total
    if self.ShowScanProgress then
        local label = entry.name or "Reagents"
        self:ShowScanProgress(progress, string.format("Scanning AH: %s (%d/%d)", label, self.ahScan.index, self.ahScan.total))
    end
    self.ahScan.querySentAt = GetTime()
    self.ahScan.lastResultAt = GetTime()
end

function FT:ProcessBrowseResults(results)
    if type(results) ~= "table" then
        return
    end
    if self.ahScan then
        self.ahScan.lastResultAt = GetTime()
    end
    for _, info in ipairs(results) do
        local itemKey = info.itemKey
        local itemID = itemKey and itemKey.itemID
        local minPrice = info.minPrice
        local quantity = info.totalQuantity or 0
        if itemID and minPrice and minPrice > 0 and quantity > 0 then
            local stamp = self.ahScan and self.ahScan.startStamp or nil
            self:SetCachedPriceMin(itemID, minPrice, stamp)
        end
    end
end

function FT:AdvanceReagentScanIfDone()
    if not self.ahScan or not self.ahScan.inProgress then
        return
    end
    local now = GetTime()
    if self.ahScan.querySentAt and (now - self.ahScan.querySentAt) > (self.ahScan.maxCategorySeconds or 8) then
        self.ahScan.lastResultAt = now
        self.ahScan.index = self.ahScan.index + 1
        if self.ahScan.index > self.ahScan.total then
            self.ahScan.inProgress = false
            self.ahScanReady = true
            self:StopScanTicker()
            if self.accountDb then
                self.accountDb.ahScan = self.accountDb.ahScan or {}
                self.accountDb.ahScan[self:GetRealmKey()] = self:GetServerTimestamp()
            end
            if self.ShowScanProgress then
                self:ShowScanProgress(nil, "")
            end
            if self.UpdateRows then
                self:UpdateRows(self.MODES.ALL)
            end
            if self.UpdateSummary then
                self:UpdateSummary(self.MODES.ALL)
            end
            return
        end
        self:SendReagentBrowseQuery()
        return
    end
    local hasFull = C_AuctionHouse.HasFullBrowseResults and C_AuctionHouse.HasFullBrowseResults()
    if not hasFull then
        if C_AuctionHouse.RequestMoreBrowseResults then
            local requested = C_AuctionHouse.RequestMoreBrowseResults()
            if requested then
                return
            end
        end
        if self.ahScan.lastResultAt and (now - self.ahScan.lastResultAt) < 6 then
            return
        end
    end

    self.ahScan.index = self.ahScan.index + 1
    if self.ahScan.index > self.ahScan.total then
        self.ahScan.inProgress = false
        self.ahScanReady = true
        self:StopScanTicker()
        if self.accountDb then
            self.accountDb.ahScan = self.accountDb.ahScan or {}
            self.accountDb.ahScan[self:GetRealmKey()] = self:GetServerTimestamp()
        end
        if self.ShowScanProgress then
            self:ShowScanProgress(nil, "")
        end
        if self.UpdateRows then
            self:UpdateRows(self.MODES.ALL)
        end
        if self.UpdateSummary then
            self:UpdateSummary(self.MODES.ALL)
        end
        return
    end
    self:SendReagentBrowseQuery()
end

function FT:PollReagentScan()
    if not self.ahScan or not self.ahScan.inProgress or not self.ahAvailable then
        return
    end
    local results = C_AuctionHouse.GetBrowseResults and C_AuctionHouse.GetBrowseResults()
    if type(results) == "table" and #results > 0 then
        self:ProcessBrowseResults(results)
    end
    self:AdvanceReagentScanIfDone()
end

function FT:GetCommodityUnitPrice(itemID)
    if not C_AuctionHouse then
        return nil
    end
    local minPrice
    if C_AuctionHouse.GetCommoditySearchResults then
        local results = C_AuctionHouse.GetCommoditySearchResults(itemID)
        if type(results) == "table" then
            for _, info in ipairs(results) do
                local price = info.unitPrice
                if price and (not minPrice or price < minPrice) then
                    minPrice = price
                end
            end
        elseif type(results) == "number" and C_AuctionHouse.GetCommoditySearchResultInfo then
            for i = 1, results do
                local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
                local price = info and info.unitPrice
                if price and (not minPrice or price < minPrice) then
                    minPrice = price
                end
            end
        end
    elseif C_AuctionHouse.GetCommoditySearchResultInfo and C_AuctionHouse.GetCommoditySearchResultsQuantity then
        local count = C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID) or 0
        for i = 1, count do
            local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
            local price = info and info.unitPrice
            if price and (not minPrice or price < minPrice) then
                minPrice = price
            end
        end
    end
    return minPrice
end

function FT:GetItemUnitPrice(itemKey)
    if not C_AuctionHouse or not itemKey then
        return nil
    end
    local minPrice
    if C_AuctionHouse.GetItemSearchResults then
        local results = C_AuctionHouse.GetItemSearchResults(itemKey)
        if type(results) == "table" then
            for _, info in ipairs(results) do
                local buyout = info.buyoutAmount
                local stack = info.quantity or info.stackSize or 1
                local unitPrice = buyout and stack and stack > 0 and math.floor(buyout / stack) or nil
                if unitPrice and (not minPrice or unitPrice < minPrice) then
                    minPrice = unitPrice
                end
            end
        elseif type(results) == "number" and C_AuctionHouse.GetItemSearchResultInfo then
            for i = 1, results do
                local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
                local buyout = info and info.buyoutAmount
                local stack = info and (info.quantity or info.stackSize) or 1
                local unitPrice = buyout and stack and stack > 0 and math.floor(buyout / stack) or nil
                if unitPrice and (not minPrice or unitPrice < minPrice) then
                    minPrice = unitPrice
                end
            end
        end
    end
    return minPrice
end

function FT:FormatMoney(copper)
    if not copper then
        return nil
    end
    local sign = ""
    if copper < 0 then
        sign = "-"
        copper = math.abs(copper)
    end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop = copper % 100
    local parts = {}
    if gold > 0 then
        table.insert(parts, string.format("%dg", gold))
    end
    if silver > 0 or (gold > 0 and cop > 0) then
        table.insert(parts, string.format("%ds", silver))
    end
    if cop > 0 or #parts == 0 then
        table.insert(parts, string.format("%dc", cop))
    end
    return sign .. table.concat(parts, " ")
end

function FT:GetAllItemsTotalValue()
    if not self.db or not self.db.allItems then
        return nil
    end
    local total = 0
    local hasValue = false
    for _, item in ipairs(self.db.allItems) do
        local unitPrice = self:GetCachedPrice(item.itemID)
        if unitPrice then
            total = total + (unitPrice * (tonumber(item.current) or 0))
            hasValue = true
        end
    end
    if not hasValue then
        return nil
    end
    return total
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
        if not self.ahScanReady then
            if self.ahAvailable then
                if self.ahScan and self.ahScan.inProgress then
                    self:Print("Auction House scan in progress. Please wait.")
                else
                    self:StartReagentScan()
                    self:Print("Scanning Auction House reagents. Please wait.")
                end
            else
                self:Print("Open the Auction House to scan reagents before starting.")
            end
            return
        end
        state.baselineCounts = self:ScanBagCounts()
        self.db.allItems = {}
        state.lastScan = 0
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

    if mode == self.MODES.ALL and state.running then
        local now = GetTime()
        if now - (state.lastScan or 0) >= 0.5 then
            state.lastScan = now
            self:RefreshProgress(mode)
        end
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
                    self:EnsurePrice(itemID)
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
    self.ahScanReady = false
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

function FT:AUCTION_HOUSE_SHOW()
    self.ahAvailable = true
    self:StartReagentScan(true)
end

function FT:AUCTION_HOUSE_CLOSED()
    self.ahAvailable = false
    if self.ahScan and self.ahScan.inProgress then
        if self.ShowScanProgress then
            self:ShowScanProgress(nil, "")
        end
        self.ahScan.inProgress = false
    end
    self:StopScanTicker()
end

function FT:COMMODITY_SEARCH_RESULTS_UPDATED(itemID)
    local inflight = self.ahInFlight
    if not inflight or not inflight.isCommodity then
        return
    end
    if itemID and itemID ~= inflight.itemID then
        return
    end
    local unitPrice = self:GetCommodityUnitPrice(inflight.itemID)
    self:HandlePriceResult(inflight.itemID, unitPrice)
end

function FT:ITEM_SEARCH_RESULTS_UPDATED(itemKey)
    local inflight = self.ahInFlight
    if not inflight or inflight.isCommodity then
        return
    end
    local keyItemID = itemKey and itemKey.itemID
    if keyItemID and keyItemID ~= inflight.itemID then
        return
    end
    local unitPrice = self:GetItemUnitPrice(inflight.itemKey)
    self:HandlePriceResult(inflight.itemID, unitPrice)
end

function FT:AUCTION_HOUSE_BROWSE_RESULTS_UPDATED()
    if not self.ahScan or not self.ahScan.inProgress then
        return
    end
    local results = C_AuctionHouse.GetBrowseResults()
    self:ProcessBrowseResults(results)
    self:AdvanceReagentScanIfDone()
end

function FT:AUCTION_HOUSE_BROWSE_RESULTS_ADDED(...)
    if not self.ahScan or not self.ahScan.inProgress then
        return
    end
    local first = ...
    if type(first) == "table" then
        self:ProcessBrowseResults(first)
    else
        self:ProcessBrowseResults({ ... })
    end
    self:AdvanceReagentScanIfDone()
end

function FT:AUCTION_HOUSE_BROWSE_FAILURE()
    if not self.ahScan or not self.ahScan.inProgress then
        return
    end
    self.ahScan.inProgress = false
    self:StopScanTicker()
    if self.ShowScanProgress then
        self:ShowScanProgress(nil, "")
    end
    self:Print("Auction House scan failed. Please try again.")
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
FT.eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
FT.eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
FT.eventFrame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
FT.eventFrame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
FT.eventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
FT.eventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
FT.eventFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_FAILURE")
