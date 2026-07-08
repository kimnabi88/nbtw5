local addonName = ...

local BtWQuestsDatabase = BtWQuestsDatabase
local BtWQuestsCharacters = BtWQuestsCharacters

local L = BtWQuests.L;

local INTERFACE_NUMBER = select(4, GetBuildInfo())
local NBTW_MOP_EXPANSION_ID = BtWQuests.Constant.Expansions.MistsOfPandaria or 4
local NBTW_DEFAULT_CATEGORY_ID = 501
local NBTW_ENABLE_EXTERNAL_MODULES = false
local NBTW_MOP_CATEGORIES = {
    {id = 501, name = "The Jade Forest"},
    {id = 502, name = "Valley of the Four Winds"},
    {id = 503, name = "Krasarang Wilds"},
    {id = 504, name = "Kun-Lai Summit"},
    {id = 505, name = "Townlong Steppes"},
    {id = 506, name = "Dread Wastes"},
    {id = 507, name = "Vale of Eternal Blossoms"},
    {id = 508, name = "Isle of Thunder"},
}

if type(Mixin) ~= "function" then
    function Mixin(object, ...)
        object = object or {}
        for index = 1, select("#", ...) do
            local mixin = select(index, ...)
            if type(mixin) == "table" then
                for key, value in pairs(mixin) do
                    object[key] = value
                end
            end
        end
        return object
    end
end

if type(CreateFromMixins) ~= "function" then
    function CreateFromMixins(...)
        return Mixin({}, ...)
    end
end

local function GetBestMapForUnit(unit)
    if type(C_Map) == "table" and type(C_Map.GetBestMapForUnit) == "function" then
        return C_Map.GetBestMapForUnit(unit)
    end
    if unit == "player" and type(SetMapToCurrentZone) == "function" and type(GetCurrentMapAreaID) == "function" then
        SetMapToCurrentZone()
        return GetCurrentMapAreaID()
    end
    return nil
end

BINDING_HEADER_BTWQUESTS = "nbtw"
BINDING_NAME_TOGGLE_BTWQUESTS = L["TOGGLE_BTWQUESTS"]

local CreateFramePoolCollection = CreateFramePoolCollection or CreatePoolCollection

local function NBTW_EnsureFrameReady(frame)
    if not frame then
        return false
    end

    if not frame.SelectCategory and BtWQuestsMixin then
        Mixin(frame, BtWQuestsMixin)
    end

    if frame.OnLoad and not frame.nbtwManualOnLoad then
        frame.nbtwManualOnLoad = true
        local ok, err = pcall(frame.OnLoad, frame)
        if not ok then
            print("nbtw onload error: " .. tostring(err))
        end
    end

    if frame.OnEvent and not frame.nbtwManualAddonLoaded then
        frame.nbtwManualAddonLoaded = true
        local ok, err = pcall(frame.OnEvent, frame, "ADDON_LOADED", addonName or "nbtw")
        if not ok then
            print("nbtw init error: " .. tostring(err))
        end
    end

    return frame.SelectCategory ~= nil
end

local function NBTW_OpenCategory(frame, categoryID)
    if not NBTW_EnsureFrameReady(frame) then
        print("nbtw: frame is not ready")
        return
    end

    local category = BtWQuestsDatabase:GetCategoryByID(categoryID)
    if not category and BtWQuestsDatabase.LoadCategory then
        category = BtWQuestsDatabase:LoadCategory(categoryID)
    end
    if not category then
        print("nbtw: category not found - " .. tostring(categoryID))
        return
    end

    local panel = frame.NBTWSimpleList
    if not panel then
        return
    end

    panel.title:SetText(category:GetName() or "Pandaria Quests")
    if panel.subtitle then
        panel.subtitle:SetText("Select a quest chain")
    end

    for _, button in ipairs(panel.buttons or {}) do
        button:Hide()
    end

    local character = frame.GetCharacter and frame:GetCharacter()
    local items = category:GetItemList(character, true, false, false, false, false)
    local shown = 0
    for _, item in ipairs(items) do
        local itemType = item:GetType()
        if itemType == "chain" or itemType == "category" then
            shown = shown + 1
            local button = panel.buttons[shown]
            if not button then
                button = CreateFrame("Button", nil, panel)
                button:SetSize(300, 24)
                if shown == 1 then
                    button:SetPoint("TOPLEFT", panel.subtitle or panel.title, "BOTTOMLEFT", 0, -18)
                else
                    button:SetPoint("TOPLEFT", panel.buttons[shown - 1], "BOTTOMLEFT", 0, -6)
                end
                button.bg = button:CreateTexture(nil, "BACKGROUND")
                button.bg:SetAllPoints()
                button.border = button:CreateTexture(nil, "BORDER")
                button.border:SetPoint("TOPLEFT", -1, 1)
                button.border:SetPoint("BOTTOMRIGHT", 1, -1)
                button.border:SetTexture(0.9, 0.8, 0.45, 0.35)
                button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                button.text:SetPoint("CENTER")
                button:SetFrameLevel(panel:GetFrameLevel() + 1)
                button:RegisterForClicks("AnyDown", "AnyUp")
                button:SetScript("OnEnter", function(self)
                    self.bg:SetTexture(0.65, 0.03, 0.03, 1)
                end)
                button:SetScript("OnLeave", function(self)
                    self.bg:SetTexture(0.45, 0.02, 0.02, 0.95)
                end)
                panel.buttons[shown] = button
            end

            button.bg:SetTexture(0.45, 0.02, 0.02, 0.95)
            button.text:SetText(item:GetName(character))
            button.targetType = itemType
            button.targetID = item:GetID()
            button:SetScript("OnMouseUp", function(self)
                local owner = self:GetParent().owner
                if self.targetType == "chain" then
                    self:GetParent():Hide()
                    local ok, err = pcall(owner.SelectChain, owner, self.targetID, nil, true)
                    if not ok then
                        print("nbtw chain error: " .. tostring(self.targetID) .. " / " .. tostring(err))
                        self:GetParent():Show()
                    end
                else
                    NBTW_OpenCategory(owner, self.targetID)
                end
            end)
            button:Show()
        end
    end

    if shown == 0 then
        print("nbtw: no chains in category - " .. tostring(categoryID))
    end
end

local function NBTW_ShowSimplePandariaList(frame)
    if not frame then
        return
    end

    if frame.Chain then
        frame.Chain:Hide()
    end
    if frame.Category then
        frame.Category:Hide()
    end
    if frame.ExpansionList then
        frame.ExpansionList:Hide()
    end

    if not frame.NBTWSimpleList then
        local panel = CreateFrame("Frame", nil, UIParent)
        panel:SetFrameStrata("DIALOG")
        panel:SetFrameLevel(900)
        panel:SetPoint("TOPLEFT", frame.Inset or frame, "TOPLEFT", 18, -24)
        panel:SetPoint("BOTTOMRIGHT", frame.Inset or frame, "BOTTOMRIGHT", -18, 18)
        panel:EnableMouse(false)
        panel.owner = frame

        panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        panel.title:SetPoint("TOPLEFT", 0, -4)
        panel.title:SetText("Pandaria Quests")

        panel.subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        panel.subtitle:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -8)
        panel.subtitle:SetText("Select a zone")

        panel.buttons = {}
        for index, info in ipairs(NBTW_MOP_CATEGORIES) do
            local button = CreateFrame("Button", nil, panel)
            button:SetSize(240, 28)
            if index == 1 then
                button:SetPoint("TOPLEFT", panel.subtitle, "BOTTOMLEFT", 0, -18)
            else
                button:SetPoint("TOPLEFT", panel.buttons[index - 1], "BOTTOMLEFT", 0, -8)
            end
            button.bg = button:CreateTexture(nil, "BACKGROUND")
            button.bg:SetAllPoints()
            button.bg:SetTexture(0.45, 0.02, 0.02, 0.95)
            button.border = button:CreateTexture(nil, "BORDER")
            button.border:SetPoint("TOPLEFT", -1, 1)
            button.border:SetPoint("BOTTOMRIGHT", 1, -1)
            button.border:SetTexture(0.9, 0.8, 0.45, 0.35)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            button.text:SetPoint("CENTER")
            button.text:SetText(info.name)
            button.categoryID = info.id
            button:SetFrameLevel(panel:GetFrameLevel() + 1)
            button:RegisterForClicks("AnyDown", "AnyUp")
            button:SetScript("OnEnter", function(self)
                self.bg:SetTexture(0.65, 0.03, 0.03, 1)
            end)
            button:SetScript("OnLeave", function(self)
                self.bg:SetTexture(0.45, 0.02, 0.02, 0.95)
            end)
            button:SetScript("OnMouseUp", function(self)
                NBTW_OpenCategory(self:GetParent().owner, self.categoryID)
            end)
            panel.buttons[index] = button
        end

        frame.NBTWSimpleList = panel
    end

    frame.NBTWSimpleList:ClearAllPoints()
    frame.NBTWSimpleList:SetPoint("TOPLEFT", frame.Inset or frame, "TOPLEFT", 18, -24)
    frame.NBTWSimpleList:SetPoint("BOTTOMRIGHT", frame.Inset or frame, "BOTTOMRIGHT", -18, 18)
    frame.NBTWSimpleList.owner = frame
    frame.NBTWSimpleList:Show()
end

local function NBTW_OpenDefaultView(frame)
    if not frame then
        return
    end

    NBTW_EnsureFrameReady(frame)
    frame:Show()
    NBTW_ShowSimplePandariaList(frame)
end
local GetLogIndexForQuestID = C_QuestLog and C_QuestLog.GetLogIndexForQuestID or GetQuestLogIndexByID
local IsQuestComplete = C_QuestLog and C_QuestLog.IsComplete or IsQuestComplete
local GetQuestIDForQuestIndex = C_QuestLog and C_QuestLog.GetInfo and function (questLogIndex)
    return C_QuestLog.GetInfo(questLogIndex).questID
end or function (questLogIndex)
    return (select(8, GetQuestLogTitle(questLogIndex)))
end
local GetQuestLogIsAutoComplete = C_QuestLog and C_QuestLog.GetInfo and function (questLogIndex)
    return C_QuestLog.GetInfo(questLogIndex).isAutoComplete
end or GetQuestLogIsAutoComplete or function () return false end
local ShowQuestDetails = QuestMapFrame_OpenToQuestDetails or function (questID)
    local mapID
    local quest = BtWQuestsDatabase:GetQuestByID(questID)
    if IsQuestComplete(questID) then
        if BtWQuests.Settings.showMapTurnIns and quest:HasTarget() then
            mapID = quest:GetTargetMapID()
        end
    elseif quest:HasObjectives() then
        if BtWQuests.Settings.showMapPOIs then
            mapID = quest:GetCurrentObjectiveMapID()
        end
    end

    if mapID then
        ShowUIPanel(WorldMapFrame);
        MaximizeUIPanel(WorldMapFrame);
        WorldMapFrame:SetMapID(mapID)
    else
        ShowUIPanel(QuestLogFrame);
        QuestLog_SetSelection(GetQuestLogIndexByID(questID))
    end

    return true
end
local function CanCompleteQuest(questLogIndex)
    return IsQuestComplete(GetQuestIDForQuestIndex(questLogIndex)) and GetQuestLogIsAutoComplete(questLogIndex)
end
local GetAddOnMetadata = GetAddOnMetadata or (C_AddOns and C_AddOns.GetAddOnMetadata)
local GetMouseFocus = GetMouseFocus or function ()
    return GetMouseFoci()[1]
end

function BtWQuests_OnAddonCompartmentClick()
    BtWQuestsFrame:Show()
end

BtWQuestsFrameChainViewMixin = {}
function BtWQuestsFrameChainViewMixin:GetTooltip()
    return BtWQuestsFrame.Tooltip
end
function BtWQuestsFrameChainViewMixin:SelectFromLink(...)
    return BtWQuestsFrame:SelectFromLink(...)
end
function BtWQuestsFrameChainViewMixin:GetCharacter()
    return BtWQuestsFrame:GetCharacter()
end

local function SettingsCreate(options)
	local optionsByKey = {};
	local defaults = {};
	for _,option in ipairs(options) do
		optionsByKey[option.key] = option;
		defaults[option.key] = option.default;
	end

	local result = Mixin({}, options);
	local mt = {}
    function mt.__call(_, tbl)
        setmetatable(tbl, {__index = defaults});
        mt.__index = tbl;
    end
    function mt.__newindex(self, key, value)
        local option = optionsByKey[key];
        if option then
            local func = option.saveValue;
            if func then
                value = func(self, key, value)
                if value ~= nil then
                    mt.__index[key] = value
                end
            else
                mt.__index[key] = value;
            end

            func = option.onChange;
            if func then
                func(self, key, value);
            end
        else
            mt.__index[key] = value;
        end
    end
    function mt.__add(self, option)
        rawset(self, #self+1, option)
        optionsByKey[option.key] = option;
        defaults[option.key] = option.default;
        return self
    end
	setmetatable(result, mt);
	result({});

	return result;
end
local Settings = SettingsCreate({
    {
        name = L["SHOW_MINIMAP_ICON"],
        key = "minimapShown",
        onChange = function (_, id, value)
            BtWQuestsMinimapButton:SetShown(value)
        end,
        default = true,
    },
    {
        name = L["SHOW_MAP_PINS"],
        key = "showMapPins",
        onChange = function (_, id, value)
            if value then
                -- Trigger creation of map pins
                BtWQuestsFrame:OnEvent("PLAYER_ENTERING_WORLD")
            end

            if WorldMapFrame:IsShown() then
                WorldMapFrame:RefreshAllDataProviders()
            end
        end,
        default = true,
    },
    {
        name = L["SHOW_MAP_OBJECTIVES"],
        key = "showMapPOIs",
        onChange = function (_, id, value)
            if value then
                -- Trigger creation of map pins
                BtWQuestsFrame:OnEvent("PLAYER_ENTERING_WORLD")
            end

            if WorldMapFrame:IsShown() then
                WorldMapFrame:RefreshAllDataProviders()
            end
        end,
        default = GetQuestPOIs == nil,
        visible = GetQuestPOIs == nil,
    },
    {
        name = L["SHOW_MAP_TURN_INS"],
        key = "showMapTurnIns",
        onChange = function (_, id, value)
            if value then
                -- Trigger creation of map pins
                BtWQuestsFrame:OnEvent("PLAYER_ENTERING_WORLD")
            end

            if WorldMapFrame:IsShown() then
                WorldMapFrame:RefreshAllDataProviders()
            end
        end,
        default = GetQuestPOIs == nil,
        visible = GetQuestPOIs == nil,
    },
    {
        name = L["USE_SMALL_MAP_ICONS"],
        key = "smallMapPins",
        onChange = function (_, id, value)
            if WorldMapFrame:IsShown() then
                WorldMapFrame:RefreshAllDataProviders()
            end
        end,
        default = false,
    },
    {
        name = L["SHOW_CATEGORY_AS_GRID"],
        key = "gridView",
        default = true,
    },
    {
        name = L["SHOW_CATEGORY_HEADERS"],
        key = "categoryHeaders",
        default = false,
    },
    {
        name = L["GROUP_COMPLETED"],
        key = "filterCompleted",
        default = false,
    },
    {
        name = L["GROUP_IGNORED"],
        key = "filterIgnored",
        default = false,
    },
    {
        name = L["SHOW_QUEST_CHAIN_TOOLTIP"],
        key = "showChainTooltip",
        default = true,
    },
    {
        name = L["SPOILER_FREE"],
        key = "hideSpoilers",
        default = false,
    },
    {
        name = L["USE_TOMTOM_WAYPOINTS"],
        key = "useTomTom",
        default = true,
    },
    {
        name = L["ACCOUNT_BOUND_SETTINGS"],
        key = "useAccountBoundSettings",
        saveValue = function (Settings, id, value)
            BtWQuests_Settings.useAccountBoundSettings = value

            -- Clone current characters settings to account bound settings
            if BtWQuests_AccountSettings == nil and value then
                BtWQuests_AccountSettings = Mixin({}, BtWQuests_Settings)
            end

            if value then
                Settings(BtWQuests_AccountSettings)
            else
                Settings(BtWQuests_Settings)
            end

            for _,option in ipairs(Settings) do
                local func = option.onChange
                if func and option.visible ~= false then
                    func(Settings, option.key, Settings[option.key]);
                end
            end
        end,
        default = true,
    },
});
BtWQuests.Settings = Settings;

BtWQuestsOptionsMenuMixin = {}
function BtWQuestsOptionsMenuMixin:OnLoad()
	self.displayMode = "MENU"
end
function BtWQuestsOptionsMenuMixin:Initialize()
    local function Select (button)
        Settings[button.value] = not button.checked
        if BtWQuestsFrame:IsShown() then
            BtWQuestsFrame:Refresh()
        end
    end

    local info = self:CreateInfo();
    info.isNotRadio = true
    -- info.keepShownOnClick = true

    for _,option in ipairs(Settings) do
        if option.visible ~= false then
            info.text = option.name
            info.value = option.key
            info.checked = Settings[option.key]
            info.func = Select
            self:AddButton(info)
        end
    end
end

BtWQuestsMixin = {}
function BtWQuestsMixin:GetCharacter()
    if not self.Character then
        self:SelectCharacter(BtWQuestsCharacters:GetPlayer());
    end
    return self.Character
end
function BtWQuestsMixin:SelectCharacter(name, realm)
    local character
    if type(name) == "table" then
        character = name;
    else
        local key
        if realm == nil then
            key = name
        else
            key = name .. "-" .. realm
        end

        character = BtWQuestsCharacters:GetCharacter(key)
    end
    if character ~= nil then
        self.Character = character
        UIDropDownMenu_SetText(self.CharacterDropDown, character:GetDisplayName())

        if self:IsShown() then
            self:Refresh()
        end
    end
end

function BtWQuestsMixin:GetExpansion()
    return self.expansionID
end
function BtWQuestsMixin:SetExpansion(id)
    self.expansionID = tonumber(id)
    self.categoryID = nil
    self.chainID = nil
end
function BtWQuestsMixin:SelectExpansion(id, scrollTo, noHistory)
    if not noHistory then
        self:UpdateCurrentHistory()
    end

    self:SetExpansion(id)

    if id == nil then
        self.navBar:Reset()
    else
        self.navBar:SetExpansion(id)
    end

    local expansion = self:GetExpansion()
    if expansion and BtWQuestsDatabase:HasExpansion(expansion) then
        self.ExpansionDropDown:SetText(BtWQuestsDatabase:GetExpansionByID(expansion):GetName());
    end

    if expansion == nil then
        self:DisplayExpansionList(scrollTo)
    else
        self:DisplayCurrentExpansion(scrollTo)
    end

    if not noHistory then
        self:AddCurrentToHistory()
    end
end

function BtWQuestsMixin:GetCategory()
    return self.categoryID
end
function BtWQuestsMixin:SetCategory(id)
    if id == nil then
        self.categoryID = nil
        self.chainID = nil
    else
        self.categoryID = tonumber(id)
        self.chainID = nil
        self.expansionID = select(4, BtWQuestsDatabase:GetCategoryByID(self.categoryID, self:GetCharacter()))
    end
end
function BtWQuestsMixin:SelectCategory(id, scrollTo, noHistory)
    if not noHistory then
        self:UpdateCurrentHistory()
    end

    local character = self:GetCharacter();
    local category = BtWQuestsDatabase:GetCategoryByID(id)
    if not category then
        category = BtWQuestsDatabase:LoadCategory(id)
    end
    assert(category, L["Failed to find request category"])
    if not category:IsValidForCharacter(character) then
        id = category:GetAlternative(character) or id
    end

    self:SetCategory(id)
    self.navBar:SetCategory(id)
    if self.NBTWSimpleList then
        self.NBTWSimpleList:Hide()
    end

    self:DisplayCurrentCategory(scrollTo)

    if not noHistory then
        self:AddCurrentToHistory()
    end
end

function BtWQuestsMixin:GetChain()
    return self.chainID
end
function BtWQuestsMixin:SetChain(id)
    self.chainID = tonumber(id)
    self.expansionID, self.categoryID = select(4, BtWQuestsDatabase:GetChainByID(self.chainID, self:GetCharacter()))
end
function BtWQuestsMixin:SelectChain(id, scrollTo, noHistory)
    if not noHistory then
        self:UpdateCurrentHistory()
    end

    local character = self:GetCharacter();
    local chain = BtWQuestsDatabase:GetChainByID(id)
    if not chain then
        chain = BtWQuestsDatabase:LoadChain(id)
    end
    assert(chain, L["Failed to find request chain"])
    if not chain:IsValidForCharacter(character) then
        id = chain:GetAlternative(character) or id
    end

    self:SetChain(id)
    self.navBar:SetChain(id)
    if self.NBTWSimpleList then
        self.NBTWSimpleList:Hide()
    end

    self:DisplayCurrentChain(scrollTo)

    if not noHistory then
        self:AddCurrentToHistory()
    end
end
function BtWQuestsMixin:SelectFromLink(link, scrollTo)
    local _, _, color, type, text, name = string.find(link, "|cff(%x*)|H([^:]+):([^|]+)|h%[([^%[%]]*)%]|h|r")
    if not color then
        _, _, type, text = string.find(link, "([^:]+):(.+)")
    end
    if type == "garrmission" then
        _, _, type, text = string.find(text, "^([^:]*):(.*)")
    end

    assert(type == "quest" or type == "btwquests")

    self.SearchBox:ClearFocus()

    if type == "quest" then
        local _, _, id = string.find(text, "^(%d+):")

        id = tonumber(id)

        local questLogIndex = GetLogIndexForQuestID(id);
        if questLogIndex and questLogIndex > 0 then
            if CanCompleteQuest(questLogIndex) then
                AutoQuestPopupTracker_RemovePopUp(id);
                ShowQuestComplete(questLogIndex);

                return true
            else
                ShowQuestDetails(id)

                return true
            end
        end
    elseif type == "btwquests" then
        local _, _, subtype, id = string.find(text, "^([^:]*):(%d+)")

        assert(subtype == "expansion" or subtype == "category" or subtype == "chain")

        if subtype == "expansion" then
            self:SelectExpansion(id, scrollTo)

            return true
        elseif subtype == "category" then
            self:SelectCategory(id, scrollTo)

            return true
        elseif subtype == "chain" then
            self:SelectChain(id, scrollTo)

            return true
        end
    end

    return false
end
function BtWQuestsMixin:SelectItem(item, scrollTo)
    if item.type == "expansion" then
        self:SelectExpansion(item.id, scrollTo or item.scrollTo)
    elseif item.type == "category" then
        self:SelectCategory(item.id, scrollTo or item.scrollTo)
    elseif item.type == "chain" then
        self:SelectChain(item.id, scrollTo or item.scrollTo)
    end
end

function BtWQuestsMixin:SelectFromHistory()
    local item = self.History[self.HistoryIndex]

    if item.type == "chain" then
        self:SelectChain(item.id, item.scrollTo, true)
    elseif item.type == "category" then
        self:SelectCategory(item.id, item.scrollTo, true)
    elseif item.type == "expansion" then
        self:SelectExpansion(item.id, item.scrollTo, true)
    end
end
function BtWQuestsMixin:Back()
    if self.HistoryIndex > 1 then
        self:UpdateCurrentHistory()

        self.HistoryIndex = self.HistoryIndex - 1

        self:SelectFromHistory()

        self:UpdateHistoryButtons()
    end
end
function BtWQuestsMixin:Forward()
    if self.HistoryIndex < #self.History then
        self:UpdateCurrentHistory()

        self.HistoryIndex = self.HistoryIndex + 1

        self:SelectFromHistory()

        self:UpdateHistoryButtons()
    end
end
function BtWQuestsMixin:Here()
    local mapID = GetBestMapForUnit("player")
    local item = mapID and BtWQuestsDatabase:GetMapItemByID(mapID, self:GetCharacter())

    if item == nil then
        self.NavHere:Disable()
    else
        self:SelectItem(item)
    end
end
function BtWQuestsMixin:ZoomOut()
    self:Back()

    self.Tooltip:Hide();
end
function BtWQuestsMixin:GetCurrentView()
    if self.Chain:IsShown() then
        return {
            type = "chain",
            id = self:GetChain(),
            scrollTo = {
                type = "coords",
                x = self.Chain.Scroll:GetHorizontalScroll(),
                y = self.Chain.Scroll:GetVerticalScroll(),
            }
        };
    elseif self:GetCategory() ~= nil then
        return {
            type = "category",
            id = self:GetCategory(),
            scrollTo = {
                type = "coords",
                x = self.Category.Scroll:GetHorizontalScroll(),
                y = self.Category.Scroll:GetVerticalScroll(),
            }
        };
    else
        return {
            type = "expansion",
            id = self:GetExpansion(),
            scrollTo = {
                type = "coords",
                x = self.Category.Scroll:GetHorizontalScroll(),
                y = self.Category.Scroll:GetVerticalScroll(),
            }
        };
    end
end
function BtWQuestsMixin:AddCurrentToHistory()
    local last = self.History[self.HistoryIndex]
    local current = self:GetCurrentView()

    if last == nil or current.type ~= last.type or current.id ~= last.id then
        self.HistoryIndex = self.HistoryIndex + 1

        while self.History[self.HistoryIndex] do
            table.remove(self.History, self.HistoryIndex)
        end

        table.insert(self.History, current);
    end

    self:UpdateHistoryButtons()
end
function BtWQuestsMixin:UpdateCurrentHistory()
    self.History[self.HistoryIndex] = self:GetCurrentView();
end
function BtWQuestsMixin:UpdateHistoryButtons()
    self.NavBack:SetEnabled(self.HistoryIndex > 1)
    self.NavForward:SetEnabled(self.HistoryIndex < #self.History)
end
function BtWQuestsMixin:UpdateHereButton()
    local mapID = GetBestMapForUnit("player")
    self.NavHere:SetEnabled(mapID ~= nil and BtWQuestsDatabase:GetMapItemByID(mapID, self:GetCharacter()) ~= nil)
end

function BtWQuestsMixin:LoadExpansion(id)
    BtWQuestsDatabase:GetExpansionByID(id):Load()
    self:Refresh()
end
function BtWQuestsMixin:DisplayExpansionList(scrollTo)
    NBTW_ShowSimplePandariaList(self)
end
function BtWQuestsMixin:DisplayItemList(items, scrollTo)
    local gridView = BtWQuests.Settings.gridView

	self.categoryItemPool:ReleaseAll();
    local questSelect = self.Category;

    local character = self:GetCharacter()
    self.Tooltip.character = character

	self.Chain:Hide();
    self.ExpansionList:Hide()
    if self.NBTWSimpleList then
        self.NBTWSimpleList:Hide()
    end
	questSelect:Show();

	local scrollFrame = questSelect.Scroll.Child;
    local scrollToButton

    local startX = 12
    local startY = -10
	local i = 1;
    local index = 1;
    local gridIndex = 1
    local previousButton = nil

    local categoryButton
    for _,item in ipairs(items) do
        if item:GetType() == "header" then
            categoryButton = self.categoryItemPool:Acquire("BtWQuestsCategoryHeaderTemplate")
            if previousButton then
                categoryButton:SetPoint("TOP", previousButton, "BOTTOM", 0, -15)
                categoryButton:SetPoint("LEFT", 5, 0)
            else
                categoryButton:SetPoint("TOPLEFT", 5, -5)
            end
            gridIndex = 1
        elseif gridView then
            categoryButton = self.categoryItemPool:Acquire("BtWQuestsCategoryGridItemTemplate")
            if previousButton then
                if (gridIndex - 1) % 4 == 0 then
                    categoryButton:SetPoint("TOP", previousButton, "BOTTOM", 0, 0)
                    categoryButton:SetPoint("LEFT", 5, 0)
                else
                    categoryButton:SetPoint("LEFT", previousButton, "RIGHT", 0, 0)
                end
            else
                categoryButton:SetPoint("TOPLEFT", 5, -5)
            end
            gridIndex = gridIndex + 1
        else
            categoryButton = self.categoryItemPool:Acquire("BtWQuestsCategoryListItemTemplate")

            if previousButton then
                categoryButton:SetPoint("TOP", previousButton, "BOTTOM", 0, 0)
            else
                categoryButton:SetPoint("TOPLEFT", 5, -5)
            end
        end

        categoryButton:Set(item, character)
        categoryButton:Show()

        if type(scrollTo) == "number" and index == scrollTo then
            scrollToButton = categoryButton
        elseif type(scrollTo) == "table" and item:EqualsItem(scrollTo) then
            scrollToButton = categoryButton
        end

        previousButton = categoryButton
        index = index + 1
    end

    if type(scrollTo) == "table" and scrollTo.type == "coords" then
        questSelect.Scroll:UpdateScrollChildRect()
        -- questSelect.Scroll:SetHorizontalScroll(scrollTo.x)
        questSelect.Scroll:SetVerticalScroll(scrollTo.y)
    elseif scrollTo ~= false then
        if scrollToButton then
            questSelect.Scroll:UpdateScrollChildRect()
            questSelect.Scroll:SetVerticalScroll(-select(5, scrollToButton:GetPoint("TOP")) - (questSelect.Scroll:GetHeight()/2) + 24)
        else
            questSelect.Scroll:SetVerticalScroll(0)
        end
    end

    self:Show();
end
function BtWQuestsMixin:DisplayCurrentExpansion(scrollTo)
    local categoryHeaders = BtWQuests.Settings.categoryHeaders
    local filterCompleted = BtWQuests.Settings.filterCompleted
    local filterIgnored = BtWQuests.Settings.filterIgnored

    local expansion = BtWQuestsDatabase:GetExpansionByID(self:GetExpansion());
    if expansion == nil then
        print(format(L["BTWQUESTS_NO_EXPANSION_ERROR"], "BtWQuests: The War Within"))
        return;
    end
    expansion:Load()
    local items = expansion:GetItemList(self:GetCharacter(), not categoryHeaders, filterCompleted, filterIgnored)
    if #items == 0 then -- Somehow selected an empty expansion, probably means all the BtWQuests modules are disabled
        print(format(L["BTWQUESTS_NO_EXPANSION_ERROR"], "BtWQuests: The War Within"))
    end
    self:DisplayItemList(items, scrollTo)
end
function BtWQuestsMixin:DisplayCurrentCategory(scrollTo)
    local categoryHeaders = BtWQuests.Settings.categoryHeaders
    local filterCompleted = BtWQuests.Settings.filterCompleted
    local filterIgnored = BtWQuests.Settings.filterIgnored

    local category = BtWQuestsDatabase:GetCategoryByID(self:GetCategory())
    local items = category:GetItemList(self:GetCharacter(), not categoryHeaders, filterCompleted, filterIgnored)
    self:DisplayItemList(items, scrollTo)
end
function BtWQuestsMixin:DisplayCurrentChain(scrollTo, zoom)
	local chain = self.Chain;

	self.Category:Hide();
    self.ExpansionList:Hide()
    chain:Show();

    -- chain.Scroll:SetCharacter(self:GetCharacter())
    chain.Scroll:SetHideSpoilers(BtWQuests.Settings.hideSpoilers)
    chain.Scroll:SetChain(self:GetChain(), scrollTo, zoom)

    if BtWQuests.Settings.showChainTooltip then
        chain.Tooltip:ClearAllPoints()
        chain.Tooltip:SetPoint("TOPLEFT", chain, "TOPRIGHT", 5, -3)
        chain.Tooltip:SetOwner(chain, "ANCHOR_PRESERVE")
        chain.Tooltip:SetChain(self:GetChain(), self:GetCharacter())

        if chain:GetRight() > chain.Tooltip:GetLeft() then
            chain.Tooltip:ClearAllPoints()
            chain.Tooltip:SetPoint("TOPRIGHT", chain, "TOPLEFT", -5, -3)
        end
    else
        chain.Tooltip:Hide() -- Just incase it was already visible
    end

    self:Show();
end
function BtWQuestsMixin:UpdateCurrentChain()
    local chain = self.Chain

    if chain:IsShown() then
        chain.Scroll:Update()

        if BtWQuests.Settings.showChainTooltip then
            chain.Tooltip:SetOwner(chain, "ANCHOR_PRESERVE")
            chain.Tooltip:SetChain(self:GetChain(), self:GetCharacter())
        else
            chain.Tooltip:Hide() -- Just incase it was already visible
        end
    end
end

local function ChainItemPool_HideAndClearAnchors(framePool, frame)
	frame:Hide();
	frame:ClearAllPoints();

    if frame.backgroundLinePool then
        frame.backgroundLinePool:ReleaseAll();
    end
end

local GetNumAddOns = C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns;
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata;
local IsAddOnLoadOnDemand = C_AddOns and C_AddOns.IsAddOnLoadOnDemand or IsAddOnLoadOnDemand;
local GetAddOnEnableState = C_AddOns and function (character, addon)
    return C_AddOns.GetAddOnEnableState(addon, character)
end or GetAddOnEnableState;
local LoadAddOn = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn;
local GetAddOnInfo = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo;

function BtWQuestsMixin:OnLoad()
    tinsert(UISpecialFrames, self:GetName());

    self:RegisterForDrag("LeftButton")

    self:RegisterEvent("ADDON_LOADED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")

    self:RegisterEvent("ZONE_CHANGED")
    self:RegisterEvent("ZONE_CHANGED_INDOORS")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")

    if C_QuestSession then
        self:RegisterEvent("QUEST_SESSION_JOINED")
        self:RegisterEvent("QUEST_SESSION_LEFT")
    end
    
    self:RegisterEvent("MODIFIER_STATE_CHANGED")

    if self.TitleContainer then
        self.TitleContainer.TitleText:SetText(L["BTWQUESTS_QUEST_JOURNAL"]);
    else
        self.TitleText:SetText(L["BTWQUESTS_QUEST_JOURNAL"]);
    end
    SetPortraitToTexture(self.portrait or self.PortraitContainer.portrait, "Interface\\QuestFrame\\UI-QuestLog-BookIcon");

    if self.NineSlice then
        if select(4, GetBuildInfo()) >= 100000 then
            -- Temp fix for Dragonflight changes
            self.NavBack:SetFrameLevel(510)
            self.NavForward:SetFrameLevel(510)
            self.NavHere:SetFrameLevel(510)
            self.OptionsButton:SetFrameLevel(510)
            self.CharacterDropDown:SetFrameLevel(510)
        elseif self.NineSlice.TopLeftCorner then
            -- Updated the NineSlice frame for our extra buttons
            self.NineSlice.TopLeftCorner:SetTexture("Interface\\Addons\\BtWQuests\\UI-Frame-Metal")
            self.NineSlice.TopLeftCorner:SetWidth(196)
            self.NineSlice.TopLeftCorner:SetTexCoord(0, 0.3828125, 0, 0.2578125)
    
            self.NineSlice.TopRightCorner:SetTexture("Interface\\Addons\\BtWQuests\\UI-Frame-Metal")
            self.NineSlice.TopRightCorner:SetTexCoord(0, 0.51171875, 0.2578125, 0.515625)
            self.NineSlice.TopRightCorner:SetWidth(262)
        end
    end

    self.categoryItemPool = CreateFramePoolCollection()--CreateFramePool("BUTTON", self.Category.Scroll.Child, "BtWQuestsCategoryButtonTemplate");
	self.categoryItemPool:CreatePool("BUTTON", self.Category.Scroll.Child, "BtWQuestsCategoryHeaderTemplate");
    self.categoryItemPool:CreatePool("BUTTON", self.Category.Scroll.Child, "BtWQuestsCategoryListItemTemplate");
	self.categoryItemPool:CreatePool("BUTTON", self.Category.Scroll.Child, "BtWQuestsCategoryGridItemTemplate");

    self.chainItemPool = CreateFramePool("BUTTON", self.Chain.Scroll.Child, "BtWQuestsChainItemButtonTemplate", ChainItemPool_HideAndClearAnchors);

    self.ExpansionScroll = nil
    self.HistoryIndex = 1
    self.History = {}

	-- LDB launcher
	local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
	if LDB then
		BtWQuestsLauncher = LDB:NewDataObject("BtWQuests", {
			type = "launcher",
            label = "BtWQuests",
			icon = "Interface\\QuestFrame\\UI-QuestLog-BookIcon",
			OnClick = function(clickedframe, button)
                if BtWQuestsFrame:IsShown() then
                    BtWQuestsFrame:Hide()
                else
                    BtWQuestsFrame:Show()
                end
			end,
		})
	end
end
function BtWQuestsMixin:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        if ... == addonName then
            if BtWQuests_Settings == nil then
                BtWQuests_Settings = {}
            end
            Settings(BtWQuests_Settings)
            if Settings.useAccountBoundSettings then
                if BtWQuests_AccountSettings == nil then
                    BtWQuests_AccountSettings = Mixin({}, BtWQuests_Settings)
                end
                Settings(BtWQuests_AccountSettings)
            end

            BtWQuests_AutoLoad = BtWQuests_AutoLoad or {}

            for i=1,GetNumAddOns() do
                -- nbtw is a standalone MoP package; ignore external BtWQuests LoD modules.
                if NBTW_ENABLE_EXTERNAL_MODULES and GetAddOnMetadata(i, "X-BtWQuests") and IsAddOnLoadOnDemand(i) and GetAddOnEnableState((UnitName("player")), i) ~= 0 then -- One of our child addons
                    local name, title, notes, loadable, reason, security, newVersion = GetAddOnInfo(i)
                    local id = tonumber(GetAddOnMetadata(name, "X-BtWQuests-Expansion"))

                    if id then
                        if BtWQuests_AutoLoad[name] == nil then
                            BtWQuests_AutoLoad[name] = GetAddOnMetadata(name, "X-BtWQuests-AutoLoad") == "1"
                        end

                        local expansion = BtWQuestsDatabase:GetExpansionByID(id)
                        if not expansion then
                            local image = GetAddOnMetadata(name, "X-BtWQuests-Expansion-Image")
                            if image then
                                local image, left, right, top, bottom = strsplit(" ", GetAddOnMetadata(name, "X-BtWQuests-Expansion-Image"))
                                expansion = BtWQuestsDatabase:AddExpansion(id, {
                                    image = {
                                        texture = string.format("Interface\\AddOns\\%s\\%s", name, image),
                                        texCoords = {0, 0.90625, 0, 0.8125}
                                    },
                                })
                            else
                                expansion = BtWQuestsDatabase:AddExpansion(id, {})
                            end
                        end

                        local autoload = false
                        expansion.addons = expansion.addons or {}
                        expansion.addons[name] = GetAddOnMetadata(i, "X-BtWQuests")
                        for name in pairs(expansion.addons) do
                            autoload = BtWQuests_AutoLoad[name] or autoload
                        end

                        do
                            local ranges = GetAddOnMetadata(name, "X-BtWQuests-Category-Range")
                            if ranges then
                                BtWQuestsDatabase:AddCategoryRanges(ranges, id)
                            end
                        end
                        do
                            local ranges = GetAddOnMetadata(name, "X-BtWQuests-Chain-Range")
                            if ranges then
                                BtWQuestsDatabase:AddChainRanges(ranges, id)
                            end
                        end

                        if autoload then
                            for name in pairs(expansion.addons) do
                                BtWQuests_AutoLoad[name] = true
                                LoadAddOn(name)
                            end
                        end
                    end
                end
            end

            if not BtWQuestsDatabase:HasMultipleExpansion() then
                local expansion = BtWQuestsDatabase:GetFirstExpansion()
                if expansion then
                    expansion:Load()
                else
                    print(format(L["BTWQUESTS_NO_EXPANSION_ERROR"], "BtWQuests: The War Within"))
                end
            end

            if Menu then
                Menu.ModifyMenu("MENU_QUEST_OBJECTIVE_TRACKER", function(owner, rootDescription, contextData)
                    local frame = GetMouseFoci()[1]:GetParent();
                    local questID = frame.id;
                    BtWQuests_AddOpenChainMenuItem(owner, rootDescription, questID)
                end);
                Menu.ModifyMenu("MENU_QUEST_MAP_LOG_TITLE", function(owner, rootDescription, contextData)
                    local questID = owner.questID;
                    BtWQuests_AddOpenChainMenuItem(owner, rootDescription, questID)
                end);
            end

            if GetAddOnInfo and select(5, GetAddOnInfo("BtWQuestsEditor")) == "DEMAND_LOADED" then
                Settings = Settings + {
                    name = "Enable Editor (reload on disable)",
                    key = "enableEditor",
                    default = false,
                    onChange = function(_, id, value)
                        if value then
                            LoadAddOn("BtWQuestsEditor")
                        elseif BtWQuestsEditor then
                            ReloadUI() -- Gotta reload to disable an addon
                        end
                    end
                }

                if BtWQuests.Settings.enableEditor then
                    LoadAddOn("BtWQuestsEditor")
                end
            end
        elseif (...):sub(1, 9) == "BtWQuests" then
            if self:IsShown() then
                self:UpdateHereButton()
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not self.addedQuestDataProviders and (BtWQuests.Settings.showMapPins or BtWQuests.Settings.showMapPOIs or BtWQuests.Settings.showMapTurnIns) then
            self.addedQuestDataProviders = true
            LibMapPinHandler[WorldMapFrame]:AddDataProvider(CreateFromMixins(BtWQuestsQuestDataProviderMixin));
            if not GetQuestPOIs then
                LibMapPinHandler[WorldMapFrame]:AddDataProvider(CreateFromMixins(BtWQuestsQuestPOIDataProviderMixin));
            end
        end
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
        if self:IsShown() then
            self:UpdateHereButton()
        end
    elseif event == "QUEST_SESSION_JOINED" or event == "QUEST_SESSION_LEFT" then
        -- Both the current character and party sync are considered "the player"
        if self:GetCharacter():IsPlayer() then
            self.Character = nil;
            self:GetCharacter();
        end
    elseif event == "MODIFIER_STATE_CHANGED" then
        if ... == "LSHIFT" or ... == "RSHIFT" then
            -- Update tooltips
            local chain = self.Chain
            if chain:IsShown() and BtWQuests.Settings.showChainTooltip then
                chain.Tooltip:SetOwner(chain, "ANCHOR_PRESERVE")
                chain.Tooltip:SetChain(self:GetChain(), self:GetCharacter())
            end

            local tooltip = self.Tooltip
            if tooltip:IsShown() then
                local button = GetMouseFocus()
                if button.OnEnter then
                    button:OnEnter()
                end
                -- tooltip:SetOwner(tooltip, "ANCHOR_PRESERVE")
                -- tooltip:SetChain(self:GetChain(), self:GetCharacter())
            end
        end
    end
end
function BtWQuestsMixin:OnDragStart()
    if self.Chain.Tooltip:IsVisible() then
        self:SetScript("OnUpdate", function (self)
            local chain = self.Chain;
            local point = chain.Tooltip:GetPoint()
            if point == "TOPRIGHT" then
                if chain:GetRight() + chain.Tooltip:GetWidth() + 5 < UIParent:GetWidth() then
                    chain.Tooltip:ClearAllPoints()
                    chain.Tooltip:SetPoint("TOPLEFT", chain, "TOPRIGHT", 5, -3)
                end
            else
                if chain:GetRight() + chain.Tooltip:GetWidth() + 5 > UIParent:GetWidth() then
                    chain.Tooltip:ClearAllPoints()
                    chain.Tooltip:SetPoint("TOPRIGHT", chain, "TOPLEFT", -5, -3)
                end
            end
        end);
    end
    self:StartMoving();
end
function BtWQuestsMixin:OnDragStop()
    self:StopMovingOrSizing();
    self:SetScript("OnUpdate", nil);
end
function BtWQuestsMixin:Refresh()
    if self:GetChain() ~= nil then
        self:SelectChain(self:GetChain(), nil, true)
    elseif self:GetCategory() ~= nil then
        self:SelectCategory(self:GetCategory(), nil, true)
    elseif self:GetExpansion() ~= nil then
        self:SelectExpansion(self:GetExpansion(), nil, true)
    else
        local expansion = BtWQuestsDatabase:GetExpansionByID(NBTW_MOP_EXPANSION_ID)
        if expansion then
            self:SelectExpansion(NBTW_MOP_EXPANSION_ID, false, true)
        else
            self.navBar:Reset()
            self:DisplayExpansionList(false)
        end
    end
end
function BtWQuestsMixin:OnShow()
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN);

    self:UpdateHereButton()

    if not self.initialized then
        self:SelectCharacter(BtWQuestsCharacters:GetPlayer())

        self.navBar:EnableExpansions(BtWQuestsDatabase:HasMultipleExpansion())

        if self:GetExpansion() == nil then -- Not guessed/set an expansion yet
            local mopExpansion = BtWQuestsDatabase:GetExpansionByID(NBTW_MOP_EXPANSION_ID)
            if mopExpansion then
                mopExpansion:Load()
                self:SelectExpansion(NBTW_MOP_EXPANSION_ID, nil, true)
            else
            local expansion = BtWQuestsDatabase:GetLoadedExpansion()
            if expansion then
                self:SelectExpansion(expansion:GetID(), nil, true)
            elseif not BtWQuestsDatabase:HasMultipleExpansion() then
                local expansion = BtWQuestsDatabase:GetFirstExpansion()
                if expansion then
                    self:SelectExpansion(BtWQuestsDatabase:GetFirstExpansion():GetID(), nil, true)
                else
                    print(format(L["BTWQUESTS_NO_EXPANSION_ERROR"], "BtWQuests: The War Within"))
                end
            end
            end
        end

        -- Quick fix for AddOnSkins issue
        if self.Chain.Scroll.ScrollBar.ThumbTexture and self.Chain.Scroll.ScrollBar.ThumbTexture.Backdrop then
            self.Chain.Scroll.ScrollBar.ThumbTexture.Backdrop:SetFrameLevel(self.Chain.Scroll.ScrollBar.Backdrop:GetFrameLevel())
            self.Category.Scroll.ScrollBar.ThumbTexture.Backdrop:SetFrameLevel(self.Category.Scroll.ScrollBar.Backdrop:GetFrameLevel())
        end

        self.initialized = true
    else
        if self:GetChain() ~= nil then
            self:UpdateCurrentChain()
        elseif self:GetCategory() ~= nil then
            self:DisplayCurrentCategory()
        elseif self:GetExpansion() ~= nil then
            self:DisplayCurrentExpansion()
        else
            local expansion = BtWQuestsDatabase:GetExpansionByID(NBTW_MOP_EXPANSION_ID)
            if expansion then
                self:SelectExpansion(NBTW_MOP_EXPANSION_ID, nil, true)
            else
                self:DisplayExpansionList()
            end
        end
    end
end
function BtWQuestsMixin:OnHide(self)
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE);
end

function BtWQuestsChainFrame_OnShow(self)
    self:RegisterEvent("QUEST_ACCEPTED")
    self:RegisterEvent("QUEST_AUTOCOMPLETE")
    self:RegisterEvent("QUEST_COMPLETE")
    self:RegisterEvent("QUEST_FINISHED")
    self:RegisterEvent("QUEST_TURNED_IN")
    if INTERFACE_NUMBER >= 70200 then
        self:RegisterEvent("QUEST_LOG_CRITERIA_UPDATE")
    end
    self:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
    self:RegisterEvent("QUEST_WATCH_UPDATE")
end
function BtWQuestsChainFrame_OnHide(self)
    self:UnregisterAllEvents()
end
function BtWQuestsChainFrame_OnEvent(self, ...)
    self:GetParent():UpdateCurrentChain()
end
function BtWQuestsChainFrameScrollFrame_OnUpdate(self)
    local mouseX, mouseY = GetCursorPosition()
    local scale = self:GetEffectiveScale()
    mouseX, mouseY = mouseX / scale, mouseY / scale

    local maxXScroll, maxYScroll = self:GetHorizontalScrollRange(), self:GetVerticalScrollRange()

    mouseX = min(max(mouseX - self.mouseX + self.scrollX, 0), maxXScroll)
    mouseY = min(max(mouseY - self.mouseY + self.scrollY, 0), maxYScroll)

    self:SetHorizontalScroll(mouseX)
    self:SetVerticalScroll(mouseY)
end

function BtWQuestsMixin:ShowFullSearch()
    self.SearchBox:ShowFullSearch()
end

-- [[ Compatibility functions ]]
-- These functions use the character from BtWQuestsFrame
function BtWQuests_GetQuestName(id)
    return BtWQuestsDatabase:GetQuestName(id)
end
function BtWQuests_IsQuestCompleted(id)
    return BtWQuestsFrame:GetCharacter():IsQuestCompleted(id)
end
function BtWQuests_IsQuestActive(id)
    return BtWQuestsFrame:GetCharacter():IsQuestActive(id)
end

function BtWQuests_GetChainName(id)
    return BtWQuestsDatabase:GetChainName(id, BtWQuestsFrame:GetCharacter())
end
function BtWQuests_IsChainCompleted(id)
    return BtWQuestsFrame:GetCharacter():IsChainCompleted(id)
end
function BtWQuests_IsChainActive(id)
    return BtWQuestsFrame:GetCharacter():IsChainCompleted(id)
end

function BtWQuests_GetCategoryName(id)
    return BtWQuestsDatabase:GetCategoryName(id, BtWQuestsFrame:GetCharacter())
end
function BtWQuests_IsCategoryCompleted(id)
    return BtWQuestsFrame:GetCharacter():IsCategoryCompleted(id)
end
function BtWQuests_IsCategoryActive(id)
    return BtWQuestsFrame:GetCharacter():IsCategoryCompleted(id)
end

-- [[ Waypoint ]]
function BtWQuests_AddWaypoint(mapId, x, y, name)
    if BtWQuests.Settings.useTomTom and TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(mapId, x, y, {
            title = name,
        })
    elseif BtWQuests.Guide then
        BtWQuests.Guide:AddWayPoint(mapId, x, y, name)
    end
end
function BtWQuests_ShowMapWithWaypoint(mapId, x, y, name)
    BtWQuests_AddWaypoint(mapId, x, y, name)

    if not IsModifiedClick("CHATLINK") then
        ShowUIPanel(WorldMapFrame);
        if INTERFACE_NUMBER < 90000 then
            MaximizeUIPanel(WorldMapFrame);
        end
        WorldMapFrame:SetMapID(mapId);
    end
end

-- [[ Quest To Chain ]]
function BtWQuests_AddOpenChainMenuItem(owner, rootDescription, questID)
    local item = BtWQuestsDatabase:GetQuestItem(questID, BtWQuestsCharacters:GetPlayer())
    if item then
        rootDescription:CreateDivider()
        rootDescription:CreateTitle(addonName)
        rootDescription:CreateButton(L["BTWQUESTS_OPEN_QUEST_CHAIN"], function()
            BtWQuestsFrame:SelectCharacter(UnitName("player"), GetRealmName())
            BtWQuestsFrame:SelectItem(item.item)
        end)
    end
end

-- [[ Slash Command ]]
local function BtWQuests_ToggleFrame()
    if not BtWQuestsFrame then
        print("nbtw: frame is not ready")
        return
    end

    if BtWQuestsFrame:IsShown() then
        BtWQuestsFrame:Hide()
    else
        NBTW_OpenDefaultView(BtWQuestsFrame)
    end
end

local function BtWQuests_HandleSlash(msg)
    msg = (msg or ""):lower()
    if msg == "minimap" then
        if BtWQuestsMinimapButton_Toggle then
            BtWQuestsMinimapButton_Toggle()
        else
            print("nbtw: minimap button is not ready")
        end
    else
        BtWQuests_ToggleFrame()
    end
end

SLASH_BTWQUESTS1 = "/nbtwmain"
SlashCmdList["BTWQUESTS"] = function(msg)
    local ok, err = pcall(BtWQuests_HandleSlash, msg)
    if not ok then print("nbtw error: " .. tostring(err)) end
end


-- [[ Hyperlink Handling ]]

local function ChatFrame_Filter(self, event, msg, ...)
    msg = msg:gsub("%[btwquests:([^:]+):(%d+):([^:]+):([^%]]+)%]","|c%3|Hgarrmission:btwquests:%1:%2|h[%4]|h|r"):gsub("https://www.btwquests.com/([^/]+)/(%d+)[-%w]*","|cffffff00|Hgarrmission:btwquests:%1:%2|h[%0]|h|r")

	return false, msg, ...;
end

local events = {
	"CHAT_MSG_SAY",
	"CHAT_MSG_YELL",
	"CHAT_MSG_EMOTE",
	"CHAT_MSG_GUILD",
	"CHAT_MSG_OFFICER",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING",
	"CHAT_MSG_BATTLEGROUND",
	"CHAT_MSG_BATTLEGROUND_LEADER",
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_BN_WHISPER_INFORM",
	"CHAT_MSG_BN_CONVERSATION",
	"CHAT_MSG_BN_INLINE_TOAST_BROADCAST",
	"CHAT_MSG_BN_INLINE_TOAST_BROADCAST_INFORM",
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_COMMUNITIES_CHANNEL",
};

for i, event in ipairs(events) do
	ChatFrame_AddMessageEventFilter(event, ChatFrame_Filter);
end

-- Convert our links to something valid for blizzard to send
hooksecurefunc("ChatEdit_ParseText", function (editBox, send, parseIfNoSpaces)
    if send == 1 then
        local text = editBox:GetText()
        text = text:gsub("|c(%x*)|Hgarrmission:btwquests:([^|]+)|h%[([^%[%]]*)%]|h|r", function (color,str,name)
            return string.format("[btwquests:%s:%s:%s]", str, color,name)
        end):gsub("|Hgarrmission:btwquests:([^|]+)|h%[([^%[%]]*)%]|h", function (str,name)
            return string.format("[btwquests:%s:%s:%s]", str, "ffffff00",name)
        end)
        editBox:SetText(text)
    end
end)

hooksecurefunc("SetItemRef", function(link, text)
    if link:find("garrmission:btwquests") then
        if IsModifiedClick("CHATLINK") then
            ChatEdit_InsertLink(text)
        else
            BtWQuestsFrame:SelectFromLink(text)
        end
    end
end);
