module CompareAmplitudes51

import TimeSamplings as ts
using DataFrames, StatsBase

function report_compare(
    filenames::Vector{String},
    measurenames::Vector{String},
    leadnames::Vector{String},
    channel_pairs::Vector{Vector{NTuple{12, Tuple{Int, Int}}}}  # вектор NхM, где N - число файлов, M - число измерений
    )

    dfs = map(enumerate(measurenames)) do (j, name)
        vdf = map(eachindex(channel_pairs)) do i
            df = map(x -> row_report(x...), channel_pairs[i][j]) |> DataFrame
            rename!(s -> join((name, s), '_'), df)
        end
        vcat(vdf...)
    end

    df_err = hcat(dfs...)

    all_leadnames = vcat(fill(leadnames, length(channel_pairs))...)

    all_recordnames = fill("", length(all_leadnames))
    all_recordnames[1:12:end] .= filenames

    insertcols!(df_err, 1, :leadname => all_leadnames)
    insertcols!(df_err, 1, :filename => all_recordnames)

    gross_row = Vector{Any}(fill(missing, size(df_err)[2]))
    gross_row[1:2] .= "GROSS"
    gross_row[6:4:end] .= map(i -> count(.!ismissing.(df_err[:,i])), 6:4:length(gross_row))

    push!(df_err, gross_row, promote = true)

    return df_err
end

function row_report(ref::Int, test::Int)

    mark = missing

    err = test - ref
    ref_abs = abs(ref)

    thr = (ref_abs > 500) ? max(ref_abs * 0.05, 40) : 25

    mark = (abs(err) > thr) ? 1 : missing # mark = 1 => превышение

    return (;ref, test, err, mark)
end

center(rng::UnitRange{Int64}) = round(Int, (first(rng)+last(rng))/2, RoundNearest)

# """
# Пара одному референтному комплексу из множества тестовых
# """
# function complex_pairs(ref_qrs::UnitRange{Int}, test_qrs::Vector{UnitRange{Int}}, fs::Float64)
#     # ищем парный qrs репрезентативному референтному комплексу
#     i_pairs = ts.outerjoin_pairs_radius([center(ref_qrs)], center.(test_qrs), round(Int, 0.150*fs))
#     pair_ind = findfirst(x -> first(x) != -1, i_pairs)

#     # индекс парного тестового qrs
#     ref_ind = isnothing(pair_ind) ? -1 : 1
#     test_ind = isnothing(pair_ind) ? -1 : last(i_pairs[pair_ind])

#     return ref_ind, test_ind
# end

function complex_pairs(ref_qrs::Vector{UnitRange{Int}}, test_qrs::Vector{UnitRange{Int}}, fs::Float64)

    pos_ref, pos_test = center.(ref_qrs), center.(test_qrs)

    # определим область сравнения
    pair_radius = round(Int, fs * 150/1000)

    if !isempty(pos_ref)
        compare_range = max(1, pos_ref[1] - pair_radius) : pos_ref[end] + pair_radius

        # берем из тестовой разметки только события внутри области сравнения (без начальных и конечных Z)
        samp_test = ts.Sampler(pos_test)
        test_range = samp_test(compare_range)

        @views pos_test = pos_test[test_range]
    end

    # !! работаем БЕЗ КОРРЕКТИРОВКИ форм для Z
    return ts.outerjoin_pairs_radius(pos_ref, pos_test, pair_radius)
end

"""
Пара амплитуд (для разрешения ситуаций с ненайденными парами)
"""
function ampl_pair(
    ref_ind::Int, ref_ampls::Vector{Int},
    test_ind::Int, test_ampls::Vector{Int})

    ref_ampl = (ref_ind == -1) ? 0 : ref_ampls[ref_ind]
    test_ampl = (test_ind == -1) ? 0 : test_ampls[test_ind]

    return ref_ampl, test_ampl
end

"""
Пары поканальных амплитуд
"""
function channel_amplitude_pairs(
    ref_ind::Int, ref_ampls::Vector{Vector{NTuple{12, Int}}},
    test_ind::Int, test_ampls::Vector{Vector{NTuple{12, Int}}})

    map(zip(ref_ampls, test_ampls)) do (refs, tests)
        map(i -> ampl_pair(ref_ind, getindex.(refs, i), test_ind, getindex.(tests, i)), Tuple(1:12))
    end
end

end
