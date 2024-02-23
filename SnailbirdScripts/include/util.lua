function string.starts(String,Start)
    return string.sub(String,1,string.len(Start))==Start
end

function Wait(predicate, callback)
    if predicate() then
        callback();
    else
        reaper.defer(function() Wait(predicate, callback) end);
    end
end