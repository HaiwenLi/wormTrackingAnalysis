function [] = analyzeCorrelationData(dataset,phase,wormnum,markerType,plotDiagnostics)
% calculate speed vs neighbr distance, directional correlation, and
% radial distribution functions
% INPUTS
% dataset: 1 or 2. To specify which dataset to run the script for.
% phase: 'joining', 'fullMovie', or 'sweeping'. Script defines stationary phase as: starts at 10% into the movie, and stops at 60% into the movie (HA and N2) or at specified stopping frames (npr-1).
% wormnum: '40', or 'HD'
% markerType: 'pharynx', or 'bodywall'
% plotDiagnostics: true (default) or false
% OUTPUTS
% none returned, but figures are exported
% issues/to-do:
% - seperate into individual functions for each statistic?
% - calculate red-green correlations as well as red-red

%% set other parameters
exportOptions = struct('Format','eps2',...
    'Color','rgb',...
    'Width',10,...
    'Resolution',300,...
    'FontMode','fixed',...
    'FontSize',12,...
    'LineWidth',1);
% define functions for grpstats
mad1 = @(x) mad(x,1); % median absolute deviation
% alternatively could use boxplot-style confidence intervals on the mean,
% which are 1.57*iqr/sqrt(n) - unclear how justified this is
iqrci = @(x) 1.57*iqr(x)/sqrt(numel(x));
% or one could use a bootstrapped confidence interval
bootserr = @(x) bootci(1e2,{@median,x},'alpha',0.05,'Options',struct('UseParallel',false));

if nargin<5
    plotDiagnostics = false; % true or false
    if nargin<4
        markerType = 'pharynx';
    end
end

if dataset ==1
    strains = {'npr1','N2'};%{'npr1','HA','N2'}
    assert(~strcmp(markerType,'bodywall'),'Bodywall marker for dataset 1 not available')
elseif dataset ==2
    strains = {'npr1','N2'};
end

nStrains = length(strains);
plotColors = lines(nStrains);
if dataset == 1
    intensityThresholds = containers.Map({'40','HD','1W'},{50, 40, 100});
elseif dataset ==2
    intensityThresholds = containers.Map({'40','HD','1W'},{60, 40, 100});
end
if strcmp(markerType,'pharynx')
    maxBlobSize = 1e4;
    channelStr = 'g';
elseif strcmp(markerType,'bodywall')
    maxBlobSize = 2.5e5;
    channelStr = 'r';
    minSkelLength = 850;
    maxSkelLength = 1500;
else
    error('unknown marker type specified, should be pharynx or bodywall')
end
pixelsize = 100/19.5; % 100 microns are 19.5 pixels
if plotDiagnostics, visitfreqFig = figure; hold on, end
distBinWidth = 50; % in units of micrometers
maxDist = 2000;
maxSpeed = 1500;
distBins = 0:distBinWidth:maxDist;
dircorrxticks = 0:500:maxDist;
load ~/Dropbox/Utilities/colormaps_ascii/increasing_cool/cmap_Blues.txt
%% go through strains, densities, movies
speedFig = figure; hold on
dircorrFig = figure; hold on
velcorrFig = figure; hold on
velnbrcorrFig = figure; hold on
poscorrFig = figure; hold on
lineHandles = NaN(nStrains,1);
for strainCtr = 1:nStrains
    %% load data
    if dataset == 1
        [phaseFrames,filenames,~] = xlsread(['datalists/' strains{strainCtr} '_' wormnum '_list.xlsx'],1,'A1:E15','basic');
    elseif dataset == 2
        [phaseFrames,filenames,~] = xlsread(['datalists/' strains{strainCtr} '_' wormnum '_' channelStr '_list.xlsx'],1,'A1:E15','basic');
    end
    numFiles = length(filenames);
    if strcmp(wormnum,'40'), visitfreq = cell(numFiles,1); end
    speeds = cell(numFiles,1);
    dxcorr = cell(numFiles,1); % for calculating directional cross-correlation
    vxcorr = cell(numFiles,1); % for calculating velocity cross-correlation
    vncorr = cell(numFiles,1); % for calculating velocity correlation with nearest neighbour position
    pairdist = cell(numFiles,1);
    nNbrDist= cell(numFiles,1);
    numNbrs= cell(numFiles,1);
    gr =cell(numFiles,1);
    for fileCtr = 1:numFiles % can be parfor
        filename = filenames{fileCtr};
        %% load tracking data
        trajData = h5read(filename,'/trajectories_data');
        blobFeats = h5read(filename,'/blob_features');
        skelData = h5read(filename,'/skeleton');
        %         min_neighbr_dist = h5read(filename,'/min_neighbr_dist');
        num_close_neighbrs = h5read(filename,'/num_close_neighbrs');
        neighbr_dist = h5read(filename,'/neighbr_distances');
        % check formats
        assert(size(skelData,1)==2,['Wrong skeleton size for ' filename])
        assert(size(skelData,2)==2,['Wrong skeleton size for ' filename])
        assert(size(skelData,3)==length(trajData.frame_number),['Wrong number of skeleton frames for ' filename])
        assert(length(blobFeats.velocity_x)==length(trajData.frame_number)&&...
            length(blobFeats.signed_speed)==length(trajData.frame_number),['Wrong number of speed frames for ' filename])
        if all(isnan(skelData(:))), warning(['all skeleton are NaN for ' filename]),end
        %% randomly sample which frames to analyze
        frameRate = double(h5readatt(filename,'/plate_worms','expected_fps'));
        [firstFrame, lastFrame] = getPhaseRestrictionFrames(phaseFrames,phase,fileCtr);
        numFrames = round((lastFrame-firstFrame)/frameRate);
        framesAnalyzed = randperm((lastFrame-firstFrame),numFrames) + firstFrame; % randomly sample frames without replacement
        %% filter worms
        if plotDiagnostics
            visualizeIntensitySizeFilter(blobFeats,pixelsize,intensityThresholds(wormnum),maxBlobSize,...
                [wormnum ' ' strains{strainCtr} ' ' strrep(filename(end-32:end-18),'/','')])
        end
        if strcmp(markerType,'pharynx')
            % reset skeleton flag for pharynx data
            trajData.has_skeleton = squeeze(~any(any(isnan(skelData))));
        end
        trajData.filtered = filterIntensityAndSize(blobFeats,pixelsize,...
            intensityThresholds(wormnum),maxBlobSize)...
            &trajData.has_skeleton;
        if strcmp(markerType,'bodywall')
            % filter red data by skeleton length
            trajData.filtered = trajData.filtered&logical(trajData.is_good_skel)&...
                filterSkelLength(skelData,pixelsize,minSkelLength,maxSkelLength);
        end
        % apply phase restriction
        phaseFrameLogInd = trajData.frame_number < lastFrame & trajData.frame_number > firstFrame;
        trajData.filtered(~phaseFrameLogInd)=false;
        %% calculate stats
        if strcmp(wormnum,'40')
            OverallArea = pi*(8300/2)^2;
        else
            OverallArea = peak2peak(trajData.coord_x(trajData.filtered)).*...
                peak2peak(trajData.coord_y(trajData.filtered)).*pixelsize.^2;
            disp(['overall background area estimated as ' num2str(OverallArea)])
        end
        speeds{fileCtr} = cell(numFrames,1);
        dxcorr{fileCtr} = cell(numFrames,1); % for calculating directional cross-correlation
        vxcorr{fileCtr} = cell(numFrames,1); % for calculating velocity cross-correlation
        vncorr{fileCtr} = cell(numFrames,1);
        pairdist{fileCtr} = cell(numFrames,1);
        nNbrDist{fileCtr}= cell(numFrames,1);
        numNbrs{fileCtr}= cell(numFrames,1);
        gr{fileCtr} = NaN(length(distBins) - 1,numFrames);
        if strcmp(markerType,'bodywall')
            [ ~, velocities_x, velocities_y, ~ ] = calculateSpeedsFromSkeleton(trajData,skelData,1:5,...
                pixelsize,frameRate,true,0);
        end
        for frameCtr = 1:numFrames % one may be able to vectorise this
            frame = framesAnalyzed(frameCtr);
            [x ,y] = getWormPositions(trajData, frame, true);
            N = length(x);
            if N>1 % need at least two worms in frame
                frameLogInd = trajData.frame_number==frame&trajData.filtered;
                if strcmp(markerType,'pharynx')
                    vx = double(blobFeats.velocity_x(frameLogInd));
                    vy = double(blobFeats.velocity_y(frameLogInd));
                    ox = double(squeeze(skelData(1,1,frameLogInd) - skelData(1,2,frameLogInd)));
                    oy = double(squeeze(skelData(2,1,frameLogInd) - skelData(2,2,frameLogInd)));
                elseif strcmp(markerType,'bodywall')
                    vx = velocities_x(frameLogInd);
                    vy = velocities_y(frameLogInd);
                    ox = double(squeeze(skelData(1,1,frameLogInd) - skelData(1,5,frameLogInd)));
                    oy = double(squeeze(skelData(2,1,frameLogInd) - skelData(2,5,frameLogInd)));
                end
                speeds{fileCtr}{frameCtr} = sqrt(vx.^2 + vy.^2)*pixelsize*frameRate; % speed of every worm in frame, in mu/s
                dxcorr{fileCtr}{frameCtr} = vectorCrossCorrelation2D(ox,oy,true,false); % directional correlation
                vxcorr{fileCtr}{frameCtr} = vectorCrossCorrelation2D(vx,vy,true,false); % velocity correlation
                pairdist{fileCtr}{frameCtr} = pdist([x y]).*pixelsize; % distance between all pairs, in micrometer
                gr{fileCtr}(:,frameCtr) = histcounts(pairdist{fileCtr}{frameCtr},distBins,'Normalization','count'); % radial distribution function
                gr{fileCtr}(:,frameCtr) = gr{fileCtr}(:,frameCtr)'.*OverallArea ...
                    ./(2*pi*distBins(2:end)*distBinWidth*N*(N-1)/2); % normalisation by N(N-1)/2 as pdist doesn't double-count pairs
                D = squareform(pairdist{fileCtr}{frameCtr}); % distance of every worm to every other
                [nNbrDist{fileCtr}{frameCtr}, nNbrIndx] = min(D + max(max(D))*eye(size(D)));
                %                 numNbrs{fileCtr}{frameCtr} = num_close_neighbrs(frameLogInd);
                numNbrs{fileCtr}{frameCtr} = zeros(nnz(frameLogInd),8);
                for n=1:8
                    numNbrs{fileCtr}{frameCtr}(:,n) = sum(neighbr_dist(frameLogInd,:)<=n*250,2);
                end
                % calculate direction towards nearest neighbour for each worm
                dx = double(x(nNbrIndx) - x); dy = double(y(nNbrIndx) - y);
                vncorr{fileCtr}{frameCtr} = vectorPairedCorrelation2D(vx,vy,dx,dy,true,false);
                if (numel(speeds{fileCtr}{frameCtr})~=numel(nNbrDist{fileCtr}{frameCtr}))||...
                        (numel(dxcorr{fileCtr}{frameCtr})~=numel(pairdist{fileCtr}{frameCtr}))
                    error(['Inconsistent number of variables in frame ' num2str(frame) ' of ' filename ])
                end
            end
        end
        %% pool data from frames
        speeds{fileCtr} = vertcat(speeds{fileCtr}{:});
        dxcorr{fileCtr} = horzcat(dxcorr{fileCtr}{:});
        vxcorr{fileCtr} = horzcat(vxcorr{fileCtr}{:});
        vncorr{fileCtr} = vertcat(vncorr{fileCtr}{:});
        pairdist{fileCtr} = horzcat(pairdist{fileCtr}{:});
        nNbrDist{fileCtr} = horzcat(nNbrDist{fileCtr}{:});
        numNbrs{fileCtr} = vertcat(numNbrs{fileCtr}{:})';
        %% heat map of sites visited - this only makes sense for 40 worm
        % dataset where we don't move the camera
        if strcmp(wormnum,'40')&& plotDiagnostics
            siteVisitFig = figure;
            h=histogram2(trajData.coord_x*pixelsize/1000,trajData.coord_y*pixelsize/1000,...
                'DisplayStyle','tile','EdgeColor','none','Normalization','pdf');
            visitfreq{fileCtr} = h.Values(:);
            cb = colorbar; cb.Label.String = '# visited';
            axis equal
            xlabel('x (mm)'), ylabel('y (mm)')
            title([strains{strainCtr} ' ' strrep(filename(end-32:end-18),'/','')])
            set(siteVisitFig,'PaperUnits','centimeters')
            figurename = ['figures/individualRecordings/' strains{strainCtr}...
                '_' strrep(strrep(filename(end-32:end-18),' ',''),'/','') '_sitesVisited' '_' phase '_data' num2str(dataset)];
            exportfig(siteVisitFig,[figurename '.eps'],exportOptions)
            system(['epstopdf ' figurename '.eps']);
            system(['rm ' figurename '.eps']);
        end
    end
    %% combine data from multiple files
    nNbrDist = horzcat(nNbrDist{:});
    numNbrs = horzcat(numNbrs{:});
    speeds = vertcat(speeds{:});
    pairdist = horzcat(pairdist{:});
    dxcorr = horzcat(dxcorr{:});
    vxcorr = horzcat(vxcorr{:});
    vncorr = vertcat(vncorr{:});
    %% plot histograms of speed and distance
    speedHistFig = figure; hold on
    histogram(speeds(nNbrDist>=0&nNbrDist<500),'Normalization','probability','DisplayStyle','stairs','BinLimits',[0 600],'BinWidth',distBinWidth/4);
    histogram(speeds(nNbrDist>=500&nNbrDist<2000),'Normalization','probability','DisplayStyle','stairs','BinLimits',[0 600],'BinWidth',distBinWidth/4);
    histogram(speeds(nNbrDist>=2000),'Normalization','probability','DisplayStyle','stairs','BinLimits',[0 600],'BinWidth',distBinWidth/4);
    xlabel(speedHistFig.Children,'speed (μm/s)')
    speedHistFig.Children.Box = 'on';
    ylabel(speedHistFig.Children,'P')
    legend('x_{nn}<500','500<=x_{nn}<2000','x_{nn}>2000')
    figurename = ['figures/correlation/phaseSpecific/speedHist_' strains{strainCtr} '_'  wormnum '_' phase '_data' num2str(dataset) '_' markerType '_jointraj'];
    exportfig(speedHistFig,[figurename '.eps'],exportOptions)
    system(['epstopdf ' figurename '.eps']);
    system(['rm ' figurename '.eps']);
    % number of close nbrs
    for n=1:8
        speedHist2FigNbrNum = figure;
        h = histogram2(numNbrs(n,:),speeds','DisplayStyle','tile','EdgeColor','none',...
            'XBinEdges',-0.5:10.5,'YBinLimits',[0 400]);
        normfactor = sum(h.BinCounts,2);
        normfactor(normfactor==0) = 1;
        h.BinCounts = h.BinCounts./normfactor; % conditional normalisation    xlabel(speedHist2FigNbrNum.Children,'number of neighbours within 500 μm')
        box on
        ylabel(speedHist2FigNbrNum.Children,'speed (μm/s)')
        xlabel(speedHist2FigNbrNum.Children,['# neighbours within' num2str(n*250) 'μm'])
        colormap(speedHist2FigNbrNum,flipud(cmap_Blues))
        xlim([-0.5 10.5])
        figurename = ['figures/correlation/phaseSpecific/speedvsneighbrnum' num2str(n*250) 'Hist2D_' strains{strainCtr} '_'  wormnum '_' phase '_data' num2str(dataset) '_' markerType '_jointraj'];
        exportfig(speedHist2FigNbrNum,[figurename '.eps'],exportOptions)
        system(['epstopdf ' figurename '.eps']);
        system(['rm ' figurename '.eps']);
    end
    %% bin distance data
    [nNbrDistcounts,nNbrDistBins,nNbrDistbinIdx]  = histcounts(nNbrDist,...
        'BinWidth',distBinWidth,'BinLimits',[min(nNbrDist) maxDist]);
    [pairDistcounts,pairDistBins,pairDistbinIdx]  = histcounts(pairdist,...
        'BinWidth',distBinWidth,'BinLimits',[min(pairdist) maxDist]);
    % convert bin edges to centres (for plotting)
    nNbrDistBins = double(nNbrDistBins(1:end-1) + diff(nNbrDistBins)/2);
    pairDistBins = double(pairDistBins(1:end-1) + diff(pairDistBins)/2);
    % ignore larger distance values and bins with only one element, as this will cause bootsci to fault
    nNdistkeepIdcs = nNbrDistbinIdx>0&ismember(nNbrDistbinIdx,find(nNbrDistcounts>1))...
        &speeds'<=maxSpeed; % also ignore outlier speed values
    nNbrDistBins = nNbrDistBins(nNbrDistcounts>1);
    speeds = speeds(nNdistkeepIdcs);
    vncorr = vncorr(nNdistkeepIdcs);
    nNbrDistbinIdx = nNbrDistbinIdx(nNdistkeepIdcs);
    pdistkeepIdcs = pairDistbinIdx>0&ismember(pairDistbinIdx,find(pairDistcounts>1));
    pairDistBins = pairDistBins(pairDistcounts>1);
    dxcorr = dxcorr(pdistkeepIdcs);
    vxcorr = vxcorr(pdistkeepIdcs);
    pairDistbinIdx = pairDistbinIdx(pdistkeepIdcs);
    [s_med,s_ci] = grpstats(speeds,nNbrDistbinIdx,{@median,bootserr});
    [corr_vn_med,corr_vn_ci] = grpstats(vncorr,nNbrDistbinIdx,{@median,bootserr});
    [corr_o_med,corr_o_ci] = grpstats(dxcorr,pairDistbinIdx,{@median,bootserr});
    [corr_v_med,corr_v_ci] = grpstats(vxcorr,pairDistbinIdx,{@median,bootserr});
    %% plot data
    [lineHandles(strainCtr), ~] = boundedline(nNbrDistBins,smooth(s_med),...
        [smooth(s_med - s_ci(:,1)), smooth(s_ci(:,2) - s_med)],...
        'alpha',speedFig.Children,'cmap',plotColors(strainCtr,:));
    % correlations
    boundedline(pairDistBins,smooth(corr_o_med),[smooth(corr_o_med - corr_o_ci(:,1)), smooth(corr_o_ci(:,2) - corr_o_med)],...
        'alpha',dircorrFig.Children,'cmap',plotColors(strainCtr,:))
    boundedline(pairDistBins,smooth(corr_v_med),[smooth(corr_v_med - corr_v_ci(:,1)), smooth(corr_v_ci(:,2) - corr_v_med)],...
        'alpha',velcorrFig.Children,'cmap',plotColors(strainCtr,:))
    boundedline(nNbrDistBins,smooth(corr_vn_med),[smooth(corr_vn_med - corr_vn_ci(:,1)), smooth(corr_vn_ci(:,2) - corr_vn_med)],...
        'alpha',velnbrcorrFig.Children,'cmap',plotColors(strainCtr,:))
    gr = cat(2,gr{:});
    boundedline(distBins(2:end)-distBinWidth/2,nanmean(gr,2),...
        [nanstd(gr,0,2) nanstd(gr,0,2)]./sqrt(nnz(sum(~isnan(gr),2))),...
        'alpha',poscorrFig.Children,'cmap',plotColors(strainCtr,:))
    if  strcmp(wormnum,'40')&& plotDiagnostics
        histogram(visitfreqFig.Children,vertcat(visitfreq{:}),'DisplayStyle','stairs','Normalization','pdf')
    end
end
%% format and export figures
for figHandle = [speedFig, dircorrFig, velcorrFig, velnbrcorrFig, poscorrFig] % common formating for both figures
    set(figHandle,'PaperUnits','centimeters')
end
%
speedFig.Children.YLim = [0 400];
speedFig.Children.XLim = [0 maxDist];
speedFig.Children.XTick = 0:500:maxDist;
speedFig.Children.XGrid = 'on';
speedFig.Children.YGrid = 'on';
speedFig.Children.Box = 'on';
speedFig.Children.XDir = 'reverse';
ylabel(speedFig.Children,'speed (μm/s)')
xlabel(speedFig.Children,'distance to nearest neighbour (μm)')
legend(speedFig.Children,lineHandles,strains)
figurename = ['figures/correlation/phaseSpecific/speedvsneighbrdistance_' wormnum '_' phase '_data' num2str(dataset) '_' markerType '_jointraj'];
exportfig(speedFig,[figurename '.eps'],exportOptions)
system(['epstopdf ' figurename '.eps']);
system(['rm ' figurename '.eps']);
%
dircorrFig.Children.YLim = [-1 1];
dircorrFig.Children.XLim = [0 maxDist];
dircorrFig.Children.XGrid = 'on';
dircorrFig.Children.YGrid = 'on';
set(dircorrFig.Children,'XTick',dircorrxticks,'XTickLabel',num2str(dircorrxticks'))
ylabel(dircorrFig.Children,'orientational correlation')
xlabel(dircorrFig.Children,'distance between pair (μm)')
legend(dircorrFig.Children,lineHandles,strains)
figurename = ['figures/correlation/phaseSpecific/dircrosscorr_' wormnum '_' phase '_data' num2str(dataset) '_' markerType '_jointraj'];
exportfig(dircorrFig,[figurename '.eps'],exportOptions)
system(['epstopdf ' figurename '.eps']);
system(['rm ' figurename '.eps']);
%
velcorrFig.Children.YLim = [-1 1];
velcorrFig.Children.XLim = [0 maxDist];
velcorrFig.Children.XGrid = 'on';
velcorrFig.Children.YGrid = 'on';
set(velcorrFig.Children,'XTick',dircorrxticks,'XTickLabel',num2str(dircorrxticks'))
ylabel(velcorrFig.Children,'velocity correlation')
xlabel(velcorrFig.Children,'distance between pair (μm)')
legend(velcorrFig.Children,lineHandles,strains)
figurename = ['figures/correlation/phaseSpecific/velcrosscorr_' wormnum '_' phase '_data' num2str(dataset) '_' markerType '_jointraj'];
exportfig(velcorrFig,[figurename '.eps'],exportOptions)
system(['epstopdf ' figurename '.eps']);
system(['rm ' figurename '.eps']);
%
velnbrcorrFig.Children.YLim = [-1 1];
velnbrcorrFig.Children.XLim = [0 maxDist];
velnbrcorrFig.Children.XGrid = 'on';
velnbrcorrFig.Children.YGrid = 'on';
set(velnbrcorrFig.Children,'XTick',dircorrxticks,'XTickLabel',num2str(dircorrxticks'))
ylabel(velnbrcorrFig.Children,'velocity-direction to neighbour correlation')
xlabel(velnbrcorrFig.Children,'distance to neareast neighbour (μm)')
legend(velnbrcorrFig.Children,lineHandles,strains)
figurename = ['figures/correlation/phaseSpecific/velnbrcorr_' wormnum '_' phase '_data' num2str(dataset) '_' markerType '_jointraj'];
exportfig(velnbrcorrFig,[figurename '.eps'],exportOptions)
system(['epstopdf ' figurename '.eps']);
system(['rm ' figurename '.eps']);
%
poscorrFig.Children.YLim(1) = 0;
poscorrFig.Children.XLim = [0 maxDist];
poscorrFig.Children.XTick = 0:500:maxDist;
poscorrFig.Children.YTick = 0:2:round(poscorrFig.Children.YLim(2));
poscorrFig.Children.Box = 'on';
poscorrFig.Children.XGrid = 'on';
poscorrFig.Children.YGrid = 'on';
ylabel(poscorrFig.Children,'positional correlation g(r)')
xlabel(poscorrFig.Children,'distance r (μm)')
legend(poscorrFig.Children,lineHandles,strains)
figurename = ['figures/correlation/phaseSpecific/radialdistributionfunction_' wormnum '_' phase '_data' num2str(dataset) '_' markerType '_jointraj'];
exportfig(poscorrFig,[figurename '.eps'],exportOptions)
system(['epstopdf ' figurename '.eps']);
system(['rm ' figurename '.eps']);

if  strcmp(wormnum,'40')&& plotDiagnostics
    visitfreqFig.Children.XScale = 'log';
    visitfreqFig.Children.YScale = 'log';
    %         visitfreqFig.Children.XLim = [4e-5 1e-1];
    xlabel(visitfreqFig.Children,'site visit frequency, f')
    ylabel(visitfreqFig.Children,'pdf p(f)')
    legend(visitfreqFig.Children,strains)
    figurename = ['figures/visitfreq_' wormnum '_' markerType];
    exportfig(visitfreqFig,[figurename '.eps'],exportOptions)
    system(['epstopdf ' figurename '.eps']);
    system(['rm ' figurename '.eps']);
end