return function(Window)
    local VisualTab = Window:CreateTab("Visual", 4483362458)
    if not VisualTab then return end

    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer

    -- =================================================================
    -- НАСТРОЙКИ МОДУЛЯ SPECIAL ESP
    -- =================================================================
    local SpecialESPSettings = {
        Enabled = false,
        Filters = {"Anti-Fling"},
        DisplayMode = "Текст + Highlight",
        Color = Color3.fromRGB(255, 50, 80),
        Transparency = 0.35,
    }

    local TagInstances = {}

    local function hasFilter(filterName)
        for _, item in ipairs(SpecialESPSettings.Filters) do
            if item == filterName then
                return true
            end
        end
        return false
    end

    local function isAntiFlingActive(player)
        if player == LocalPlayer then return false end
        local char = player.Character
        if not char then return false end

        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then return false end

        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return false end

        local totalParts = 0
        local collidableParts = 0

        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") and not part.Name:match("XCLIENT") then
                totalParts = totalParts + 1
                if part.CanCollide then
                    collidableParts = collidableParts + 1
                end
            end
        end

        return totalParts > 0 and collidableParts == 0
    end

    local function removePlayerESP(player)
        local data = TagInstances[player]
        if data then
            if data.Highlight and data.Highlight.Parent then
                data.Highlight:Destroy()
            end
            if data.Billboard and data.Billboard.Parent then
                data.Billboard:Destroy()
            end
            TagInstances[player] = nil
        end
    end

    local function clearAllESP()
        for player in pairs(TagInstances) do
            removePlayerESP(player)
        end
    end

    local function updatePlayerESP(player)
        local char = player.Character
        local head = char and char:FindFirstChild("Head")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local targetPart = head or root

        if not targetPart or not char then
            removePlayerESP(player)
            return
        end

        local data = TagInstances[player]
        if not data then
            data = {}
            TagInstances[player] = data
        end

        local mode = SpecialESPSettings.DisplayMode
        local needHighlight = (mode == "Highlight" or mode == "Текст + Highlight")
        local needText = (mode == "Надпись над головой" or mode == "Текст + Highlight")

        -- 1. Управление Highlight
        if needHighlight then
            if not data.Highlight or data.Highlight.Parent ~= char then
                if data.Highlight then data.Highlight:Destroy() end
                local hl = Instance.new("Highlight")
                hl.Name = "XCLIENT_AntiFlingHighlight"
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.Parent = char
                data.Highlight = hl
            end
            data.Highlight.FillColor = SpecialESPSettings.Color
            data.Highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            data.Highlight.FillTransparency = SpecialESPSettings.Transparency
            data.Highlight.OutlineTransparency = 0
            data.Highlight.Enabled = true
        else
            if data.Highlight then
                data.Highlight:Destroy()
                data.Highlight = nil
            end
        end

        -- 2. Управление BillboardGui
        if needText then
            if not data.Billboard or data.Billboard.Adornee ~= targetPart then
                if data.Billboard then data.Billboard:Destroy() end

                local bb = Instance.new("BillboardGui")
                bb.Name = "XCLIENT_AntiFlingTag"
                bb.Size = UDim2.new(0, 105, 0, 22)
                bb.StudsOffset = Vector3.new(0, 2.6, 0)
                bb.AlwaysOnTop = true
                bb.Adornee = targetPart
                bb.ResetOnSpawn = false

                local frame = Instance.new("Frame")
                frame.Name = "TagFrame"
                frame.Size = UDim2.new(1, 0, 1, 0)
                frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
                frame.BackgroundTransparency = 0.25
                frame.BorderSizePixel = 0
                frame.Parent = bb

                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 5)
                corner.Parent = frame

                local stroke = Instance.new("UIStroke")
                stroke.Name = "TagStroke"
                stroke.Thickness = 1
                stroke.Color = SpecialESPSettings.Color
                stroke.Parent = frame

                local label = Instance.new("TextLabel")
                label.Name = "TagLabel"
                label.Size = UDim2.new(1, 0, 1, 0)
                label.BackgroundTransparency = 1
                label.Font = Enum.Font.GothamBold
                label.TextSize = 11
                label.Text = "⚠ ANTIFLING"
                label.TextColor3 = SpecialESPSettings.Color
                label.Parent = frame

                bb.Parent = targetPart
                data.Billboard = bb
                data.Label = label
                data.Stroke = stroke
            end

            if data.Label then
                data.Label.TextColor3 = SpecialESPSettings.Color
            end
            if data.Stroke then
                data.Stroke.Color = SpecialESPSettings.Color
            end
        else
            if data.Billboard then
                data.Billboard:Destroy()
                data.Billboard = nil
                data.Label = nil
                data.Stroke = nil
            end
        end
    end

    Players.PlayerRemoving:Connect(removePlayerESP)

    task.spawn(function()
        while task.wait(0.15) do
            if SpecialESPSettings.Enabled and hasFilter("Anti-Fling") then
                for _, player in ipairs(Players:GetPlayers()) do
                    if isAntiFlingActive(player) then
                        updatePlayerESP(player)
                    else
                        removePlayerESP(player)
                    end
                end
            else
                clearAllESP()
            end
        end
    end)

    -- =================================================================
    -- ИНТЕРФЕЙС ВО ВКЛАДКЕ VISUAL
    -- =================================================================
    VisualTab:CreateSection("Special Detection ESP")

    VisualTab:CreateToggle({
        Name = "Включить Special ESP",
        CurrentValue = false,
        Flag = "SpecialESPToggle",
        Description = "Позволяет выявлять скрытые механики игроков",
        Callback = function(Value)
            SpecialESPSettings.Enabled = Value
            if not Value then
                clearAllESP()
            end
        end,
        Settings = {
            "Параметры фильтрации",
            {
                Type = "Dropdown",
                Name = "Режим отображения",
                Options = {"Текст + Highlight", "Надпись над головой", "Highlight"},
                CurrentOption = "Текст + Highlight",
                Flag = "SpecialESPDisplayMode",
                Callback = function(Value)
                    if type(Value) == "table" then Value = Value[1] end
                    if Value then
                        SpecialESPSettings.DisplayMode = Value
                    end
                end
            },
            {
                Type = "ColorPicker",
                Name = "Цвет подсветки",
                Color = Color3.fromRGB(255, 50, 80),
                Flag = "SpecialESPColor",
                Callback = function(Value)
                    SpecialESPSettings.Color = Value
                end
            },
            {
                Type = "Slider",
                Name = "Прозрачность Highlight (%)",
                Range = {0, 100},
                Increment = 5,
                Suffix = "%",
                CurrentValue = 35,
                Flag = "SpecialESPTransparency",
                Callback = function(Value)
                    SpecialESPSettings.Transparency = Value / 100
                end
            }
        }
    })

    VisualTab:CreateDropdown({
        Name = "Выбор целей подсветки",
        Options = {"Anti-Fling"},
        CurrentOption = {"Anti-Fling"},
        MultipleOptions = true,
        Flag = "SpecialESPTargetFilter",
        Callback = function(Options)
            SpecialESPSettings.Filters = Options or {}
            if not hasFilter("Anti-Fling") then
                clearAllESP()
            end
        end
    })
end
