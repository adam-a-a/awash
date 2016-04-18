using DataArrays
using OptiMimi

netset = "usa" # dummy or usa

# Only include counties within this state (give as 2 digit FIPS)
# "10" for Delaware (3 counties), "08" for Colorado (64 counties)
filterstate = nothing #"10"

include("world.jl")
include("weather.jl")

include("Agriculture.jl")
include("ReturnFlows.jl")
include("ConjunctiveUse.jl")
include("DomesticDemand.jl")
include("Market.jl")
include("Transportation.jl")
include("WaterNetwork.jl")

println("Creating model...")

# First solve entire problem in a single timestep
m = newmodel();

# Add all of the components
domesticdemand = initdomesticdemand(m, m.indices_values[:time]); # exogenous
agriculture = initagriculture(m); # optimization-only
returnflows = initreturnflows(m) # exogenous/optimization
conjunctiveuse = initconjunctiveuse(m); # dep. Agriculture, DomesticDemand
waternetwork = initwaternetwork(m); # dep. ConjunctiveUse
transportation = inittransportation(m); # optimization-only
market = initmarket(m); # dep. Transporation, Agriculture

# Connect up the components
conjunctiveuse[:totalirrigation] = agriculture[:totalirrigation];
conjunctiveuse[:domesticuse] = domesticdemand[:waterdemand];

waternetwork[:removed] = returnflows[:removed];
conjunctiveuse[:withdrawals] = returnflows[:copy_withdrawals];

market[:produced] = agriculture[:production];
market[:regionimports] = transportation[:regionimports];
market[:regionexports] = transportation[:regionexports];

# Run it and time it!
@time run(m)


