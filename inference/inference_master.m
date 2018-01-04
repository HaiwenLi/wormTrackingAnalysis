% Setting parameters
% State how many summary statistics are to be computed
num_statistics = 2

addpath('component_functions')

%% Analyse simulation data
sim_ss_array = f_analyse_sims('datalists/woidM18_7900_samples.txt', 0, num_statistics);

%% Analyse experimental data
[exp_ss_array, exp_strain_list] = f_analyse_exps(...
    {'npr1'},2,num_statistics);

%% Obtain distances between each of the experiments and simulations
expsim_dists = f_exp2sim_dist(...
    exp_ss_array, sim_ss_array, exp_strain_list);

%% Perform parameter inference
[chosen_params, chosen_samples] = f_infer_params(...
    expsim_dists, {'revRateClusterEdge','dkdN'}, [0.02, 0.01],...
    '../../../sworm-model/woidModel/paramSamples_nSim10000_nParam2.mat');

%% Plot summary statistics of experiments and best samples
for statCtr = 1:num_statistics
    figure
    plot(exp_ss_array{statCtr+1},'LineWidth',2)
    hold on
    for ii=1:10
        plot(sim_ss_array{chosen_samples(ii),statCtr+1})
    end
    title(['summary statistic ' num2str(statCtr)])
    legend('expmnt mean','best simulations')
end

% %% plot surface of dissimilatirity
% load ../../../sworm-model/woidModel/paramSamples_nSim10000_nParam2.mat
% F = scatteredInterpolant(paramSamples.dkdN,paramSamples.revRateClusterEdge,expsim_dists(:,1));