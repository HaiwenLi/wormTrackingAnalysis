% plot cumulative smoothed head angle changes

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
phase = 'sweeping'; % 'fullMovie', 'joining', or 'sweeping'.
dataset = 2; % 1 or 2
marker = 'bodywall'; % 'pharynx' or 'bodywall'
strains = {'npr1'}; % {'npr1','N2'}
wormnums = {'40'};% {'40'};
postExitDuration = 5; % set the duration (in seconds) after a worm exits a cluster to be included in the analysis

if dataset == 1
    intensityThresholds_g = containers.Map({'40','HD','1W'},{50, 40, 100});
elseif dataset ==2
    intensityThresholds_g = containers.Map({'40','HD','1W'},{60, 40, 100});
end
intensityThresholds_r = containers.Map({'40','HD','1W'},{60, 40, 100});
maxBlobSize_g = 1e4;
maxBlobSize_r = 2.5e5;
minSkelLength_r = 850;
maxSkelLength_r = 1500;
minNeighbrDist = 2000;
inClusterNeighbourNum = 3;
pixelsize = 100/19.5; % 100 microns are 19.5 pixels

%% go through strains, densities, movies
for strainCtr = 1:length(strains)
    strain = strains{strainCtr};
    for numCtr = 1:length(wormnums)
        wormnum = wormnums{numCtr};
        % load file list
        if dataset ==1 & strcmp(marker,'pharynx')
            [phaseFrames,filenames,~] = xlsread(['datalists/' strains{strainCtr} '_' wormnum '_list_hamm.xlsx'],1,'A1:E15','basic');
        elseif dataset ==2 & strcmp(marker,'pharynx')
            [phaseFrames,filenames,~] = xlsread(['datalists/' strains{strainCtr} '_' wormnum '_g_list_hamm.xlsx'],1,'A1:E15','basic');
        elseif dataset ==2 & strcmp(marker,'bodywall')
            [phaseFrames,filenames,~] = xlsread(['datalists/' strains{strainCtr} '_' wormnum '_r_list_hamm.xlsx'],1,'A1:E15','basic');
        else
            warning('specified dataset/marker combination does not exist')
        end
        phaseFrames = phaseFrames-1; % correct for python indexing at 0
        numFiles = length(filenames);
        % create empty cell arrays to hold individual file values, so they can be pooled for a given strain/density combination
        sHeadAngleChangeRate_leaveCluster = cell(numFiles,1);
        sHeadAngleChangeRate_loneWorm = cell(numFiles,1);
        sHeadAngleChangeRateFig = figure;
        
        %% go through individual movies
        for fileCtr = 1:numFiles
            %% load data
            filename = filenames{fileCtr}
            trajData = h5read(filename,'/trajectories_data');
            blobFeats = h5read(filename,'/blob_features');
            skelData = h5read(filename,'/skeleton');
            frameRate = double(h5readatt(filename,'/plate_worms','expected_fps'));
            if strcmp(phase, 'fullMovie')
                firstFrame = 0;
                lastFrame = phaseFrames(fileCtr,4);
            elseif strcmp(phase,'joining')
                firstFrame = phaseFrames(fileCtr,1);
                lastFrame = phaseFrames(fileCtr,2);
            elseif strcmp(phase,'sweeping')
                firstFrame = phaseFrames(fileCtr,3);
                lastFrame = phaseFrames(fileCtr,4);
            end
            
            %% filter worms by various criteria
            if strcmp(marker, 'pharynx')
                % filter green by blob size and intensity
                trajData.filtered = filterIntensityAndSize(blobFeats,pixelsize,...
                intensityThresholds_g(wormnum),maxBlobSize_g);
            elseif strcmp(marker, 'bodywall')
                % filter red by blob size and intensity
                if contains(filename,'55')||contains(filename,'54')
                    intensityThreshold = 80;
                else
                    intensityThreshold = 40;
                end
                trajData.filtered = filterIntensityAndSize(blobFeats,pixelsize,...
                    intensityThreshold,maxBlobSize_r);
                % filter red by skeleton length
                trajData.filtered = trajData.filtered&logical(trajData.is_good_skel)...
                    &filterSkelLength(skelData,pixelsize,minSkelLength_r,maxSkelLength_r);
            end
            % apply phase restriction
            phaseFrameLogInd = trajData.frame_number <= lastFrame & trajData.frame_number >= firstFrame;
            trajData.filtered(~phaseFrameLogInd) = false;
            % find worms that have just left a cluster vs lone worms
            [leaveClusterLogInd, loneWormLogInd] = findLeaveClusterWorms(filename,inClusterNeighbourNum,minNeighbrDist,postExitDuration);
            
            %% calculate or extract desired feature values
            % calculate cHeadAngle by looping through each worm path
            uniqueWormpaths = unique(trajData.worm_index_joined);
            worm_xcoords = squeeze(skelData(1,:,:))'; 
            worm_ycoords = squeeze(skelData(2,:,:))';
            sHeadAngleChangeRate_leaveCluster_thisFile = NaN(1,numel(uniqueWormpaths));
            sHeadAngleChangeRate_loneWorm_thisFile = NaN(1,numel(uniqueWormpaths));
            for wormpathCtr = 1:numel(uniqueWormpaths)
                wormpathLogInd = trajData.worm_index_joined==uniqueWormpaths(wormpathCtr);
                wormpath_xcoords_leaveCluster = worm_xcoords((wormpathLogInd & leaveClusterLogInd & trajData.filtered),:);
                wormpath_ycoords_leaveCluster = worm_ycoords((wormpathLogInd & leaveClusterLogInd & trajData.filtered),:);
                wormpath_xcoords_loneWorm = worm_xcoords(wormpathLogInd & loneWormLogInd & trajData.filtered,:);
                wormpath_ycoords_loneWorm = worm_ycoords(wormpathLogInd & loneWormLogInd & trajData.filtered,:);
                % sample a section of the specified postExitDuration for trajectories
                if size(wormpath_xcoords_leaveCluster,1)>(postExitDuration+1)*frameRate
                    firstFrame = 1;
                    lastFrame = firstFrame + (postExitDuration+1)*frameRate;
                    wormpath_xcoords_leaveCluster = wormpath_xcoords_leaveCluster(firstFrame:lastFrame,:);
                    wormpath_ycoords_leaveCluster = wormpath_ycoords_leaveCluster(firstFrame:lastFrame,:);
                end
                if size(wormpath_xcoords_loneWorm,1)>(postExitDuration+1)*frameRate
                    firstFrame = randi(size(wormpath_xcoords_loneWorm,1)-(postExitDuration+1)*frameRate,1);
                    lastFrame = firstFrame + (postExitDuration+1)*frameRate;
                    wormpath_xcoords_loneWorm = wormpath_xcoords_loneWorm(firstFrame:lastFrame,:);
                    wormpath_ycoords_loneWorm = wormpath_ycoords_loneWorm(firstFrame:lastFrame,:);
                end
                % calculate angles
                [angleArray_leaveCluster,meanAngles_leaveCluster] = makeAngleArray(wormpath_xcoords_leaveCluster,wormpath_ycoords_leaveCluster);
                angleArray_leaveCluster = angleArray_leaveCluster+meanAngles_leaveCluster;
                [angleArray_loneWorm,meanAngles_loneWorm] = makeAngleArray(wormpath_xcoords_loneWorm,wormpath_ycoords_loneWorm);
                angleArray_loneWorm = angleArray_loneWorm + meanAngles_loneWorm;
                if strcmp(marker,'bodywall')
                    % take mean head angles
                    headAngle_leaveCluster = nanmean(angleArray_leaveCluster(:,1:8),2); 
                    headAngle_loneWorm = nanmean(angleArray_loneWorm(:,1:8),2);
                elseif strcmp(marker,'pharynx')
                    headAngle_leaveCluster = angleArray_leaveCluster;
                    headAngle_loneWorm = angleArray_loneWorm;
                end
                % set to head angles to smooth over 1 second
                smoothFactor = frameRate; 
                smoothHeadAngle_leaveCluster = zeros(length(headAngle_leaveCluster)-smoothFactor,1);
                smoothHeadAngle_loneWorm = zeros(length(headAngle_loneWorm)-smoothFactor,1);
                for smoothCtr = 1:(length(headAngle_leaveCluster)-smoothFactor)
                    smoothHeadAngle_leaveCluster(smoothCtr) = nanmean(headAngle_leaveCluster(smoothCtr:smoothCtr+smoothFactor));
                end
                for smoothCtr = 1:(length(headAngle_loneWorm)-smoothFactor)
                    smoothHeadAngle_loneWorm(smoothCtr) = nanmean(headAngle_loneWorm(smoothCtr:smoothCtr+smoothFactor));
                end
                % calculate total smoothed head angle change per second
                sHeadAngleChangeRate_leaveCluster_thisFile(wormpathCtr) = nansum(smoothHeadAngle_leaveCluster)/length(smoothHeadAngle_leaveCluster);
                sHeadAngleChangeRate_loneWorm_thisFile(wormpathCtr) = nansum(smoothHeadAngle_loneWorm)/length(smoothHeadAngle_loneWorm);
            end
            sHeadAngleChangeRate_leaveCluster_thisFile(isnan(sHeadAngleChangeRate_leaveCluster_thisFile)) = [];
            sHeadAngleChangeRate_loneWorm_thisFile(isnan(sHeadAngleChangeRate_loneWorm_thisFile)) = [];
            
            % pool from different movies
            sHeadAngleChangeRate_leaveCluster{fileCtr} = sHeadAngleChangeRate_leaveCluster_thisFile;
            sHeadAngleChangeRate_loneWorm{fileCtr} = sHeadAngleChangeRate_loneWorm_thisFile;
        end
        % pool data from all files belonging to the same strain and worm density
        sHeadAngleChangeRate_leaveCluster = abs(horzcat(sHeadAngleChangeRate_leaveCluster{:}));
        sHeadAngleChangeRate_loneWorm = abs(horzcat(sHeadAngleChangeRate_loneWorm{:}));
        
        %% plot data, format, and export
        set(0,'CurrentFigure',sHeadAngleChangeRateFig)
        histogram(sHeadAngleChangeRate_leaveCluster,'Normalization','pdf','DisplayStyle','stairs')
        hold on
        histogram(sHeadAngleChangeRate_loneWorm,'Normalization','pdf','DisplayStyle','stairs')
        leaveClusterLegend = strcat('leave cluster, n=',num2str(size(sHeadAngleChangeRate_leaveCluster,2)));
        loneWormLegend = strcat('lone worm, n=',num2str(size(sHeadAngleChangeRate_loneWorm,2)));
        legend(leaveClusterLegend, loneWormLegend)
        title([strains{strainCtr} '\_' wormnums{numCtr}],'FontWeight','normal')
        xlabel('head angle change rate (�/s)')
        ylabel('probability')
        if strcmp(marker,'bodywall')
            xlim([0 30])
            ylim([0 0.09])
        end
        set(sHeadAngleChangeRateFig,'PaperUnits','centimeters')
        figurename = ['figures/turns/headAngleChangeRate_' strains{strainCtr} '_' wormnums{numCtr} '_' phase '_data' num2str(dataset) '_' marker '_CL'];
        %savefig(sHeadAngleChangeRateFig,[figurename '.fig'])
        %exportfig(sHeadAngleChangeRateFig,[figurename '.eps'],exportOptions)
        %system(['epstopdf ' figurename '.eps']);
        %system(['rm ' figurename '.eps']);
    end
end