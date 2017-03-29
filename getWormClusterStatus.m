function [ numCloseNeighbours, mindist] = getWormClusterStatus(trajData, frame,...
    pixelsize, inClusterRadius)
% for a given frame, computes which worms are in/out of cluster based on
% positions
% returns logical vectors to index worms in/out of cluster

[x, y] = getWormPositions(trajData, frame);

if numel(x)>1 % need at least two worms in frame to calculate distances
    D = squareform(pdist([x y]).*pixelsize); % distance of every worm to every other
    % find lone worms
    mindist = min(D + max(max(D))*eye(size(D)));
    % find worms in clusters
    numCloseNeighbours = sum(D<inClusterRadius,2);
else
    numCloseNeighbours = zeros(size(x'));
    mindist = NaN(size(x'));
end
end

