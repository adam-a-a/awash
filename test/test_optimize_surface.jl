using Base.Test

using DataArrays
using DataFrames
using OptiMimi

include("../src/lib/readconfig.jl")
config = readconfig("../configs/standard-1year.yml")

include("../src/optimization-given.jl")

house = optimization_given(false)

using MathProgBase
using Gurobi
solver = GurobiSolver()

@time sol = houseoptimize(house, solver)
