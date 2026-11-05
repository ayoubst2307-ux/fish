-- AutoFlower.lua
-- Runtime : Roblox executor (Synapse X / KRNL / Fluxus)
-- Luau — LocalScript context
-- F5 = set flower zone | F6 = toggle | F7 = set home

-------------------------------------------------
-- SERVICES
-------------------------------------------------
local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local UIS         = game:GetService("UserInputService")
local VR          = game:GetService("VirtualInputManager")

local lp          = Players.LocalPlayer
local gui         = lp:WaitForChild("PlayerGui")

-------------------------------------------------
-- CONFIG
-------------------------------------------------
local CFG = {
    holdTime       = 2.15,   -- secondes de maintien E par fleur
    maxFlowers     = 5,      -- fleurs à ramasser par run
    searchRadius   = 30,     -- studs — rayon de scan fleurs
    scanRate       = 0.4,    -- secondes entre chaque scan
    tpWarmup       = 0.15,   -- délai après TP avant de bouger
    buffKeywords   = { "pollinated", "pollen" },   -- textes GUI du buff
    promptKeywords = { "open", "collect", "flower", "fleur" },
}

-------------------------------------------------
-- STATE
-------------------------------------------------
local state = {
    enabled     = false,
    homePos     = nil,   -- CFrame de base (défini par F7 ou auto)
    flowerPos   = nil,   -- CFrame zone fleurs (défini par F5 ou auto)
    phase       = "IDLE",
    -- phases : IDLE | GOING_FLOWERS | COLLECTING | GOING_HOME | WAITING_BUFF
    count       = 0,
    busy        = false,
}

-------------------------------------------------
-- UTILS
-------------------------------------------------
local function getChar()
    return lp.Character
end

local function getHRP()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getRootPos()
    local h = getHRP()
    return h and h.CFrame
end

local function tpTo(cf)
    local h = getHRP()
    if not h then return end
    h.CFrame = cf
    task.wait(CFG.tpWarmup)
end

-- scan le PlayerGui pour le buff actif
local function isBuffActive()
    for _, obj in ipairs(gui:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("Frame") then
            local txt = (obj:IsA("Frame") and "") or obj.Text or ""
            txt = txt:lower()
            for _, kw in ipairs(CFG.buffKeywords) do
                if txt:find(kw) then
                    -- vérifie que l'objet est visible
                    local vis = true
                    local cur = obj
                    while cur and cur ~= gui do
                        if not cur.Visible then vis = false break end
                        cur = cur.Parent
                    end
                    if vis then return true end
                end
            end
        end
    end
    return false
end

-- cherche le ProximityPrompt de fleur le plus proche
local function nearestFlowerPrompt()
    local hrp = getHRP()
    if not hrp then return nil end
    local best, bestDist = nil, math.huge
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then
            local at = (obj.ActionText or ""):lower()
            local ot = (obj.ObjectText or ""):lower()
            local combined = at .. " " .. ot
            local match = false
            for _, kw in ipairs(CFG.promptKeywords) do
                if combined:find(kw) then match = true break end
            end
            if match and obj.Enabled then
                local part = obj.Parent
                if part and part:IsA("BasePart") then
                    local d = (hrp.Position - part.Position).Magnitude
                    if d < bestDist and d < CFG.searchRadius then
                        best, bestDist = obj, d
                    end
                end
            end
        end
    end
    return best
end

-------------------------------------------------
-- COLLECT UNE FLEUR (hold ~2s)
-------------------------------------------------
local function collectOne(prompt)
    -- méthode 1 : fireproximityprompt executor func
    local ok1 = pcall(function()
        fireproximityprompt(prompt) -- Synapse / Fluxus
    end)
    if ok1 then
        task.wait(prompt.HoldDuration + 0.1)
        return true
    end

    -- méthode 2 : InputHoldBegin / InputHoldEnd directs
    local ok2 = pcall(function()
        prompt:InputHoldBegin()
        task.wait(math.max(prompt.HoldDuration, CFG.holdTime))
        prompt:InputHoldEnd()
    end)
    if ok2 then return true end

    -- méthode 3 : firetouchinterest + hold virtuel
    pcall(function()
        local hrp = getHRP()
        if hrp then
            firetouchinterest(hrp, prompt.Parent, 0)
        end
        task.wait(CFG.holdTime)
        firetouchinterest(hrp, prompt.Parent, 1)
    end)
    return false
end

-------------------------------------------------
-- RUN COLLECT (5 fleurs)
-------------------------------------------------
local function runCollect()
    state.count = 0
    while state.count < CFG.maxFlowers and state.enabled do
        local prompt = nearestFlowerPrompt()
        if prompt then
            collectOne(prompt)
            state.count = state.count + 1
            print(string.format("[AutoFlower] %d / %d", state.count,
