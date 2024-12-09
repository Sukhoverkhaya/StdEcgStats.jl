module CompareForms

import TimeSamplings as ts
using DataFrames, CSV

export pair_event_labels, report_comparison

# @enum Forms begin # формы аналайзера (только первая буква, без подтипов)
#     V = 1
#     A = 2
#     S = 3
#     C = 4
#     F = 5
#     B = 6
#     W = 7
#     Z = 8
#     X = 9
#     U = 10
#     Q = 11

#     O = 12
# end

@enum FormsShort begin # краткий список форм конкретно для нашей задачи
    # сокращённый до 3-х форм вариант (для стандартной таблицы)
    V = 1
    S
    O

    # остальные формы (для расширенной таблицы)
    W
    A
    B
    F

    U

    # X = 7
    # Z = 8
end

const short = Dict{Symbol, FormsShort}( # пары: форма аналайзера => укороченная форма из нашей выборки
   :V => V,
   :A => A,
   :S => S,
   :C => O,
   :F => F,
   :B => B,
   :W => W,
   :Z => O,
   :X => O,
   :U => U, ## ?
#    :Q => O,

   :O => O
)

const extra_short = Dict{Symbol, FormsShort}( # делим все формы только на V и S (и O для всяких помех)
    :V => V,
    :A => S,
    :S => S,
    :C => S,
    :F => V,
    :B => S,
    :W => S

    # остальные заменим на O и не будем включать в статистику
)

form_pair(ref::FormsShort, test::FormsShort) = string(ref)*lowercase(string(test)) |> Symbol

function pair_event_labels( # skv: перенесено из из CompareBeat2beat
    pos_ref::AbstractVector,
    form_ref::AbstractVector,
    pos_test::AbstractVector,
    form_test::AbstractVector,
    fs::Float64;
    radius_ms = 150
    )

    # определим область сравнения
    pair_radius = round(Int, fs * radius_ms/1000)

    if !isempty(pos_ref)
        compare_range = max(1, pos_ref[1] - pair_radius) : pos_ref[end] + pair_radius

        # берем из тестовой разметки только события внутри области сравнения (без начальных и конечных Z)
        samp_test = ts.Sampler(pos_test)
        test_range = samp_test(compare_range)

        @views pos_test, form_test = pos_test[test_range], form_test[test_range]
    end

    # !! работаем БЕЗ КОРРЕКТИРОВКИ форм для Z
    indexpairs = ts.outerjoin_pairs_radius(pos_ref, pos_test, pair_radius)

    pairs_form = Vector{NTuple{2,Symbol}}(undef, length(indexpairs))
    pairs_pos = Vector{NTuple{2,Int}}(undef, length(indexpairs))
    for (k, (i1, i2)) in enumerate(indexpairs)
        t1, f1 = i1 < 1 ? (-1, :O) : (pos_ref[i1], Symbol(form_ref[i1]))
        t2, f2 = i2 < 1 ? (-1, :O) : (pos_test[i2], Symbol(form_test[i2]))
        pairs_pos[k] = (t1, t2)
        pairs_form[k] = (f1, f2)
    end

    # correct_pairs!(pairs_form) # adapter? исключаем участки U, VF (это надо делать перед сравнением???)

    return pairs_pos, pairs_form
end

function calc_crossmatrix(pairs_form, mode::Dict{Symbol, FormsShort} = extra_short)

    N = maximum(Int.(values(mode)))

    M = zeros(Int, N, N) # матрица попаданий

    for i in eachindex(pairs_form)

        ref, test = pairs_form[i]
        iref = get(mode, ref, 0) |> Int
        itest = get(mode, test, 0) |> Int

        # не включаем в рассмотрение формы, которых нет в подборке mode
        all(!iszero, (iref, itest)) && (M[iref, itest] += 1)

    end

    return M
end

calc_crossmatrix(mode::Dict{Symbol, FormsShort} = extra_short) = pairs_form -> calc_crossmatrix(pairs_form, mode)

function confusion_matrix(M::Matrix{Int})
    N = size(M)[1]
    confM = map(1:N) do form_ind
        tp_r = tp_c = form_ind
        fn_r = fp_c = form_ind
        fn_c = fp_r = tn_r = tn_c = deleteat!(collect(1:N), form_ind)

        TP = M[tp_r, tp_c]
        FN = M[fn_r, fn_c] |> sum
        FP = M[fp_r, fp_c] |> sum
        TN = M[tn_r, tn_c] |> sum

        (;TP, FN, FP, TN)
    end

    return confM
end

function confusion_params(TP::Int, FN::Int, FP::Int, TN::Int)
    Se = round(TP/(TP+FN)*100, digits = 2)
    Sp = round(TN/(TN+FP)*100, digits = 2)
    PPv = round(TP/(TP+FP)*100, digits = 2)
    Acc = round((TP+TN)/(TP+TN+FP+FN)*100, digits = 2)

    return [Se, Sp, PPv, Acc]
end

const properties(forms::Vector{String}) = [fname.*["_Se", "_Sp", "_PPv", "_Acc"] for fname in forms]

function report_comparison(filenames::Vector{String}, pairs_form::Vector{Vector{Tuple{Symbol, Symbol}}}; mode::Symbol = :extra_short)

    mode = (mode == :extra_short) ? extra_short : (mode == :short) ? short : error("Unknown `mode` value")

    props = unique(string.(sort(collect(values(mode))))) |> properties
    paramnames = Symbol.(vcat(props...))

    crossM = pairs_form .|> calc_crossmatrix(mode)

    M = Matrix{Float64}(undef, length(pairs_form), length(paramnames))
    for i in eachindex(pairs_form)
        conf = confusion_matrix(crossM[i])
        values = [confusion_params(x...) for x in conf]

        M[i,:] .= vcat(values...)
    end

    df = DataFrame(M, paramnames)
    insertcols!(df, 1, :File => filenames)

    totalM = sum(crossM)
    conf = confusion_matrix(totalM)
    gross = [confusion_params(x...) for x in conf]
    push!(df, vcat("GROSS", gross...))

    return df
end

end
