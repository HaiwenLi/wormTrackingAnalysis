function [revStartInd, revDuration, untrackedRevEnds, interRevTime, incompleteInterRev] =...
    findReversals(midbody_speed, worm_index)
% finds reversals based on worm tracking data features file

% define reversal starting events as when sign of speed changes from + to -
revStartInd = find(midbody_speed(1:end-1)>0&midbody_speed(2:end)<0);
% reversals end when sign of speed changes from - to + (but there could
% be more or fewer of these than reversal start times)
revEndInd = 1+find(midbody_speed(1:end-1)<0&midbody_speed(2:end)>0);
% match up reversal end times with starts
revEndIndMatched = NaN(size(revStartInd));
untrackedRevEnds = false(size(revStartInd));
nRevs = length(revStartInd);
for revCtr = 1:nRevs
    if revStartInd(revCtr)<max(revEndInd)
        revEndIndMatched(revCtr) = revEndInd(find(revEndInd>revStartInd(revCtr),1,'first'));
        if worm_index(revStartInd(revCtr)) ~= worm_index(revEndIndMatched(revCtr))
            % reversal 'end' is actually from a different worm, which means
            % that the reversal end is not tracked (at least not under the
            % same identity)
            [revStartInd(revCtr), revEndIndMatched(revCtr)] = findLastTracked(revStartInd(revCtr),...
                revEndIndMatched(revCtr),worm_index,midbody_speed);
            untrackedRevEnds(revCtr) = true;
        end
        % it can happen that the end of the reversal is not tracked, and
        % that another reversal has started before the matched end
        if revCtr<nRevs&&revEndIndMatched(revCtr)>revStartInd(revCtr+1)&&~isnan(revStartInd(revCtr))
            [revStartInd(revCtr), revEndIndMatched(revCtr)] = findLastTracked(revStartInd(revCtr),...
                revEndIndMatched(revCtr),worm_index,midbody_speed);
            untrackedRevEnds(revCtr) = true;
        end
    else % reversal still ongoing when tracking ends
        [revStartInd(revCtr), revEndIndMatched(revCtr)] = findLastTracked(revStartInd(revCtr),...
            numel(midbody_speed),worm_index,midbody_speed);
        untrackedRevEnds(revCtr) = true;
    end
end
% cut-out any reversals that had been misidentified as such
keepLogInd = ~isnan(revStartInd);
revEndIndMatched = revEndIndMatched(keepLogInd);
revStartInd = revStartInd(keepLogInd);
untrackedRevEnds = untrackedRevEnds(keepLogInd);
% calculate duration and interrevtime
revDuration = revEndIndMatched - revStartInd;
interRevTime = [diff(revStartInd); ...
    find(worm_index==worm_index(revStartInd(end)),1,'last') - revStartInd(end)]; % the last reversal has a censored interrev time until the end of tracking
incompleteInterRev = false(size(interRevTime));
incompleteInterRev(end) = true;
% censor those inter-reversal times where the worm_index changes
wormChangeInd = find(worm_index(revStartInd)~=worm_index(revStartInd+interRevTime));
for wcCtr = wormChangeInd'
    interRevTime(wcCtr) = find(worm_index==worm_index(revStartInd(wcCtr)),1,'last') - revStartInd(wcCtr);
end
incompleteInterRev(wormChangeInd) = true;
end

function [firstTracked, lastTracked] = findLastTracked(currentStartInd,wrongEndInd,worm_index,midbody_speed)
firstTwoEntriesWithPositiveSpeed = find(worm_index(currentStartInd:wrongEndInd)==worm_index(currentStartInd)...
    &midbody_speed(currentStartInd:wrongEndInd)>0,2,'first'); % check in case we have multiple zero crossings with missing data
if numel(firstTwoEntriesWithPositiveSpeed)>1
    wrongEndInd = currentStartInd - 1 + firstTwoEntriesWithPositiveSpeed(end);
end
lastTracked = currentStartInd - 1 + find(worm_index(currentStartInd:wrongEndInd)==worm_index(currentStartInd)...
    &midbody_speed(currentStartInd:wrongEndInd)<0,1,'last');
if isempty(lastTracked) % in case we now think it's no reversal at all
    lastTracked = wrongEndInd;
    firstTracked = NaN;
else
    firstTracked = currentStartInd;
end
if lastTracked>=wrongEndInd&&~isnan(firstTracked) % check that the last time the reversal was tracked is before the end of the next reversal
    warning('lastTracked was after a change in worm index')
    lastTracked = wrongEndInd;
end
end