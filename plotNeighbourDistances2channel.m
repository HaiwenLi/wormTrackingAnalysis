% calculate various single worm statistics for different numbers of worms
% on plate

% issues / todo:
% - should distances be calculated only to other moving worms, or to any
% object (ie also worms that won't appear in the next frame)?

clear
close all

exportOptions = struct('Format','eps2',...
    'Color','rgb',...
    'Width',10,...
    'Resolution',300,...
    'FontMode','fixed',...
    'FontSize',12,...
    'LineWidth',1);

pixelsize = 100/19.5; % 100 microns are 19.5 pixels

strains = {'npr1','N2'};
wormnums = {'40','HD'};
intensityThresholds_g = [60, 40];
maxBlobSize_g = 1e4;
maxBlobSize_r = 2.5e5;
clusterthreshold = 1000;
plotDiagnostics = false;

for numCtr = 1:length(wormnums)
    wormnum = wormnums{numCtr};
    distFig = figure; hold on
    clustFig = figure; hold on
    for strainCtr = 1:length(strains)
        %% load data
        filenames_g = importdata([strains{strainCtr} '_' wormnum '_g_list.txt']);
        filenames_r = importdata([strains{strainCtr} '_' wormnum '_r_list.txt']);
        numFiles = length(filenames_g);
        assert(length(filenames_r)==numFiles,'Number of files for two channels do not match.')
        pairDistances = cell(numFiles,1);
        clustercount = cell(numFiles,1);
        for fileCtr = 1:numFiles
            filename_g = filenames_g{fileCtr};
            filename_r = filenames_r{fileCtr};
            trajData_g = h5read(filename_g,'/trajectories_data');
            trajData_r = h5read(filename_r,'/trajectories_data');
            blobFeats_g = h5read(filename_g,'/blob_features');
            blobFeats_r = h5read(filename_r,'/blob_features');
            frameRate = h5readatt(filename_g,'/plate_worms','expected_fps');
            maxNumFrames = numel(unique(trajData_g.frame_number));
            numFrames = round(maxNumFrames/frameRate/10);
            framesAnalyzed = randperm(maxNumFrames,numFrames); % randomly sample frames without replacement
            %% filter worms
            if contains(filename_r,'55')||contains(filename_r,'54')
                intensityThreshold_r = 70;
            else
                intensityThreshold_r = 35;
            end
            if plotDiagnostics
                plotIntensitySizeFilter(blobFeats_g,pixelsize,...
                    intensityThresholds_g(numCtr),maxBlobSize_g,...
                    [wormnum ' ' strains{strainCtr} ' ' ...
                    strrep(strrep(filename_g(end-31:end),'_X1_skeletons.hdf5',''),'/','')])
                plotIntensitySizeFilterBodywall(blobFeats_r,pixelsize,...
                    intensityThreshold_r,maxBlobSize_r,...
                    [wormnum ' ' strains{strainCtr} ' ' ...
                    strrep(strrep(filename_r(end-31:end),'_X1_skeletons.hdf5',''),'/','')])
            end
            trajData_g.filtered = (blobFeats_g.area*pixelsize^2<=maxBlobSize_g)&...
                (blobFeats_g.intensity_mean>=intensityThresholds_g(numCtr));
            trajData_r.filtered = (blobFeats_r.area*pixelsize^2<=maxBlobSize_r)&...
                (blobFeats_r.intensity_mean>=intensityThreshold_r)&...
                logical(trajData_r.is_good_skel);
            %% calculate stats
            pairDistances{fileCtr} = cell(numFrames,1);
            for frameCtr = 1:numFrames
                frame = framesAnalyzed(frameCtr);
                [x_g, y_g] = getWormPositions(trajData_g, frame);
                [x_r, y_r] = getWormPositions(trajData_r, frame);
                if numel(x_g)>=1&&numel(x_r)>=1 % need at least two worms in frame to calculate distances
                    redToGreenDistances = pdist2([x_r y_r],[x_g y_g]).*pixelsize; % distance of every red worm to every green
                    pairDistances{fileCtr}{frameCtr} = redToGreenDistances(:);
                else
                    pairDistances{fileCtr}{frameCtr} = single(NaN);
                end
            end
            % count how many worms are within clusterthreshold
            clustercount{fileCtr} = cellfun(@(x) nnz(x<=clusterthreshold), pairDistances{fileCtr});
        end
        %% plot data
        % pool data from all frames for each file, then for all files
        pairDistances = cellfun(@(x) {vertcat(x{:})},pairDistances);
        histogram(distFig.Children,vertcat(pairDistances{:}),'Normalization','Probability',...
            'DisplayStyle','stairs')
        histogram(clustFig.Children,vertcat(clustercount{:}),'Normalization','Probability',...
            'DisplayStyle','stairs')
    end
    %% format and export figures
    title(distFig.Children,wormnum,'FontWeight','normal');
    set(distFig,'PaperUnits','centimeters')
    distFig.Children.XLim = [0 1.2e4];
    xlabel(distFig.Children,'r-g pair distance (\mum)')
    ylabel(distFig.Children,'P')
    legend(distFig.Children,strains)
    figurename = ['pairdistance_rg_' wormnum];
    exportfig(distFig,[figurename '.eps'],exportOptions)
    system(['epstopdf ' figurename '.eps']);
    system(['rm ' figurename '.eps']);
    %
    title(clustFig.Children,wormnum,'FontWeight','normal');
    set(clustFig,'PaperUnits','centimeters')
    clustFig.Children.XLim = [0 40];
    clustFig.Children.YLim = [0 0.25];
    xlabel(clustFig.Children,['number of neigbbours within ' num2str(clusterthreshold) '\mum'])
    ylabel(clustFig.Children,'P')
    legend(clustFig.Children,strains)
    figurename = ['clusthist_rg_' wormnum];
    exportfig(clustFig,[figurename '.eps'],exportOptions)
    system(['epstopdf ' figurename '.eps']);
    system(['rm ' figurename '.eps']);
end