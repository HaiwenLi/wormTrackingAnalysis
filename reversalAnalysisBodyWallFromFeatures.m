% calculate various single worm statistics for different numbers of worms
% on plate

% issues / todo:

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
wormnums = {'1W','40','HD'};
intensityThresholds_g = [100, 60, 40];
maxBlobSize_g = 1e4;
midbodyIndcs = 19:33;
plotColors = lines(length(wormnums));

for strainCtr = 1:length(strains)
    revFreqFig = figure; hold on
    for numCtr = 1:length(wormnums)
        revDurFig = figure; hold on
        wormnum = wormnums{numCtr};
        %% load data
        filenames = importdata(['datalists/' strains{strainCtr} '_' wormnum '_r_list.txt']);
        if ~strcmp(wormnum,'1W')
            filenames_g = importdata(['datalists/' strains{strainCtr} '_' wormnum '_g_list.txt']);
        else
            filenames_g = {};
        end
        numFiles = length(filenames);
        midbodySpeeds = cell(numFiles,1);
        reversalfreq_lone = NaN(numFiles,1);
        reversaldurations_lone = cell(numFiles,1);
        reversalfreq_incluster = NaN(numFiles,1);
        reversaldurations_incluster = cell(numFiles,1);
        reversalfreq_neither = NaN(numFiles,1);
        reversaldurations_neither = cell(numFiles,1);
        for fileCtr = 1:numFiles % can be parfor?
            filename = filenames{fileCtr};
            trajData = h5read(filename,'/trajectories_data');
            if ~strcmp(wormnum,'1W')
                filename_g = filenames_g{fileCtr};
                trajData_g = h5read(filename_g,'/trajectories_data');
                % filter data
                blobFeats_g = h5read(filename_g,'/blob_features');
                trajData_g.filtered = (blobFeats_g.area*pixelsize^2<=maxBlobSize_g)&...
                    (blobFeats_g.intensity_mean>=intensityThresholds_g(numCtr));
            end
            featData = h5read(strrep(filename,'skeletons','features'),'/features_timeseries');
            frameRate = double(h5readatt(filename,'/plate_worms','expected_fps'));
            %% calculate stats
            if ~strcmp(wormnum,'1W')
                 try 
                     min_neighbor_dist_rr = h5read(filename,'/min_neighbor_dist_rr');
                     min_neighbor_dist_rg = h5read(filename,'/min_neighbor_dist_rg');
                     num_close_neighbours_rg = h5read(filename,'/num_close_neighbours_rg');
                 catch
                     disp(['Could not read cluster status from ' filename ])
                    [min_neighbor_dist_rr, min_neighbor_dist_rg, num_close_neighbours_rg] ...
                        = calculateClusterStatus(trajData,trajData_g,pixelsize,500);
                    % write stats to hdf5-file
                    h5create(filename,'/min_neighbor_dist_rr',...
                        size(min_neighbor_dist_rr))
                    h5write(filename,'/min_neighbor_dist_rr',...
                        single(min_neighbor_dist_rr))
                    h5create(filename,'/min_neighbor_dist_rg',...
                        size(min_neighbor_dist_rg))
                    h5write(filename,'/min_neighbor_dist_rg',...
                        single(min_neighbor_dist_rg))
                    h5create(filename,'/num_close_neighbours_rg',...
                        size(num_close_neighbours_rg))
                    h5write(filename,'/num_close_neighbours_rg',...
                        uint16(num_close_neighbours_rg))
                end
                loneWorms = min_neighbor_dist_rr>=1100&min_neighbor_dist_rg>=1600;
                inCluster = num_close_neighbours_rg>=3;
                neitherClusterNorLone = num_close_neighbours_rg==1|num_close_neighbours_rg==2;
                %~inCluster&~loneWorms;
            else
                loneWorms = true(size(trajData.frame_number));
                inCluster = false(size(trajData.frame_number));
                neitherClusterNorLone = false(size(trajData.frame_number));
            end
            % features from the tracker
            midbodySpeedSigned = featData.midbody_speed;
            % smooth speed to denoise
            midbodySpeedSigned = smooth(midbodySpeedSigned,3,'moving');
            %%
            % find reversals in midbody speed
            [revStartInd, revDuration] = findReversals(...
                midbodySpeedSigned,featData.worm_index);
            loneReversals = ismember(featData.skeleton_id(revStartInd)+1,find(loneWorms));
            inclusterReversals = ismember(featData.skeleton_id(revStartInd)+1,find(inCluster));
            neitherClusterNorLoneReversals = ismember(featData.skeleton_id(revStartInd)+1,find(neitherClusterNorLone));
            loneWormsFeats = ismember(featData.skeleton_id+1,find(loneWorms));
            inClusterFeats = ismember(featData.skeleton_id+1,find(inCluster));
            neitherClusterNorLoneFeats = ismember(featData.skeleton_id+1,find(neitherClusterNorLone));
            Nrev_lone = nnz(loneReversals);
            Nrev_incluster = nnz(inclusterReversals);
            Nrev_neither = nnz(neitherClusterNorLoneReversals);
            T_lone = nnz(loneWormsFeats)/frameRate;
            T_incluster = nnz(inClusterFeats)/frameRate;
            T_neither = nnz(neitherClusterNorLone)/frameRate;
            Trev_lone = nnz(midbodySpeedSigned(loneWormsFeats)<0)/frameRate;
            Trev_incluster = nnz(midbodySpeedSigned(inClusterFeats)<0)/frameRate;
            Trev_neither = nnz(midbodySpeedSigned(neitherClusterNorLoneFeats)<0)/frameRate;
            reversalfreq_lone(fileCtr) = Nrev_lone./(T_lone - Trev_lone);
            reversalfreq_incluster(fileCtr) = Nrev_incluster./(T_incluster - Trev_incluster);
            reversalfreq_neither(fileCtr) = Nrev_neither./(T_neither - Trev_neither);
            reversaldurations_lone{fileCtr} = revDuration(loneReversals)/frameRate;
            reversaldurations_incluster{fileCtr} = revDuration(inclusterReversals)/frameRate;
            reversaldurations_neither{fileCtr} = revDuration(neitherClusterNorLoneReversals)/frameRate;
        end
        %% plot data
        boxplot(revFreqFig.Children,reversalfreq_lone,'Positions',numCtr-1/4,...
            'Notch','off')
        boxplot(revFreqFig.Children,reversalfreq_neither,'Positions',numCtr,...
            'Notch','off','Colors',0.5*ones(1,3))
        boxplot(revFreqFig.Children,reversalfreq_incluster,'Positions',numCtr+1/4,...
            'Notch','off','Colors','r')
        revFreqFig.Children.XLim = [0 length(wormnums)+1];
        %
        reversaldurations_lone = vertcat(reversaldurations_lone{:});
        reversaldurations_incluster = vertcat(reversaldurations_incluster{:});
        reversaldurations_neither = vertcat(reversaldurations_neither{:});
        histogram(revDurFig.Children,reversaldurations_lone,0:1/frameRate:15,...
            'Normalization','pdf','DisplayStyle','stairs');
        histogram(revDurFig.Children,reversaldurations_neither,0:1/frameRate:15,...
            'Normalization','pdf','DisplayStyle','stairs','EdgeColor',0.5*ones(1,3));
        histogram(revDurFig.Children,reversaldurations_incluster,0:1/frameRate:15,...
            'Normalization','pdf','DisplayStyle','stairs','EdgeColor','r');
        %
        title(revDurFig.Children,strains{strainCtr},'FontWeight','normal');
        set(revDurFig,'PaperUnits','centimeters')
        xlabel(revDurFig.Children,'time (s)')
        ylabel(revDurFig.Children,'P')
        revDurFig.Children.XLim = [0 15];
        if ~strcmp(wormnum,'1W')
            legend(revDurFig.Children,{'lone worms','neither','in cluster'})
        else
            legend(revDurFig.Children,'single worms')
        end
        figurename = ['figures/reversaldurationsFromFeatures_' strains{strainCtr} '_' wormnum];
        exportfig(revDurFig,[figurename '.eps'],exportOptions)
        system(['epstopdf ' figurename '.eps']);
        system(['rm ' figurename '.eps']);
    end
    %% format and export figures
    title(revFreqFig.Children,strains{strainCtr},'FontWeight','normal');
    set(revFreqFig,'PaperUnits','centimeters')
    revFreqFig.Children.XTick = 1:length(wormnums);
    revFreqFig.Children.XTickLabel = strrep(wormnums,'HD','200');
    revFreqFig.Children.XLabel.String = 'worm number';
    revFreqFig.Children.YLabel.String = 'reversals (1/s)';
    revFreqFig.Children.YLim = [0 1];
    figurename = ['figures/reversalfrequencyFromFeatures_' strains{strainCtr}];
    exportfig(revFreqFig,[figurename '.eps'],exportOptions)
    system(['epstopdf ' figurename '.eps']);
    system(['rm ' figurename '.eps']);

end