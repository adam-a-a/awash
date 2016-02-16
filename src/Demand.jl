# The demand component
#
# Each region has an `demand`, and compares this to the amount of `releases`
# resource.  The result is a `surplus`, which may be negative if `releases` <
# `demand`.

using Mimi
using Distributions

@defcomp Demand begin
    regions = Index()

    # Internal
    # Resource demands
    demand = Parameter(index=[regions, time])

    # External
    # Resource availability from Economy
    releases = Parameter(index=[regions, time])

    # Resource surplus over (or below) demand
    surplus = Variable(index=[regions, time])
end

"""
Compute the `surplus` as `releases` - `demand`.
"""
function timestep(c::Demand, tt::Int)
    v = c.Variables
    p = c.Parameters
    d = c.Dimensions

    for rr in d.regions
        v.surplus[rr, tt] = p.releases[rr, tt] - p.demand[rr, tt]
    end
end

"""
Add a demand component to the model.
"""
function initdemand(m::Model)
    demand = addcomponent(m, Demand)

    # Use random demands, from a LogNormal distribution and constant across all
    # time.
    demand[:demand] = repeat(asmynumeric(rand(LogNormal(log(1000.0), log(10.0)), m.indices_counts[:regions])), outer=[1, m.indices_counts[:time]]);

    demand
end
