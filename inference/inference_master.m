% Setting parameters
% State how many summary statistics are to be computed
global num_statistics
num_statistics = 4
num_statistics = num_statistics+1

% Analyse simulation data
sim_ss_array = f_analyse_sims('list_extended_simulations.txt')

% Analyse experimental data
[exp_ss_array, exp_strain_list] = f_analyse_exps(...
    {'N2_40_g_list.txt'},1)

% Obtain distances between each of the experiments and simulations
expsim_dists = f_exp2sim_dist(...
    exp_ss_array, sim_ss_array, exp_strain_list)

% Perform parameter inference
chosen_params = f_infer_params(...
    {'vs', 'revRateClusterEdge', 'Rir', 'Ris'}, [0.01])