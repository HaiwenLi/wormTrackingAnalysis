% script visualises sweeping in high density worm pharynx datasets in several ways. (adapted from visualiseSweeping.m)
% 1. phase-specific histogram of sites visited based on trajData (plot): makeVideo = false; useBlobThreshold = false; (untested)
% 2. time-lapse histogram of sites visited based on trajData (movie): makeVideo = true; useBlobThreshold = false; (untested)
% 3. time-lapse, binary intensity thresholding of site visit histograms based on trajData (movie): makeVideo = true; useBlobThreshold = true; (untested)
% 4. intensity and area thresholding of site visit histograms based on trajData (plot): makeVideo = false; useBlobThreshold = true; plotClusters = true; (tested)

close all
clear

%% set analysis parameters
dataset = 1;
phase = 'fullMovie';
wormnum = 'HD'; % only works when phase = 'fullMovie'
markerType = 'pharynx';
makeVideo = false;
useBlobIntensityThreshold = true;

if strcmp(wormnum,'HD')
    minPerSlice = 5; % 5 works best
    if minPerSlice == 5
        minContiniousDuration = 10; % time in minutes of continous FOV required for a plot to be generated.
    elseif minPerSlice == 2.5
        minContiniousDuration = 7.5;
    end
end

if useBlobIntensityThreshold
    if minPerSlice == 5
        blobHeatMapIntensityThreshold = 1300;
    elseif minPerSlice == 2.5
        blobHeatMapIntensityThreshold = 650;
    end
    blobAreaThreshold = 8;
    plotClusters = true;
end

%% set fixed parameters

if dataset ==1
    strains = {'npr1','N2','HA'};%{'npr1','HA','N2'}
    assert(~strcmp(markerType,'bodywall'),'Bodywall marker for dataset 1 not available')
elseif dataset ==2
    strains = {'npr1','N2'};
end
pixelsize = 100/19.5; % 100 microns are 19.5 pixels

% filtering parameters
if dataset == 1
    intensityThresholds = containers.Map({'40','HD','1W'},{50, 40, 100});
elseif dataset ==2
    intensityThresholds = containers.Map({'40','HD','1W'},{60, 40, 100});
end
if strcmp(markerType,'pharynx')
    maxBlobSize = 1e5;
    channelStr = 'g';
else
    error('unknown marker type specified, should be pharynx or bodywall')
end

% export fig parameters
exportOptions = struct('Format','EPS2',...
    'Color','rgb',...
    'Width',10,...
    'Resolution',300,...
    'FontMode','fixed',...
    'FontSize',12,...
    'LineWidth',1);

%% other initial set up

addpath('auxiliary/')
addpath('visualisation/')


%% loop through strains
for strainCtr = 3%1:length(strains)
    %% load file lists
    if dataset == 1
        [phaseFrames,filenames,~] = xlsread(['datalists/' strains{strainCtr} '_' wormnum '_list.xlsx'],1,'A1:E15','basic');
    elseif dataset == 2
        [phaseFrames,filenames,~] = xlsread(['datalists/' strains{strainCtr} '_' wormnum '_' channelStr '_list.xlsx'],1,'A1:E15','basic');
    end
    if strcmp(wormnum, 'HD')
        if strcmp(phase,'fullMovie')
            % load continuous frames list
            if dataset == 1
                [~,~,continuousFrames] = xlsread(['datalists/' strains{strainCtr} '_' wormnum '_list.xlsx'],1,'G1:P15','basic');
            elseif dataset == 2
                [~,~,continuousFrames] = xlsread(['datalists/' strains{strainCtr} '_' wormnum '_' channelStr '_list.xlsx'],1,'G1:P15','basic');
            end
            % replace NaN's with empty cells
            for k = 1:numel(continuousFrames)
                if isnan(continuousFrames{k})
                    continuousFrames{k} = '';
                end
            end
        else
            error('high density movies cannot be phase-restricted for this analysis. Set phase to "fullMovie".')
        end
    end
    %% loop through files
    for fileCtr = 1:length(filenames) % can be parfor
        filename = filenames{fileCtr};
        %% make new video
        if makeVideo
            if useBlobIntensityThreshold
                writerObj = VideoWriter(['figures/sweeping/' strains{strainCtr} '_' strrep(strrep(filename(end-32:end-18),' ',''),'/','') '_sitesVisited_blobs.avi']);
            else
                writerObj = VideoWriter(['figures/sweeping/' strains{strainCtr} '_' strrep(strrep(filename(end-32:end-18),' ',''),'/','') '_sitesVisited.avi']);
            end
            writerObj.FrameRate = 2;
            open(writerObj);
        end
        %% load tracking data
        trajData = h5read(filename,'/trajectories_data');
        blobFeats = h5read(filename,'/blob_features');
        frameRate = double(h5readatt(filename,'/plate_worms','expected_fps'));
        %% get phase restriction frames
        [firstFrame, lastFrame] = getPhaseRestrictionFrames(phaseFrames,phase,fileCtr);
        
        %% filter data for worms
        if strcmp(markerType,'pharynx')
            % reset skeleton flag for pharynx data
            trajData.has_skeleton = true(size(trajData.has_skeleton)); %squeeze(~any(any(isnan(skelData))));
        end
        trajData.filtered = filterIntensityAndSize(blobFeats,pixelsize,...
            intensityThresholds(wormnum),maxBlobSize)...
            &trajData.has_skeleton; % careful: we may not want to filter for skeletonization for clustering statistics
        if strcmp(markerType,'bodywall')
            % filter red data by skeleton length
            trajData.filtered = trajData.filtered&logical(trajData.is_good_skel)&...
                filterSkelLength(skelData,pixelsize,minSkelLength,maxSkelLength);
        end
        % apply phase restriction
        phaseFilter_logInd = trajData.frame_number < lastFrame & trajData.frame_number > firstFrame;
        trajData.filtered(~phaseFilter_logInd)=false;
        
        if useBlobIntensityThreshold
            % adjust intensity thresholding values for 3 Hz movies
            if dataset == 1
                if frameRate == 3
                    blobHeatMapIntensityThreshold = blobHeatMapIntensityThreshold/3;
                end
            end
        end
        
        %% get continuous frames
        if strcmp(wormnum, 'HD')
            for frameRunCtr = 1:10
                if ~isempty(continuousFrames{fileCtr,frameRunCtr})
                    frameRun = continuousFrames{fileCtr,frameRunCtr};
                    frameRunLimits = strsplit(frameRun,'-');
                    firstFrame = str2double(frameRunLimits{1});
                    if strcmp(frameRunLimits{2},'end')
                        lastFrame = max(trajData.frame_number);
                    else
                        lastFrame = str2double(frameRunLimits{2});
                    end
                    if lastFrame-firstFrame+1>minContiniousDuration*60*frameRate
                        numMovieSlices = floor((lastFrame-firstFrame+1)/60/frameRate/minPerSlice);
                        if numMovieSlices<2
                            error('something wrong with continuous movie run slicing. Slice number should be 3 or more!')
                        else
                            plotColors = parula(numMovieSlices);
                            % generate movie slices
                            frameSlices = zeros(numMovieSlices,2);
                            for sliceCtr = 1:numMovieSlices
                                frameSlices(sliceCtr,:) = [round((lastFrame-firstFrame+1)/numMovieSlices*(sliceCtr-1))...
                                    round((lastFrame-firstFrame+1)/numMovieSlices*(sliceCtr-1)+(lastFrame-firstFrame+1)/numMovieSlices)];
                            end
                            
                            % create figure to hold cluster outline plots
                            clusterOutlineFig = figure; hold on
                            
                            % select frame slices
                            for sliceCtr = 1:size(frameSlices,1)
                                sliceStart = frameSlices(sliceCtr,1);
                                sliceEnd = frameSlices(sliceCtr,2);
                                sliceLogInd = false(size(trajData.filtered));
                                for frameCtr = sliceStart:sliceEnd
                                    sliceLogInd(frameCtr==trajData.frame_number)=true;
                                end
                                
                                %% heat map of sites visited 
                                siteVisitFig = figure;
                                x = trajData.coord_x(trajData.filtered & sliceLogInd);
                                y = trajData.coord_y(trajData.filtered & sliceLogInd);
                                h=histogram2(x*pixelsize/1000,y*pixelsize/1000,48,...
                                    'DisplayStyle','tile','EdgeColor','none','Normalization','count');
                                %caxis([0 600/15000*nnz(trajData.filtered & sliceLogInd)]); % normalise intensity based on number of tracked objects in each slice
                                colorbar
                                cb = colorbar; cb.Label.String = '# visited';
                                xlabel('x (mm)'), ylabel('y (mm)')
                                xlim([0 12]);
                                ylim([0 12]);
                                set(siteVisitFig,'PaperUnits','centimeters')
                                figurename = ['figures/sweeping/' strains{strainCtr}...
                                    '_' strrep(strrep(filename(end-32:end-18),' ',''),'/','') '_sitesVisited' '_' phase '_slice' num2str(round((sliceCtr-1)*60/numMovieSlices)) '_data' num2str(dataset)];
                                
                                if useBlobIntensityThreshold
                                    binaryImage = h.Values > blobHeatMapIntensityThreshold; % apply blob heat map intensity threshold values
                                    binaryImage = imfill(binaryImage, 'holes');
                                    binaryFig = figure; imshow(binaryImage)
                                    set(gcf,'PaperUnits','centimeters')
                                    %xlim([0 12]);
                                    %ylim([0 12]);
                                    if plotClusters
                                        set(0,'CurrentFigure',clusterOutlineFig)
                                        labeledImage = bwlabel(binaryImage, 8); % label each blob so we can make measurements of it
                                        blobMeasurements = regionprops(binaryImage, 'Area');
                                        blobLogInd = [blobMeasurements.Area] > blobAreaThreshold; % apply blob area threshold values
                                        blobBoundaries = bwboundaries(binaryImage);
                                        for blobCtr = 1:numel(blobLogInd) % plot individual blob boundaries that meet area threshold requirements
                                            if blobLogInd(blobCtr)
                                                plot(blobBoundaries{blobCtr}(:,1)/size(binaryImage,1)*12,...
                                                    blobBoundaries{blobCtr}(:,2)/size(binaryImage,2)*12,...
                                                    'Color', plotColors(sliceCtr,:),'LineWidth',0.5) % reset the size of the plot to 12x12 cm
                                            end
                                        end
                                    else
                                        set(0,'CurrentFigure',binaryFig)
                                        cb = colorbar; cb.Label.String = '# visited';
                                        xlabel('x (pixels)'), ylabel('y (pixels)') % binary images are 1167x875 pixels
                                        title([strains{strainCtr} ' ' strrep(filename(end-32:end-18),'/','') ', ' num2str(round((sliceCtr-1)*60/numMovieSlices)) 'min'])
                                        axis on
                                        colorbar off
                                        colormap(colorMap)
                                        saveas(gcf,[figurename '.tif'])
                                    end
                                end
                                
                                if ~useBlobIntensityThreshold
                                    title([strains{strainCtr} ' ' strrep(filename(end-32:end-18),'/','') ', ' num2str(round((sliceCtr-1)*60/numMovieSlices)) 'min'])
                                    saveas(gcf,[figurename '.tif'])
                                end
                                
                                % write heatmap to video
                                if makeVideo
                                    image = imread([figurename '.tif']);
                                    frame = im2frame(image);
                                    writeVideo(writerObj,frame)
                                end
                                if exist([ figurename '.tif'])
                                    system(['rm ' figurename '.tif']);
                                end
                            end
                            % format and export cluster plot from this recording
                            if useBlobIntensityThreshold
                                if plotClusters
                                    set(0,'CurrentFigure',clusterOutlineFig)
                                    xlim([0 12])
                                    ylim([0 12])
                                    xticks([0:2:12])
                                    yticks([0:2:12])
                                    xlabel('x (mm)'), ylabel('y (mm)')
                                    title([strains{strainCtr} ' ' strrep(filename(end-32:end-18),'/','') ', ' num2str(round(firstFrame/60/frameRate)) '-' num2str(round(lastFrame/60/frameRate)) ' min'])
                                    colorbar
                                    caxis([round(firstFrame/60/frameRate) round(lastFrame/60/frameRate)])
                                    cb = colorbar; cb.Label.String = 'minutes';
                                    figurename = ['figures/sweeping/' strains{strainCtr}...
                                        '_' wormnum '_' strrep(strrep(filename(end-32:end-18),' ',''),'/','') '_blobsOverTime_'...
                                        num2str(round(firstFrame/60/frameRate)) '-' num2str(round(lastFrame/60/frameRate)) ' min_' ...
                                        num2str(minPerSlice) 'minSlices_' phase '_data' num2str(dataset)];
                                    exportfig(clusterOutlineFig,[figurename '.eps'],exportOptions)
                                    plot2svg([figurename '.svg'],clusterOutlineFig)
                                end
                                % reset parameter from 3Hz movies, if necessary
                                if dataset == 1
                                    if frameRate == 3
                                        blobHeatMapIntensityThreshold = blobHeatMapIntensityThreshold*3;
                                    end
                                end
                            end
                            % close the videos made from this recording
                            if makeVideo
                                close(writerObj);
                            end
                            % close individual heat maps from this recording
                            close all
                        end
                    end
                end
            end
        end
    end
end