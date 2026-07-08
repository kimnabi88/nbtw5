local categories = {
    {id = 501, name = "비취 숲"},
    {id = 502, name = "네 바람의 계곡"},
    {id = 503, name = "크라사랑 밀림"},
    {id = 504, name = "쿤라이 봉우리"},
    {id = 505, name = "탕랑 평원"},
    {id = 506, name = "공포의 황무지"},
}

local chainNames = {
    [50101] = "포우돈 마을",
    [50102] = "물예언 의식",
    [50103] = "하얀 폰",
    [50104] = "진주지느러미 마을",
    [50105] = "헬스크림의 철권호의 잔해",
    [50106] = "첫 조우",
    [50107] = "수상한 협력자",
    [50108] = "그루끼끼 언덕",
    [50109] = "새벽의 꽃",
    [50110] = "녹옥 채석장",
    [50111] = "티엔 수도원",
    [50112] = "열 천둥의 정원",
    [50113] = "옥룡사",
    [50114] = "감로바람 과수원",
    [50115] = "숲의 전투",
    [50116] = "숲의 전투",
    [50117] = "의심 이겨내기",
    [50201] = "썬더풋 밭",
    [50202] = "머드머그의 집",
    [50203] = "첸의 걸작",
    [50204] = "스톰스타우트 양조장",
    [50205] = "은둔 고수",
    [50206] = "네싱워리의 원정대",
}

local questNames = {
    [54870] = "장군 나즈그림",
    [29612] = "전쟁의 기술",
    [1853] = "모두 탑승!",
    [29690] = "안개 속으로",
    [31765] = "붉게 물들여라!",
    [31766] = "착륙",
    [31767] = "끝장을 내라!",
    [31768] = "불이 언제나 답이다",
    [31769] = "최후의 일격!",
    [31770] = "우리 편이 아니면...",
    [29694] = "재집결!",
    [31771] = "결과와 대면하기",
    [31773] = "배회자 문제",
    [31978] = "우선순위!",
}

local ShowCategory
local ShowChain
local ShowZones
local ShowSearchResults
local PAGE_SIZE = 8
local FRAME_WIDTH = 540
local FRAME_HEIGHT = 496

local function GetCharacter()
    if BtWQuestsFrame and BtWQuestsFrame.GetCharacter then
        return BtWQuestsFrame:GetCharacter()
    end
    if BtWQuestsCharacters and BtWQuestsCharacters.GetPlayer then
        return BtWQuestsCharacters:GetPlayer()
    end
    return nil
end

local function RunSafe(label, func)
    local ok, err = pcall(func)
    if not ok then
        print("nbtw " .. tostring(label) .. " 오류: " .. tostring(err))
    end
end

local function GetDisplayName(item, character, fallbackType)
    local id
    if item.GetID then
        local okID, resultID = pcall(item.GetID, item)
        if okID then
            id = resultID
        end
    end
    if id and chainNames[id] then
        return chainNames[id]
    end
    if id and questNames[id] then
        return questNames[id]
    end
    if item.GetName then
        local ok, name = pcall(item.GetName, item, character)
        if ok and name then
            return name
        end
    end
    return tostring(fallbackType or "항목") .. " " .. tostring(id or "?")
end

local function GetDatabaseName(itemType, id)
    if not BtWQuestsDatabase or not id then
        return nil
    end
    if itemType == "chain" and chainNames[id] then
        return chainNames[id]
    end
    if itemType == "quest" and questNames[id] then
        return questNames[id]
    end
    if itemType == "quest" and BtWQuestsDatabase.GetQuestName then
        local ok, name = pcall(BtWQuestsDatabase.GetQuestName, BtWQuestsDatabase, id)
        if ok and name then
            return name
        end
    end

    local getter
    if itemType == "npc" then
        getter = BtWQuestsDatabase.GetNPCByID
    elseif itemType == "object" then
        getter = BtWQuestsDatabase.GetObjectByID
    elseif itemType == "chain" then
        getter = BtWQuestsDatabase.GetChainByID
    end
    if getter then
        local ok, data = pcall(getter, BtWQuestsDatabase, id)
        if ok and data and data.GetName then
            local okName, name = pcall(data.GetName, data)
            if okName and name then
                return name
            end
        end
    end
    return nil
end

local function GetRawDisplayName(raw)
    if not raw then
        return "항목 ?"
    end
    local source = raw
    if raw.variations and raw.variations[1] then
        source = raw.variations[1]
    elseif raw[1] then
        source = raw[1]
    end
    local itemType = source.type or raw.type or "item"
    local id = source.id or raw.id
    if not id and source.ids then
        id = source.ids[1]
    end
    if not id and raw.ids then
        id = raw.ids[1]
    end
    local name = GetDatabaseName(itemType, id)
    if name then
        return name, itemType, id
    end
    return tostring(itemType or "항목") .. " " .. tostring(id or "?"), itemType, id
end

local function GetChainItemSafe(chain, index, character)
    local ok, item = pcall(chain.GetItem, chain, index, character)
    if ok then
        return item
    end
    return nil, item
end

local function TextMatches(text, query)
    if not text or not query then
        return false
    end
    return string.find(string.lower(tostring(text)), string.lower(tostring(query)), 1, true) ~= nil
end

local function ResultMatches(result, query)
    return TextMatches(result.name, query)
        or TextMatches(result.zoneName, query)
        or TextMatches(result.chainName, query)
        or TextMatches(result.itemType, query)
        or TextMatches(result.id, query)
end

local function AddSearchResult(results, seen, result)
    local key = tostring(result.kind or "?") .. ":" .. tostring(result.id or "?") .. ":" .. tostring(result.chainID or "?") .. ":" .. tostring(result.categoryID or "?")
    if seen[key] then
        return
    end
    seen[key] = true
    results[#results + 1] = result
end

local function GetPageBounds(total, page)
    local maxPage = math.max(1, math.ceil(total / PAGE_SIZE))
    page = math.max(1, math.min(page or 1, maxPage))
    local first = ((page - 1) * PAGE_SIZE) + 1
    local last = math.min(first + PAGE_SIZE - 1, total)
    return page, maxPage, first, last
end

local function OpenQuestLogByID(questID)
    if type(questID) ~= "number" then
        return false
    end
    local index = GetQuestLogIndexByID and GetQuestLogIndexByID(questID)
    if not index or index <= 0 then
        return false
    end
    if QuestLogFrame then
        ShowUIPanel(QuestLogFrame)
    end
    if SelectQuestLogEntry then
        SelectQuestLogEntry(index)
    end
    if QuestLog_SetSelection then
        QuestLog_SetSelection(index)
    end
    if QuestLog_Update then
        QuestLog_Update()
    end
    return true
end

local function IsQuestCompletedByID(questID)
    if not questID or type(questID) ~= "number" then
        return false
    end
    if IsQuestFlaggedCompleted then
        local ok, completed = pcall(IsQuestFlaggedCompleted, questID)
        if ok and completed then
            return true
        end
    end
    return false
end

local function IsChainItemCompleted(item, itemType, itemID, character)
    if item and item.IsCompleted then
        local ok, completed = pcall(item.IsCompleted, item, character)
        if ok and completed then
            return true
        end
    end
    if itemType == "quest" then
        return IsQuestCompletedByID(itemID)
    end
    return false
end

local function PrepareButton(panel, index, width, height)
    local button = panel.buttons[index]
    if not button then
        button = CreateFrame("Button", nil, panel)
        if index == 1 then
            button:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -14)
        else
            button:SetPoint("TOPLEFT", panel.buttons[index - 1], "BOTTOMLEFT", 0, -6)
        end
        button.bg = button:CreateTexture(nil, "BACKGROUND")
        button.bg:SetAllPoints()
        button.border = button:CreateTexture(nil, "BORDER")
        button.border:SetPoint("TOPLEFT", -1, 1)
        button.border:SetPoint("BOTTOMRIGHT", 1, -1)
        button.border:SetTexture(0.9, 0.8, 0.45, 0.35)
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button.text:SetPoint("CENTER")
        button:SetFrameLevel(panel:GetFrameLevel() + 10)
        button:RegisterForClicks("AnyUp")
        button:SetScript("OnEnter", function(self)
            self.bg:SetTexture(0.65, 0.03, 0.03, 1)
        end)
        button:SetScript("OnLeave", function(self)
            self.bg:SetTexture(self.normalR or 0.45, self.normalG or 0.02, self.normalB or 0.02, self.normalA or 0.95)
        end)
        panel.buttons[index] = button
    end
    button:SetSize(width, height)
    button.normalR = 0.45
    button.normalG = 0.02
    button.normalB = 0.02
    button.normalA = 0.95
    button.bg:SetTexture(button.normalR, button.normalG, button.normalB, button.normalA)
    button:Show()
    return button
end

local function SetButtonColor(button, r, g, b, a)
    button.normalR = r
    button.normalG = g
    button.normalB = b
    button.normalA = a
    button.bg:SetTexture(r, g, b, a)
end

local function HideButtons(panel)
    for _, button in ipairs(panel.buttons or {}) do
        button:Hide()
        button:SetScript("OnClick", nil)
        button:SetScript("OnMouseUp", nil)
    end
end

local function HideFramePart(part)
    if part and part.Hide then
        part:Hide()
        if part.SetAlpha then
            part:SetAlpha(0)
        end
        if part.EnableMouse then
            part:EnableMouse(false)
        end
    end
end

local function HideFrameTextures(frame)
    if not frame then
        return
    end
    local regions = {frame:GetRegions()}
    for _, region in ipairs(regions) do
        if region and region.SetAlpha and not region.NBTWKeep then
            region:SetAlpha(0)
        end
    end
end

local function SetupPlainBackdrop(frame)
    if not frame.NBTWPlainBackdrop then
        frame.NBTWPlainBackdrop = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        frame.NBTWPlainBackdrop.NBTWKeep = true
        frame.NBTWPlainBackdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -18)
        frame.NBTWPlainBackdrop:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)

        frame.NBTWPlainBorder = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        frame.NBTWPlainBorder.NBTWKeep = true
        frame.NBTWPlainBorder:SetPoint("TOPLEFT", frame.NBTWPlainBackdrop, "TOPLEFT", -1, 1)
        frame.NBTWPlainBorder:SetPoint("BOTTOMRIGHT", frame.NBTWPlainBackdrop, "BOTTOMRIGHT", 1, -1)

        frame.NBTWBorderTop = frame:CreateTexture(nil, "BORDER")
        frame.NBTWBorderTop.NBTWKeep = true
        frame.NBTWBorderTop:SetPoint("TOPLEFT", frame.NBTWPlainBackdrop, "TOPLEFT", 0, 0)
        frame.NBTWBorderTop:SetPoint("TOPRIGHT", frame.NBTWPlainBackdrop, "TOPRIGHT", 0, 0)
        frame.NBTWBorderTop:SetHeight(1)

        frame.NBTWBorderBottom = frame:CreateTexture(nil, "BORDER")
        frame.NBTWBorderBottom.NBTWKeep = true
        frame.NBTWBorderBottom:SetPoint("BOTTOMLEFT", frame.NBTWPlainBackdrop, "BOTTOMLEFT", 0, 0)
        frame.NBTWBorderBottom:SetPoint("BOTTOMRIGHT", frame.NBTWPlainBackdrop, "BOTTOMRIGHT", 0, 0)
        frame.NBTWBorderBottom:SetHeight(1)

        frame.NBTWBorderLeft = frame:CreateTexture(nil, "BORDER")
        frame.NBTWBorderLeft.NBTWKeep = true
        frame.NBTWBorderLeft:SetPoint("TOPLEFT", frame.NBTWPlainBackdrop, "TOPLEFT", 0, 0)
        frame.NBTWBorderLeft:SetPoint("BOTTOMLEFT", frame.NBTWPlainBackdrop, "BOTTOMLEFT", 0, 0)
        frame.NBTWBorderLeft:SetWidth(1)

        frame.NBTWBorderRight = frame:CreateTexture(nil, "BORDER")
        frame.NBTWBorderRight.NBTWKeep = true
        frame.NBTWBorderRight:SetPoint("TOPRIGHT", frame.NBTWPlainBackdrop, "TOPRIGHT", 0, 0)
        frame.NBTWBorderRight:SetPoint("BOTTOMRIGHT", frame.NBTWPlainBackdrop, "BOTTOMRIGHT", 0, 0)
        frame.NBTWBorderRight:SetWidth(1)
    end

    frame.NBTWPlainBackdrop:SetTexture(0, 0, 0, 0.68)
    frame.NBTWPlainBorder:SetTexture(0, 0, 0, 0)
    frame.NBTWBorderTop:SetTexture(0.8, 0.7, 0.35, 0.45)
    frame.NBTWBorderBottom:SetTexture(0.8, 0.7, 0.35, 0.45)
    frame.NBTWBorderLeft:SetTexture(0.8, 0.7, 0.35, 0.45)
    frame.NBTWBorderRight:SetTexture(0.8, 0.7, 0.35, 0.45)
    frame.NBTWPlainBackdrop:Show()
    frame.NBTWPlainBorder:Hide()
    frame.NBTWBorderTop:Show()
    frame.NBTWBorderBottom:Show()
    frame.NBTWBorderLeft:Show()
    frame.NBTWBorderRight:Show()
end

local function SetupFrameSize(frame)
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
end

local function SetupSimpleChrome(frame)
    SetupFrameSize(frame)
    HideFrameTextures(frame)
    HideFramePart(frame.NavBack)
    HideFramePart(frame.NavForward)
    HideFramePart(frame.NavHere)
    HideFramePart(frame.navBar)
    HideFramePart(frame.CharacterDropDown)
    HideFramePart(frame.OptionsButton)
    HideFramePart(frame.ExpansionDropDown)
    HideFramePart(frame.SearchPreview)
    HideFramePart(frame.SearchResults)
    HideFramePart(frame.PortraitContainer)
    HideFramePart(frame.Portrait)
    HideFramePart(_G[frame:GetName() .. "Portrait"])
    HideFramePart(_G[frame:GetName() .. "PortraitFrame"])
    HideFrameTextures(frame.Inset)
    SetupPlainBackdrop(frame)

    if not frame.NBTWTitle then
        frame.NBTWTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        frame.NBTWTitle.NBTWKeep = true
        frame.NBTWTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -2)
    end
    frame.NBTWTitle:SetText("나비퀘스트추적기  made by kimnabi88")
    frame.NBTWTitle:Show()

    if frame.SearchBox then
        frame.SearchBox:ClearAllPoints()
        frame.SearchBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -34)
        frame.SearchBox:SetSize(220, 20)
        frame.SearchBox:SetFrameLevel(frame:GetFrameLevel() + 25)
        frame.SearchBox:Show()
        frame.SearchBox:SetAlpha(1)
        frame.SearchBox:SetScript("OnTextChanged", function(self)
            local owner = self:GetParent()
            if not owner or not owner.NBTWSimpleList or not owner.NBTWSimpleList:IsShown() then
                return
            end
            local text = self:GetText() or ""
            owner.NBTWSimpleList.searchPage = 1
            if text == "" then
                ShowZones(owner)
            else
                ShowSearchResults(owner, text)
            end
        end)
        frame.SearchBox:SetScript("OnEnterPressed", function(self)
            local owner = self:GetParent()
            if owner and owner.NBTWSimpleList then
                owner.NBTWSimpleList.searchPage = 1
                ShowSearchResults(owner, self:GetText() or "")
            end
            self:ClearFocus()
        end)
        frame.SearchBox:SetScript("OnEscapePressed", function(self)
            self:SetText("")
            self:ClearFocus()
            local owner = self:GetParent()
            if owner then
                ShowZones(owner)
            end
        end)
    end
    if frame.CloseButton then
        frame.CloseButton:SetFrameLevel(frame:GetFrameLevel() + 25)
        frame.CloseButton:Show()
        frame.CloseButton:SetAlpha(1)
    end

    if not frame.NBTWRefreshButton then
        local refresh = CreateFrame("Button", nil, frame)
        refresh:SetSize(58, 18)
        refresh:SetPoint("TOPRIGHT", frame.SearchBox or frame, "TOPLEFT", -6, -1)
        refresh:SetFrameLevel(frame:GetFrameLevel() + 25)
        refresh.bg = refresh:CreateTexture(nil, "BACKGROUND")
        refresh.bg:SetAllPoints()
        refresh.bg:SetTexture(0.08, 0.08, 0.08, 0.95)
        refresh.border = refresh:CreateTexture(nil, "BORDER")
        refresh.border:SetPoint("TOPLEFT", -1, 1)
        refresh.border:SetPoint("BOTTOMRIGHT", 1, -1)
        refresh.border:SetTexture(0.9, 0.8, 0.2, 0.45)
        refresh.text = refresh:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        refresh.text:SetPoint("CENTER")
        refresh.text:SetText("새로고침")
        refresh:SetScript("OnClick", function(self)
            local owner = self:GetParent()
            local panel = owner and owner.NBTWSimpleList
            if not panel then
                return
            end
            RunSafe("refresh", function()
                if panel.view == "search" then
                    ShowSearchResults(owner, panel.searchQuery or "")
                elseif panel.view == "chain" then
                    ShowChain(owner, panel.currentChainID, panel.currentChainName)
                elseif panel.view == "category" then
                    ShowCategory(owner, panel.currentCategoryID, panel.currentCategoryName)
                else
                    ShowZones(owner)
                end
            end)
        end)
        frame.NBTWRefreshButton = refresh
    end

    frame.NBTWRefreshButton:Show()

    if not frame.NBTWLockButton then
        local lock = CreateFrame("Button", nil, frame)
        lock:SetSize(44, 18)
        lock:SetPoint("TOPRIGHT", frame.CloseButton or frame, "TOPLEFT", -4, -5)
        lock:SetFrameLevel(frame:GetFrameLevel() + 20)
        lock.bg = lock:CreateTexture(nil, "BACKGROUND")
        lock.bg:SetAllPoints()
        lock.bg:SetTexture(0.08, 0.08, 0.08, 0.95)
        lock.border = lock:CreateTexture(nil, "BORDER")
        lock.border:SetPoint("TOPLEFT", -1, 1)
        lock.border:SetPoint("BOTTOMRIGHT", 1, -1)
        lock.border:SetTexture(0.9, 0.8, 0.2, 0.45)
        lock.text = lock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lock.text:SetPoint("CENTER")
        lock:SetScript("OnClick", function(self)
            local owner = self:GetParent()
            owner.NBTWLocked = not owner.NBTWLocked
            self.text:SetText(owner.NBTWLocked and "잠금" or "이동")
        end)
        frame.NBTWLockButton = lock
    end

    frame.NBTWLocked = frame.NBTWLocked ~= false
    frame.NBTWLockButton.text:SetText(frame.NBTWLocked and "잠금" or "이동")
    frame.NBTWLockButton:Show()

    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not self.NBTWLocked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
end

ShowZones = function(frame)
    local panel = frame.NBTWSimpleList
    if not panel then return end
    panel.view = "zones"
    panel.currentCategoryID = nil
    panel.currentCategoryName = nil
    panel.currentChainID = nil
    panel.currentChainName = nil
    panel.searchQuery = nil
    panel.title:SetText("판다리아 퀘스트")
    HideButtons(panel)
    for index, info in ipairs(categories) do
        local button = PrepareButton(panel, index, 290, 28)
        button.text:SetText(info.name)
        button.zoneID = info.id
        button.zoneName = info.name
        local function clickZone(self)
            RunSafe("zone", function()
                panel.categoryPage = 1
                panel.chainPage = 1
                ShowCategory(frame, self.zoneID, self.zoneName)
            end)
        end
        button:SetScript("OnClick", clickZone)
    end
end

ShowCategory = function(frame, categoryID, fallbackName)
    local panel = frame.NBTWSimpleList
    if not panel then return end
    panel.view = "category"
    panel.currentCategoryID = categoryID
    panel.currentCategoryName = fallbackName
    panel.currentChainID = nil
    panel.currentChainName = nil
    panel.searchQuery = nil
    if not BtWQuestsDatabase then
        print("nbtw: 데이터베이스가 아직 준비되지 않았습니다")
        return
    end
    local category = BtWQuestsDatabase:GetCategoryByID(categoryID)
    if not category and BtWQuestsDatabase.LoadCategory then
        category = BtWQuestsDatabase:LoadCategory(categoryID)
    end
    if not category then
        print("nbtw: 지역을 찾지 못했습니다 - " .. tostring(categoryID))
        return
    end

    panel.title:SetText(fallbackName or category:GetName() or "퀘스트 줄거리")
    HideButtons(panel)

    local character = GetCharacter()
    local ok, itemsOrError = pcall(category.GetItemList, category, character, true, false, false, false, false)
    if not ok then
        print("nbtw 목록 오류: " .. tostring(itemsOrError))
        return
    end

    local back = PrepareButton(panel, 1, 160, 24)
    back.text:SetText("< 지역 목록")
    back:SetScript("OnClick", function()
        RunSafe("back", function()
            ShowZones(frame)
        end)
    end)

    local rows = {}
    for _, item in ipairs(itemsOrError) do
        local okType, itemType = pcall(item.GetType, item)
        if itemType == "chain" or itemType == "category" then
            local okID, itemID = pcall(item.GetID, item)
            local name = GetDisplayName(item, character, itemType)
            rows[#rows + 1] = {
                id = okID and itemID or nil,
                itemType = itemType,
                name = name,
            }
        end
    end

    local page, maxPage, first, last = GetPageBounds(#rows, panel.categoryPage)
    panel.categoryPage = page

    local shown = 1
    for rowIndex = first, last do
        local row = rows[rowIndex]
        shown = shown + 1
        local button = PrepareButton(panel, shown, 430, 24)
        button.text:SetText(row.name)
        button.targetType = row.itemType
        button.targetID = row.id
        button.targetName = row.name
        local function clickItem(self)
            RunSafe("item", function()
                if self.targetType == "category" then
                    panel.categoryPage = 1
                    ShowCategory(frame, self.targetID, self.targetName)
                else
                    panel.lastCategoryID = categoryID
                    panel.lastCategoryName = fallbackName
                    panel.chainPage = 1
                    ShowChain(frame, self.targetID, self.targetName)
                end
            end)
        end
        button:SetScript("OnClick", clickItem)
    end

    if maxPage > 1 then
        if page > 1 then
            shown = shown + 1
            local prev = PrepareButton(panel, shown, 175, 24)
            prev.text:SetText("< 이전 (" .. tostring(page) .. "/" .. tostring(maxPage) .. ")")
            prev:SetScript("OnClick", function()
                RunSafe("prev", function()
                    panel.categoryPage = math.max(1, page - 1)
                    ShowCategory(frame, categoryID, fallbackName)
                end)
            end)
        end

        if page < maxPage then
            shown = shown + 1
            local next = PrepareButton(panel, shown, 175, 24)
            next.text:SetText("다음 (" .. tostring(page) .. "/" .. tostring(maxPage) .. ") >")
            next:SetScript("OnClick", function()
                RunSafe("next", function()
                    panel.categoryPage = math.min(maxPage, page + 1)
                    ShowCategory(frame, categoryID, fallbackName)
                end)
            end)
        end
    end

    if #rows == 0 then
        print("nbtw: 이 지역에 표시할 줄거리가 없습니다 - " .. tostring(categoryID))
    end
end


ShowChain = function(frame, chainID, fallbackName)
    local panel = frame.NBTWSimpleList
    if not panel then return end
    panel.view = "chain"
    panel.currentChainID = chainID
    panel.currentChainName = fallbackName
    panel.searchQuery = nil
    if not BtWQuestsDatabase then
        print("nbtw: 데이터베이스가 아직 준비되지 않았습니다")
        return
    end
    local chain = BtWQuestsDatabase:GetChainByID(chainID, GetCharacter())
    if not chain then
        print("nbtw: 줄거리를 찾지 못했습니다 - " .. tostring(chainID))
        return
    end

    local title = chainNames[chainID] or fallbackName
    if not title and chain.GetName then
        local okTitle, resultTitle = pcall(chain.GetName, chain, GetCharacter())
        if okTitle then
            title = resultTitle
        end
    end
    panel.title:SetText(title or ("줄거리 " .. tostring(chainID)))
    HideButtons(panel)

    local back = PrepareButton(panel, 1, 160, 24)
    back.text:SetText("< 뒤로")
    local function clickBack()
        RunSafe("back", function()
            if panel.lastCategoryID then
                ShowCategory(frame, panel.lastCategoryID, panel.lastCategoryName)
            else
                ShowZones(frame)
            end
        end)
    end
    back:SetScript("OnClick", clickBack)

    local character = GetCharacter()
    local rows = {}
    local index = 1
    while chain.items and chain.items[index] do
        local item, itemError = GetChainItemSafe(chain, index, character)
        local itemType
        if item and item.GetType then
            local okType, resultType = pcall(item.GetType, item)
            if okType then
                itemType = resultType
            end
        end
        if item and itemType and itemType ~= "header" then
            local label = GetDisplayName(item, character, itemType)
            local itemID
            if item.GetID then
                local okID, resultID = pcall(item.GetID, item)
                if okID then
                    itemID = resultID
                end
            end
            rows[#rows + 1] = {
                item = item,
                itemType = itemType,
                itemID = itemID,
                label = label,
                completed = IsChainItemCompleted(item, itemType, itemID, character),
            }
        elseif not item then
            local rawLabel, rawType, rawID = GetRawDisplayName(chain.items[index])
            rows[#rows + 1] = {
                item = nil,
                itemType = rawType,
                itemID = rawID,
                label = rawLabel,
                completed = IsChainItemCompleted(nil, rawType, rawID, character),
                error = itemError,
            }
        end
        index = index + 1
    end

    local page, maxPage, first, last = GetPageBounds(#rows, panel.chainPage)
    panel.chainPage = page

    local shown = 1
    for rowIndex = first, last do
        local row = rows[rowIndex]
        shown = shown + 1
        local button = PrepareButton(panel, shown, 430, 22)
        local prefix = row.completed and "[완료] " or ""
        button.text:SetText(prefix .. tostring(rowIndex) .. ". " .. row.label)
        if row.completed then
            SetButtonColor(button, 0.16, 0.16, 0.16, 0.88)
        else
            SetButtonColor(button, 0.45, 0.02, 0.02, 0.95)
        end
        button.chainLabel = row.label
        button.chainItem = row.item
        button.chainItemType = row.itemType
        button.chainItemID = row.itemID
        local function clickChainItem(self)
            RunSafe("chain item", function()
                local id = self.chainItemID
                if not id and self.chainItem and self.chainItem.GetID then
                    local okID, resultID = pcall(self.chainItem.GetID, self.chainItem)
                    if okID then
                        id = resultID
                    end
                end
                local itemType = self.chainItemType or "item"
                if self.chainItem and self.chainItem.GetType then
                    local okType, resultType = pcall(self.chainItem.GetType, self.chainItem)
                    if okType then
                        itemType = resultType
                    end
                end
                if itemType == "quest" and OpenQuestLogByID(id) then
                    return
                end
                local link
                if self.chainItem and self.chainItem.GetLink then
                    local okLink, resultLink = pcall(self.chainItem.GetLink, self.chainItem)
                    if okLink then
                        link = resultLink
                    end
                end
                if link and ChatEdit_TryInsertChatLink and ChatEdit_TryInsertChatLink(link) then
                    return
                end
                print("nbtw: " .. tostring(self.chainLabel) .. " (" .. tostring(itemType) .. ":" .. tostring(id) .. ")")
            end)
        end
        button:SetScript("OnClick", clickChainItem)
    end

    if maxPage > 1 then
        if page > 1 then
            shown = shown + 1
            local prev = PrepareButton(panel, shown, 175, 22)
            prev.text:SetText("< 이전 (" .. tostring(page) .. "/" .. tostring(maxPage) .. ")")
            prev:SetScript("OnClick", function()
                RunSafe("prev", function()
                    panel.chainPage = math.max(1, page - 1)
                    ShowChain(frame, chainID, fallbackName)
                end)
            end)
        end

        if page < maxPage then
            shown = shown + 1
            local next = PrepareButton(panel, shown, 175, 22)
            next.text:SetText("다음 (" .. tostring(page) .. "/" .. tostring(maxPage) .. ") >")
            next:SetScript("OnClick", function()
                RunSafe("next", function()
                    panel.chainPage = math.min(maxPage, page + 1)
                    ShowChain(frame, chainID, fallbackName)
                end)
            end)
        end
    end

    if #rows == 0 then
        print("nbtw: 이 줄거리에 표시할 항목이 없습니다 - " .. tostring(chainID))
    end
end

local function BuildSearchResults(query)
    local results = {}
    local seen = {}
    if not BtWQuestsDatabase or not query or query == "" then
        return results
    end

    local character = GetCharacter()
    for _, info in ipairs(categories) do
        if ResultMatches({name = info.name, id = info.id}, query) then
            AddSearchResult(results, seen, {
                kind = "category",
                id = info.id,
                name = info.name,
                categoryID = info.id,
                zoneName = info.name,
            })
        end

        local category = BtWQuestsDatabase:GetCategoryByID(info.id)
        if not category and BtWQuestsDatabase.LoadCategory then
            category = BtWQuestsDatabase:LoadCategory(info.id)
        end
        if category then
            local okList, list = pcall(category.GetItemList, category, character, true, false, false, false, false)
            if okList and list then
                for _, categoryItem in ipairs(list) do
                    local okType, itemType = pcall(categoryItem.GetType, categoryItem)
                    local okID, chainID = pcall(categoryItem.GetID, categoryItem)
                    if okType and okID and itemType == "chain" then
                        local chainName = GetDisplayName(categoryItem, character, itemType)
                        local chainResult = {
                            kind = "chain",
                            id = chainID,
                            name = chainName,
                            categoryID = info.id,
                            zoneName = info.name,
                            chainID = chainID,
                            chainName = chainName,
                        }
                        if ResultMatches(chainResult, query) then
                            AddSearchResult(results, seen, chainResult)
                        end

                        local chain = BtWQuestsDatabase:GetChainByID(chainID, character)
                        if chain and chain.items then
                            for index = 1, #chain.items do
                                local chainItem = GetChainItemSafe(chain, index, character)
                                local label, rowType, rowID
                                if chainItem then
                                    local okItemType, itemResultType = pcall(chainItem.GetType, chainItem)
                                    if okItemType then
                                        rowType = itemResultType
                                    end
                                    label = GetDisplayName(chainItem, character, rowType)
                                    if chainItem.GetID then
                                        local okItemID, itemResultID = pcall(chainItem.GetID, chainItem)
                                        if okItemID then
                                            rowID = itemResultID
                                        end
                                    end
                                else
                                    label, rowType, rowID = GetRawDisplayName(chain.items[index])
                                end

                                local result = {
                                    kind = rowType or "item",
                                    id = rowID,
                                    name = label,
                                    categoryID = info.id,
                                    zoneName = info.name,
                                    chainID = chainID,
                                    chainName = chainName,
                                    completed = IsChainItemCompleted(chainItem, rowType, rowID, character),
                                }
                                if rowType ~= "header" and ResultMatches(result, query) then
                                    AddSearchResult(results, seen, result)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return results
end

ShowSearchResults = function(frame, query)
    local panel = frame.NBTWSimpleList
    if not panel then return end
    if not query or query == "" then
        ShowZones(frame)
        return
    end
    panel.view = "search"
    panel.searchQuery = query

    local results = BuildSearchResults(query)
    panel.title:SetText("검색: " .. tostring(query) .. " (" .. tostring(#results) .. ")")
    HideButtons(panel)

    local back = PrepareButton(panel, 1, 160, 24)
    back.text:SetText("< 지역 목록")
    back:SetScript("OnClick", function()
        RunSafe("search back", function()
            if frame.SearchBox then
                frame.SearchBox:SetText("")
                frame.SearchBox:ClearFocus()
            end
            ShowZones(frame)
        end)
    end)

    panel.searchPage = panel.searchPage or 1
    local page, maxPage, first, last = GetPageBounds(#results, panel.searchPage)
    panel.searchPage = page

    local shown = 1
    for index = first, last do
        local result = results[index]
        shown = shown + 1
        local button = PrepareButton(panel, shown, 470, 24)
        local prefix = "항목"
        if result.kind == "category" then
            prefix = "지역"
        elseif result.kind == "chain" then
            prefix = "줄거리"
        elseif result.kind == "quest" then
            prefix = "퀘스트"
        elseif result.kind == "npc" then
            prefix = "NPC"
        elseif result.kind == "object" then
            prefix = "오브젝트"
        end
        local suffix = result.id and (" [" .. tostring(result.id) .. "]") or ""
        local completePrefix = result.completed and "[완료] " or ""
        button.text:SetText(completePrefix .. prefix .. ": " .. tostring(result.name) .. suffix)
        if result.completed then
            SetButtonColor(button, 0.16, 0.16, 0.16, 0.88)
        else
            SetButtonColor(button, 0.45, 0.02, 0.02, 0.95)
        end
        button.searchResult = result
        button:SetScript("OnClick", function(self)
            RunSafe("search result", function()
                local row = self.searchResult
                if row.kind == "category" then
                    panel.categoryPage = 1
                    ShowCategory(frame, row.categoryID, row.zoneName)
                elseif row.kind == "chain" then
                    panel.lastCategoryID = row.categoryID
                    panel.lastCategoryName = row.zoneName
                    panel.chainPage = 1
                    ShowChain(frame, row.chainID, row.chainName)
                else
                    panel.lastCategoryID = row.categoryID
                    panel.lastCategoryName = row.zoneName
                    panel.chainPage = 1
                    if row.kind == "quest" and OpenQuestLogByID(row.id) then
                        return
                    end
                    ShowChain(frame, row.chainID, row.chainName)
                end
            end)
        end)
    end

    if maxPage > 1 then
        if page > 1 then
            shown = shown + 1
            local prev = PrepareButton(panel, shown, 175, 22)
            prev.text:SetText("< 이전 (" .. tostring(page) .. "/" .. tostring(maxPage) .. ")")
            prev:SetScript("OnClick", function()
                RunSafe("search prev", function()
                    panel.searchPage = math.max(1, page - 1)
                    ShowSearchResults(frame, query)
                end)
            end)
        end
        if page < maxPage then
            shown = shown + 1
            local next = PrepareButton(panel, shown, 175, 22)
            next.text:SetText("다음 (" .. tostring(page) .. "/" .. tostring(maxPage) .. ") >")
            next:SetScript("OnClick", function()
                RunSafe("search next", function()
                    panel.searchPage = math.min(maxPage, page + 1)
                    ShowSearchResults(frame, query)
                end)
            end)
        end
    end

    if #results == 0 then
        print("nbtw: 검색 결과 없음 - " .. tostring(query))
    end
end

local function ShowSimpleList(frame)
    SetupSimpleChrome(frame)

    if frame.Chain then frame.Chain:Hide() end
    if frame.Category then frame.Category:Hide() end
    if frame.ExpansionList then frame.ExpansionList:Hide() end

    if not frame.NBTWSimpleList then
        local panel = CreateFrame("Frame", nil, UIParent)
        panel:SetFrameStrata("DIALOG")
        panel:SetFrameLevel(900)
        panel:SetPoint("TOPLEFT", frame.Inset or frame, "TOPLEFT", 18, -42)
        panel:SetPoint("BOTTOMRIGHT", frame.Inset or frame, "BOTTOMRIGHT", -18, 18)
        panel:EnableMouse(false)
        panel.owner = frame
        panel.bg = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
        panel.bg:SetPoint("TOPLEFT", -14, 12)
        panel.bg:SetPoint("BOTTOMRIGHT", 14, -12)
        panel.bg:SetTexture(0, 0, 0, 0.18)
        panel.border = panel:CreateTexture(nil, "BACKGROUND", nil, -7)
        panel.border:SetPoint("TOPLEFT", panel.bg, "TOPLEFT", -1, 1)
        panel.border:SetPoint("BOTTOMRIGHT", panel.bg, "BOTTOMRIGHT", 1, -1)
        panel.border:SetTexture(0, 0, 0, 0)
        panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        panel.title:SetPoint("TOPLEFT", 0, -4)
        panel.buttons = {}
        frame.NBTWSimpleList = panel
    end

    frame.NBTWSimpleList:ClearAllPoints()
    frame.NBTWSimpleList:SetPoint("TOPLEFT", frame.Inset or frame, "TOPLEFT", 18, -42)
    frame.NBTWSimpleList:SetPoint("BOTTOMRIGHT", frame.Inset or frame, "BOTTOMRIGHT", -18, 18)
    frame.NBTWSimpleList.owner = frame
    if frame.NBTWSimpleList.bg then
        frame.NBTWSimpleList.bg:Show()
    end
    if frame.NBTWSimpleList.border then
        frame.NBTWSimpleList.border:Show()
    end
    frame.NBTWSimpleList:Show()
    ShowZones(frame)
end

local function ToggleNbtw()
    if BtWQuestsFrame then
        if BtWQuestsFrame:IsShown() then
            BtWQuestsFrame:Hide()
            if BtWQuestsFrame.NBTWSimpleList then
                BtWQuestsFrame.NBTWSimpleList:Hide()
            end
        else
            BtWQuestsFrame:Show()
            ShowSimpleList(BtWQuestsFrame)
        end
    else
        print("nbtw: 애드온은 로드됐지만 창이 아직 준비되지 않았습니다")
    end
end

local function CheckNbtwLinks()
    if not BtWQuestsDatabase then
        print("nbtw: 데이터베이스가 아직 준비되지 않았습니다")
        return
    end

    local character = GetCharacter()
    local missingCategories = 0
    local missingChains = 0
    local brokenItems = 0

    for _, info in ipairs(categories) do
        local category = BtWQuestsDatabase:GetCategoryByID(info.id)
        if not category and BtWQuestsDatabase.LoadCategory then
            category = BtWQuestsDatabase:LoadCategory(info.id)
        end
        if not category then
            missingCategories = missingCategories + 1
            print("nbtw 점검: 지역 없음 - " .. tostring(info.id) .. " " .. tostring(info.name))
        else
            local okList, list = pcall(category.GetItemList, category, character, true, false, false, false, false)
            if okList and list then
                for _, item in ipairs(list) do
                    local okType, itemType = pcall(item.GetType, item)
                    local okID, itemID = pcall(item.GetID, item)
                    if okType and okID and itemType == "chain" then
                        local chain = BtWQuestsDatabase:GetChainByID(itemID, character)
                        if not chain then
                            missingChains = missingChains + 1
                            print("nbtw 점검: 체인 없음 - " .. tostring(itemID))
                        elseif chain.items then
                            for index = 1, #chain.items do
                                local chainItem, err = GetChainItemSafe(chain, index, character)
                                if not chainItem then
                                    brokenItems = brokenItems + 1
                                    local label = GetRawDisplayName(chain.items[index])
                                    print("nbtw 점검: 백업 표시 사용 - " .. tostring(itemID) .. " #" .. tostring(index) .. " " .. tostring(label))
                                end
                            end
                        end
                    end
                end
            else
                print("nbtw 점검: 지역 목록 오류 - " .. tostring(info.id) .. " " .. tostring(list))
            end
        end
    end

    print("nbtw 점검 완료: 지역누락 " .. tostring(missingCategories) .. ", 체인누락 " .. tostring(missingChains) .. ", 백업항목 " .. tostring(brokenItems))
end

SLASH_NBTWBOOT1 = "/nbtw"
SLASH_NBTWBOOT2 = "/nbtwboot"
SlashCmdList["NBTWBOOT"] = function(msg)
    local ok, err = pcall(ToggleNbtw)
    if not ok then print("nbtw 오류: " .. tostring(err)) end
end

SLASH_NBTWCHECK1 = "/nbtwcheck"
SlashCmdList["NBTWCHECK"] = function(msg)
    local ok, err = pcall(CheckNbtwLinks)
    if not ok then print("nbtw 점검 오류: " .. tostring(err)) end
end

SLASH_NBTWSEARCH1 = "/nbtwsearch"
SlashCmdList["NBTWSEARCH"] = function(msg)
    local ok, err = pcall(function()
        if not BtWQuestsFrame then
            print("nbtw: 창이 아직 준비되지 않았습니다")
            return
        end
        BtWQuestsFrame:Show()
        ShowSimpleList(BtWQuestsFrame)
        if BtWQuestsFrame.SearchBox then
            BtWQuestsFrame.SearchBox:SetText(msg or "")
        end
        ShowSearchResults(BtWQuestsFrame, msg or "")
    end)
    if not ok then print("nbtw 검색 오류: " .. tostring(err)) end
end
