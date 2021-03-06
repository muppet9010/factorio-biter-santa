local Santa = {}
local SantaStates = require("scripts/santa_states")
local Logging = require("utility/logging")
local Utils = require("utility/utils")
local Commands = require("utility/commands")
local EventScheduler = require("utility/event-scheduler")
local debug = false

Santa.CreateGlobals = function()
    global.santa = global.santa or {}
    global.santa.landingPos = global.santa.landingPos or nil
    global.nextScheduledSantaTick = global.nextScheduledSantaTick or nil
    global.santaShouldReturnAfterDelay = global.santaShouldReturnAfterDelay or nil
end

Santa.OnLoad = function()
    EventScheduler.RegisterScheduler()
    Commands.Register("call-santa", {"api-description.biter_santa-call_santa"}, Santa.CallSantaCommand, true)
    Commands.Register("dismiss-santa", {"api-description.biter_santa-dismiss_santa"}, Santa.DismissSantaCommand, true)
    Commands.Register("delete-santa", {"api-description.biter_santa-delete_santa"}, Santa.DeleteSantaCommand, true)
    Commands.Register("set-santa-landing-position", {"api-description.biter_santa-set_santa_landing_position"}, Santa.SetLandingPosition, true)
    Commands.Register("offset-santa-landing-position", {"api-description.biter_santa-offset_santa_landing_position"}, Santa.OffsetLandingPosition, true)
    Commands.Register("reintroduce-santa", {"api-description.biter_santa-reintroduce_santa"}, Santa.ReintroduceSantaCommand, true)
    EventScheduler.RegisterScheduledEventType("Santa.CallSantaScheduledEvent", Santa.CallSantaScheduledEvent)
end

Santa.CallSantaCommand = function(commandDetails)
    if commandDetails ~= nil then
        if global.SantaGroup ~= nil then
            game.players[commandDetails.player_index].print("Santa is already on the map and there is only 1 of him!")
            return
        end
        game.players[commandDetails.player_index].print("Santa called")
    end
    Santa.CreateSantaGroup()
end

Santa.CreateSantaGroup = function()
    local tickMoveSpeed = 0.4
    local descendSpeedReducton = 0.25
    local maxVTOHeightRiseRate = 0.05
    local altitudeChangeDistanceTiles = 80
    local flyingHeightTiles = 10
    local groundDamageHeight = 3
    local groundEntitySpriteHeight = 2
    local smokeMinSpeed = 0.35
    local phaseInOutDistance = math.floor(20 / tickMoveSpeed) * tickMoveSpeed
    local landedPos =
        global.santa.landingPos or
        {
            x = tonumber(settings.global["santa-landed-spot-x"].value),
            y = tonumber(settings.global["santa-landed-spot-y"].value)
        }

    local groundSlowdownStartingSpeed = tickMoveSpeed - (tickMoveSpeed * descendSpeedReducton)
    local descentPattern = Santa.CalculateDescentPattern(tickMoveSpeed, groundSlowdownStartingSpeed, altitudeChangeDistanceTiles, flyingHeightTiles)
    local groundSlowdownPattern = Santa.CalculateGroundSlowdownPattern(groundSlowdownStartingSpeed)
    local landingDistance = Santa.CalculateLandingDistance(descentPattern, groundSlowdownPattern)

    local landingStartPos = {
        x = landedPos.x - landingDistance,
        y = landedPos.y
    }
    local takeOffEndPos = {
        x = landedPos.x + altitudeChangeDistanceTiles,
        y = landedPos.y
    }
    local idealSpawnTilesLeft = (math.floor((tonumber(settings.global["santa-spawn-tiles-left"].value) - landingDistance) / tickMoveSpeed) * tickMoveSpeed) + landingDistance
    Logging.Log("idealSpawnTilesLeft: " .. idealSpawnTilesLeft, debug)
    local spawnPos = {
        x = landedPos.x - math.max(idealSpawnTilesLeft, (landingDistance + phaseInOutDistance)),
        y = landedPos.y
    }
    local surface = game.surfaces[1]
    local takeoffSettingRaw = settings.global["santa-takeoff-method"].value
    local takeoffMode, vtoUpPattern, vtoClimbPattern, idealDisappearTilesRight, minDisappearTilesRight
    if takeoffSettingRaw == "rolling horizontal takeoff" then
        takeoffMode = "rolling"
        idealDisappearTilesRight = (math.floor((tonumber(settings.global["santa-disappear-tiles-right"].value) - landingDistance) / tickMoveSpeed) * tickMoveSpeed) + landingDistance
        minDisappearTilesRight = landingDistance + phaseInOutDistance
    elseif takeoffSettingRaw == "vertical takeoff" then
        takeoffMode = "vto"
        local transitionHeight = math.max((flyingHeightTiles / 2), (groundDamageHeight + 1))
        local heightReached, currentRiseRate
        vtoUpPattern, heightReached, currentRiseRate = Santa.CalculateVTOUpPattern(transitionHeight, maxVTOHeightRiseRate)
        vtoClimbPattern = Santa.CalculateVTOClimbPattern(heightReached, flyingHeightTiles, tickMoveSpeed, currentRiseRate)
        local vtoTakeOffDistance = Santa.CalculateVTOTakeoffDistance(vtoClimbPattern)
        idealDisappearTilesRight = (math.floor((tonumber(settings.global["santa-disappear-tiles-right"].value) - vtoTakeOffDistance) / tickMoveSpeed) * tickMoveSpeed) + vtoTakeOffDistance
        minDisappearTilesRight = vtoTakeOffDistance + phaseInOutDistance
    end
    Logging.Log("idealDisappearTilesRight: " .. idealDisappearTilesRight, debug)

    local disappearPos = {
        x = landedPos.x + math.max(idealDisappearTilesRight, minDisappearTilesRight),
        y = landedPos.y
    }
    local phaseOutSmokeTriggerXPos = disappearPos.x - (240 * tickMoveSpeed)

    global.SantaGroup = {
        nextStateTick = nil,
        santaEntity = nil,
        santaSpriteId = nil,
        santaShadowSpriteId = nil,
        vtoFlame1Entity = nil,
        vtoFlame2Entity = nil,
        vtoFlame1AnimationId = nil,
        vtoFlame2AnimationId = nil,
        surface = surface,
        state = SantaStates.pre_spawning,
        currentPos = spawnPos,
        spawnPos = spawnPos,
        landingStartPos = landingStartPos,
        landedPos = landedPos,
        takeOffEndPos = takeOffEndPos,
        disappearPos = disappearPos,
        tickMoveSpeed = tickMoveSpeed,
        altitudeChangeDistanceTiles = altitudeChangeDistanceTiles,
        flyingHeightTiles = flyingHeightTiles,
        groundDamageHeight = groundDamageHeight,
        groundEntitySpriteHeight = groundEntitySpriteHeight,
        collisionBox = game.entity_prototypes["biter_santa_landed"].collision_box,
        descendSpeedReducton = descendSpeedReducton,
        descentPattern = descentPattern,
        groundSlowdownPattern = groundSlowdownPattern,
        stateIteration = 1,
        phaseInSmokeIteration = 1,
        takeoffMode = takeoffMode,
        vtoUpPattern = vtoUpPattern,
        vtoClimbPattern = vtoClimbPattern,
        phaseOutSmokeTriggerXPos = phaseOutSmokeTriggerXPos,
        smokeMinSpeed = smokeMinSpeed,
        speed = 0
    }
    if debug then
        Logging.LogPrint("Santa Created")
        Logging.Log(Utils.TableContentsToString(global.SantaGroup, "global.SantaGroup"))
    end
end

Santa.SpawnSantaEntity = function(creationPos, height)
    local santaGroup = global.SantaGroup
    if santaGroup.state == SantaStates.spawning then
        Santa.RemoveSantaEntity()
        height = santaGroup.flyingHeightTiles
        santaGroup.santaSpriteId = rendering.draw_sprite {sprite = "biter_santa_flying", render_layer = "air-object", target = creationPos, surface = santaGroup.surface}
    elseif santaGroup.state == SantaStates.landing_air_near_ground then
        Santa.RemoveSantaEntity()
        santaGroup.santaEntity = santaGroup.surface.create_entity {name = "biter_santa_flying", position = creationPos, direction = defines.direction.east, force = "neutral"}
        santaGroup.santaEntity.destructible = false
    elseif santaGroup.state == SantaStates.landed then
        Santa.RemoveSantaEntity()
        height = 0
        santaGroup.santaEntity = santaGroup.surface.create_entity {name = "biter_santa_landed", position = creationPos, direction = defines.direction.east, force = "neutral"}
        Santa.AddContentsToSanta()
        santaGroup.santaEntity.destructible = false
    elseif santaGroup.state == SantaStates.taking_off_ground or santaGroup.state == SantaStates.vto_up_near_ground then
        Santa.RemoveSantaEntity()
        height = 0
        santaGroup.santaEntity = santaGroup.surface.create_entity {name = "biter_santa_flying", position = creationPos, direction = defines.direction.east, force = "neutral"}
        santaGroup.santaEntity.destructible = false
    elseif santaGroup.state == SantaStates.taking_off_air or santaGroup.state == SantaStates.vto_up then
        Santa.RemoveSantaEntity()
        santaGroup.santaSpriteId = rendering.draw_sprite {sprite = "biter_santa_flying", render_layer = "object", target = creationPos, surface = santaGroup.surface}
    else
        return
    end
    Santa.CreateSantaEntityShadowSprite(height)
end

Santa.AddContentsToSanta = function()
    local contentsString = settings.global["santa-inventory-contents"].value
    local santaHasInventory = settings.startup["santa-has-inventory"].value
    if contentsString == nil or contentsString == "" then
        return
    end
    if santaHasInventory ~= true then
        Logging.LogPrint("Error: Biter Santa has contents set, but inventory isn't enabled")
        return
    end
    local contents = game.json_to_table(contentsString)
    if contents == nil then
        Logging.LogPrint("Error: Biter Santa inventory has invalid contents setting: " .. tostring(contentsString))
        return
    end

    for _, content in pairs(contents) do
        local itemName, quantity = content.name, content.quantity
        if game.item_prototypes[itemName] == nil then
            Logging.LogPrint("Error: Biter Santa inventory invalid content item: " .. tostring(itemName))
            return
        elseif type(quantity) ~= "number" or quantity < 0 then
            Logging.LogPrint("Error: Biter Santa inventory invalid content item count for '" .. itemName .. "': " .. tostring(quantity))
            return
        else
            global.SantaGroup.santaEntity.insert({name = itemName, count = quantity})
        end
    end
end

Santa.CreateSantaEntityShadowSprite = function(height)
    local santaGroup = global.SantaGroup
    santaGroup.santaShadowSpriteId = rendering.draw_sprite {sprite = "biter_santa_shadow", render_layer = "air-object", target = Santa.CalculateShadowSantaPosition(height), surface = santaGroup.surface}
end

Santa.CalculateShadowSantaPosition = function(height)
    local santaGroup = global.SantaGroup
    local heightMod = height / 100
    local shadowPos = {
        x = santaGroup.currentPos.x + (60 * heightMod),
        y = santaGroup.currentPos.y + (48 * heightMod)
    }
    return shadowPos
end

Santa.RemoveSantaEntity = function()
    local santaGroup = global.SantaGroup
    if santaGroup.santaEntity ~= nil and santaGroup.santaEntity.valid then
        santaGroup.santaEntity.destroy()
        santaGroup.santaEntity = nil
    end
    if santaGroup.santaSpriteId ~= nil and rendering.is_valid(santaGroup.santaSpriteId) then
        rendering.destroy(santaGroup.santaSpriteId)
        santaGroup.santaSpriteId = nil
    end
    if santaGroup.santaShadowSpriteId ~= nil and rendering.is_valid(santaGroup.santaShadowSpriteId) then
        rendering.destroy(santaGroup.santaShadowSpriteId)
        santaGroup.santaShadowSpriteId = nil
    end
end

Santa.DismissSantaCommand = function(commandDetails)
    if commandDetails ~= nil then
        if global.SantaGroup == nil then
            game.players[commandDetails.player_index].print("Santa is not on the map!")
            return
        elseif global.SantaGroup.state ~= SantaStates.landed then
            game.players[commandDetails.player_index].print("Santa can only be dismissed when landed")
            return
        end
        game.players[commandDetails.player_index].print("Santa dismissed")
    end
    Santa.TakeOff()
end

Santa.DeleteSantaCommand = function(commandDetails)
    if commandDetails ~= nil then
        game.players[commandDetails.player_index].print("Santa deleted")
    end
    Santa.DeleteSanta()
end

Santa.DeleteSanta = function()
    if global.SantaGroup == nil then
        return
    end
    Santa.RemoveSantaEntity()
    global.SantaGroup = nil
end

Santa.CalculateDescentPattern = function(tickMoveSpeed, endingSpeed, altitudeChangeDistanceTiles, flyingHeightTiles)
    local averageSpeed = tickMoveSpeed - ((tickMoveSpeed - endingSpeed) / 2)
    local numberOfFrames = math.floor(altitudeChangeDistanceTiles / averageSpeed)

    local range = 30
    local jumpSize = range / (numberOfFrames + 1)
    local samplePoints = {}
    for i = 1, (numberOfFrames + 1) do
        samplePoints[i] = (i * jumpSize) - (range / 2)
    end

    local heightSpreader = 0.2
    local heightValue = flyingHeightTiles + heightSpreader
    local currentSpeed = tickMoveSpeed
    local speedDecrease = (tickMoveSpeed - endingSpeed) / numberOfFrames
    local steepness = 0.3
    local descentPattern = {}
    for i, sp in pairs(samplePoints) do
        currentSpeed = currentSpeed - speedDecrease
        local currentHeight = Utils.LogisticEquation(sp, heightValue, steepness) - 0.1
        if currentHeight < flyingHeightTiles and currentHeight > 0 then
            table.insert(
                descentPattern,
                {
                    speed = currentSpeed,
                    height = currentHeight
                }
            )
        end
    end

    return descentPattern
end

Santa.CalculateGroundSlowdownPattern = function(startingSpeed)
    local slowdownPattern = {}
    local slowdownPercentPerSecond = 0.75
    local slowdownPercentPerTick = slowdownPercentPerSecond / 60
    local currentSpeed = startingSpeed
    while currentSpeed > 0.01 do
        currentSpeed = currentSpeed - (currentSpeed * slowdownPercentPerTick)
        table.insert(slowdownPattern, currentSpeed)
    end
    return slowdownPattern
end

Santa.CalculateLandingDistance = function(descentPattern, groundSlowdownPattern)
    local descentDistance = 0
    for k, data in pairs(descentPattern) do
        descentDistance = descentDistance + data.speed
    end
    Logging.Log("descentDistance: " .. descentDistance, debug)
    local stoppingDistance = 0
    for k, speed in pairs(groundSlowdownPattern) do
        stoppingDistance = stoppingDistance + speed
    end
    Logging.Log("stoppingDistance: " .. stoppingDistance, debug)
    local landingDistance = descentDistance + stoppingDistance
    Logging.Log("landingDistance: " .. landingDistance, debug)
    return landingDistance
end

Santa.IsSantaEntityValid = function()
    local santaGroup = global.SantaGroup
    if (santaGroup.santaEntity == nil or not santaGroup.santaEntity.valid) and (santaGroup.santaSpriteId == nil or not rendering.is_valid(santaGroup.santaSpriteId)) then
        return false
    end
    if santaGroup.santaShadowSpriteId == nil or not rendering.is_valid(santaGroup.santaShadowSpriteId) then
        return false
    end
    return true
end

Santa.NotValidEntityOccured = function()
    game.print("Critical Error - Santa Entity Invalid")
    Santa.DeleteSanta()
end

Santa.CreateWheelSparks = function(santaEntityPosition)
    local santaGroup = global.SantaGroup
    local bottomWheelRowYPos = santaEntityPosition.y + 0.9
    local wheelSparkSpotsXPos = {
        santaEntityPosition.x - 2.5,
        santaEntityPosition.x - 3.5,
        santaEntityPosition.x - 6.5,
        santaEntityPosition.x - 7.5
    }
    for _, xPos in pairs(wheelSparkSpotsXPos) do
        santaGroup.surface.create_trivial_smoke {name = "santa_wheel_sparks", position = {x = xPos, y = bottomWheelRowYPos}}
    end
end

Santa.CreateFlyingBiterSmoke = function(santaEntityPosition)
    local santaGroup = global.SantaGroup
    local biterRowsYPos = {
        santaEntityPosition.y - 1,
        santaEntityPosition.y,
        santaEntityPosition.y + 0.5,
        santaEntityPosition.y + 1.2
    }
    local biterSmokeSpotsXPos = {
        santaEntityPosition.x + 8,
        santaEntityPosition.x + 7,
        santaEntityPosition.x + 6,
        santaEntityPosition.x + 5,
        santaEntityPosition.x + 4,
        santaEntityPosition.x + 3,
        santaEntityPosition.x + 2,
        santaEntityPosition.x + 1,
        santaEntityPosition.x,
        santaEntityPosition.x - 1
    }
    for _, yPos in pairs(biterRowsYPos) do
        for _, xPos in pairs(biterSmokeSpotsXPos) do
            santaGroup.surface.create_trivial_smoke {name = "santa_biter_air_smoke", position = {x = xPos, y = yPos}}
        end
    end

    local topWheelRowYPos = santaEntityPosition.y - 0.5
    local bottomWheelRowYPos = santaEntityPosition.y + 0.9
    local wheelSmokeSpotsXPos = {
        santaEntityPosition.x - 2.5,
        santaEntityPosition.x - 3.5,
        santaEntityPosition.x - 6.5,
        santaEntityPosition.x - 7.5
    }
    for k, xPos in pairs(wheelSmokeSpotsXPos) do
        santaGroup.surface.create_trivial_smoke {name = "santa_biter_air_smoke", position = {x = xPos, y = topWheelRowYPos}}
        santaGroup.surface.create_trivial_smoke {name = "santa_biter_air_smoke", position = {x = xPos, y = bottomWheelRowYPos}}
    end
end

Santa.MoveSantaEntity = function(santaEntityPos, height, noSmoke)
    local santaGroup = global.SantaGroup
    if height == nil then
        height = 0
    end
    if santaGroup.santaEntity ~= nil and santaGroup.santaEntity.valid then
        santaGroup.santaEntity.teleport(santaEntityPos)
    elseif santaGroup.santaSpriteId ~= nil and rendering.is_valid(santaGroup.santaSpriteId) then
        rendering.set_target(santaGroup.santaSpriteId, santaEntityPos)
    end
    if not noSmoke and height > 0 and santaGroup.speed >= santaGroup.smokeMinSpeed then
        Santa.CreateFlyingBiterSmoke(santaEntityPos)
    end
    rendering.set_target(santaGroup.santaShadowSpriteId, Santa.CalculateShadowSantaPosition(height))
    if santaGroup.vtoFlame1Entity ~= nil or santaGroup.vtoFlame1AnimationId ~= nil then
        Santa.MoveVTOFlames(santaEntityPos)
    end
end

Santa.TakeOff = function()
    local santaGroup = global.SantaGroup
    if santaGroup.takeoffMode == "rolling" then
        santaGroup.state = SantaStates.taking_off_ground
        santaGroup.stateIteration = #santaGroup.groundSlowdownPattern
    elseif santaGroup.takeoffMode == "vto" then
        santaGroup.state = SantaStates.vto_up_near_ground
        santaGroup.stateIteration = 1
        Santa.CreateVTOFlameEntities(santaGroup.landedPos)
    end
    Santa.SpawnSantaEntity(santaGroup.landedPos)
end

Santa.CalculateVTOUpPattern = function(targetHeight, maxRiseRate)
    local vtoUpPattern = {}
    local currentRise = 0.001
    local riseIncrease = 1.1
    local currentHeight = 0
    while currentHeight < targetHeight do
        currentRise = math.min((currentRise * riseIncrease), maxRiseRate)
        currentHeight = (currentHeight + currentRise)
        table.insert(vtoUpPattern, currentHeight)
    end
    return vtoUpPattern, currentHeight, currentRise
end

Santa.CalculateVTOClimbPattern = function(startHeight, targetHeight, maxSpeed, currentRiseRate)
    local vtoClimbPattern = {}
    local heightRiseSlowdown = 0.75
    local speedIncreaseRate = 1.02
    local minRiseRate = 0.015
    local currentHeight = startHeight
    local nearTargetHeight = targetHeight - 1
    local currentSpeed = 0.01
    while Utils.FuzzyCompareDoubles(currentHeight, "<", nearTargetHeight) do
        if Utils.FuzzyCompareDoubles(currentRiseRate, ">", minRiseRate) then
            currentRiseRate = math.max((currentRiseRate * heightRiseSlowdown), minRiseRate)
        end
        if Utils.FuzzyCompareDoubles(currentSpeed, "<=", maxSpeed) then
            currentSpeed = math.min((currentSpeed * speedIncreaseRate), maxSpeed)
        end
        currentHeight = currentHeight + currentRiseRate
        table.insert(vtoClimbPattern, {height = currentHeight, speed = currentSpeed})
    end
    while Utils.FuzzyCompareDoubles(currentHeight, "<", targetHeight) or Utils.FuzzyCompareDoubles(currentSpeed, "<", maxSpeed) do
        currentHeight = math.min((currentHeight + currentRiseRate), targetHeight)
        currentSpeed = math.min((currentSpeed * speedIncreaseRate), maxSpeed)
        table.insert(vtoClimbPattern, {height = currentHeight, speed = currentSpeed})
    end
    return vtoClimbPattern
end

Santa.CalculateVTOTakeoffDistance = function(vtoClimbPattern)
    local climbDistance = 0
    for k, data in pairs(vtoClimbPattern) do
        climbDistance = climbDistance + data.speed
    end
    Logging.Log("climbDistance: " .. climbDistance, debug)
    local vtoTakeoffDistance = climbDistance
    Logging.Log("vtoTakeoffDistance: " .. vtoTakeoffDistance, debug)
    return vtoTakeoffDistance
end

Santa.CreateVTOFlameEntities = function(santaEntityPosition)
    local santaGroup = global.SantaGroup
    santaGroup.vtoFlame1Entity = santaGroup.surface.create_entity {name = "santa_biter_vto_flame", position = santaEntityPosition, force = "neutral"}
    santaGroup.vtoFlame1Entity.destructible = false
    santaGroup.vtoFlame2Entity = santaGroup.surface.create_entity {name = "santa_biter_vto_flame", position = santaEntityPosition, force = "neutral"}
    santaGroup.vtoFlame2Entity.destructible = false
    Santa.MoveVTOFlames(santaEntityPosition)
end

Santa.MoveVTOFlames = function(santaEntityPosition)
    local santaGroup = global.SantaGroup
    local flamePos1 = {
        x = santaEntityPosition.x - 2.9,
        y = santaEntityPosition.y + 2.1
    }
    local flamePos2 = {
        x = santaEntityPosition.x - 7.1,
        y = santaEntityPosition.y + 2.1
    }
    if santaGroup.vtoFlame1Entity ~= nil then
        santaGroup.vtoFlame1Entity.teleport(flamePos1)
        santaGroup.vtoFlame2Entity.teleport(flamePos2)
    elseif santaGroup.vtoFlame1AnimationId ~= nil then
        rendering.set_target(santaGroup.vtoFlame1AnimationId, flamePos1)
        rendering.set_target(santaGroup.vtoFlame2AnimationId, flamePos2)
    end
end

Santa.ReplaceVTOFlames = function()
    local santaGroup = global.SantaGroup
    santaGroup.vtoFlame1AnimationId = rendering.draw_animation {animation = "santa_biter_vto_flame", render_layer = "air-object", target = santaGroup.vtoFlame1Entity.position, surface = santaGroup.surface}
    santaGroup.vtoFlame2AnimationId = rendering.draw_animation {animation = "santa_biter_vto_flame", render_layer = "air-object", target = santaGroup.vtoFlame2Entity.position, surface = santaGroup.surface}
    Santa.DestroyVTOFlames()
end

Santa.DestroyVTOFlames = function()
    local santaGroup = global.SantaGroup
    if santaGroup.vtoFlame1Entity ~= nil then
        santaGroup.vtoFlame1Entity.destroy()
        santaGroup.vtoFlame1Entity = nil
        santaGroup.vtoFlame2Entity.destroy()
        santaGroup.vtoFlame2Entity = nil
    end
end

Santa.DestroyVTOFlameAnimations = function()
    local santaGroup = global.SantaGroup
    if santaGroup.vtoFlame1AnimationId ~= nil then
        rendering.destroy(santaGroup.vtoFlame1AnimationId)
        santaGroup.vtoFlame1AnimationId = nil
        rendering.destroy(santaGroup.vtoFlame2AnimationId)
        santaGroup.vtoFlame2AnimationId = nil
    end
end

Santa.GeneratePhaseInOutSmokeTickIteration = function(santaGroupPosition)
    local santaGroup = global.SantaGroup
    if santaGroup.phaseInSmokeIteration <= 60 then
        if santaGroup.phaseInSmokeIteration % 6 == 0 then
            santaGroup.nextStateTick = game.tick + 180
            local smokePos = {
                x = santaGroupPosition.x,
                y = santaGroupPosition.y - santaGroup.flyingHeightTiles
            }
            Santa.CreatePhaseInOutSmoke(smokePos)
        end
        santaGroup.phaseInSmokeIteration = santaGroup.phaseInSmokeIteration + 1
    end
end

Santa.CreatePhaseInOutSmoke = function(santaEntityPosition)
    local santaGroup = global.SantaGroup
    santaGroup.surface.create_trivial_smoke {name = "santa_biter_transition_smoke_massive", position = {x = santaEntityPosition.x, y = santaEntityPosition.y}}
end

Santa.SetLandingPosition = function(commandDetails)
    local args = Commands.GetArgumentsFromCommand(commandDetails.parameter)
    if #args == 0 then
        global.santa.landingPos = nil
    elseif #args == 2 then
        local x, y = tonumber(args[1]), tonumber(args[2])
        if x == nil then
            game.print({"message.biter_santa-set_santa_landing_position_arg_not_number", "1st (x)", args[1]})
            return
        end
        if y == nil then
            game.print({"message.biter_santa-set_santa_landing_position_arg_not_number", "second (y)", args[2]})
            return
        end
        global.santa.landingPos = {x = x, y = y}
    else
        game.print({"message.biter_santa-set_santa_landing_position_wrong_arg_count", #args})
    end
end

Santa.OffsetLandingPosition = function(commandDetails)
    local args = Commands.GetArgumentsFromCommand(commandDetails.parameter)
    if #args == 2 then
        local x, y = tonumber(args[1]), tonumber(args[2])
        if x == nil then
            game.print({"message.biter_santa-offset_santa_landing_position_arg_not_number", "1st (x)", args[1]})
            return
        end
        if y == nil then
            game.print({"message.biter_santa-offset_santa_landing_position_arg_not_number", "second (y)", args[2]})
            return
        end
        local currentPos =
            global.santa.landingPos or
            {
                x = tonumber(settings.global["santa-landed-spot-x"].value),
                y = tonumber(settings.global["santa-landed-spot-y"].value)
            }
        global.santa.landingPos = Utils.ApplyOffsetToPosition(currentPos, {x = x, y = y})
    else
        game.print({"message.biter_santa-offset_santa_landing_position_wrong_arg_count", #args})
    end
end

Santa.ReintroduceSantaCommand = function(commandDetails)
    local args = Commands.GetArgumentsFromCommand(commandDetails.parameter)
    if #args == 0 or #args == 1 then
        local delay = 0
        if #args == 1 then
            delay = tonumber(args[1])
            if delay == nil then
                game.print({"message.biter_santa-reintroduce_santa_arg_not_number", "1st (delay)", args[1]})
                return
            end
            delay = delay * 60
        end

        if global.SantaGroup == nil then
            -- No current santa
            Santa.ScheduleCallSanta(delay)
            return
        elseif global.SantaGroup.state == SantaStates.landed then
            -- Santa is ready to be dismissed
            Santa.TakeOff()
        elseif global.SantaGroup.state == SantaStates.pre_spawning or global.SantaGroup.state == SantaStates.spawning or global.SantaGroup.state == SantaStates.arriving or global.SantaGroup.state == SantaStates.landing_air or global.SantaGroup.state == SantaStates.landing_air_near_ground or global.SantaGroup.state == SantaStates.landing_ground then
            -- Santa is in the process of landing so abort this command.
            return
        end

        -- Record that after santa dissapears his return should be scheduled after a delay.
        if global.santaShouldReturnAfterDelay == nil or delay < global.santaShouldReturnAfterDelay then
            global.santaShouldReturnAfterDelay = delay
        end
    else
        game.print({"message.biter_santa-reintroduce_santa_wrong_arg_count", #args})
    end
end

Santa.ScheduleCallSanta = function(delay)
    local scheduledTick, scheduleSanta = game.tick + delay, false
    if global.nextScheduledSantaTick == nil then
        scheduleSanta = true
    elseif scheduledTick <= global.nextScheduledSantaTick then
        EventScheduler.RemoveScheduledEvents("Santa.CallSantaScheduledEvent", nil, global.nextScheduledSantaTick)
        scheduleSanta = true
    end
    if scheduleSanta then
        global.nextScheduledSantaTick = scheduledTick
        EventScheduler.ScheduleEvent(scheduledTick, "Santa.CallSantaScheduledEvent")
    end
    global.santaShouldReturnAfterDelay = nil
end

Santa.CallSantaScheduledEvent = function()
    if global.SantaGroup ~= nil then
        return
    end
    Santa.CreateSantaGroup()
end

Santa.SantaComming = function()
    global.nextScheduledSantaTick = nil
    global.santaShouldReturnAfterDelay = nil
end

Santa.SantaDisappeared = function()
    if global.santaShouldReturnAfterDelay == nil then
        return
    end
    Santa.ScheduleCallSanta(global.santaShouldReturnAfterDelay)
end

return Santa
