function [omegaFrames, upsilonFrames] = omegaUpsilonDetectCurvature(angleArray, stageFlag)
% OMEGAUPSILONDETECTDV This function determines which frames of the input
% angle array contain part of an omega turn.  Omega turns have three
% characteristics: they start with high curvature in the first third of the
% worm, they continue with high curvature at the midbody, and end with high
% curvature at the tail.
% Upsilon bends are similar to omega bends but have less pronounced
% curvature at each stage of the turn.
%
% Input:
%   angleChange   - matrix of skeleton tangent angle changes
%   stageFlag     - logical array indicating stage movement
%
% Output:
%   omegaFrames   - frames that contain part of an omega turn are indicated
%                   by +/- 1, other frames are 0. If the worm side is
%                   included, the sign indicates whether the bend is ventral
%                   (+1) or dorsal (-1)
%   upsilonFrames - frames that contain part of an upsilon turn are
%                   indicated by +/- 1, other frames are 0. If the worm
%                   side is included, the sign indicates whether the bend
%                   is ventral (+1) or dorsal (-1)

[numSegments, numFrames] = size(angleArray);

% initialize output arrays
omegaFrames = zeros(numFrames, 1);
upsilonFrames = zeros(numFrames, 1);

% divide angle array into three parts and take the mean of each
headAngle = nanmean(angleArray(1:round(numSegments * (1/3)), :));
bodyAngle = nanmean(angleArray(round(numSegments * (1/3) ) + 1:...
    round(numSegments * (2/3)), :));
tailAngle = nanmean(angleArray(round(numSegments * (2/3) + 1:end), :));

%only proceed if there are at least two non-NaN value in each angle vector
if sum(~isnan(headAngle)) > 1 && sum(~isnan(bodyAngle)) > 1 && sum(~isnan(tailAngle)) > 1
    
    % interpolate arrays over NaN values (where there were stage
    % movements, touching, or some other segmentation problem)
    % ***This is of course only an approximate solution to the problem of
    % not segmenting coiled shapes***
    headAngle(isnan(headAngle)) = interp1(find(~isnan(headAngle)),...
        headAngle(~isnan(headAngle)), find(isnan(headAngle)),'linear', 'extrap');
    tailAngle(isnan(tailAngle)) = interp1(find(~isnan(tailAngle)),...
        tailAngle(~isnan(tailAngle)), find(isnan(tailAngle)),'linear', 'extrap');
    
    %********************** Find Positive Omegas **************************
    
    %find frames that satisfy conditions for omega bend start
    startCond = headAngle > 30 & abs(tailAngle) < 30;
    startInds = find(diff(startCond) == 1) + 1; %add 1 for shift due to diff
    
    %find frames that satisfy conditions for middle of omega bend (these
    %could be coils of stage motions, so include check for NaNs
    midCond = bodyAngle > 30 | isnan(bodyAngle);
    midStarts = find(diff(midCond) == 1) + 1; %add 1 for shift due to diff
    midEnds = find(diff(midCond) == -1);
    
    %find frames that satisfy conditions for omega bend end
    endCond = abs(headAngle) < 30 & tailAngle > 30;
    endInds = find(diff(endCond) == -1);
    
    for j = 1:length(midStarts)
        % find the next end index that is greater than the current startInd
        possibleEnd = find(midEnds > midStarts(j), 1);
        
        % stage motions are allowed during turns, but there must be at
        % least one valid non-motion frame.
        if all(stageFlag(midStarts(j):midEnds(possibleEnd)))
            continue;
        end
                
        % check that frames before and after the possible omega turn are
        % valid start and end frames respectively
        if ~isempty(possibleEnd)
            if startCond(midStarts(j) - 1) && endCond(midEnds(possibleEnd) + 1)
                % we have a positive omega turn.  Now find actual start and end
                % points.
                currentStart = find(startInds < midStarts(j), 1, 'last');
                currentEnd = find(endInds > midEnds(possibleEnd), 1);
                
                omegaFrames(startInds(currentStart):endInds(currentEnd)) = 1;
            end
        end
    end
    
    %********************** Find Negative Omegas **************************
    
    %find frames that satisfy conditions for omega bend start
    startCond = headAngle < -30 & abs(tailAngle) < 30;
    startInds = find(diff(startCond) == 1) + 1; %add 1 for shift due to diff
    
    %find frames that satisfy conditions for middle of omega bend
    midCond = bodyAngle < -30 | isnan(bodyAngle);
    midStarts = find(diff(midCond) == 1) + 1; %add 1 for shift due to diff
    midEnds = find(diff(midCond) == -1);
    
    %find frames that satisfy conditions for omega bend end
    endCond = abs(headAngle) < 30 & tailAngle < -30;
    endInds = find(diff(endCond) == -1);
    
    for j = 1:length(midStarts)
        % find the next end index that is greater than the current startInd
        possibleEnd = find(midEnds > midStarts(j), 1);
        
        % stage motions are allowed during turns, but there must be at
        % least one valid non-motion frame.
        if all(stageFlag(midStarts(j):midEnds(possibleEnd)))
            continue;
        end
                
        % check that frames before and after the possible omega turn are
        % valid start and end frames respectively
        if ~isempty(possibleEnd)
            if startCond(midStarts(j) - 1) && endCond(midEnds(possibleEnd) + 1)
                % we have a positive omega turn.  Now find actual start and end
                % points.
                currentStart = find(startInds < midStarts(j), 1, 'last');
                currentEnd = find(endInds > midEnds(possibleEnd), 1);
                
                omegaFrames(startInds(currentStart):endInds(currentEnd)) = -1;
            end
        end
    end
    
    %********************** Find Positive Upsilons ************************
    
    %find frames that satisfy conditions for upsilon bend start
    startCond = headAngle > 15 & abs(tailAngle) < 30;
    startInds = find(diff(startCond) == 1) + 1; %add 1 for shift due to diff
    
    %find frames that satisfy conditions for middle of upsilon bend
    midCond = bodyAngle > 15 | isnan(bodyAngle);
    midStarts = find(diff(midCond) == 1) + 1; %add 1 for shift due to diff
    midEnds = find(diff(midCond) == -1);
    
    %find frames that satisfy conditions for upsilon bend end
    endCond = abs(headAngle) < 30 & tailAngle > 15;
    endInds = find(diff(endCond) == -1);
    
    for j = 1:length(midStarts)
        % find the next end index that is greater than the current startInd
        possibleEnd = find(midEnds > midStarts(j), 1);
        
        % stage motions are allowed during turns, but there must be at
        % least one valid non-motion frame.
        if all(stageFlag(midStarts(j):midEnds(possibleEnd)))
            continue;
        end
                
        % check that frames before and after the possible upsilon turn are
        % valid start and end frames respectively
        if ~isempty(possibleEnd)
            if startCond(midStarts(j) - 1) && endCond(midEnds(possibleEnd) + 1)
                % we have a positive upsilon turn.  Now find actual start and end
                % points.
                currentStart = find(startInds < midStarts(j), 1, 'last');
                currentEnd = find(endInds > midEnds(possibleEnd), 1);
                
                % Here we will check if an upsilon bend has an omega bend
                % inside. If yes we will not count it and will go to the
                % next iteration.
                if ~any(abs(omegaFrames( ...
                        startInds(currentStart):endInds(currentEnd) )))
                    upsilonFrames( ...
                         startInds(currentStart):endInds(currentEnd) ) = 1;
                end
            end
        end
    end
    
    %********************** Find Negative Upsilons ************************
    
    %find frames that satisfy conditions for upsilon bend start
    startCond = headAngle < -15 & abs(tailAngle) < 30;
    startInds = find(diff(startCond) == 1) + 1; %add 1 for shift due to diff
    
    %find frames that satisfy conditions for middle of upsilon bend
    midCond = bodyAngle < -15 | isnan(bodyAngle);
    midStarts = find(diff(midCond) == 1) + 1; %add 1 for shift due to diff
    midEnds = find(diff(midCond) == -1);
    
    %find frames that satisfy conditions for upsilon bend end
    endCond = abs(headAngle) < 30 & tailAngle < -15;
    endInds = find(diff(endCond) == -1);
    
    for j = 1:length(midStarts)
        % find the next end index that is greater than the current startInd
        possibleEnd = find(midEnds > midStarts(j), 1);
        
        % stage motions are allowed during turns, but there must be at
        % least one valid non-motion frame.
        if all(stageFlag(midStarts(j):midEnds(possibleEnd)))
            continue;
        end
        
        % check that frames before and after the possible upsilon turn are
        % valid start and end frames respectively
        if ~isempty(possibleEnd)
            if startCond(midStarts(j) - 1) && endCond(midEnds(possibleEnd) + 1)
                % we have a positive upsilon turn.  Now find actual start and end
                % points.
                currentStart = find(startInds < midStarts(j), 1, 'last');
                currentEnd = find(endInds > midEnds(possibleEnd), 1);
                
                % Here we will check if an upsilon bend has an omega bend
                % inside. If yes we will not count it and will go to the
                % next iteration.
                if ~any(abs(omegaFrames( ...
                        startInds(currentStart):endInds(currentEnd) )))
                    upsilonFrames( ...
                        startInds(currentStart):endInds(currentEnd) ) = -1;
                end
            end
        end
    end
end


