% plot percentage of worms in cluster, with the option to restrict movies
% to the initial stationary phase

clear
close all

exportOptions = struct('Format','eps2',...
    'Color','rgb',...
    'Width',10,...
    'Resolution',300,...
    'FontMode','fixed',...
    'FontSize',12,...
    'LineWidth',1);

%% set parameters
dataset = 1; % specify which dataset to run the script for. Enter either 1 or 2
if dataset ==1
    strains = {'npr1'};
elseif dataset ==2
    strains = {'npr1'};
end
wormnums = {'40'};%{'40','HD'};
if dataset == 1
    intensityThresholds = containers.Map({'40','HD','1W'},{50, 40, 100});
elseif dataset ==2
    intensityThresholds = containers.Map({'40','HD','1W'},{60, 40, 100});
end
maxBlobSize = 1e4;
minNeighbrDist = 2000;
inClusterNeighbourNum = 3;
pixelsize = 100/19.5; % 100 microns are 19.5 pixels
startFrame = 1;
endFrame = 0; % specify 1 for the end of the whole movie, or 0 for the end of the initial stationary phase
binSeconds = 30; % create bins measured in seconds - only applied to full movie analysis

%% go through strains, densities, movies
for strainCtr = 1:length(strains)
    strain = strains{strainCtr};
    for numCtr = 1:length(wormnums)
        wormnum = wormnums{numCtr};
        % load data
        if dataset == 1
            [phaseEndFrame,filenames,~] = xlsread(['datalists/' strains{strainCtr} '_' wormnum '_list.xlsx'],1,'A1:B15','basic');
        elseif dataset == 2
            [phaseEndFrame,filenames,~] = xlsread(['datalists/' strains{strainCtr} '_' wormnum '_g_list.xlsx'],1,'A1:B15','basic');
        end
        numFiles = length(filenames);
        inClusterProportionFig = figure; hold on
        loneWormProportionFig = figure; hold on
        for fileCtr = 1:numFiles
            filename = filenames{fileCtr};
            trajData = h5read(filename,'/trajectories_data');
            blobFeats = h5read(filename,'/blob_features');
            frameRate = double(h5readatt(filename,'/plate_worms','expected_fps'));
            if endFrame ==1
                lastFrame = double(max(trajData.frame_number));
            elseif endFrame ==0
                lastFrame = phaseEndFrame(fileCtr);
            end
            % filter by blob size and intensity
            trajData.filtered = filterIntensityAndSize(blobFeats,pixelsize,...
                intensityThresholds(wormnum),maxBlobSize);
            % filter by in-cluster/lone status
            min_neighbr_dist = h5read(filename,'/min_neighbr_dist');
            num_close_neighbrs = h5read(filename,'/num_close_neighbrs');
            neighbr_dist = h5read(filename,'/neighbr_distances');
            inClusterLogInd = num_close_neighbrs>=inClusterNeighbourNum;
            inClusterLogInd(~trajData.filtered)=false;
            loneWormLogInd = min_neighbr_dist>=minNeighbrDist;
            loneWormLogInd(~trajData.filtered)=false;
            % count in-cluster/lone worms in bins across the movie
            totalObjInFrame = trajData.frame_number(trajData.filtered);
            inClusterInFrame = trajData.frame_number(inClusterLogInd);
            loneWormInFrame = trajData.frame_number(loneWormLogInd);
            binEdges = linspace(1,lastFrame,lastFrame/frameRate/binSeconds);
            if endFrame ==0  % restrict movies to stationary phase
                totalObjInFrame = totalObjInFrame(totalObjInFrame<lastFrame);
                inClusterInFrame = inClusterInFrame(inClusterInFrame<lastFrame);
                loneWormInFrame = loneWormInFrame(loneWormInFrame<lastFrame);
                binEdges = linspace(1,lastFrame,120); % create 120 bins over the stationary phase
            end
            [totalObjPerSecond,~]=histcounts(totalObjInFrame,binEdges);
            [inClusterPerSecond,~]=histcounts(inClusterInFrame,binEdges);
            [loneWormPerSecond,~]=histcounts(loneWormInFrame,binEdges);
            % plot in-cluster/lone worms as percentage of total worms
            % across the movie
            percentInCluster = inClusterPerSecond./totalObjPerSecond*100;
            percentLoneWorm = loneWormPerSecond./totalObjPerSecond*100;
            set(0,'CurrentFigure',inClusterProportionFig)
            plot(percentInCluster)
            set(0,'CurrentFigure',loneWormProportionFig)
            plot(percentLoneWorm)
        end
        % format plot and export
        %
        set(0,'CurrentFigure',inClusterProportionFig)
        title([strains{strainCtr} '\_' wormnums{numCtr} '\_inCluster'],'FontWeight','normal')
        xlabel('time')
        if endFrame == 1
            xlim([0 (3600/binSeconds)]) % set x axis for 1 hour
        end
        ylabel('percentage')
        ylim([0 100])
        set(inClusterProportionFig,'PaperUnits','centimeters')
        if endFrame ==1
            figurename = ['figures/inClusterProportion/inClusterProportion_' strains{strainCtr} '_' wormnums{numCtr} '_fullMovie_data' num2str(dataset)];
        elseif endFrame ==0
            figurename = ['figures/inClusterProportion/inClusterProportion_' strains{strainCtr} '_' wormnums{numCtr} '_stationary_data' num2str(dataset)];
        end
        exportfig(inClusterProportionFig,[figurename '.eps'],exportOptions)
        system(['epstopdf ' figurename '.eps']);
        system(['rm ' figurename '.eps']);
        %
        set(0,'CurrentFigure',loneWormProportionFig)
        title([strains{strainCtr} '\_' wormnums{numCtr} '\_loneWorms'],'FontWeight','normal')
        xlabel('time')
        if endFrame == 1
            xlim([0 (3600/binSeconds)]) % set x axis for 1 hour
        end
        ylabel('percentage')
        ylim([0 50])
        set(loneWormProportionFig,'PaperUnits','centimeters')
        if endFrame ==1
            figurename = ['figures/inClusterProportion/loneWormsProportion_' strains{strainCtr} '_' wormnums{numCtr} '_fullMovie_data' num2str(dataset)];
        elseif endFrame ==0
            figurename = ['figures/inClusterProportion/loneWormsProportion_' strains{strainCtr} '_' wormnums{numCtr} '_stationary_data' num2str(dataset)];
        end
        exportfig(loneWormProportionFig,[figurename '.eps'],exportOptions)
        system(['epstopdf ' figurename '.eps']);
        system(['rm ' figurename '.eps']);
    end
end