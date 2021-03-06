using DataFrames

## Univariate crop parametrs
unicrop_irrigationrate = Dict("barley" => 12.9, "corn" => 13.0,
                              "sorghum" => 0., "soybeans" => 16.8,
                              "wheat" => 21.4, "hay" => 0.) # mm/year
unicrop_irrigationstress = Dict("barley" => 95.2, "corn" => 73.1,
                                "sorghum" => 0., "soybeans" => 0.,
                                "wheat" => 7.4, "hay" => 0.) # (mm/year) / m-deficiency

known_irrigationrate = Dict("corn.co.rainfed" => 0,
                            "corn.co.irrigated" => 1.6 * 304.8, # convert ft -> mm
                            "wheat.co.rainfed" => 0,
                            "wheat.co.irrigated" => 1.9 * 304.8) # convert ft -> mm

# Irrigation crop parameters
water_requirements = Dict("alfalfa" => 1.63961100235402, "otherhay" => 1.63961100235402,
                          "Barley" => 1.18060761343329, "Barley.Winter" => 1.18060761343329,
                          "Maize" => 1.47596435526564,
                          "Sorghum" => 1.1364914374721,
                          "Soybeans" => 1.37599595071683,
                          "Wheat" => 0.684836198198068, "Wheat.Winter" => 0.684836198198068,
"barley" => 1.18060761343329, "corn" => 1.47596435526564,
"sorghum" => 1.1364914374721, "soybeans" => 1.37599595071683,
"wheat" => 0.684836198198068, "hay" => 1.63961100235402) # in m

# Per year costs
cultivation_costs = Dict("alfalfa" => 306., "otherhay" => 306., "Hay" => 306,
                         "Barley" => 442., "Barley.Winter" => 442.,
                         "Maize" => 554., "Sorghum" => 314.,
                         "Soybeans" => 221., "Wheat" => 263., "Wheat.Winter" => 263., "barley" => 442.,
                         "corn" => 554., "corn.co.rainfed" => 554., "corn.co.irrigated" => 554.,
                         "sorghum" => 314., "soybeans" => 221.,
"wheat" => 263., "wheat.co.rainfed" => 263., "wheat.co.irrigated" => 263,
"hay" => 306.) # USD / acre

maximum_yields = Dict("alfalfa" => 25., "otherhay" => 25., "Hay" => 306,
                      "Barley" => 200., "Barley.Winter" => 200.,
                      "Maize" => 250.,
                      "Sorghum" => 150.,
                      "Soybeans" => 100.,
                      "Wheat" => 250., "Wheat.Winter" => 250.,
                      "barley" => 200., "corn" => 250.,
                      "sorghum" => 150., "soybeans" => 100.,
"wheat" => 250., "hay" => 306.)

quickstats_planted = Dict("corn.co.rainfed" => "agriculture/allyears/maize-nonirrigated-planted.csv",
                          "corn.co.irrigated" => "agriculture/allyears/maize-irrigated-planted.csv",
                          "wheat.co.rainfed" => "agriculture/allyears/wheat-nonirrigated-planted.csv",
                          "wheat.co.irrigated" => "agriculture/allyears/wheat-irrigated-planted.csv")

type StatisticalAgricultureModel
    intercept::Float64
    interceptse::Float64
    gdds::Float64
    gddsse::Float64
    kdds::Float64
    kddsse::Float64
    wreq::Float64
    wreqse::Float64

    gddoffset::Float64
    kddoffset::Float64
end

function StatisticalAgricultureModel(df::DataFrame, filter::Symbol, fvalue::Any)
    interceptrow = findfirst((df[filter] .== fvalue) & (df[:coef] .== "intercept"))
    gddsrow = findfirst((df[filter] .== fvalue) & (df[:coef] .== "gdds"))
    kddsrow = findfirst((df[filter] .== fvalue) & (df[:coef] .== "kdds"))
    wreqrow = findfirst((df[filter] .== fvalue) & (df[:coef] .== "wreq"))
    gddoffsetrow = findfirst((df[filter] .== fvalue) & (df[:coef] .== "gddoffset"))
    kddoffsetrow = findfirst((df[filter] .== fvalue) & (df[:coef] .== "kddoffset"))

    if interceptrow > 0
        intercept = df[interceptrow, :mean]
        interceptse = df[interceptrow, :serr]
    else
        intercept = 0
        interceptse = 0
    end

    gdds = gddsrow != 0 ? df[gddsrow, :mean] : 0
    gddsse = gddsrow != 0 ? df[gddsrow, :serr] : Inf
    kdds = kddsrow != 0 ? df[kddsrow, :mean] : 0
    kddsse = kddsrow != 0 ? df[kddsrow, :serr] : Inf
    wreq = wreqrow != 0 ? df[wreqrow, :mean] : 0
    wreqse = wreqrow != 0 ? df[wreqrow, :serr] : Inf
    gddoffset = gddoffsetrow != 0 ? df[gddoffsetrow, :mean] : 0
    kddoffset = kddoffsetrow != 0 ? df[kddoffsetrow, :mean] : 0

    StatisticalAgricultureModel(intercept, interceptse, gdds, gddsse, kdds, kddsse, wreq, wreqse, gddoffset, kddoffset)
end

function gaussianpool(mean1, sdev1, mean2, sdev2)
    if isna(sdev1) || isnan(sdev1)
        mean2, sdev2
    elseif isna(sdev2) || isnan(sdev2)
        mean1, sdev1
    else
        (mean1 / sdev1^2 + mean2 / sdev2^2) / (1 / sdev1^2 + 1 / sdev2^2), 1 / (1 / sdev1^2 + 1 / sdev2^2)
    end
end

function fallbackpool(meanfallback, sdevfallback, mean1, sdev1)
    if isna(mean1)
        meanfallback, sdevfallback
    else
        mean1, sdev1
    end
end

function findcroppath(prefix, crop, suffix, recurse=true)
    println(prefix * crop * suffix)
    if isfile(datapath(prefix * crop * suffix))
        return datapath(prefix * crop * suffix)
    end

    if isupper(crop[1]) && isfile(datapath(prefix * lcfirst(crop) * suffix))
        return datapath(prefix * lcfirst(crop) * suffix)
    end

    if islower(crop[1]) && isfile(datapath(prefix * ucfirst(crop) * suffix))
        return datapath(prefix * ucfirst(crop) * suffix)
    end

    if !recurse
        return nothing
    end

    croptrans = Dict{AbstractString, Vector{AbstractString}}("corn" => ["maize"], "hay" => ["otherhay"], "maize" => ["corn"])
    if lowercase(crop) in keys(croptrans)
        for crop2 in croptrans[lowercase(crop)]
            path2 = findcroppath(prefix, crop2, suffix, false)
            if path2 != nothing
                return path2
            end
        end
    end

    return nothing
end

if isfile(cachepath("agmodels.jld"))
    println("Loading from saved region network...")

    agmodels = deserialize(open(cachepath("agmodels.jld"), "r"));
else
    # Prepare all the agricultural models
    agmodels = Dict{UTF8String, Dict{UTF8String, StatisticalAgricultureModel}}() # {crop: {fips: model}}
    nationals = readtable(joinpath(datapath("agriculture/nationals.csv")))
    nationalcrop = Dict{UTF8String, UTF8String}("barley" => "Barley", "corn" => "Maize",
                                                "sorghum" => "Sorghum", "soybeans" => "Soybeans",
                                                "wheat" => "Wheat", "hay" => "alfalfa")
    for crop in allcrops
        println(crop)
        agmodels[crop] = Dict{Int64, StatisticalAgricultureModel}()

        # Create the national model
        national = StatisticalAgricultureModel(nationals, :crop, get(nationalcrop, crop, crop))
        bayespath = nothing #findcroppath("agriculture/bayesian/", crop, ".csv")
        if bayespath != nothing
            counties = readtable(bayespath)
            combiner = fallbackpool
        else
            croppath = findcroppath("agriculture/unpooled-", crop, ".csv")
            if croppath == nothing
                continue
            end
            counties = readtable(croppath)
            combiner = gaussianpool
        end

        for regionid in unique(regionindex(counties, :, tostr=false))
            county = StatisticalAgricultureModel(counties, lastindexcol, regionid)

            # Construct a pooled or fallback combination
            gdds, gddsse = combiner(national.gdds, national.gddsse, county.gdds, county.gddsse)
            kdds, kddsse = combiner(national.kdds, national.kddsse, county.kdds, county.kddsse)
            wreq, wreqse = combiner(national.wreq, national.wreqse, county.wreq, county.wreqse)
            agmodel = StatisticalAgricultureModel(county.intercept, county.interceptse, gdds, gddsse, kdds, kddsse, wreq, wreqse, county.gddoffset, county.kddoffset)
            agmodels[crop][canonicalindex(regionid)] = agmodel
        end
    end

    fp = open(cachepath("agmodels.jld"), "w")
    serialize(fp, agmodels)
    close(fp)
end

alluniquecrops = ["barley", "corn", "sorghum", "soybeans", "wheat", "hay"]
uniquemapping = Dict{AbstractString, Vector{AbstractString}}("barley" => ["Barley", "Barley.Winter"], "corn" => ["Maize"], "sorghum" => ["Sorghum"], "soybeans" => ["Soybeans"], "wheat" => ["Wheat", "Wheat.Winter"], "hay" => ["alfalfa", "otherhay"])

"""
Determine which crops are not represented
"""
function missingcrops()
    for crop in alluniquecrops
        found = false
        if crop in allcrops
            found = true
        else
            for othername in uniquemapping[crop]
                if othername in allcrops
                    found = true
                    break
                end
            end
        end

        if !found
            produce(crop)
        end
    end
end

"""
Return the current crop area for every crop, in Ha
"""
function currentcroparea(crop::AbstractString)
    df = getfilteredtable(datapath("agriculture/totalareas.csv"))
    df[:, crop] * 0.404686
end

"""
Return the current irrigation for the given crop, in mm
"""
function cropirrigationrates(crop::AbstractString)
    df = getfilteredtable(datapath("agriculture/totalareas.csv"))
    getunivariateirrigationrates(crop)
end

"""
Read Naresh's special yield file format
"""
function read_nareshyields(crop::AbstractString)
    # Get the yield data
    if crop == "corn.co.rainfed"
        df = readtable(datapath("colorado/blended_predicted_corn.txt"), separator=' ')
        fipses = map(xfips -> "0" * string(xfips)[2:end], names(df))
        yields = df[1:61,:]
    elseif crop == "corn.co.irrigated"
        df = readtable(datapath("colorado/blended_predicted_corn.txt"), separator=' ')
        fipses = map(xfips -> "0" * string(xfips)[2:end], names(df))
        yields = df[62:122,:]
    elseif crop == "wheat.co.rainfed"
        df = readtable(datapath("colorado/blended_predicted_wheat.txt"), separator=' ')
        fipses = map(xfips -> "0" * string(xfips)[2:end], names(df))
        yields = df[1:61,:]
    elseif crop == "wheat.co.irrigated"
        df = readtable(datapath("colorado/blended_predicted_wheat.txt"), separator=' ')
        fipses = map(xfips -> "0" * string(xfips)[2:end], names(df))
        yields = df[62:122,:]
    end

    # Get the order into our fips
    regionindices = getregionindices(fipses)
    result = zeros(numcounties, numsteps)

    for ii in 1:numsteps
        result[regionindices, ii] = vec(convert(Matrix{Float64}, yields[index2year(ii) - 1949, :]))
    end

    result
end

"""
Read USDA QuickStats data
"""
function read_quickstats(filepath::AbstractString)
    df = readtable(filepath)
    df[:fips] = [isna(df[ii, :County_ANSI]) ? 0 : df[ii, :State_ANSI] * 1000 + df[ii, :County_ANSI] for ii in 1:nrow(df)];
    df[:xvalue] = map(str -> parse(Float64, replace(str, ",", "")), df[:Value]);

    # Reorder these values to match regions
    indices = getregionindices(canonicalindex(convert(Vector{Int64}, df[:fips])))
    result = zeros(nrow(masterregions))
    result[indices[indices .> 0]] = df[:xvalue][indices .> 0]

    result
end
