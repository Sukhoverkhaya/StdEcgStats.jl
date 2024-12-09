module CompareDurations51

import TimeSamplings as ts
using DataFrames, StatsBase

"""
Отчет о сравнении глобальных интервалов и длительностей
"""
function report_compare_global(
    filenames::Vector{String},
    measurenames::Vector{String},
    global_pairs::Vector{Vector{Tuple{Int, Int}}} # вектор NхM, где N - число файлов, M - число измерений
    )

    err_dfs = map(enumerate(measurenames)) do (i, name)
        err_df = DataFrame([row_report.(x...) for x in getindex.(global_pairs, i)])
        rename!(s -> join((name, s), '_'), err_df)
    end

    df_err = hcat(err_dfs...)
    insertcols!(df_err, 1, :filename => filenames)

    df_gross = DataFrame([measure_gross(df_err[:,i]) for i in 4:3:size(df_err)[2]])
    insertcols!(df_gross, 1, :Metric => measurenames)

    return df_err, df_gross
end

"""
Отчет о сравнении поканальных интервалов и длительностей
"""
function report_compare_channel(
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

    df_gross = DataFrame([measure_gross(df_err[:,i]) for i in 5:3:size(df_err)[2]])
    insertcols!(df_gross, 1, :Metric => measurenames)

    return df_err, df_gross
end

"""
Удалить `n` наибольших ПО МОДУЛЮ значений из массива `vec`
"""
function rm_max_n!(vec, n::Int)
    i2rm = sortperm(vec, by = abs)[end-n+1:end]
    deleteat!(vec, sort(i2rm))
    return vec
end

"""
Ошибка определения длительности
"""
row_report(ref::Int, test::Int) = (;ref, test, err = test - ref)

"""
Среднее и СКО ошибок по всей базе (с учетом удаления максимальных отклонений)
"""
function measure_gross(errs::Vector{Int})
    errs = rm_max_n!(copy(errs), 2)
    m = round(mean(errs), digits = 2)
    s = isone(length(errs)) ? 0. : round(std(errs), digits = 2)
    return (;mean = m, std = s)
end

center(rng::UnitRange{Int64}) = round(Int, (first(rng)+last(rng))/2, RoundNearest)
dur_ms(rng::Union{Missing, UnitRange{Int64}}, fs::Float64) = ismissing(rng) ? 0 : round(Int, (last(rng)-first(rng))/fs*1000, RoundNearest)

"""
Пара длительностей (для разрешения ситуаций с ненайденными парами)
"""
function duration_pair(
    ref_ind::Int, ref_durs::Vector{Int},
    test_ind::Int, test_durs::Vector{Int})

    ref_dur = (ref_ind == -1) ? 0 : ref_durs[ref_ind]
    test_dur = (test_ind == -1) ? 0 : test_durs[test_ind]
    return ref_dur, test_dur
end

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

    isempty(ref_qrs) && return collect(zip(fill(-1, length(test_qrs)), collect(eachindex(test_qrs)))) # когда используем для нахождения пар P, референтных может не быть

    pos_ref, pos_test = center.(ref_qrs), center.(test_qrs)

    # определим область сравнения
    pair_radius = round(Int, fs * 150/1000)

    compare_range = max(1, pos_ref[1] - pair_radius) : pos_ref[end] + pair_radius

    # берем из тестовой разметки только события внутри области сравнения (без начальных и конечных Z)
    samp_test = ts.Sampler(pos_test)
    test_range = samp_test(compare_range)

    @views pos_test = pos_test[test_range]

    # !! работаем БЕЗ КОРРЕКТИРОВКИ форм для Z
    indexpairs = ts.outerjoin_pairs_radius(pos_ref, pos_test, pair_radius)

    # возвращаем исходные тестовые индексы
    result = map(indexpairs) do (ref, test)
        test = (test == -1) ? -1 : test + first(test_range) - 1
        (ref, test)
    end

    return result
end

"""
Пары глобальных длительностей
"""
function global_duration_pairs(
    ref_ind::Int, ref_durs::Vector{Vector{Int}},
    test_ind::Int, test_durs::Vector{Vector{Int}})

    [duration_pair(ref_ind, ref, test_ind, test) for (ref, test) in zip(ref_durs, test_durs)]
end

"""
Пары поканальных длительностей
"""
function channel_duration_pairs(
    ref_ind::Int, ref_durs::Vector{Vector{NTuple{12, Int}}},
    test_ind::Int, test_durs::Vector{Vector{NTuple{12, Int}}})

    map(zip(ref_durs, test_durs)) do (refs, tests)
        map(i -> duration_pair(ref_ind, getindex.(refs, i), test_ind, getindex.(tests, i)), Tuple(1:12))
    end
end

end # module
