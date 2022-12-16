function table:deepCopy()
       if type(self) ~= 'table' then return self end
       local res = setmetatable({}, getmetatable(self))
       for k, v in pairs(self) do res[table.deepCopy(k)] = table.deepCopy(v) end
       return res
end

local function matchCriteria(fn, criteria)
    local isArray = false
    local arrayMatch = false
    for k, v in pairs(criteria) do
        if math.type(k) ~= nil then
            isArray = true
            if fn.id == v then
                arrayMatch = true
                break
            end
        else
            if k == 'id' then
                if fn.id ~= v then return false end
            end
            if k == 'type' then
                if fn.type:match('^' .. v .. '$') == nil then return false end
            end
            if fn.meta[k] == nil then return false end
            if fn.meta[k]:match('^' .. v .. '$') == nil then return false end
        end
    end
    if isArray then return arrayMatch end
    return true
end

function findFunction(criteria)
    if math.type(criteria) ~= nil then
        for _, fn in ipairs(functions) do
            if fn.id == criteria then return fn end
        end
    elseif type(criteria) == 'table' then
        for _, fn in ipairs(functions) do
            if matchCriteria(fn, criteria) then return fn end
        end
    end
    return nil
end


function findFunctions(criteria)
    local res = {}
    if type(criteria) == 'table' then
        for _, fn in ipairs(functions) do
            if matchCriteria(fn, criteria) then table.insert(res, fn) end
        end
    end
    return res
end

local calibratedFunction

function onMessage(topic, payload, retained)
	local data = json:decode(payload)
	local newMessage = {value: data.value + cfg.calibration}
	mq:pub(topic .. '/calibrated', json:encode(newMessage))
end

function onCreate()
	local newFn = table.deepCopy(findFunction(cfg.baseFunction))
	newFn.meta.name = 'Calibrated ' .. newFn.meta.name
	newFn.meta.derived_from = tostring(newFn.id)
	newFn.meta["app.id"] = tostring(app.id)
	newFn.meta.topic_read = newFn.meta.topic_read .. '/calibrated'
	lynx.createFunction(newFn)
end

function onFunctionsUpdated()
	local newCalibratedFunction = findFunction({
	    ["app.id"] = tostring(app.id)
	})
	if newCalibratedFunction.meta.topic_read ~= calibratedFunction.meta.topic_read then
    	mq:unsub(calibratedFunction.meta.topic_read)
    	mq:unbind(calibratedFunction.meta.topic_read, onMessage)

	    mq:sub(newCalibratedFunction.meta.topic_read)
    	mq:bind(newCalibratedFunction.meta.topic_read, onMessage)
    end
    calibratedFunction = newCalibratedFunction
end

function onDestroy()
	lynx.deleteFunction(calibratedFunction.id)
end

function onStart()
	calibratedFunction = findFunction({
	    ["app.id"] = tostring(app.id)
	})
	mq:sub(calibratedFunction.meta.topic_read)
	mq:bind(calibratedFunction.meta.topic_read, onMessage)
end