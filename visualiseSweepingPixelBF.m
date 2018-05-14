% script visualises sweeping using pixel data from selected frames, using
% up to 5 hours of long sweeping brightfield recordings (Leah's 1 patch dataset)
% step 1: read image frame
% step 2: generate binary image based on intensity threshold to pick out worm pixels from background
% step 3: dilate image to "connect" loose pharynxes and apply area thresholding to binary image to pick up clusters
% step 4: draw clusters over time (optional: plot centroid)
% step 5: plot food contour on top of the image (optional)
% script also calculates cluster centroid speed.

%%%% issues to deal with: run rep 1 for N2 (track to get skeleton files after it finishes copying), change blobAreaThreshold for
%%%% N2 and all, and look at median cluser speeds plot for npr-1 (moving
%%%% avg etc.)

close all
clear

strains = {'npr1','N2'};
sampleEveryNSec = 120; % in seconds
blobAreaThreshold = 8000; % single worm area ~ 500
plotCentroid = true;
plotFoodContour = true;

exportOptions = struct('Format','EPS2',...
    'Color','rgb',...
    'Width',10,...
    'Resolution',300,...
    'FontMode','fixed',...
    'FontSize',12,...
    'LineWidth',1);

addpath('auxiliary/')

for strainCtr = 1%:length(strains)
    [annotationNum,annotationFilenames,~] = xlsread('datalists/BFLongSweeping.xlsx',strainCtr,'A1:E30','basic');
    % xy coordinates and radius of food contour obtained by hand annotation using VGG
    if strcmp(strains{strainCtr},'npr1')
        foodCtnCoords_xyr = [1203,914,379;1057,867,348;997,810,328;1007,790,334;988,711,335;1006,683,327];
    elseif strcmp(strains{strainCtr},'N2')
        foodCtnCoords_xyr = [1055,800,380;1194,754,356;714,783,322;1328,881,338;1022,678,328;905,786,330];
    end
    
    clusterCentroidSpeedFig = figure; hold on
    recordingColors = distinguishable_colors(6);
    
    for fileCtr = 1:6 % go through each recording replicate (6 in total)
        clusterVisFig = figure; hold on
        totalFrames = 0;
        totalSegs = 0;
        for segCtr = 1:5 % go through each hour of the recording replicate (5 hours maximum)
            fileIdx = find(annotationNum(:,1) == fileCtr & annotationNum(:,2) == segCtr);
            firstFrame{segCtr} = annotationNum(fileIdx,4)+1; % +1 to adjust for python 0 indexing
            lastFrame{segCtr} = annotationNum(fileIdx,5)+1;
            filename{segCtr} = annotationFilenames{fileIdx};
            if lastFrame{segCtr} - firstFrame{segCtr} > 0 % if this recording has any valid frames
                totalFrames = totalFrames+lastFrame{segCtr}-firstFrame{segCtr}+1;
                totalSegs = totalSegs+1;
            end
        end
        totalSampleFrames = ceil(totalFrames/sampleEveryNSec/25);
        % initialise
        plotColors = parula(totalSampleFrames);
        blobCentroidCoords = NaN(2,totalSampleFrames);
        cumFrame = 0; % keep track of cumulative frames across replicate segments
        leftoverFrames = 0; % keep track of leftover frames at the end of one segment that combines with the start of the next segment
        
        for segCtr = 1:totalSegs
            skelFilename = strrep(strrep(filename{segCtr},'MaskedVideos','Results'),'.hdf5','_skeletons.hdf5');
            % load data
            frameRate = double(h5readatt(skelFilename,'/plate_worms','expected_fps'));
            pixelsize = double(h5readatt(skelFilename,'/trajectories_data','microns_per_pixel')); % 10 microns per pixel
            trajData = h5read(skelFilename,'/trajectories_data');
            fileInfo = h5info(filename{segCtr});
            dims = fileInfo.Datasets(2).Dataspace.Size;
            if leftoverFrames>0
                assert(firstFrame{segCtr} ==1); % if there are leftover frames from the previous segment, then this segment must start from the very first frame
                firstFrame{segCtr} = sampleEveryNSec*frameRate-leftoverFrames+firstFrame{segCtr};
            end
            movieFrames = firstFrame{segCtr}:sampleEveryNSec*frameRate:...
                floor((lastFrame{segCtr}-firstFrame{segCtr}+1)/sampleEveryNSec/frameRate)*sampleEveryNSec*frameRate+firstFrame{segCtr};
            for frameCtr = 1:numel(movieFrames)
                imageFrame = h5read(filename{segCtr},'/mask',[1,1,movieFrames(frameCtr)],[dims(1),dims(2),1]);
                % generate binary segmentation based on black/white contrast
                binaryImage = imageFrame>0 & imageFrame<100;
                binaryImage = imfill(binaryImage, 'holes');
                % filter by blob size
                blobMeasurements = regionprops(binaryImage, 'Area','Centroid');
                blobCentroidsCoords = reshape([blobMeasurements.Centroid],[2, numel([blobMeasurements.Centroid])/2]);
                blobLogInd = [blobMeasurements.Area] > blobAreaThreshold; % apply blob area threshold values
                blobLogInd = blobLogInd & blobCentroidsCoords(2,:) > 250; % get rid of the annoying box at the edge
                % restrict to blobs near the food patch centre (within 500 pixels or 5 mm)
                blobLogInd = blobLogInd & blobCentroidsCoords(1,:)<foodCtnCoords_xyr(fileCtr,1)+500 & blobCentroidsCoords(1,:)>foodCtnCoords_xyr(fileCtr,1)-500;
                blobLogInd = blobLogInd & blobCentroidsCoords(2,:)<foodCtnCoords_xyr(fileCtr,2)+500 & blobCentroidsCoords(2,:)>foodCtnCoords_xyr(fileCtr,2)-500;
                blobBoundaries = bwboundaries(binaryImage,8,'noholes');
                % plot individual blob boundaries that meet area threshold requirements
                set(0,'CurrentFigure',clusterVisFig)
                for blobCtr = 1:numel(blobLogInd)
                    if blobLogInd(blobCtr)
                        fill(blobBoundaries{blobCtr}(:,1)*pixelsize/1000,blobBoundaries{blobCtr}(:,2)*pixelsize/1000,plotColors(cumFrame+frameCtr,:),'edgecolor','none')
                        alpha 0.5
                    end
                end
                % get centroids
                if nnz(blobLogInd)>0
                    [~,maxAreaIdx] = max([blobMeasurements.Area].*blobLogInd);
                    blobCentroidCoords(1,cumFrame+frameCtr) = blobCentroidsCoords(1,maxAreaIdx);
                    blobCentroidCoords(2,cumFrame+frameCtr) = blobCentroidsCoords(2,maxAreaIdx);
                    if plotCentroid
                        set(0,'CurrentFigure',clusterVisFig)
                        plot(blobCentroidCoords(2,cumFrame+frameCtr)*pixelsize/1000,blobCentroidCoords(1,cumFrame+frameCtr)*pixelsize/1000,'k--x')
                    end
                end
            end
            cumFrame = cumFrame+numel(movieFrames);
            leftoverFrames = lastFrame{segCtr} - max(movieFrames);
        end
        
        axis equal
        colorbar
        caxis([0 ceil(totalFrames/25/60)])
        cb = colorbar; cb.Label.String = 'minutes';
        xmax = round(foodCtnCoords_xyr(fileCtr,2)*pixelsize/1000+5);
        xmin = round(foodCtnCoords_xyr(fileCtr,2)*pixelsize/1000-5);
        ymax = round(foodCtnCoords_xyr(fileCtr,1)*pixelsize/1000+5);
        ymin = round(foodCtnCoords_xyr(fileCtr,1)*pixelsize/1000-5);
        xlim([xmin xmax])
        ylim([ymin ymax])
        xticks(xmin:2:xmax)
        yticks(ymin:2:ymax)
        xlabel('x (mm)')
        ylabel('y (mm)')
        if plotFoodContour
            viscircles([foodCtnCoords_xyr(fileCtr,2),foodCtnCoords_xyr(fileCtr,1)]*pixelsize/1000,foodCtnCoords_xyr(fileCtr,3)*pixelsize/1000,'Color','k','LineStyle','--','LineWidth',1);
        end
        % export figure
        if plotCentroid
            if plotFoodContour
                figurename = ['figures/sweeping/' strains{strainCtr} '_clusterCentroidSpeed_rep' num2str(fileCtr) '_blobsOverTimePixelCentroidFood_blobArea' num2str(blobAreaThreshold) '_timeStep' num2str(sampleEveryNSec) '_dataBF'];
            else
                figurename = ['figures/sweeping/' strains{strainCtr} '_clusterCentroidSpeed_rep' num2str(fileCtr) '_blobsOverTimePixelCentroid_blobArea' num2str(blobAreaThreshold) '_timeStep' num2str(sampleEveryNSec) '_dataBF'];
            end
        elseif plotFoodContour
            figurename = ['figures/sweeping/' strains{strainCtr} '_clusterCentroidSpeed_rep' num2str(fileCtr) '_blobsOverTimePixelFood_blobArea' num2str(blobAreaThreshold) '_timeStep' num2str(sampleEveryNSec) '_dataBF'];
        else
            figurename = ['figures/sweeping/' strains{strainCtr} '_clusterCentroidSpeed_rep' num2str(fileCtr) '_blobsOverTimePixel_blobArea' num2str(blobAreaThreshold) '_timeStep' num2str(sampleEveryNSec) '_dataBF'];
        end
        exportfig(clusterVisFig,[figurename '.eps'],exportOptions)
        % calculate centroid speed (in microns per minute)
        clusterCentroidSpeed{fileCtr} = NaN(1,totalSampleFrames);
        for frameCtr = 1:totalSampleFrames-10
            if ~isnan(blobCentroidCoords(1,frameCtr))
                for stepCtr = 1:10 % in case the next sample frame has no cluster, go up to 10 time steps away
                    if ~isnan(blobCentroidCoords(1,frameCtr+stepCtr))
                        break
                    end
                end
                clusterCentroidSpeed{fileCtr}(frameCtr) = sqrt((blobCentroidCoords(1,frameCtr+stepCtr)-blobCentroidCoords(1,frameCtr))^2 +...
                    (blobCentroidCoords(2,frameCtr+stepCtr)-blobCentroidCoords(2,frameCtr))^2)...
                    /stepCtr*pixelsize*60/sampleEveryNSec;
                if clusterCentroidSpeed{fileCtr}(frameCtr)>500
                    clusterCentroidSpeed{fileCtr}(frameCtr) = NaN;
                end
            end
        end
        set(0,'CurrentFigure',clusterCentroidSpeedFig)
        recordingsPlotX = 1:sampleEveryNSec/60:ceil(totalFrames/25/60);
        if numel(recordingsPlotX) == numel(clusterCentroidSpeed{fileCtr})
            plot(recordingsPlotX,smoothdata(clusterCentroidSpeed{fileCtr},'movmedian',6,'omitnan'),'Color',recordingColors(fileCtr,:))
        elseif numel(recordingsPlotX) < numel(clusterCentroidSpeed{fileCtr})
            plot(recordingsPlotX,smoothdata(clusterCentroidSpeed{fileCtr}(1:numel(recordingsPlotX)),'movmedian',6,'omitnan'),'Color',recordingColors(fileCtr,:))
        elseif numel(recordingsPlotX) > numel(clusterCentroidSpeed{fileCtr})
            plot(recordingsPlotX(1:numel(clusterCentroidSpeed{fileCtr})),smoothdata(clusterCentroidSpeed{fileCtr},'movmedian',6,'omitnan'),'Color',recordingColors(fileCtr,:))
        end
    end
    % export cluster centroid speed figure
    set(0,'CurrentFigure',clusterCentroidSpeedFig)
    xlabel('Time (min)'), ylabel('Cluster Speed (microns/min)')
    legend({'1','2','3','4','5','6'},'Location','eastoutside')
    xlim([0 300])
    figurename = ['figures/sweeping/' strains{strainCtr} '_clusterCentroidSpeed_dataBF'];
    %exportfig(clusterCentroidSpeedFig,[figurename '.eps'],exportOptions)
    % save cluster centroid speednumbers
    %save(['figures/sweeping/' strains{strainCtr} '_clusterCentroidSpeed_dataBF.mat'],'clusterCentroidSpeed');
    % calculate average speed
    for fileCtr = 1:6 %[1,2,3,4,6]
        averageSpeed(fileCtr) = nanmedian(clusterCentroidSpeed{fileCtr});
    end
    averageSpeed = nanmedian(averageSpeed)
end