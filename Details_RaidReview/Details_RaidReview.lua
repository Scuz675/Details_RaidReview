local _detalhes = _G._detalhes
if not _detalhes then
    return
end

local PLUGIN_NAME = "Raid Review"
local PLUGIN_ABSOLUTE_NAME = "DETAILS_PLUGIN_RAID_REVIEW"
local PLUGIN_VERSION = "v0.4.3"
local PLUGIN_ICON = [[Interface\Icons\INV_Misc_Note_01]]

local Review = _detalhes:NewPluginObject("Details_RaidReview")
local ReviewFrame = Review.Frame
Review:SetPluginDescription("Post-combat raid review: performance, deaths, CC breaks, interrupts, dispels, defensive cooldowns, resurrections and consumable usage.")

local DF = _detalhes.gump
local SharedMedia = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
local unpack = unpack
local floor = math.floor
local min = math.min
local max = math.max
local sort = table.sort
local ipairs = ipairs
local pairs = pairs
local wipe = _G.wipe or table.wipe or function(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

Review.Rows = {}
Review.ShownRows = {}
Review.RowHeight = 14
Review.CanShow = 0
Review.currentCombat = nil
Review.currentData = {}
Review.ScrollOffset = 0
Review.ScrollStep = 3
Review.ScrollBarVisible = false
Review.MaxBarMetric = 1

local function getOnlyName(name)
    if not name then
        return "Unknown"
    end
    return name:match("^([^%-]+)") or name
end

local function isGroupPlayer(actor)
    if not actor then
        return false
    end
    if actor.grupo then
        return true
    end
    if actor.IsGroupPlayer then
        return actor:IsGroupPlayer()
    end
    return false
end

local function getActorName(actor)
    return actor and (actor.nome or actor.name)
end

local function getPotionCount(miscActor)
    if not miscActor then
        return 0
    end

    local total = 0
    local buffs = miscActor.buff_uptime_spells and miscActor.buff_uptime_spells._ActorTable
    if buffs and DetailsFramework and DetailsFramework.PotionIDs then
        for spellId in pairs(DetailsFramework.PotionIDs) do
            local aura = buffs[spellId]
            if aura then
                local uses = aura.activedamt or aura.appliedamt or 1
                if uses < 1 then uses = 1 end
                total = total + uses
            end
        end
    end

    local debuffs = miscActor.debuff_uptime_spells and miscActor.debuff_uptime_spells._ActorTable
    if debuffs and DETAILS_FOCUS_POTION_ID and debuffs[DETAILS_FOCUS_POTION_ID] then
        total = total + 1
    end

    return total
end

local function getHealthConsumableCount(healActor)
    if not healActor or not healActor.GetSpellList or not DETAILS_HEALTH_POTION_LIST then
        return 0
    end

    local total = 0
    for spellId, spell in pairs(healActor:GetSpellList()) do
        if DETAILS_HEALTH_POTION_LIST[spellId] then
            local uses = spell.counter or ((spell.n_amt or 0) + (spell.c_amt or 0))
            if not uses or uses < 1 then uses = 1 end
            total = total + uses
        end
    end
    return total
end

local function getActorRate(actor, cachedKey)
    if not actor then
        return 0
    end

    -- Details normally maintains last_dps / last_hps using the same timing
    -- rules as its standard Damage Done and Healing Done displays. Prefer
    -- those cached values so Raid Review matches what the player sees there.
    local cached = tonumber(actor[cachedKey]) or 0
    if cached > 0 then
        return cached
    end

    -- Fallback for a segment which has not had its normal Details refresh yet.
    local total = tonumber(actor.total) or 0
    if total <= 0 then
        return 0
    end

    local elapsed = 0
    if actor.Tempo then
        local ok, value = pcall(actor.Tempo, actor)
        if ok and type(value) == "number" then
            elapsed = value
        end
    end

    if elapsed > 0 then
        return total / elapsed
    end
    return 0
end

local function formatAmount(value)
    value = tonumber(value) or 0
    return _detalhes:ToK(value)
end

local function formatRate(value)
    value = tonumber(value) or 0
    return _detalhes:ToK(value) .. "/s"
end

local function getDeathCount(combat, name)
    local deaths = 0
    local deathTable = combat and combat.last_events_tables
    if deathTable then
        for _, death in ipairs(deathTable) do
            if death and death[3] == name then
                deaths = deaths + 1
            end
        end
    end
    return deaths
end

local function getActivityScore(data)
    return (data.interrupts or 0)
        + (data.dispels or 0)
        + (data.defensives or 0)
        + (data.resses or 0)
        + (data.potions or 0)
        + (data.healthConsumables or 0)
end

local function hasReviewActivity(data)
    return (data.deaths or 0) > 0
        or (data.ccBreaks or 0) > 0
        or (data.damageTaken or 0) > 0
        or getActivityScore(data) > 0
end

local function buildSummary(data)
    -- Keep the visible row deliberately quiet. The bar length and row order
    -- carry the review signal; the tooltip carries the detailed evidence.
    return "X" .. (data.deaths or 0)
end

local function dataSort(a, b)
    local mode = (Review.saveddata and Review.saveddata.sortMode) or "priority"

    if mode == "damage" then
        if a.damageTaken ~= b.damageTaken then return a.damageTaken > b.damageTaken end
        if a.deaths ~= b.deaths then return a.deaths > b.deaths end

    elseif mode == "deaths" then
        if a.deaths ~= b.deaths then return a.deaths > b.deaths end
        if a.damageTaken ~= b.damageTaken then return a.damageTaken > b.damageTaken end

    elseif mode == "actions" then
        local aActivity = getActivityScore(a)
        local bActivity = getActivityScore(b)
        if aActivity ~= bActivity then return aActivity > bActivity end
        if a.interrupts ~= b.interrupts then return a.interrupts > b.interrupts end
        if a.dispels ~= b.dispels then return a.dispels > b.dispels end
        if a.defensives ~= b.defensives then return a.defensives > b.defensives end

    else
        -- Default raid-leader view: problems first, then incoming damage.
        -- This is intentionally lexicographic rather than pretending that one
        -- interrupt is mathematically equivalent to some amount of damage.
        if a.deaths ~= b.deaths then return a.deaths > b.deaths end
        if a.ccBreaks ~= b.ccBreaks then return a.ccBreaks > b.ccBreaks end
        if a.damageTaken ~= b.damageTaken then return a.damageTaken > b.damageTaken end

        local aActivity = getActivityScore(a)
        local bActivity = getActivityScore(b)
        if aActivity ~= bActivity then return aActivity > bActivity end
    end

    return (a.name or "") < (b.name or "")
end

local function getBarMetric(data)
    local mode = (Review.saveddata and Review.saveddata.sortMode) or "priority"
    if mode == "damage" then
        return data.damageTaken or 0
    elseif mode == "deaths" then
        return data.deaths or 0
    elseif mode == "actions" then
        return getActivityScore(data)
    end

    -- Review Priority is a visual attention meter only. Deaths and CC breaks
    -- establish urgency; normalized damage taken fills in the remaining signal.
    return (data.priorityScore or 0)
end

local function addTooltipLine(left, right, lr, lg, lb, rr, rg, rb)
    if not GameTooltip then
        return
    end

    left = left == nil and "" or tostring(left)
    right = right == nil and "" or tostring(right)

    if right ~= "" then
        GameTooltip:AddDoubleLine(
            left,
            right,
            lr or 1, lg or 1, lb or 1,
            rr or 0.85, rg or 0.85, rb or 0.85
        )
    else
        GameTooltip:AddLine(left, lr or 1, lg or 1, lb or 1)
    end
end

local function addSection(title)
    addTooltipLine(" ", "")
    addTooltipLine(title, "", 1, 0.82, 0.20)
end

local function addSpellSection(title, spellContainer, valueKey)
    if not spellContainer or not spellContainer._ActorTable then
        return
    end

    local rows = {}
    for spellId, spell in pairs(spellContainer._ActorTable) do
        local count = spell[valueKey] or spell.counter or 0
        if count and count > 0 then
            rows[#rows + 1] = {spellId, count}
        end
    end

    if #rows == 0 then
        return
    end

    sort(rows, function(a, b) return a[2] > b[2] end)
    addSection(title)
    local maxRows = (Review.saveddata and Review.saveddata.maxSpellRows) or 6
    for i = 1, min(maxRows, #rows) do
        local spellId, count = rows[i][1], rows[i][2]
        local spellName, _, spellIcon = GetSpellInfo(spellId)
        spellName = spellName or ("Spell " .. tostring(spellId))
        if spellIcon then
            spellName = "|T" .. spellIcon .. ":12:12:0:0|t " .. spellName
        end
        addTooltipLine(spellName, floor(count))
    end
end

function Review:ShowPlayerTooltip(data, anchor)
    if not data or not data.combat or not GameTooltip then
        return
    end

    local combat = data.combat
    local misc = data.misc
    local heal = data.heal
    local name = data.name

    GameTooltip:Hide()
    GameTooltip:SetOwner(anchor or UIParent, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()

    GameTooltip:AddLine("Raid Review - " .. getOnlyName(name), 1, 0.82, 0.20)
    if data.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.class] then
        local c = RAID_CLASS_COLORS[data.class]
        GameTooltip:AddLine(data.class, c.r, c.g, c.b)
    end

    addSection("Performance")
    addTooltipLine("Damage Done", formatAmount(data.damageDone or 0))
    addTooltipLine("DPS", formatRate(data.dps or 0))
    addTooltipLine("Healing Done", formatAmount(data.healingDone or 0))
    addTooltipLine("HPS", formatRate(data.hps or 0))

    local overheal = data.overheal or 0
    local totalHealingAttempted = (data.healingDone or 0) + overheal
    local overhealPercent = totalHealingAttempted > 0 and (overheal / totalHealingAttempted * 100) or 0
    addTooltipLine("Overheal", formatAmount(overheal) .. " (" .. string.format("%.1f", overhealPercent) .. "%)")

    addSection("Review Flags")
    addTooltipLine("Deaths", data.deaths, 1, 1, 1, data.deaths > 0 and 1 or 0.8, data.deaths > 0 and 0.25 or 0.8, data.deaths > 0 and 0.25 or 0.8)
    addTooltipLine("CC Breaks", data.ccBreaks, 1, 1, 1, data.ccBreaks > 0 and 1 or 0.8, data.ccBreaks > 0 and 0.55 or 0.8, data.ccBreaks > 0 and 0.15 or 0.8)

    addSection("Raid Actions")
    addTooltipLine("Interrupts", data.interrupts)
    addTooltipLine("Dispels", data.dispels)
    addTooltipLine("Defensive Cooldowns", data.defensives)
    addTooltipLine("Resurrections", data.resses)
    addTooltipLine("Potions", data.potions)
    addTooltipLine("Health Pot/Stone", data.healthConsumables)

    addSection("Context")
    addTooltipLine("Damage Taken", _detalhes:ToK(data.damageTaken or 0))
    local sortMode = (Review.saveddata and Review.saveddata.sortMode) or "priority"
    local sortLabels = {priority = "Review Priority", damage = "Damage Taken", deaths = "Deaths", actions = "Raid Actions"}
    addTooltipLine("Bar / Sort", sortLabels[sortMode] or sortMode)

    if misc then
        addSpellSection("Interrupts Used", misc.interrupt_spells, "counter")
        addSpellSection("Dispels Used", misc.dispell_spells, "dispell")
        addSpellSection("Defensive Cooldowns", misc.cooldowns_defensive_spells, "counter")
        addSpellSection("Resurrections", misc.ress_spells, "ress")
        addSpellSection("CC Breaks", misc.cc_break_spells, "cc_break")
    end

    if misc and misc.interrompeu_oque then
        local rows = {}
        for spellId, count in pairs(misc.interrompeu_oque) do
            if count and count > 0 then
                rows[#rows + 1] = {spellId, count}
            end
        end
        if #rows > 0 then
            sort(rows, function(a, b) return a[2] > b[2] end)
            addSection("Spells Interrupted")
            local maxRows = (Review.saveddata and Review.saveddata.maxSpellRows) or 6
            for i = 1, min(maxRows, #rows) do
                local spellName, _, spellIcon = GetSpellInfo(rows[i][1])
                spellName = spellName or ("Spell " .. tostring(rows[i][1]))
                if spellIcon then
                    spellName = "|T" .. spellIcon .. ":12:12:0:0|t " .. spellName
                end
                addTooltipLine(spellName, floor(rows[i][2]))
            end
        end
    end

    if misc and misc.dispell_oque then
        local rows = {}
        for spellId, count in pairs(misc.dispell_oque) do
            if count and count > 0 then
                rows[#rows + 1] = {spellId, count}
            end
        end
        if #rows > 0 then
            sort(rows, function(a, b) return a[2] > b[2] end)
            addSection("Auras Dispelled")
            local maxRows = (Review.saveddata and Review.saveddata.maxSpellRows) or 6
            for i = 1, min(maxRows, #rows) do
                local spellName, _, spellIcon = GetSpellInfo(rows[i][1])
                spellName = spellName or ("Spell " .. tostring(rows[i][1]))
                if spellIcon then
                    spellName = "|T" .. spellIcon .. ":12:12:0:0|t " .. spellName
                end
                addTooltipLine(spellName, floor(rows[i][2]))
            end
        end
    end

    if misc then
        local buffs = misc.buff_uptime_spells and misc.buff_uptime_spells._ActorTable
        local debuffs = misc.debuff_uptime_spells and misc.debuff_uptime_spells._ActorTable
        local potionRows = {}

        if buffs and DetailsFramework and DetailsFramework.PotionIDs then
            for spellId in pairs(DetailsFramework.PotionIDs) do
                local aura = buffs[spellId]
                if aura then
                    local uses = aura.activedamt or aura.appliedamt or 1
                    if uses < 1 then uses = 1 end
                    potionRows[#potionRows + 1] = {spellId, uses}
                end
            end
        end
        if debuffs and DETAILS_FOCUS_POTION_ID and debuffs[DETAILS_FOCUS_POTION_ID] then
            potionRows[#potionRows + 1] = {DETAILS_FOCUS_POTION_ID, 1}
        end

        if #potionRows > 0 then
            addSection("Potions Used")
            for _, row in ipairs(potionRows) do
                local spellName, _, spellIcon = GetSpellInfo(row[1])
                spellName = spellName or ("Spell " .. tostring(row[1]))
                if spellIcon then
                    spellName = "|T" .. spellIcon .. ":12:12:0:0|t " .. spellName
                end
                addTooltipLine(spellName, floor(row[2]))
            end
        end
    end

    if heal and heal.GetSpellList and DETAILS_HEALTH_POTION_LIST then
        local rows = {}
        for spellId, spell in pairs(heal:GetSpellList()) do
            if DETAILS_HEALTH_POTION_LIST[spellId] then
                local uses = spell.counter or ((spell.n_amt or 0) + (spell.c_amt or 0))
                if not uses or uses < 1 then uses = 1 end
                rows[#rows + 1] = {spellId, uses, spell.total or 0}
            end
        end
        if #rows > 0 then
            addSection("Health Consumables")
            for _, row in ipairs(rows) do
                local spellName, _, spellIcon = GetSpellInfo(row[1])
                spellName = spellName or ("Spell " .. tostring(row[1]))
                if spellIcon then
                    spellName = "|T" .. spellIcon .. ":12:12:0:0|t " .. spellName
                end
                addTooltipLine(spellName, floor(row[2]) .. " use(s), " .. _detalhes:ToK(row[3]))
            end
        end
    end

    local deathTable = combat.last_events_tables
    if data.deaths > 0 and deathTable then
        addSection("Death Recap")
        local hitsToShow = (Review.saveddata and Review.saveddata.deathHits) or 3
        local deathNumber = 0

        for _, death in ipairs(deathTable) do
            if death and death[3] == name then
                deathNumber = deathNumber + 1
                addTooltipLine("Death " .. deathNumber, death[6] or "", 1, 0.45, 0.45)

                local events = death[1]
                local shown = 0
                if events then
                    for i = #events, 1, -1 do
                        local event = events[i]
                        if event and type(event[1]) == "boolean" and event[1] then
                            local spellName, _, spellIcon = GetSpellInfo(event[2])
                            spellName = spellName or ("Spell " .. tostring(event[2]))
                            local source = event[6] or "Unknown"
                            local amount = event[3] or 0
                            local secondsBefore = 0
                            if death[2] and event[4] then
                                secondsBefore = max(0, death[2] - event[4])
                            end
                            local left = "-" .. string.format("%.1f", secondsBefore) .. "s " .. spellName .. " (" .. source .. ")"
                            if spellIcon then
                                left = "|T" .. spellIcon .. ":12:12:0:0|t " .. left
                            end
                            addTooltipLine(left, _detalhes:ToK(amount))
                            shown = shown + 1
                            if shown >= hitsToShow then
                                break
                            end
                        end
                    end
                end

                if shown == 0 then
                    addTooltipLine("No damaging events recorded", "")
                end
            end
        end
    end

    GameTooltip:Show()
end

function Review:HidePlayerTooltip()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

function Review:ShowPlayerTooltipSafe(data, anchor)
    local ok, err = pcall(Review.ShowPlayerTooltip, Review, data, anchor)
    if ok then
        return
    end

    -- Never fail silently on this old client. If one of the richer data
    -- sections is shaped differently on Triumvirate, show the error in the
    -- tooltip so it can be reported without needing Lua errors enabled.
    if GameTooltip then
        GameTooltip:Hide()
        GameTooltip:SetOwner(anchor or UIParent, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Raid Review - " .. getOnlyName(data and data.name), 1, 0.82, 0.20)
        GameTooltip:AddLine("Tooltip error", 1, 0.25, 0.25)
        GameTooltip:AddLine(tostring(err), 1, 1, 1, true)
        GameTooltip:Show()
    end

    local message = tostring(err)
    if Review.lastTooltipError ~= message then
        Review.lastTooltipError = message
        print("|cFFFF5555Raid Review tooltip error:|r " .. message)
    end
end

function Review:RefreshRowStyle(row)
    local instance = Review:GetPluginInstance()
    if not instance then
        return
    end

    local font = instance.row_info.font_face
    if SharedMedia then
        font = SharedMedia:Fetch("font", instance.row_info.font_face, true) or font
    end
    row.textsize = instance.row_info.font_size
    row.textfont = font
    row.texture = instance.row_info.texture
    row.shadow = instance.row_info.textL_outline
    row:SetWidth(instance.baseframe:GetWidth() - (Review.ScrollBarVisible and 11 or 6))
end

function Review:NewRow(index)
    local row = DF:NewBar(ReviewFrame, nil, "DetailsRaidReviewRow" .. index, nil, 300, Review.RowHeight)
    row:SetPoint("TOPLEFT", ReviewFrame, "TOPLEFT", 3, -((index - 1) * (Review.RowHeight + 1)))
    row:SetValue(100)
    row.reviewData = nil

    -- Details' instance/window layers can sit above a RAID plugin's custom
    -- status bars for mouse hit-testing even though the bars remain visible.
    -- Put a dedicated invisible Button above each bar and let *it* own hover.
    -- Parenting it to the statusbar also means it automatically follows row
    -- movement, sizing, showing and hiding.
    local hitbox = CreateFrame("Button", "DetailsRaidReviewHitbox" .. index, row.widget)
    hitbox:SetAllPoints(row.widget)
    hitbox:SetFrameStrata(row.widget:GetFrameStrata())
    hitbox:SetFrameLevel(row.widget:GetFrameLevel() + 20)
    hitbox:EnableMouse(true)
    hitbox.reviewRow = row

    hitbox:SetScript("OnEnter", function(frame)
        local reviewRow = frame.reviewRow
        if reviewRow and reviewRow.background then
            reviewRow.background:Show()
        end
        if reviewRow and reviewRow.reviewData then
            Review:ShowPlayerTooltipSafe(reviewRow.reviewData, frame)
        end
    end)

    hitbox:SetScript("OnLeave", function(frame)
        local reviewRow = frame.reviewRow
        if reviewRow and reviewRow.background then
            reviewRow.background:Hide()
        end
        Review:HidePlayerTooltip()
    end)

    hitbox:EnableMouseWheel(true)
    hitbox:SetScript("OnMouseWheel", function(frame, delta)
        Review:Scroll(delta)
    end)

    row.hitbox = hitbox

    Review.Rows[#Review.Rows + 1] = row
    Review:RefreshRowStyle(row)
    row:Hide()
    return row
end

function Review:EnsureScrollBar()
    if Review.ScrollTrack then
        return
    end

    local track = CreateFrame("Frame", "DetailsRaidReviewScrollTrack", ReviewFrame)
    track:SetWidth(4)
    track:SetPoint("TOPRIGHT", ReviewFrame, "TOPRIGHT", -1, -1)
    track:SetPoint("BOTTOMRIGHT", ReviewFrame, "BOTTOMRIGHT", -1, 1)

    local bg = track:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(track)
    bg:SetTexture(0, 0, 0, 0.25)

    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(0.75, 0.75, 0.75, 0.75)
    thumb:SetWidth(4)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)

    track:SetFrameLevel(ReviewFrame:GetFrameLevel() + 30)

    Review.ScrollTrack = track
    Review.ScrollThumb = thumb
    track:Hide()

    ReviewFrame:EnableMouseWheel(true)
    ReviewFrame:SetScript("OnMouseWheel", function(frame, delta)
        Review:Scroll(delta)
    end)
end

function Review:UpdateScrollBar()
    Review:EnsureScrollBar()

    local total = #Review.currentData
    local visible = Review.CanShow or 1
    local maxOffset = max(0, total - visible)
    Review.ScrollBarVisible = maxOffset > 0

    if not Review.ScrollBarVisible then
        Review.ScrollOffset = 0
        Review.ScrollTrack:Hide()
        return
    end

    if Review.ScrollOffset > maxOffset then Review.ScrollOffset = maxOffset end
    if Review.ScrollOffset < 0 then Review.ScrollOffset = 0 end

    Review.ScrollTrack:Show()
    local trackHeight = max(1, Review.ScrollTrack:GetHeight())
    local thumbHeight = max(12, floor(trackHeight * (visible / total)))
    if thumbHeight > trackHeight then thumbHeight = trackHeight end
    Review.ScrollThumb:SetHeight(thumbHeight)
    Review.ScrollThumb:ClearAllPoints()

    local travel = max(0, trackHeight - thumbHeight)
    local progress = maxOffset > 0 and (Review.ScrollOffset / maxOffset) or 0
    Review.ScrollThumb:SetPoint("TOP", Review.ScrollTrack, "TOP", 0, -(travel * progress))
end

function Review:Scroll(delta)
    if not Review.currentData or #Review.currentData <= (Review.CanShow or 1) then
        return
    end

    local maxOffset = max(0, #Review.currentData - Review.CanShow)
    local step = Review.ScrollStep or 3
    if delta > 0 then
        Review.ScrollOffset = max(0, Review.ScrollOffset - step)
    elseif delta < 0 then
        Review.ScrollOffset = min(maxOffset, Review.ScrollOffset + step)
    end

    Review:HidePlayerTooltip()
    Review:RenderRows()
end

function Review:UpdateLayout()
    local instance = Review:GetPluginInstance()
    if not instance then
        return
    end

    local width, height = instance:GetSize()
    ReviewFrame:SetSize(width, height)

    Review.RowHeight = instance.row_height or 14
    if Review.RowHeight < 10 then Review.RowHeight = 10 end
    Review.CanShow = math.max(1, floor(height / (Review.RowHeight + 1)))

    for i = #Review.Rows + 1, Review.CanShow do
        Review:NewRow(i)
    end

    wipe(Review.ShownRows)
    for i, row in ipairs(Review.Rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", ReviewFrame, "TOPLEFT", 3, -((i - 1) * (Review.RowHeight + 1)))
        row:SetHeight(Review.RowHeight)
        row._icon:SetSize(Review.RowHeight, Review.RowHeight)
        Review:RefreshRowStyle(row)
        if i <= Review.CanShow then
            Review.ShownRows[#Review.ShownRows + 1] = row
        else
            row:Hide()
        end
    end
end

function Review:BuildReviewData(combat)
    local seen = {}
    local data = {}

    if not combat or not combat.GetActorList then
        return data
    end

    local function addActor(actor)
        if not isGroupPlayer(actor) then
            return
        end

        local name = getActorName(actor)
        if not name or seen[name] then
            return
        end
        seen[name] = true

        local misc = combat:GetActor(DETAILS_ATTRIBUTE_MISC, name)
        local damage = combat:GetActor(DETAILS_ATTRIBUTE_DAMAGE, name)
        local heal = combat:GetActor(DETAILS_ATTRIBUTE_HEAL, name)
        local base = misc or damage or heal or actor

        local rowData = {
            name = name,
            class = base and base.classe,
            combat = combat,
            misc = misc,
            damage = damage,
            heal = heal,
            deaths = getDeathCount(combat, name),
            ccBreaks = misc and floor(misc.cc_break or 0) or 0,
            interrupts = misc and floor(misc.interrupt or 0) or 0,
            dispels = misc and floor(misc.dispell or 0) or 0,
            defensives = misc and floor(misc.cooldowns_defensive or 0) or 0,
            resses = misc and floor(misc.ress or 0) or 0,
            potions = getPotionCount(misc),
            healthConsumables = getHealthConsumableCount(heal),
            damageTaken = damage and (damage.damage_taken or 0) or 0,
            damageDone = damage and (damage.total or 0) or 0,
            dps = getActorRate(damage, "last_dps"),
            healingDone = heal and (heal.total or 0) or 0,
            hps = getActorRate(heal, "last_hps"),
            overheal = heal and (heal.totalover or 0) or 0,
        }

        if (Review.saveddata and Review.saveddata.showInactivePlayers == false) and not hasReviewActivity(rowData) then
            return
        end

        data[#data + 1] = rowData
    end

    local attrs = {DETAILS_ATTRIBUTE_MISC, DETAILS_ATTRIBUTE_DAMAGE, DETAILS_ATTRIBUTE_HEAL}
    for _, attribute in ipairs(attrs) do
        local actors = combat:GetActorList(attribute)
        if actors then
            for _, actor in ipairs(actors) do
                addActor(actor)
            end
        end
    end

    local maxDamageTaken = 0
    for _, rowData in ipairs(data) do
        if (rowData.damageTaken or 0) > maxDamageTaken then
            maxDamageTaken = rowData.damageTaken or 0
        end
    end

    for _, rowData in ipairs(data) do
        local damagePercent = maxDamageTaken > 0 and ((rowData.damageTaken or 0) / maxDamageTaken * 100) or 0
        rowData.damagePercent = damagePercent
        rowData.priorityScore = damagePercent + ((rowData.deaths or 0) * 100) + ((rowData.ccBreaks or 0) * 50)
    end

    sort(data, dataSort)
    return data
end

function Review:RenderRows()
    Review:UpdateScrollBar()

    Review.MaxBarMetric = 0
    for _, data in ipairs(Review.currentData) do
        local metric = getBarMetric(data)
        if metric > Review.MaxBarMetric then
            Review.MaxBarMetric = metric
        end
    end
    if Review.MaxBarMetric <= 0 then Review.MaxBarMetric = 1 end

    for index, row in ipairs(Review.ShownRows) do
        local data = Review.currentData[(Review.ScrollOffset or 0) + index]
        if data then
            row.reviewData = data
            row:SetLeftText(getOnlyName(data.name))
            row:SetRightText(buildSummary(data))

            local metric = getBarMetric(data)
            local percent = (metric / Review.MaxBarMetric) * 100
            if metric > 0 and percent < 2 then percent = 2 end
            row:SetValue(percent)

            -- Keep colour purely informational: the bar uses the player's class
            -- colour, while bar length carries the selected review metric and X#
            -- on the right carries death count. This avoids making every death
            -- row look identical while still keeping deaths immediately visible.
            local options = Review.saveddata or {}
            local color = options.useClassColors ~= false and data.class and RAID_CLASS_COLORS[data.class]
            if color then
                row:SetColor(color.r, color.g, color.b, 0.90)
            else
                row:SetColor(0.55, 0.55, 0.55, 0.85)
            end

            local coords = data.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[data.class]
            row._icon:SetTexture([[Interface\Glues\CharacterCreate\UI-CharacterCreate-Classes]])
            if coords then
                row._icon:SetTexCoord(unpack(coords))
            else
                row._icon:SetTexCoord(0, 1, 0, 1)
            end
            Review:RefreshRowStyle(row)
            row:Show()
        else
            row.reviewData = nil
            row:Hide()
        end
    end
end

function Review:RefreshData()
    local instance = Review:GetPluginInstance()
    if not instance then
        return
    end

    Review:UpdateLayout()

    local combat = instance:GetShowingCombat()
    if Review.currentCombat and Review.currentCombat ~= combat then
        Review.ScrollOffset = 0
    end
    Review.currentCombat = combat
    Review.currentData = Review:BuildReviewData(combat)
    Review:RenderRows()
end

function Review:OnDetailsEvent(event, ...)
    if event == "SHOW" then
        local instance = Review:GetPluginInstance()
        if instance then
            ReviewFrame:SetParent(instance.baseframe)
            Review:RefreshData()
        end

    elseif event == "HIDE" then
        Review:HidePlayerTooltip()

    elseif event == "COMBAT_PLAYER_LEAVE" then
        if ReviewFrame:IsShown() then
            Review:RefreshData()
        end

    elseif event == "DETAILS_INSTANCE_CHANGESEGMENT" then
        local changedInstance = select(1, ...)
        local instance = Review:GetPluginInstance()
        if instance and changedInstance == instance and ReviewFrame:IsShown() then
            Review:RefreshData()
        end

    elseif event == "DETAILS_INSTANCE_ENDRESIZE" or event == "DETAILS_INSTANCE_SIZECHANGED" then
        local changedInstance = select(1, ...)
        local instance = Review:GetPluginInstance()
        if instance and changedInstance == instance then
            Review:UpdateLayout()
            Review:RefreshData()
        end

    elseif event == "DETAILS_OPTIONS_MODIFIED" then
        local changedInstance = select(1, ...)
        local instance = Review:GetPluginInstance()
        if instance and changedInstance == instance then
            Review:UpdateLayout()
            Review:RefreshData()
        end

    elseif event == "DETAILS_DATA_RESET" then
        if ReviewFrame:IsShown() then
            Review:RefreshData()
        end
    end
end

local function buildOptionsPanel()
    local optionsFrame = Review:CreatePluginOptionsFrame("DetailsRaidReviewOptionsWindow", "Raid Review Options", 1)

    local menu = {
        {
            type = "toggle",
            get = function() return Review.saveddata.showInactivePlayers end,
            set = function(self, fixedparam, value) Review.saveddata.showInactivePlayers = value; Review:RefreshData() end,
            name = "Show Entire Group",
            desc = "Show players even when they have no deaths, CC breaks or recorded raid actions in the selected segment.",
        },
        {
            type = "select",
            get = function() return Review.saveddata.sortMode end,
            values = function()
                local function choose(_, _, value)
                    Review.saveddata.sortMode = value
                    Review.ScrollOffset = 0
                    Review:RefreshData()
                end
                return {
                    {value = "priority", label = "Review Priority", onclick = choose},
                    {value = "damage", label = "Damage Taken", onclick = choose},
                    {value = "deaths", label = "Deaths", onclick = choose},
                    {value = "actions", label = "Raid Actions", onclick = choose},
                }
            end,
            name = "Sort Rows",
            desc = "Review Priority puts deaths and CC breaks first, then orders by damage taken. Other modes let the bars and ordering represent one specific metric.",
        },
        {
            type = "toggle",
            get = function() return Review.saveddata.useClassColors end,
            set = function(self, fixedparam, value) Review.saveddata.useClassColors = value; Review:RefreshData() end,
            name = "Use Class Colors",
            desc = "Use class colours for normal rows. Death and CC-break highlighting can override this.",
        },
        {
            type = "range",
            get = function() return Review.saveddata.deathHits end,
            set = function(self, fixedparam, value) Review.saveddata.deathHits = floor(value) end,
            min = 1,
            max = 5,
            step = 1,
            name = "Death Recap Hits",
            desc = "How many final damaging events to show for each death in the tooltip.",
        },
        {
            type = "range",
            get = function() return Review.saveddata.maxSpellRows end,
            set = function(self, fixedparam, value) Review.saveddata.maxSpellRows = floor(value) end,
            min = 3,
            max = 10,
            step = 1,
            name = "Tooltip Spell Rows",
            desc = "Maximum number of spells shown in each tooltip section.",
        },
    }

    _detalhes.gump:BuildMenu(optionsFrame, menu, 15, -65, 280)
end

Review.OpenOptionsPanel = function()
    if not _G.DetailsRaidReviewOptionsWindow then
        buildOptionsPanel()
    end
    _G.DetailsRaidReviewOptionsWindow:Show()
end

local function IsInRaidMenu()
    if not _detalhes.RaidTables or not _detalhes.RaidTables.Menu then
        return false
    end

    for index, entry in ipairs(_detalhes.RaidTables.Menu) do
        if entry and entry[4] == PLUGIN_ABSOLUTE_NAME then
            return true, index
        end
    end

    return false
end

local function InstallReviewPlugin()
    if Review.installed then
        return true
    end

    -- If Details already knows this absolute plugin name, reuse that state instead
    -- of attempting to register it twice (e.g. after a UI reload in unusual loaders).
    local existing = _detalhes.GetPlugin and _detalhes:GetPlugin(PLUGIN_ABSOLUTE_NAME)
    if existing and existing ~= Review then
        Review.installError = "plugin absolute name is already registered by another object"
        return false
    end

    if existing == Review then
        Review.installed = true
        return true
    end

    if not _detalhes.InstallPlugin or not _detalhes.RaidTables then
        Review.installError = "Details plugin API is not ready"
        return false
    end

    local install, saveddata = _detalhes:InstallPlugin(
        "RAID",
        PLUGIN_NAME,
        PLUGIN_ICON,
        Review,
        PLUGIN_ABSOLUTE_NAME,
        1,
        "Scuz / OpenAI",
        PLUGIN_VERSION,
        {}
    )

    if type(install) == "table" and install.error then
        Review.installError = install.error
        return false
    elseif not install then
        Review.installError = "Details rejected the plugin registration"
        return false
    end

    Review.saveddata = saveddata or {}
    if Review.saveddata.showInactivePlayers == nil then Review.saveddata.showInactivePlayers = true end
    if Review.saveddata.sortMode == nil then Review.saveddata.sortMode = "priority" end
    if Review.saveddata.useClassColors == nil then Review.saveddata.useClassColors = true end
    Review.saveddata.deathHits = Review.saveddata.deathHits or 3
    Review.saveddata.maxSpellRows = Review.saveddata.maxSpellRows or 6

    _detalhes:RegisterEvent(Review, "COMBAT_PLAYER_LEAVE")
    _detalhes:RegisterEvent(Review, "DETAILS_INSTANCE_CHANGESEGMENT")
    _detalhes:RegisterEvent(Review, "DETAILS_INSTANCE_ENDRESIZE")
    _detalhes:RegisterEvent(Review, "DETAILS_INSTANCE_SIZECHANGED")
    _detalhes:RegisterEvent(Review, "DETAILS_OPTIONS_MODIFIED")
    _detalhes:RegisterEvent(Review, "DETAILS_DATA_RESET")

    Review.installed = true
    Review.initialized = true
    Review.installError = nil
    return true
end

function Review:OnEvent(_, event, ...)
    -- NewPluginObject turns PLAYER_LOGIN into a synthetic ADDON_LOADED call.
    -- v0.2.1 no longer depends on that path, but keep it as a fallback for
    -- unusual addon loaders.
    if not Review.installed then
        InstallReviewPlugin()
    end
end

local function PrintStatus()
    local menuFound, menuIndex = IsInRaidMenu()
    local pluginObject = _detalhes.GetPlugin and _detalhes:GetPlugin(PLUGIN_ABSOLUTE_NAME)

    print("|cFFFFD100Details_RaidReview " .. PLUGIN_VERSION .. "|r")
    print("Addon Lua: |cFF55FF55loaded|r")
    print("Details plugin: " .. (pluginObject == Review and "|cFF55FF55installed|r" or "|cFFFF5555not installed|r"))
    print("Automation menu: " .. (menuFound and ("|cFF55FF55present|r (#" .. tostring(menuIndex) .. ")") or "|cFFFF5555missing|r"))
    if Review.installError then
        print("Install error: |cFFFF5555" .. tostring(Review.installError) .. "|r")
    end
end

SLASH_DETAILSRAIDREVIEW1 = "/rrp"
SLASH_DETAILSRAIDREVIEW2 = "/raidreview"
SlashCmdList.DETAILSRAIDREVIEW = function(msg)
    local command = (msg or ""):match("^%s*(%S*)") or ""
    command = command:lower()

    if command == "show" then
        local instance = _detalhes:GetInstance(2) or _detalhes:GetInstance(1)
        if instance and _detalhes.RaidTables and _detalhes.RaidTables.EnableRaidMode then
            _detalhes.RaidTables:EnableRaidMode(instance, PLUGIN_ABSOLUTE_NAME)
        else
            print("|cFFFF5555Raid Review: no Details window is available.|r")
        end
    elseif command == "install" then
        local ok = InstallReviewPlugin()
        print(ok and "|cFF55FF55Raid Review registered.|r" or "|cFFFF5555Raid Review registration failed.|r")
        PrintStatus()
    elseif command == "options" or command == "config" then
        Review.OpenOptionsPanel()
    elseif command == "refresh" then
        Review:RefreshData()
        print("|cFF55FF55Raid Review refreshed.|r")
    elseif command == "debug" then
        PrintStatus()
        local row = Review.Rows and Review.Rows[1]
        local focus = GetMouseFocus and GetMouseFocus()
        print("Mouse focus: " .. tostring(focus and focus:GetName() or focus or "nil"))
        if row and row.widget then
            print("Row 1: shown=" .. tostring(row.widget:IsShown()) .. " level=" .. tostring(row.widget:GetFrameLevel()) .. " strata=" .. tostring(row.widget:GetFrameStrata()))
            if row.hitbox then
                print("Hitbox 1: shown=" .. tostring(row.hitbox:IsShown()) .. " level=" .. tostring(row.hitbox:GetFrameLevel()) .. " strata=" .. tostring(row.hitbox:GetFrameStrata()) .. " mouse=" .. tostring(row.hitbox:IsMouseEnabled()))
            else
                print("Hitbox 1: missing")
            end
        else
            print("Row 1: missing")
        end
    else
        PrintStatus()
        print("Commands: /rrp status, /rrp show, /rrp options, /rrp refresh, /rrp debug, /rrp install")
    end
end

-- Details is a RequiredDeps addon, so by the time this file executes its
-- plugin API is already available. Register immediately so Raid Review is in
-- RaidTables.Menu before the Window Automatization dropdown is opened.
InstallReviewPlugin()
