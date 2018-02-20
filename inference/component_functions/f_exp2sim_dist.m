function expsim_dists = f_exp2sim_dist(exp_ss_array, sim_ss_array, weights)
% Compute the appropriate distances between each of the
% simulations and the experimental references

% Constuct a n-by-m-by-l+1 matrix for containing the distances between each
% experiment (n) and each simulation (m) for each of the summary statistics
% computed (l)

num_statistics = size(exp_ss_array,2)-1;

if nargin<3
    weights=[];
end
numStrains = size(exp_ss_array,1);
expsim_dists = cell(numStrains,1);

for strainCtr = 1:numStrains
    numSims = size(sim_ss_array{strainCtr},1);
    expsim_dists{strainCtr} = zeros(numSims, 1+num_statistics);
    for statCtr = 1:num_statistics
        exp_data = exp_ss_array{strainCtr,1+statCtr};
        scale_factor = 1;
        %         % to penalise for experimental variability of the summary
        %         % we could scale by the standard deviation of each statistic.
        %         % since we also have distributions (ie binned
        %         % data), we will divide by the deviation for each bin - unclear
        %         if this works as expected with logged summary statistics
        %         scale_factor = std(exp_data);
        for simCtr = 1:numSims
            sim_data = sim_ss_array{strainCtr}{simCtr,1+statCtr};
            dim_factor = 1./sqrt(length(exp_data)); % correction factor for higher dimensional summary statistics
            % Compute the distance between this simulation and the
            % reference - careful not to take log(0)
            expsim_dists{strainCtr}(simCtr,1+statCtr) = sum(vecnorm(...
                (log(max(exp_data,eps)) - log(max(sim_data,eps)))./scale_factor... % take scaled difference of all observed values of this summary stat and this simulated one
                ,2,2)... % take norm for each expmntl sample
                .*dim_factor... % correct for dim of summary stat
                );% sum this distance over expmntl samples
            % add the distance to the total from all summary statistics
            expsim_dists{strainCtr}(simCtr,1) = expsim_dists{strainCtr}(simCtr,1)...
                + weights(statCtr).*expsim_dists{strainCtr}(simCtr,1+statCtr); % weight summary statistic
            if expsim_dists{strainCtr}(simCtr,1)==0
                1;
            end
        end
    end
end

end