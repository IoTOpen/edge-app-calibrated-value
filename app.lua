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
local baseFunction

function onMessage(topic, payload, retained)
	local data = json:decode(payload)
	local newMessage = {value = data.value + cfg.calibration, timestamp = data.timestamp}
	mq:pub(calibratedFunction.meta.topic_read, json:encode(newMessage))
end

function onCreate()
	baseFunction = findFunction(cfg.baseFunction)
	local newFn = table.deepCopy(findFunction(cfg.baseFunction))
	newFn.meta.name = 'Calibrated ' .. newFn.meta.name
	newFn.meta.derived_from = tostring(newFn.id)
	newFn.meta["app.id"] = tostring(app.id)
	newFn.meta.topic_read = newFn.meta.topic_read .. '/calibrated'
	newFn.protected_meta = nil
	local resp, err = lynx.createFunction(newFn)
	if err ~= nil then
		log.d("%s", err.message)
	else
		log.d("Created new function: %s", resp.meta.name)
		calibratedFunction = resp
	end
end

function onFunctionsUpdated()
	log.d('Functions updated..')
	local newCalibratedFunction = findFunction({
	    ["app.id"] = tostring(app.id)
	})
	if newCalibratedFunction == nil then
	      log.d("Calibrated function not found; removed?")
	      return
	end
	local newBaseFunction = findFunction(cfg.baseFunction)
	if newBaseFunction == nil then
	      log.d("Base function not found; removed?")
	      return
	end
	if newBaseFunction.meta.topic_read ~= baseFunction.meta.topic_read then
	      log.d("Base function topic changed; adapting...")
	      mq:unsub(baseFunction.meta.topic_read)
	      mq:unbind(baseFunction.meta.topic_read, onMessage)
              mq:sub(newBaseFunction.meta.topic_read)
    	      mq:bind(newBaseFunction.meta.topic_read, onMessage)
        end
        calibratedFunction = newCalibratedFunction
	baseFunction = newBaseFunction
end

function onDestroy()
	lynx.deleteFunction(calibratedFunction.id)
end

function onStart()
	if calibratedFunction == nil then
		calibratedFunction = findFunction({
		    ["app.id"] = tostring(app.id)
		})
	end
	if calibratedFunction == nil then
		log.d("Calibrated function not found; removed?")
		return
	end
	if baseFunction == nil then
		baseFunction = findFunction(cfg.baseFunction)
		if baseFunction == nil then
			log.d("Base function not found; removed?")
			return
		end
	end
	if baseFunction ~= nil then
		mq:sub(baseFunction.meta.topic_read)
		mq:bind(baseFunction.meta.topic_read, onMessage)
	end
end
