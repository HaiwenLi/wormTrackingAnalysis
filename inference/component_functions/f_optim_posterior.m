function [weights_optim,min_obj] = f_optim_posterior(exp_ss_array, sim_ss_array,...
    p_cutoff, param_names, param_values, supportRange,scaleflag)
% Optimise the weights of summary statistics to maximise the Hellinger
% distance between the prior and posterior, and return the the appropriate distances
% between each of the simulations and the experimental references
% issues / to-do:
% - we may be able to improve performance by not evaluating the prior again
% for each strain, if we can rely in ksdensity to always query the same points
if nargin<7
    scaleflag = 'linear';
end
if strcmp(scaleflag,'log')
    for strainCtr = 1:length(param_values)
        param_values{strainCtr} = log10(param_values{strainCtr});
    end
    supportRange = log10(supportRange);
end
numStats = size(exp_ss_array,2) - 1;

% set up objecive function distance
lambda = 1e-4; % regularization parameter
% define the objective function for joint optimisation over both strains
L = @(x) hellinger(x,exp_ss_array,sim_ss_array,p_cutoff,param_names,param_values,supportRange) ...
    + lambda*norm(x,1); % include regularisation
nIter = max(10*numStats,50);
initial_weights = lhsdesign(nIter,numStats);% just specify the extreme values in here, the rest should be filled in by ga randomly
initial_weights(initial_weights==0) = 1e-14; % to satisfy the optimisation bounds

%% use the ga global optimization toolbox solver
options = optimoptions('ga','PopulationSize',nIter,'InitialPopulationMatrix',initial_weights,'UseParallel',true,'Display','iter',...
    'HybridFcn',@fmincon); % 'UseParallel', true
[weights_optim,min_obj] = ga(L,numStats,[],[],[],[],eps*ones(numStats,1),100*ones(numStats,1),[],options);

% normalise weights (for convenience only)
weights_optim = weights_optim./sum(weights_optim);

% %% use the particle swarm optimizer
% options = optimoptions('particleswarm','InitialSwarmMatrix',initial_weights,'Display','iter',...
%     'HybridFcn',@fmincon);
% [wsw,Lsw] = particleswarm(L,numStats,1e-2*ones(numStats,1),10*ones(numStats,1),options);

% %% use simulated annealing
% options = optimoptions('simulannealbnd','Display','iter');
% [wsa,Lsa] = simulannealbnd(L,mean(initial_weights),zeros(numStats,1),[],options);
end

function L = hellinger(weights,exp_ss_array,sim_ss_array,p_cutoff,param_names,param_values,supportRange)
% for given weights, compute the distances
expsim_dists = f_exp2sim_dist(exp_ss_array, sim_ss_array, weights);
% for these distances, select fraction of closest parameters
[chosen_params, chosen_samples] = f_infer_params(...
    expsim_dists, [], p_cutoff, param_names, param_values, false, supportRange);
% construct a kernel density estimate of the posterior
nStrains = size(exp_ss_array,1);
H = 0;
for strainCtr = 1:nStrains
    kde_weights = 1./expsim_dists{strainCtr}(chosen_samples{strainCtr},1);
    [posti,posti_query_points] = ksdensity(chosen_params{strainCtr},...
        'Support',supportRange,'BoundaryCorrection','reflection','Weights',kde_weights);
    % construct a kernel density estimate of the prior at the same sample points
    [prior, prior_query_points] = ksdensity(param_values{strainCtr},posti_query_points,...
        'Support',supportRange,'BoundaryCorrection','reflection');
    % check that density estimates are evaluated at the same points - shouldn't
    % be necessary
    assert(all(all(prior_query_points==posti_query_points)))
    % calculate the hellinger distance between the prior and posterior distributions
    H = H + 1./sqrt(2).*norm(sqrt(posti) - sqrt(prior));
end
% give back the negative of the distance, as this is the objective to
% minimize
L = -H;
end

function [c, ceq] = weights_constraint(weights) % may not need this
c = [];
ceq = sum(weights,2) -1; % vectorized
end
