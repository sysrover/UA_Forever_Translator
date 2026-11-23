local _, ns = ...
local Q = {}; ns.IncomingQueue = Q

function Q.new(options)
    local capacity, budget = 64, 4
    local schedulingReserve = 0.25
    local pending, first, count = {}, 1, 0
    local active, scheduled, deadline
    local stats = {queued=0, completed=0, unchanged=0, failed=0, cancelled=0, evicted=0, peak=0}
    local queue = {}

    local function checkpoint()
        if options.clock() >= deadline then coroutine.yield() end
    end

    local function removeFirst()
        local job = pending[first]
        pending[first], active = nil, nil
        first, count = first % capacity + 1, count - 1
        return job
    end

    local function present(job, result, originalOnly)
        local ok, outcome = pcall(options.present, job, result, originalOnly, true)
        if not ok then
            stats.failed = stats.failed + 1
            options.reportError(outcome)
        elseif not originalOnly then
            stats[outcome] = stats[outcome] + 1
        end
    end

    local schedule
    local function drain()
        -- Allow for the work between checkpoints and returning to the client.
        scheduled, deadline = nil, options.clock() + budget - schedulingReserve
        while count > 0 and options.clock() < deadline do
            local job = pending[first]
            local model = options.model()
            if not options.eligible(job) then
                removeFirst()
                stats.cancelled = stats.cancelled + 1
            else
                if not active or job.model ~= model then
                    job.model = model
                    active = coroutine.create(function()
                        return options.translate(job, checkpoint, model)
                    end)
                end
                local startedAt = job.translationMs and options.now()
                local ok, result = coroutine.resume(active)
                local sliceMs = options.duration(startedAt)
                if sliceMs then
                    job.translationMs = job.translationMs + sliceMs
                    job.maxSliceMs = math.max(job.maxSliceMs, sliceMs)
                else
                    job.translationMs, job.maxSliceMs = nil, nil
                end
                if ok and coroutine.status(active) ~= "dead" then break end
                removeFirst()
                if ok then present(job, result)
                else
                    stats.failed = stats.failed + 1
                    options.reportError(result)
                end
            end
        end
        if count > 0 then schedule() end
    end

    schedule = function()
        if scheduled then return end
        scheduled = true
        options.schedule(drain)
    end

    function queue.push(job)
        local overflow
        if count == capacity then
            overflow = removeFirst()
            stats.evicted = stats.evicted + 1
        end
        pending[(first + count - 1) % capacity + 1] = job
        count = count + 1
        stats.queued, stats.peak = stats.queued + 1, math.max(stats.peak, count)
        schedule()
        if overflow then present(overflow, nil, true) end
    end

    function queue.cancel()
        if count == 0 then return end
        stats.cancelled = stats.cancelled + count
        pending, first, count, active = {}, 1, 0, nil
    end

    function queue.hasPending()
        return count > 0
    end

    function queue.counters()
        local snapshot = {pending=count, budgetMs=budget}
        for name, value in pairs(stats) do snapshot[name] = value end
        return snapshot
    end

    return queue
end
