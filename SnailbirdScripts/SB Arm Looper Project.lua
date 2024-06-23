require "Scripts.SnailbirdScripts.include.util";
require "Scripts.SnailbirdScripts.include.track_util";
require "Scripts.SnailbirdScripts.include.proj_util";

local DEBUG_OUTPUT = true;
local LOOP_NAME = "~LOOP~";
local LOOP_START = "~LOOP START~";
local LOOP_END = "~LOOP END~";

function MuteUnmuteLooperSends(tracks, mute)
  if(#tracks > 0)
  then
    for index = 1, #tracks do
      local track = tracks[index];
      local hardSends = reaper.GetTrackNumSends(track, 1);
      for sendIndex = 0, hardSends - 1 do
        local _, sendName = reaper.GetTrackSendName(track, sendIndex);
        local _, sendMute = reaper.GetTrackSendUIMute(track, sendIndex);
        if sendMute ~= mute then
          reaper.ToggleTrackSendUIMute(track, sendIndex);
        end
      end
    end
  end
end

-- The Routine
reaper.defer(
function()
  -- Only bother if we're up and running
  if reaper.GetPlayState() ~= 1 then return; end
  
  session_proj = reaper.EnumProjects(-1); -- current project is client
  _, looper_proj = GetProjectByName("Looper");

  local looper_track_names = {"Looper TR-8S Kick Sub",
                              "Looper TD-3",
                              "Looper Neutron",
                              "Looper Minilogue",
                              "Looper Hydrasynth",
                              "Looper Pump Buss",
                              "Looper TR-8S Hands",
                              "Looper Acid Rain Quadraverb"};
                            
  local looper_tracks_found, looper_tracks = GetTracksByName(looper_proj, looper_track_names);

  if looper_tracks_found then

    local mixer_track_names = {"TR-8S Kick Sub Mixer",
                              "TD-3 Mixer",
                              "Neutron Mixer",
                              "Minilogue Mixer",
                              "Hydrasynth Mixer",
                              "Pump Buss Mixer",
                              "TR-8S Hands Mixer",
                              "Acid Rain Quadraverb Mixer"};
    
    local mixer_tracks_found, mixer_tracks = GetTracksByName(session_proj, mixer_track_names);
    if mixer_tracks_found then
    
      -- Arm the looper
      SelectAndArmTracks(looper_tracks);
      
      -- Clean any previous stuff
      if reaper.GetPlayStateEx(looper_proj) ~= 0 then
        reaper.CSurf_OnStop(); -- this only works because arming the tracks above puts this looper project in focus
      end
      
      -- Prepare the looper sends
      MuteUnmuteLooperSends(mixer_tracks, false);
      if DEBUG_OUTPUT then
        reaper.ShowConsoleMsg("Sends Activated\n");
      end
      
      -- Get the transport time and figure out where the next starting point should be
      local looper_playtime = reaper.GetPlayPosition2(looper_proj);
      local beats, looper_current_measure = reaper.TimeMap2_timeToBeats(looper_proj, looper_playtime);
      local session_playtime = reaper.GetPlayPosition2(session_proj);
      local _, session_current_measure = reaper.TimeMap2_timeToBeats(session_proj, session_playtime);
            
      -- !!! build in protections about engaging record if we are already looping in the buffer
      local timesig_beats, timesig_beat, timesig_tempo = reaper.TimeMap_GetTimeSigAtTime(session_proj, session_playtime);
      if beats >= timesig_beats - 2 then looper_current_measure =  looper_current_measure + 1 ; end -- make sure we have time to set up the record
      
      -- Translate the bar loop points to time, and set looped time selection with those time limits      
      local LOOP_LENGTH = 4;
      
      local looper_start_measure = math.ceil(looper_current_measure / LOOP_LENGTH) * LOOP_LENGTH;
      local looper_end_measure = looper_start_measure + LOOP_LENGTH;
      local start_time = reaper.TimeMap2_beatsToTime(looper_proj, 0, looper_start_measure);
      local end_time = reaper.TimeMap2_beatsToTime(looper_proj, 0, looper_end_measure);
      
      local session_start_measure = math.ceil(session_current_measure / LOOP_LENGTH) * LOOP_LENGTH;
      local session_start_time = reaper.TimeMap2_beatsToTime(session_proj, 0, session_start_measure)

      if DEBUG_OUTPUT then
        reaper.ShowConsoleMsg('Start Measre: ' .. tostring(looper_start_measure + 1) .. "\n" ..
                              'End Measure: ' .. tostring(looper_end_measure + 1) .. "\n");
      end
      
      -- Set up the tempo and transport of the looper to match the session
      reaper.SetTempoTimeSigMarker(looper_proj, 1, start_time, 1, 1, timesig_tempo, timesig_beats, timesig_beat, true);
      reaper.SetEditCurPos2(looper_proj, start_time, true, true);
      
      -- Set up the loop time selection
      reaper.GetSet_LoopTimeRange(1, true, start_time, end_time, false);
      reaper.GetSetRepeatEx(looper_proj, 1);
      reaper.UpdateArrange();
      
      local RECORDING_METHOD = "WAITTRIGGER";
      
      if RECORDING_METHOD == "MARKER" then
        -- -- set up the recording markers
        -- local loop_start_marker_id = reaper.AddProjectMarker(looper_proj, false, start_time, 0, LOOP_START, 98);
        -- local loop_end_marker_id = reaper.AddProjectMarker(looper_proj, false, end_time, 0, LOOP_END, 99);
        
        -- -- start record
        -- reaper.Main_OnCommand(40056, 0); -- Transport: Start/stop recording at next session_project marker
        -- if DEBUG_OUTPUT then
        --   reaper.ShowConsoleMsg("Recording armed\n");
        -- end
        -- reaper.UpdateArrange();
        
        -- Wait(
        --   function()
        --     return reaper.GetPlayPosition() > start_time; 
        --   end,
        --   function()
        --     -- stop record
        --     if DEBUG_OUTPUT then
        --       reaper.ShowConsoleMsg(tostring(reaper.GetPlayState()) .. "\n");
        --     end
        --     reaper.Main_OnCommand(40056, 0); -- Transport: Start/stop recording at next session_project marker
            
        --     -- Wait for recording to stop to delete markers
        --     Wait(
        --         function()
        --           if DEBUG_OUTPUT then
        --             reaper.ShowConsoleMsg("Checking record state...\n");
        --           end
        --           return reaper.GetPlayState() & 4 == 0;
        --         end,
        --         function()
        --           if DEBUG_OUTPUT then
        --             reaper.ShowConsoleMsg("Cleanup...\n");
        --           end
                  
        --           -- cleanup markers
        --           reaper.DeleteProjectMarker(looper_proj, loop_start_marker_id, false);
        --           reaper.DeleteProjectMarker(looper_proj, loop_end_marker_id, false);

        --           -- Mute Sends to the looper so passthrough audio is overridden by the recorded audio
        --           MuteUnmuteLooperSends(mixer_tracks, true);
        --           reaper.UpdateArrange();
        --         end);
        --   end);
        elseif RECORDING_METHOD == "WAITTRIGGER" then
          local block_offset = 0;
          Wait(
            function()
              return reaper.GetPlayPositionEx(session_proj) >= session_start_time - block_offset;
            end,
            function()
              reaper.CSurf_OnRecord();
            end
          );

      end
      -- end main section
    else
        reaper.ShowConsoleMsg("Mixer Tracks not found\n");
    end
  else
    reaper.ShowConsoleMsg("Looper Tracks not found\n");
  end
end);
