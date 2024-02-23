require "include.track_util";

local DEBUG_OUTPUT = false;
local LOOP_NAME = "~LOOP~";
local LOOP_START = "~LOOP START~";
local LOOP_END = "~LOOP END~";

function MuteUnmuteLooperSends(tracks, mute)
  if(#tracks > 0)
  then
    for index = 1, #tracks do
      local track = tracks[index];
      local hardSends = reaper.GetTrackNumSends(track, 1);
      for sendIndex = hardSends, reaper.GetTrackNumSends(track, 0) + hardSends - 1 do
        local _, sendName = reaper.GetTrackSendName(track, sendIndex);
        local _, sendMute = reaper.GetTrackSendUIMute(track, sendIndex);
        if string.starts(string.lower(sendName), "looper") and sendMute ~= mute then
          reaper.ToggleTrackSendUIMute(track, sendIndex);
        end
      end
    end
  end
end

function Wait(predicate, callback)
  if predicate() then
    callback();
  else
    reaper.defer(function() Wait(predicate, callback) end);
  end
end

-- The Routine
reaper.defer(
function()
  --reaper.ShowConsoleMsg(tostring(reaper.GetPlayState()));

  -- only bother if we're up and running
  if reaper.GetPlayState() ~= 1 then return; end

  local looper_track_names = {"Looper TR-8S Kick Sub", 
                              "Looper TD-3", 
                              "Looper Neutron", 
                              "Looper Minilogue", 
                              "Looper Hydrasynth", 
                              "Looper Pump Buss", 
                              "Looper TR-8S Hands", 
                              "Looper Acid Rain Quadraverb"};
                            
  local looper_tracks_found, looper_tracks = GetTracksByName(looper_track_names);

  if looper_tracks_found then

    local mixer_track_names = {"TR-8S Kick Sub Mixer",
                              "TD-3 Mixer",
                              "Neutron Mixer",
                              "Minilogue Mixer",
                              "Hydrasynth Mixer",
                              "Pump Buss Mixer",
                              "TR-8S Hands Mixer",
                              "Acid Rain Quadraverb Mixer"};
    
    local mixer_tracks_found, mixer_tracks = GetTracksByName(mixer_track_names);
    if mixer_tracks_found then
      MuteUnmuteLooperSends(mixer_tracks, false);
      if DEBUG_OUTPUT then
        reaper.ShowConsoleMsg("Sends Activated\n");
      end
    
      reaper.Main_OnCommand(40635, 0); -- Time selection: Remove (unselect) time selection
      
      SelectAndArmTracks(looper_tracks);
      
      -- get the transport time and figure out where the next starting point should be
      local playtime = reaper.GetPlayPosition();
      local proj = reaper.EnumProjects(0);
      local beats, current_measure = reaper.TimeMap2_timeToBeats(proj, playtime);
      
      
      -- !!! build in protections about engaging record if we are already looping in the buffer
      local timesig_beats, timesig_beat, timesig_tempo = reaper.TimeMap_GetTimeSigAtTime(proj, playtime);
      if beats >= timesig_beats - 2 then current_measure =  current_measure + 1 ; end -- make sure we have time to set up the record
      
      -- translate the bar loop points to time
      -- set looped time selection with those time limits
      
      
      local LOOP_LENGTH = 4;
      local start_measure = math.ceil(current_measure / LOOP_LENGTH) * LOOP_LENGTH;
      local end_measure = start_measure + LOOP_LENGTH;
      
      if DEBUG_OUTPUT then
        reaper.ShowConsoleMsg('Start Measre: ' .. tostring(start_measure + 1) .. "\n" ..
                              'End Measure: ' .. tostring(end_measure + 1) .. "\n");
      end
      
      -- Set up the loop time selection
      local start_time = reaper.TimeMap2_beatsToTime(proj, 0, start_measure);
      local end_time = reaper.TimeMap2_beatsToTime(proj, 0, end_measure); 
      reaper.GetSet_LoopTimeRange(1, true, start_time, end_time, false);
      reaper.GetSetRepeat(1);
      reaper.UpdateArrange();
      
      local RECORDING_METHOD = "MARKER";
      
      if RECORDING_METHOD == "BARWAIT" then
        -- Wait until the right before start of the loop
        for measure = current_measure, start_measure - 2 do
          reaper.Main_OnCommand(reaper.NamedCommandLookup('_SWS_BARWAIT'), 0);
        end
        
        -- Start the recording
        reaper.Main_OnCommand(40003, 0); -- Transport: Start/stop recording at next measure
        --reaper.Main_OnCommand(1013, 0); -- Transport: Record
        
        for measure = start_measure, end_measure - 1 do
          reaper.Main_OnCommand(reaper.NamedCommandLookup('_SWS_BARWAIT'), 0);
          reaper.Main_OnCommand(2009, 0); -- Action: Wait 0.5 seconds before next action
          if DEBUG_OUTPUT then reaper.ShowConsoleMsg(tostring(measure + 1) .. " "); end
        end
        
        -- Stop the recording and let it ride
        reaper.Main_OnCommand(reaper.NamedCommandLookup('_SWS_BARWAIT'), 0);
        reaper.Main_OnCommand(40003, 0); -- Transport: Start/stop recording at next measure

        -- Mute Sends to the looper so passthrough audio is overridden by the recorded audio
        MuteUnmuteLooperSends(mixer_tracks, true);
        reaper.UpdateArrange();
      elseif RECORDING_METHOD == "MARKER" then
        -- set up the recording markers
        local loop_start_marker_id = reaper.AddProjectMarker(proj, false, start_time, 0, LOOP_START, 98);
        local loop_end_marker_id = reaper.AddProjectMarker(proj, false, end_time, 0, LOOP_END, 99);
        
        -- start record
        reaper.Main_OnCommand(40056, 0); -- Transport: Start/stop recording at next project marker
        if DEBUG_OUTPUT then
          reaper.ShowConsoleMsg("Recording armed\n");
        end
        reaper.UpdateArrange();
        local counter = 0;
        
        Wait(
              function()
                if DEBUG_OUTPUT then
                  reaper.ShowConsoleMsg("Checking time... " .. tostring(counter) .. " " .. tostring(reaper.GetPlayPosition()) .. "\n");
                end
                return reaper.GetPlayPosition() > start_time;
              end,
              function()
                -- stop record
                if DEBUG_OUTPUT then
                  reaper.ShowConsoleMsg(tostring(reaper.GetPlayState()) .. "\n");
                end
                reaper.Main_OnCommand(40056, 0); -- Transport: Start/stop recording at next project marker
                
                -- Wait for recording to stop to delete markers
                Wait(
                      function()
                        if DEBUG_OUTPUT then
                          reaper.ShowConsoleMsg("Checking record state...\n");
                        end
                        return reaper.GetPlayState() & 4 == 0;
                      end,
                      function()
                        if DEBUG_OUTPUT then
                          reaper.ShowConsoleMsg("Cleanup...\n");
                        end
                        
                        -- cleanup markers
                        reaper.DeleteProjectMarker(proj, loop_start_marker_id, false);
                        reaper.DeleteProjectMarker(proj, loop_end_marker_id, false);

                        -- Mute Sends to the looper so passthrough audio is overridden by the recorded audio
                        MuteUnmuteLooperSends(mixer_tracks, true);
                        reaper.UpdateArrange();
                      end);
              end);
      end
    else
        reaper.ShowConsoleMsg("Mixer Tracks not found\n");
    end
  else
    reaper.ShowConsoleMsg("Looper Tracks not found\n");
  end
end);
